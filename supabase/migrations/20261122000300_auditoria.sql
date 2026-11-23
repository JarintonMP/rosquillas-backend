-- =====================================================================
-- Bitácora de auditoría genérica e inmutable.
-- Ver docs/DISENO_BD.md, secciones 3 (Auditoría) y 6.5.
--
-- * Un solo trigger para todas las tablas: auditar una tabla nueva es
--   agregarle el trigger, sin crear tablas nuevas.
-- * En ediciones se guardan solo las columnas que cambiaron, para
--   ahorrar espacio (el plan gratis de Supabase tiene 500 MB).
-- * Nadie puede editar ni borrar la bitácora, ni el super admin.
-- =====================================================================

create table auditoria.bitacora (
  id          bigint generated always as identity primary key,
  esquema     text not null,
  tabla       text not null,
  registro_id text not null,
  accion      text not null check (accion in (
                'creacion', 'edicion', 'deshabilitacion', 'habilitacion',
                'eliminacion', 'restauracion', 'anulacion')),
  cambios     jsonb not null,
  usuario_id  uuid,
  fecha       timestamptz not null default now()
);

comment on table auditoria.bitacora is
  'Quién hizo qué y cuándo. En creación guarda la fila; en los demás casos solo {columna: {antes, despues}}.';
comment on column auditoria.bitacora.cambios is
  'creacion: fila completa. Otras acciones: solo columnas modificadas, como {"col": {"antes": x, "despues": y}}.';

create index bitacora_registro_idx on auditoria.bitacora (esquema, tabla, registro_id, fecha desc);
create index bitacora_usuario_idx  on auditoria.bitacora (usuario_id, fecha desc);
create index bitacora_fecha_idx    on auditoria.bitacora (fecha desc);

-- ---------------------------------------------------------------------
-- Diferencia entre dos filas: solo las columnas que cambiaron
-- ---------------------------------------------------------------------
create or replace function auditoria.diferencias(p_antes jsonb, p_despues jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    jsonb_object_agg(d.key, jsonb_build_object('antes', p_antes -> d.key, 'despues', d.value)),
    '{}'::jsonb
  )
  from jsonb_each(p_despues) d
  where (p_antes -> d.key) is distinct from d.value
    and d.key not in ('actualizado_en', 'actualizado_por')
$$;

-- ---------------------------------------------------------------------
-- Trigger genérico
-- ---------------------------------------------------------------------
-- Uso: create trigger auditar after insert or update on <tabla>
--        for each row execute function auditoria.registrar('<columna_id>');
create or replace function auditoria.registrar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_columna_id text := coalesce(tg_argv[0], 'id');
  v_antes      jsonb;
  v_despues    jsonb := to_jsonb(new);
  v_cambios    jsonb;
  v_accion     text;
begin
  if tg_op = 'INSERT' then
    v_accion := 'creacion';
    v_cambios := v_despues;
  else
    v_antes := to_jsonb(old);
    v_cambios := auditoria.diferencias(v_antes, v_despues);

    if v_cambios = '{}'::jsonb then
      return new;  -- no cambió nada relevante
    end if;

    v_accion := case
      when v_cambios ? 'eliminado_en' and (v_despues ->> 'eliminado_en') is not null then 'eliminacion'
      when v_cambios ? 'eliminado_en' then 'restauracion'
      when v_cambios ? 'estado' and (v_despues ->> 'estado') in ('anulada', 'anulado') then 'anulacion'
      when v_cambios ? 'activo' and (v_despues ->> 'activo')::boolean is false then 'deshabilitacion'
      when v_cambios ? 'activo' then 'habilitacion'
      else 'edicion'
    end;
  end if;

  insert into auditoria.bitacora (esquema, tabla, registro_id, accion, cambios, usuario_id)
  values (tg_table_schema, tg_table_name, v_despues ->> v_columna_id, v_accion, v_cambios, auth.uid());

  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Inmutabilidad
-- ---------------------------------------------------------------------
create or replace function auditoria.impedir_cambios()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform seguridad.lanzar_error('OPERACION_NO_PERMITIDA', 'La bitácora no se puede modificar ni borrar.');
  return null;
end;
$$;

create trigger bitacora_inmutable
  before update or delete on auditoria.bitacora
  for each row execute function auditoria.impedir_cambios();

create trigger bitacora_sin_truncate
  before truncate on auditoria.bitacora
  for each statement execute function auditoria.impedir_cambios();

-- ---------------------------------------------------------------------
-- Acceso: solo lectura con bitacora.ver, mediante una vista
-- ---------------------------------------------------------------------
alter table auditoria.bitacora enable row level security;

create policy bitacora_ver on auditoria.bitacora
  for select to authenticated
  using (seguridad.tiene_permiso('bitacora.ver'));

create view auditoria.v_bitacora
with (security_invoker = true) as
select b.id, b.esquema, b.tabla, b.registro_id, b.accion, b.cambios,
       b.usuario_id, p.nombre_completo as usuario, b.fecha
from auditoria.bitacora b
left join seguridad.perfiles p on p.id = b.usuario_id;

comment on view auditoria.v_bitacora is 'Bitácora con el nombre de quien hizo cada cambio.';

revoke all on all tables in schema auditoria from public, anon, authenticated;
grant select on auditoria.bitacora, auditoria.v_bitacora to authenticated;
revoke all on all functions in schema auditoria from public, anon, authenticated;

-- Tamaño de las tablas, para vigilar el límite del plan gratis.
create or replace view auditoria.v_tamano_tablas as
select n.nspname as esquema,
       c.relname as tabla,
       pg_total_relation_size(c.oid) as bytes,
       pg_size_pretty(pg_total_relation_size(c.oid)) as tamano
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where c.relkind = 'r'
  and n.nspname in ('seguridad', 'catalogo', 'ventas', 'inventario', 'auditoria')
order by bytes desc;

revoke all on auditoria.v_tamano_tablas from public, anon, authenticated;
