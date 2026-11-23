-- Pruebas del catálogo: validaciones de Costa Rica, deshabilitar, borrado lógico y permisos.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(21);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000b1', 'jefe@ejemplo.cr'),
  ('00000000-0000-0000-0000-0000000000b2', 'admin@ejemplo.cr'),
  ('00000000-0000-0000-0000-0000000000b3', 'familia@ejemplo.cr');
update seguridad.perfiles set rol = 'super_admin', activo = true where id = '00000000-0000-0000-0000-0000000000b1';
update seguridad.perfiles set rol = 'admin',       activo = true where id = '00000000-0000-0000-0000-0000000000b2';
update seguridad.perfiles set rol = 'familiar',    activo = true where id = '00000000-0000-0000-0000-0000000000b3';

-- ---------------------------------------------------------------------
-- Validaciones puras (deben coincidir con src/lib/validaciones.ts)
-- ---------------------------------------------------------------------
select ok(catalogo.identificacion_valida('cedula_fisica', '503450678'),       'Cédula física de 9 dígitos es válida');
select ok(not catalogo.identificacion_valida('cedula_fisica', '012345678'),   'Cédula física no empieza con 0');
select ok(catalogo.identificacion_valida('cedula_juridica', '3101123456'),    'Cédula jurídica de 10 dígitos es válida');
select ok(catalogo.identificacion_valida('dimex', '155812345678'),            'DIMEX de 12 dígitos es válido');
select ok(not catalogo.telefono_valido('1234567'),                            'Teléfono de 7 dígitos no es válido');
select ok(catalogo.telefono_valido('88887777'),                               'Teléfono móvil de 8 dígitos es válido');

-- ---------------------------------------------------------------------
-- Permisos para crear
-- ---------------------------------------------------------------------
set local role authenticated;

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000b3"}', true);
select throws_ok(
  $$ select catalogo.crear_cliente('{"tipo_persona": "fisica", "nombre": "Ana"}') $$,
  '42501', null,
  'Un familiar no puede crear clientes'
);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000b2"}', true);
select is(
  catalogo.crear_cliente(
    '{"id": "00000000-0000-0000-0000-0000000000c1", "tipo_persona": "fisica",
      "tipo_identificacion": "cedula_fisica", "numero_identificacion": "503450678",
      "nombre": "Ana", "apellidos": "Mora Díaz", "telefono": "88887777"}',
    true, 50000),
  '00000000-0000-0000-0000-0000000000c1'::uuid,
  'Un admin crea un cliente físico con crédito'
);

select is(
  catalogo.crear_cliente('{"id": "00000000-0000-0000-0000-0000000000c1", "tipo_persona": "fisica", "nombre": "Ana"}'),
  '00000000-0000-0000-0000-0000000000c1'::uuid,
  'Reenviar el mismo cliente (sincronización) no lo duplica'
);

select throws_ok(
  $$ select catalogo.crear_cliente('{"tipo_persona": "fisica", "tipo_identificacion": "cedula_fisica",
                                     "numero_identificacion": "503450678", "nombre": "Otra"}') $$,
  'P0001', 'Ya existe una persona con esa identificación.',
  'No se repite una cédula'
);

select throws_ok(
  $$ select catalogo.crear_cliente('{"tipo_persona": "juridica", "nombre": "Pulpería"}') $$,
  'P0001', null,
  'Una persona jurídica necesita razón social y no lleva nombre'
);

select throws_ok(
  $$ select catalogo.crear_cliente('{"tipo_persona": "fisica", "nombre": "Luis"}', false, 10000) $$,
  'P0001', null,
  'No hay límite de crédito si el crédito no está habilitado'
);

select lives_ok(
  $$ select catalogo.crear_proveedor('{"id": "00000000-0000-0000-0000-0000000000c1", "tipo_persona": "fisica", "nombre": "Ana"}') $$,
  'La misma persona puede ser también proveedora'
);

select throws_ok(
  $$ insert into catalogo.productos (nombre, clase, unidad) values ('Rosquilla', 'producto_terminado', 'unidad') $$,
  '23514', null,
  'Un producto terminado necesita precio de venta'
);

-- ---------------------------------------------------------------------
-- Deshabilitar y borrado lógico
-- ---------------------------------------------------------------------
update catalogo.clientes set activo = false where persona_id = '00000000-0000-0000-0000-0000000000c1';
select is(
  (select accion from auditoria.bitacora
   where tabla = 'clientes' and registro_id = '00000000-0000-0000-0000-0000000000c1'
   order by id desc limit 1),
  'deshabilitacion',
  'Deshabilitar queda en la bitácora como deshabilitación'
);

select throws_ok(
  $$ update catalogo.clientes set eliminado_en = now() where persona_id = '00000000-0000-0000-0000-0000000000c1' $$,
  '42501', null,
  'Un admin no puede borrar'
);

select throws_ok(
  $$ delete from catalogo.clientes where persona_id = '00000000-0000-0000-0000-0000000000c1' $$,
  '42501', null,
  'Nadie puede borrar físicamente desde la app'
);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000b1"}', true);
update catalogo.clientes set eliminado_en = now() where persona_id = '00000000-0000-0000-0000-0000000000c1';

select throws_ok(
  $$ update catalogo.clientes set credito_habilitado = false where persona_id = '00000000-0000-0000-0000-0000000000c1' $$,
  'P0001', null,
  'Un registro borrado no se edita sin restaurarlo'
);

select is(
  (select count(*)::int from catalogo.v_clientes where id = '00000000-0000-0000-0000-0000000000c1'),
  1,
  'El super admin sigue viendo el cliente borrado (respaldado)'
);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000b2"}', true);
select is(
  (select count(*)::int from catalogo.v_clientes where id = '00000000-0000-0000-0000-0000000000c1'),
  0,
  'El admin ya no ve el cliente borrado'
);

reset role;
select is(
  (select count(*)::int from catalogo.clientes where persona_id = '00000000-0000-0000-0000-0000000000c1'),
  1,
  'El dato sigue en la base después de borrarlo'
);

select * from finish();
rollback;
