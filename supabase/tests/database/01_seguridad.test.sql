-- Pruebas de seguridad: esquemas, RLS, perfiles, roles y permisos.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(18);

-- ---------------------------------------------------------------------
-- Estructura
-- ---------------------------------------------------------------------
select has_schema('seguridad');
select has_schema('catalogo');
select has_schema('ventas');
select has_schema('inventario');
select has_schema('auditoria');

select is(
  (select count(*)::int
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where c.relkind = 'r'
     and n.nspname in ('seguridad', 'catalogo', 'ventas', 'inventario', 'auditoria')
     and not c.relrowsecurity),
  0,
  'Todas las tablas tienen RLS activo (fail-closed)'
);

select is(
  (select count(*)::int from seguridad.rol_permisos where rol = 'super_admin'),
  (select count(*)::int from seguridad.permisos),
  'El super admin tiene todos los permisos'
);

-- ---------------------------------------------------------------------
-- Usuarios de prueba
-- ---------------------------------------------------------------------
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000a1', 'jefe@ejemplo.cr',    '{"nombre_completo": "Jefe de Prueba"}'),
  ('00000000-0000-0000-0000-0000000000a2', 'admin@ejemplo.cr',   null),
  ('00000000-0000-0000-0000-0000000000a3', 'familia@ejemplo.cr', null);

select results_eq(
  $$ select nombre_completo, rol, activo from seguridad.perfiles
     where id = '00000000-0000-0000-0000-0000000000a1' $$,
  $$ values ('Jefe de Prueba'::text, 'familiar'::text, false) $$,
  'Un usuario nuevo nace con perfil inactivo y rol familiar'
);

-- Activación inicial (la hace el dueño desde el panel SQL de Supabase).
update seguridad.perfiles set rol = 'super_admin', activo = true where id = '00000000-0000-0000-0000-0000000000a1';
update seguridad.perfiles set rol = 'admin', activo = true where id = '00000000-0000-0000-0000-0000000000a2';

-- ---------------------------------------------------------------------
-- Sin sesión o con cuenta inactiva: todo es "no"
-- ---------------------------------------------------------------------
set local role authenticated;
select set_config('request.jwt.claims', '', true);
select is(seguridad.tiene_permiso('catalogo.ver'), false, 'Sin sesión no hay permisos');

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a3"}', true);
select is(seguridad.tiene_permiso('catalogo.ver'), false, 'Con la cuenta inactiva no hay permisos');
select is(
  (select count(*)::int from seguridad.perfiles),
  1,
  'Un usuario sin permisos solo ve su propio perfil'
);

select throws_ok(
  $$ update seguridad.perfiles set activo = true where id = auth.uid() $$,
  '42501', null,
  'Nadie puede activarse a sí mismo editando la tabla'
);

-- ---------------------------------------------------------------------
-- Gestión de usuarios
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a2"}', true);
select throws_ok(
  $$ select seguridad.actualizar_perfil('00000000-0000-0000-0000-0000000000a3', 'familiar', true) $$,
  '42501', null,
  'Un admin no puede gestionar usuarios'
);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a1"}', true);
select lives_ok(
  $$ select seguridad.actualizar_perfil('00000000-0000-0000-0000-0000000000a3', 'familiar', true) $$,
  'El super admin activa a un familiar'
);

select throws_ok(
  $$ select seguridad.actualizar_perfil('00000000-0000-0000-0000-0000000000a1', 'admin', true) $$,
  'P0001', null,
  'El super admin no puede quitarse su propio rol'
);

-- ---------------------------------------------------------------------
-- Matriz del familiar
-- ---------------------------------------------------------------------
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a3"}', true);
select ok(seguridad.tiene_permiso('saldos_clientes.ver'), 'El familiar ve los saldos de los clientes');
select ok(not seguridad.tiene_permiso('saldos_proveedores.ver'), 'El familiar no ve los saldos con proveedores');
select ok(not seguridad.tiene_permiso('catalogo.gestionar'), 'El familiar no gestiona el catálogo');

reset role;
select * from finish();
rollback;
