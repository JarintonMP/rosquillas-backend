-- =====================================================================
-- Seguridad: perfiles de la familia, roles y permisos como datos.
-- Ver docs/DISENO_BD.md, secciones 4 y 6.1 a 6.3.
--
-- Principios:
--   * Fail-closed: sin perfil activo o sin permiso, la respuesta es "no".
--   * La identidad sale siempre de auth.uid(), nunca de lo que mande la app.
--   * Los permisos se dan a roles, no a personas.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Formato único de errores
-- ---------------------------------------------------------------------
-- Todas las funciones lanzan errores con:
--   message = texto en español para mostrar a la persona
--   detail  = código estable para la app (SIN_PERMISO, DATOS_INVALIDOS…)
-- SIN_PERMISO usa el SQLSTATE 42501 para que la API responda 403.
create or replace function seguridad.lanzar_error(p_codigo text, p_mensaje text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  if p_codigo = 'SIN_PERMISO' then
    raise exception using message = p_mensaje, detail = p_codigo, errcode = '42501';
  else
    raise exception using message = p_mensaje, detail = p_codigo, errcode = 'P0001';
  end if;
end;
$$;

comment on function seguridad.lanzar_error(text, text) is
  'Lanza un error con el formato único del proyecto: mensaje en español y código en detail.';

-- ---------------------------------------------------------------------
-- Catálogo de roles y permisos
-- ---------------------------------------------------------------------
create table seguridad.roles (
  codigo      text primary key check (codigo ~ '^[a-z_]+$'),
  nombre      text not null,
  descripcion text not null,
  es_base     boolean not null default true
);

comment on table seguridad.roles is 'Roles de la aplicación. Los roles base no se pueden borrar.';

create table seguridad.permisos (
  codigo      text primary key check (codigo ~ '^[a-z_]+\.[a-z_]+$'),
  modulo      text not null,
  descripcion text not null
);

comment on table seguridad.permisos is 'Permisos finos con formato modulo.accion.';

create table seguridad.rol_permisos (
  rol     text not null references seguridad.roles (codigo) on update cascade on delete restrict,
  permiso text not null references seguridad.permisos (codigo) on update cascade on delete restrict,
  primary key (rol, permiso)
);

comment on table seguridad.rol_permisos is 'Matriz de permisos: qué puede hacer cada rol.';

-- ---------------------------------------------------------------------
-- Perfiles (solo familia; clientes y proveedores no inician sesión)
-- ---------------------------------------------------------------------
create table seguridad.perfiles (
  id              uuid primary key references auth.users (id) on delete restrict,
  nombre_completo text not null check (length(btrim(nombre_completo)) between 3 and 120),
  rol             text not null default 'familiar' references seguridad.roles (codigo) on update cascade,
  activo          boolean not null default false,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  actualizado_por uuid
);

comment on table seguridad.perfiles is
  'Usuarios de la familia. Un perfil nuevo nace inactivo con rol familiar hasta que el super admin lo activa.';

create index perfiles_rol_idx on seguridad.perfiles (rol) where activo;

-- Al crear un usuario en Supabase Auth se crea su perfil, inactivo (fail-closed).
create or replace function seguridad.crear_perfil_de_usuario()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into seguridad.perfiles (id, nombre_completo)
  values (
    new.id,
    coalesce(nullif(btrim(new.raw_user_meta_data ->> 'nombre_completo'), ''), split_part(coalesce(new.email, 'Usuario nuevo'), '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger al_crear_usuario
  after insert on auth.users
  for each row execute function seguridad.crear_perfil_de_usuario();

-- ---------------------------------------------------------------------
-- Funciones de autorización
-- ---------------------------------------------------------------------
create or replace function seguridad.rol_actual()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.rol
  from seguridad.perfiles p
  where p.id = auth.uid()
    and p.activo
$$;

comment on function seguridad.rol_actual() is
  'Rol del usuario de la petición, o null si no tiene perfil activo.';

create or replace function seguridad.tiene_permiso(p_permiso text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((
    select true
    from seguridad.perfiles p
    join seguridad.rol_permisos rp on rp.rol = p.rol
    where p.id = auth.uid()
      and p.activo
      and rp.permiso = p_permiso
  ), false)
$$;

comment on function seguridad.tiene_permiso(text) is
  'Devuelve true solo si el usuario tiene perfil activo y su rol tiene el permiso. Ante cualquier duda, false.';

create or replace function seguridad.exigir_permiso(p_permiso text)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not seguridad.tiene_permiso(p_permiso) then
    perform seguridad.lanzar_error('SIN_PERMISO', 'No tiene permiso para realizar esta acción.');
  end if;
end;
$$;

create or replace function seguridad.mis_permisos()
returns setof text
language sql
stable
security definer
set search_path = ''
as $$
  select rp.permiso
  from seguridad.perfiles p
  join seguridad.rol_permisos rp on rp.rol = p.rol
  where p.id = auth.uid()
    and p.activo
  order by 1
$$;

comment on function seguridad.mis_permisos() is
  'Permisos del usuario actual, para que la app muestre u oculte opciones. La seguridad real la hace la base.';

-- ---------------------------------------------------------------------
-- Gestión de usuarios (solo con usuarios.gestionar)
-- ---------------------------------------------------------------------
create or replace function seguridad.actualizar_perfil(
  p_usuario_id uuid,
  p_rol text,
  p_activo boolean,
  p_nombre_completo text default null
)
returns seguridad.perfiles
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil seguridad.perfiles;
  v_super_admins_restantes int;
begin
  perform seguridad.exigir_permiso('usuarios.gestionar');

  if p_usuario_id = auth.uid() and (p_rol <> 'super_admin' or not p_activo) then
    perform seguridad.lanzar_error('OPERACION_NO_PERMITIDA',
      'No puede quitarse a sí mismo el rol de super admin ni desactivar su propia cuenta.');
  end if;

  if not exists (select 1 from seguridad.roles where codigo = p_rol) then
    perform seguridad.lanzar_error('DATOS_INVALIDOS', 'El rol indicado no existe.');
  end if;

  update seguridad.perfiles
     set rol = p_rol,
         activo = p_activo,
         nombre_completo = coalesce(nullif(btrim(p_nombre_completo), ''), nombre_completo)
   where id = p_usuario_id
  returning * into v_perfil;

  if v_perfil.id is null then
    perform seguridad.lanzar_error('NO_ENCONTRADO', 'El usuario no existe.');
  end if;

  select count(*) into v_super_admins_restantes
  from seguridad.perfiles
  where rol = 'super_admin' and activo;

  if v_super_admins_restantes = 0 then
    perform seguridad.lanzar_error('OPERACION_NO_PERMITIDA', 'Debe quedar al menos un super admin activo.');
  end if;

  return v_perfil;
end;
$$;

comment on function seguridad.actualizar_perfil(uuid, text, boolean, text) is
  'Cambia rol, estado o nombre de un usuario. Protege que siempre quede un super admin activo.';

-- ---------------------------------------------------------------------
-- Columnas de control (quién y cuándo) para todas las tablas editables
-- ---------------------------------------------------------------------
create or replace function seguridad.fijar_columnas_control()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    new.creado_en := now();
    new.creado_por := auth.uid();
  else
    new.creado_en := old.creado_en;
    new.creado_por := old.creado_por;
  end if;
  new.actualizado_en := now();
  new.actualizado_por := auth.uid();
  return new;
end;
$$;

create or replace function seguridad.fijar_actualizacion_perfil()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.creado_en := old.creado_en;
  new.actualizado_en := now();
  new.actualizado_por := auth.uid();
  return new;
end;
$$;

create trigger control_perfiles
  before update on seguridad.perfiles
  for each row execute function seguridad.fijar_actualizacion_perfil();

-- ---------------------------------------------------------------------
-- RLS y privilegios
-- ---------------------------------------------------------------------
alter table seguridad.roles        enable row level security;
alter table seguridad.permisos     enable row level security;
alter table seguridad.rol_permisos enable row level security;
alter table seguridad.perfiles     enable row level security;

create policy roles_ver on seguridad.roles
  for select to authenticated using (seguridad.rol_actual() is not null);

create policy permisos_ver on seguridad.permisos
  for select to authenticated using (seguridad.rol_actual() is not null);

create policy rol_permisos_ver on seguridad.rol_permisos
  for select to authenticated using (seguridad.rol_actual() is not null);

-- Cada quien ve su propio perfil (aunque esté inactivo, para que la app
-- muestre "su cuenta está pendiente de activación"). Quien gestiona
-- usuarios ve todos.
create policy perfiles_ver on seguridad.perfiles
  for select to authenticated
  using (id = auth.uid() or seguridad.tiene_permiso('usuarios.gestionar'));

-- Sin políticas de INSERT, UPDATE ni DELETE: los cambios pasan por
-- seguridad.actualizar_perfil().
revoke all on all tables in schema seguridad from public, anon, authenticated;
grant select on all tables in schema seguridad to authenticated;

revoke all on all functions in schema seguridad from public, anon;
grant execute on function seguridad.rol_actual()        to authenticated;
grant execute on function seguridad.tiene_permiso(text) to authenticated;
grant execute on function seguridad.mis_permisos()      to authenticated;
grant execute on function seguridad.exigir_permiso(text) to authenticated;
grant execute on function seguridad.lanzar_error(text, text) to authenticated;
grant execute on function seguridad.actualizar_perfil(uuid, text, boolean, text) to authenticated;
