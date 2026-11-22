-- =====================================================================
-- Catálogo: personas (físicas y jurídicas), clientes, proveedores y productos.
-- Ver docs/DISENO_BD.md, secciones 1.2, 1.3 y 3.
--
-- * Supertipo "personas" con dos roles: clientes y proveedores.
--   Una misma persona puede ser cliente y proveedor sin duplicarse.
-- * Deshabilitar = activo false. Borrar = eliminado_en (borrado lógico,
--   solo con catalogo.eliminar). Nunca hay DELETE físico.
-- * Las validaciones de identidad son las de Costa Rica y deben ser
--   idénticas a src/lib/validaciones.ts del frontend.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Validaciones reutilizables (una sola fuente por regla)
-- ---------------------------------------------------------------------
create or replace function catalogo.identificacion_valida(p_tipo text, p_numero text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case p_tipo
    when 'cedula_fisica'   then p_numero ~ '^[1-9][0-9]{8}$'
    when 'cedula_juridica' then p_numero ~ '^[0-9]{10}$'
    when 'dimex'           then p_numero ~ '^[0-9]{11,12}$'
    when 'ninguna'         then p_numero is null
    else false
  end
$$;

comment on function catalogo.identificacion_valida(text, text) is
  'Cédula física: 9 dígitos sin cero inicial. Jurídica: 10 dígitos. DIMEX: 11 o 12 dígitos.';

create or replace function catalogo.telefono_valido(p_telefono text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_telefono is null or p_telefono ~ '^[245678][0-9]{7}$'
$$;

comment on function catalogo.telefono_valido(text) is
  'Teléfono de Costa Rica de 8 dígitos, sin guiones ni +506 (la app lo normaliza).';

create or replace function catalogo.correo_valido(p_correo text)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_correo is null or p_correo ~* '^[^@\s]+@[^@\s]+\.[a-z]{2,}$'
$$;

-- ---------------------------------------------------------------------
-- Personas
-- ---------------------------------------------------------------------
create table catalogo.personas (
  id                    uuid primary key default gen_random_uuid(),
  tipo_persona          text not null check (tipo_persona in ('fisica', 'juridica')),
  tipo_identificacion   text not null default 'ninguna'
                          check (tipo_identificacion in ('cedula_fisica', 'cedula_juridica', 'dimex', 'ninguna')),
  numero_identificacion text,
  nombre                text check (nombre is null or length(btrim(nombre)) between 2 and 80),
  apellidos             text check (apellidos is null or length(btrim(apellidos)) between 2 and 80),
  razon_social          text check (razon_social is null or length(btrim(razon_social)) between 2 and 150),
  nombre_comercial      text check (nombre_comercial is null or length(btrim(nombre_comercial)) between 2 and 150),
  telefono              text,
  correo                text,
  direccion             text check (direccion is null or length(direccion) <= 300),
  notas                 text check (notas is null or length(notas) <= 500),
  activo                boolean not null default true,
  eliminado_en          timestamptz,
  creado_en             timestamptz not null default now(),
  creado_por            uuid,
  actualizado_en        timestamptz not null default now(),
  actualizado_por       uuid,

  constraint personas_identificacion_valida
    check (catalogo.identificacion_valida(tipo_identificacion, numero_identificacion)),
  constraint personas_identificacion_segun_tipo
    check (
      (tipo_persona = 'fisica'   and tipo_identificacion in ('cedula_fisica', 'dimex', 'ninguna'))
      or (tipo_persona = 'juridica' and tipo_identificacion in ('cedula_juridica', 'ninguna'))
    ),
  constraint personas_nombre_segun_tipo
    check (
      (tipo_persona = 'fisica'   and nombre is not null and razon_social is null)
      or (tipo_persona = 'juridica' and razon_social is not null and nombre is null and apellidos is null)
    ),
  constraint personas_telefono_valido check (catalogo.telefono_valido(telefono)),
  constraint personas_correo_valido   check (catalogo.correo_valido(correo))
);

comment on table catalogo.personas is
  'Datos de identidad de clientes y proveedores, físicos o jurídicos. No son usuarios de la app.';

create unique index personas_identificacion_unica
  on catalogo.personas (tipo_identificacion, numero_identificacion)
  where numero_identificacion is not null and eliminado_en is null;

create index personas_busqueda_idx
  on catalogo.personas (lower(coalesce(nombre_comercial, razon_social, nombre || ' ' || coalesce(apellidos, ''))))
  where eliminado_en is null;

-- ---------------------------------------------------------------------
-- Roles de persona: clientes y proveedores
-- ---------------------------------------------------------------------
create table catalogo.clientes (
  persona_id         uuid primary key references catalogo.personas (id) on delete restrict,
  credito_habilitado boolean not null default false,
  limite_credito     bigint check (limite_credito is null or limite_credito > 0),
  activo             boolean not null default true,
  eliminado_en       timestamptz,
  creado_en          timestamptz not null default now(),
  creado_por         uuid,
  actualizado_en     timestamptz not null default now(),
  actualizado_por    uuid,

  constraint clientes_limite_solo_con_credito
    check (limite_credito is null or credito_habilitado)
);

comment on table catalogo.clientes is
  'Rol de cliente. Recurrente o casual se calcula por frecuencia; el esporádico es una venta sin cliente.';
comment on column catalogo.clientes.limite_credito is 'En colones. Null = sin límite (si el crédito está habilitado).';

create table catalogo.proveedores (
  persona_id      uuid primary key references catalogo.personas (id) on delete restrict,
  activo          boolean not null default true,
  eliminado_en    timestamptz,
  creado_en       timestamptz not null default now(),
  creado_por      uuid,
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid
);

comment on table catalogo.proveedores is 'Rol de proveedor.';

-- ---------------------------------------------------------------------
-- Productos (insumos y producto terminado)
-- ---------------------------------------------------------------------
create table catalogo.productos (
  id              uuid primary key default gen_random_uuid(),
  nombre          text not null check (length(btrim(nombre)) between 2 and 80),
  clase           text not null check (clase in ('insumo', 'producto_terminado')),
  unidad          text not null check (unidad in ('unidad', 'kg', 'g', 'l', 'ml', 'paquete')),
  precio_venta    bigint check (precio_venta is null or precio_venta > 0),
  stock_minimo    numeric(12, 3) not null default 0 check (stock_minimo >= 0),
  activo          boolean not null default true,
  eliminado_en    timestamptz,
  creado_en       timestamptz not null default now(),
  creado_por      uuid,
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid,

  constraint productos_precio_si_se_vende
    check (clase <> 'producto_terminado' or precio_venta is not null)
);

comment on table catalogo.productos is 'Insumos (se compran) y productos terminados (se producen y venden).';
comment on column catalogo.productos.precio_venta is 'En colones enteros. Obligatorio para producto terminado.';

create unique index productos_nombre_unico
  on catalogo.productos (lower(btrim(nombre)))
  where eliminado_en is null;

create table catalogo.proveedor_productos (
  proveedor_id  uuid not null references catalogo.proveedores (persona_id) on delete restrict,
  producto_id   uuid not null references catalogo.productos (id) on delete restrict,
  ultimo_costo  bigint check (ultimo_costo is null or ultimo_costo > 0),
  creado_en       timestamptz not null default now(),
  creado_por      uuid,
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid,
  primary key (proveedor_id, producto_id)
);

comment on table catalogo.proveedor_productos is 'Qué productos entrega cada proveedor (N a N).';

create index proveedor_productos_producto_idx on catalogo.proveedor_productos (producto_id);

-- ---------------------------------------------------------------------
-- Reglas de deshabilitar y borrar
-- ---------------------------------------------------------------------
create or replace function catalogo.validar_cambio_estado()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Borrar o restaurar: solo con catalogo.eliminar (super admin).
  if new.eliminado_en is distinct from old.eliminado_en then
    perform seguridad.exigir_permiso('catalogo.eliminar');
    if new.eliminado_en is not null then
      new.eliminado_en := now();
      new.activo := false;
    end if;
  -- Un registro borrado no se edita: primero hay que restaurarlo.
  elsif old.eliminado_en is not null then
    perform seguridad.lanzar_error('OPERACION_NO_PERMITIDA',
      'Este registro fue eliminado. Restáurelo antes de editarlo.');
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- Triggers: columnas de control, estado y auditoría
-- ---------------------------------------------------------------------
create trigger control before insert or update on catalogo.personas
  for each row execute function seguridad.fijar_columnas_control();
create trigger control before insert or update on catalogo.clientes
  for each row execute function seguridad.fijar_columnas_control();
create trigger control before insert or update on catalogo.proveedores
  for each row execute function seguridad.fijar_columnas_control();
create trigger control before insert or update on catalogo.productos
  for each row execute function seguridad.fijar_columnas_control();
create trigger control before insert or update on catalogo.proveedor_productos
  for each row execute function seguridad.fijar_columnas_control();

create trigger validar_estado before update on catalogo.personas
  for each row execute function catalogo.validar_cambio_estado();
create trigger validar_estado before update on catalogo.clientes
  for each row execute function catalogo.validar_cambio_estado();
create trigger validar_estado before update on catalogo.proveedores
  for each row execute function catalogo.validar_cambio_estado();
create trigger validar_estado before update on catalogo.productos
  for each row execute function catalogo.validar_cambio_estado();

create trigger auditar after insert or update on catalogo.personas
  for each row execute function auditoria.registrar('id');
create trigger auditar after insert or update on catalogo.clientes
  for each row execute function auditoria.registrar('persona_id');
create trigger auditar after insert or update on catalogo.proveedores
  for each row execute function auditoria.registrar('persona_id');
create trigger auditar after insert or update on catalogo.productos
  for each row execute function auditoria.registrar('id');
create trigger auditar after insert or update on catalogo.proveedor_productos
  for each row execute function auditoria.registrar('producto_id');

-- ---------------------------------------------------------------------
-- Crear cliente o proveedor en una sola transacción
-- ---------------------------------------------------------------------
-- p_persona es un objeto JSON con las columnas de catalogo.personas.
-- Si trae "id", se usa (la app lo genera para poder trabajar sin internet).
create or replace function catalogo.guardar_persona(p_persona jsonb)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid := coalesce((p_persona ->> 'id')::uuid, gen_random_uuid());
begin
  insert into catalogo.personas (
    id, tipo_persona, tipo_identificacion, numero_identificacion,
    nombre, apellidos, razon_social, nombre_comercial,
    telefono, correo, direccion, notas
  )
  values (
    v_id,
    p_persona ->> 'tipo_persona',
    coalesce(p_persona ->> 'tipo_identificacion', 'ninguna'),
    nullif(btrim(p_persona ->> 'numero_identificacion'), ''),
    nullif(btrim(p_persona ->> 'nombre'), ''),
    nullif(btrim(p_persona ->> 'apellidos'), ''),
    nullif(btrim(p_persona ->> 'razon_social'), ''),
    nullif(btrim(p_persona ->> 'nombre_comercial'), ''),
    nullif(btrim(p_persona ->> 'telefono'), ''),
    nullif(lower(btrim(p_persona ->> 'correo')), ''),
    nullif(btrim(p_persona ->> 'direccion'), ''),
    nullif(btrim(p_persona ->> 'notas'), '')
  )
  on conflict (id) do nothing;
  return v_id;
exception
  when unique_violation then
    perform seguridad.lanzar_error('DUPLICADO', 'Ya existe una persona con esa identificación.');
  when check_violation then
    perform seguridad.lanzar_error('DATOS_INVALIDOS', 'Revise los datos de la persona: ' || sqlerrm);
end;
$$;

create or replace function catalogo.crear_cliente(
  p_persona jsonb,
  p_credito_habilitado boolean default false,
  p_limite_credito bigint default null
)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform seguridad.exigir_permiso('catalogo.gestionar');
  v_id := catalogo.guardar_persona(p_persona);
  insert into catalogo.clientes (persona_id, credito_habilitado, limite_credito)
  values (v_id, p_credito_habilitado, p_limite_credito)
  on conflict (persona_id) do nothing;
  return v_id;
exception
  when check_violation then
    perform seguridad.lanzar_error('DATOS_INVALIDOS',
      'El límite de crédito debe ser mayor que cero y solo aplica si el crédito está habilitado.');
end;
$$;

comment on function catalogo.crear_cliente(jsonb, boolean, bigint) is
  'Crea la persona y su rol de cliente en una transacción. Idempotente si se reenvía el mismo id (sincronización).';

create or replace function catalogo.crear_proveedor(p_persona jsonb)
returns uuid
language plpgsql
set search_path = ''
as $$
declare
  v_id uuid;
begin
  perform seguridad.exigir_permiso('catalogo.gestionar');
  v_id := catalogo.guardar_persona(p_persona);
  insert into catalogo.proveedores (persona_id) values (v_id)
  on conflict (persona_id) do nothing;
  return v_id;
end;
$$;

comment on function catalogo.crear_proveedor(jsonb) is
  'Crea la persona y su rol de proveedor en una transacción. Si la persona ya existe (mismo id), solo agrega el rol.';

-- ---------------------------------------------------------------------
-- Vistas para la app (respetan RLS con security_invoker)
-- ---------------------------------------------------------------------
create view catalogo.v_clientes
with (security_invoker = true) as
select c.persona_id as id,
       p.tipo_persona,
       p.tipo_identificacion,
       p.numero_identificacion,
       case p.tipo_persona
         when 'fisica' then btrim(p.nombre || ' ' || coalesce(p.apellidos, ''))
         else coalesce(p.nombre_comercial, p.razon_social)
       end as nombre_mostrado,
       p.nombre, p.apellidos, p.razon_social, p.nombre_comercial,
       p.telefono, p.correo, p.direccion, p.notas,
       c.credito_habilitado, c.limite_credito,
       (c.activo and p.activo) as activo,
       coalesce(c.eliminado_en, p.eliminado_en) as eliminado_en
from catalogo.clientes c
join catalogo.personas p on p.id = c.persona_id;

create view catalogo.v_proveedores
with (security_invoker = true) as
select pr.persona_id as id,
       p.tipo_persona,
       p.tipo_identificacion,
       p.numero_identificacion,
       case p.tipo_persona
         when 'fisica' then btrim(p.nombre || ' ' || coalesce(p.apellidos, ''))
         else coalesce(p.nombre_comercial, p.razon_social)
       end as nombre_mostrado,
       p.nombre, p.apellidos, p.razon_social, p.nombre_comercial,
       p.telefono, p.correo, p.direccion, p.notas,
       (pr.activo and p.activo) as activo,
       coalesce(pr.eliminado_en, p.eliminado_en) as eliminado_en
from catalogo.proveedores pr
join catalogo.personas p on p.id = pr.persona_id;

-- ---------------------------------------------------------------------
-- RLS
-- ---------------------------------------------------------------------
alter table catalogo.personas            enable row level security;
alter table catalogo.clientes            enable row level security;
alter table catalogo.proveedores         enable row level security;
alter table catalogo.productos           enable row level security;
alter table catalogo.proveedor_productos enable row level security;

-- Ver: con catalogo.ver. Los eliminados solo los ve quien puede eliminar.
create policy ver on catalogo.personas for select to authenticated
  using (seguridad.tiene_permiso('catalogo.ver')
         and (eliminado_en is null or seguridad.tiene_permiso('catalogo.eliminar')));
create policy ver on catalogo.clientes for select to authenticated
  using (seguridad.tiene_permiso('catalogo.ver')
         and (eliminado_en is null or seguridad.tiene_permiso('catalogo.eliminar')));
create policy ver on catalogo.proveedores for select to authenticated
  using (seguridad.tiene_permiso('catalogo.ver')
         and (eliminado_en is null or seguridad.tiene_permiso('catalogo.eliminar')));
create policy ver on catalogo.productos for select to authenticated
  using (seguridad.tiene_permiso('catalogo.ver')
         and (eliminado_en is null or seguridad.tiene_permiso('catalogo.eliminar')));
create policy ver on catalogo.proveedor_productos for select to authenticated
  using (seguridad.tiene_permiso('catalogo.ver'));

-- Crear y editar: con catalogo.gestionar. Sin políticas de DELETE.
create policy crear on catalogo.personas for insert to authenticated
  with check (seguridad.tiene_permiso('catalogo.gestionar'));
create policy editar on catalogo.personas for update to authenticated
  using (seguridad.tiene_permiso('catalogo.gestionar'))
  with check (seguridad.tiene_permiso('catalogo.gestionar'));

create policy crear on catalogo.clientes for insert to authenticated
  with check (seguridad.tiene_permiso('catalogo.gestionar'));
create policy editar on catalogo.clientes for update to authenticated
  using (seguridad.tiene_permiso('catalogo.gestionar'))
  with check (seguridad.tiene_permiso('catalogo.gestionar'));

create policy crear on catalogo.proveedores for insert to authenticated
  with check (seguridad.tiene_permiso('catalogo.gestionar'));
create policy editar on catalogo.proveedores for update to authenticated
  using (seguridad.tiene_permiso('catalogo.gestionar'))
  with check (seguridad.tiene_permiso('catalogo.gestionar'));

create policy crear on catalogo.productos for insert to authenticated
  with check (seguridad.tiene_permiso('catalogo.gestionar'));
create policy editar on catalogo.productos for update to authenticated
  using (seguridad.tiene_permiso('catalogo.gestionar'))
  with check (seguridad.tiene_permiso('catalogo.gestionar'));

create policy crear on catalogo.proveedor_productos for insert to authenticated
  with check (seguridad.tiene_permiso('catalogo.gestionar'));
create policy editar on catalogo.proveedor_productos for update to authenticated
  using (seguridad.tiene_permiso('catalogo.gestionar'))
  with check (seguridad.tiene_permiso('catalogo.gestionar'));

-- ---------------------------------------------------------------------
-- Privilegios: nunca DELETE ni TRUNCATE desde la app
-- ---------------------------------------------------------------------
revoke all on all tables in schema catalogo from public, anon, authenticated;
grant select, insert, update on
  catalogo.personas, catalogo.clientes, catalogo.proveedores,
  catalogo.productos, catalogo.proveedor_productos
  to authenticated;
grant select on catalogo.v_clientes, catalogo.v_proveedores to authenticated;

revoke all on all functions in schema catalogo from public, anon;
grant execute on function catalogo.identificacion_valida(text, text) to authenticated;
grant execute on function catalogo.telefono_valido(text)              to authenticated;
grant execute on function catalogo.correo_valido(text)                to authenticated;
grant execute on function catalogo.guardar_persona(jsonb)             to authenticated;
grant execute on function catalogo.crear_cliente(jsonb, boolean, bigint) to authenticated;
grant execute on function catalogo.crear_proveedor(jsonb)             to authenticated;
