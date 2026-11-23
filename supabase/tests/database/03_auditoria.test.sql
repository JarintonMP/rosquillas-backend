-- Pruebas de la bitácora: guarda solo lo que cambió, es inmutable y solo la ve quien tiene permiso.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = extensions, public;

select plan(6);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000d2', 'admin@ejemplo.cr'),
  ('00000000-0000-0000-0000-0000000000d3', 'familia@ejemplo.cr');
update seguridad.perfiles set rol = 'admin',    activo = true where id = '00000000-0000-0000-0000-0000000000d2';
update seguridad.perfiles set rol = 'familiar', activo = true where id = '00000000-0000-0000-0000-0000000000d3';

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000d2"}', true);

insert into catalogo.productos (id, nombre, clase, unidad, precio_venta)
values ('00000000-0000-0000-0000-0000000000e1', 'Producto de prueba de bitácora', 'producto_terminado', 'unidad', 700);
update catalogo.productos set precio_venta = 800 where id = '00000000-0000-0000-0000-0000000000e1';

select results_eq(
  $$ select accion, cambios from auditoria.bitacora
     where tabla = 'productos' and registro_id = '00000000-0000-0000-0000-0000000000e1' and accion = 'edicion' $$,
  $$ values ('edicion'::text, '{"precio_venta": {"antes": 700, "despues": 800}}'::jsonb) $$,
  'Una edición guarda solo la columna que cambió'
);

select is(
  (select usuario from auditoria.v_bitacora
   where registro_id = '00000000-0000-0000-0000-0000000000e1' and accion = 'creacion'),
  'admin',
  'La bitácora muestra quién hizo el cambio'
);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000d3"}', true);
select is(
  (select count(*)::int from auditoria.v_bitacora),
  0,
  'Un familiar no ve la bitácora'
);

select throws_ok(
  $$ delete from auditoria.bitacora $$,
  '42501', null,
  'La app no puede borrar la bitácora'
);

reset role;
select throws_ok(
  $$ update auditoria.bitacora set accion = 'edicion' $$,
  'P0001', 'La bitácora no se puede modificar ni borrar.',
  'Ni el dueño de la base puede editar la bitácora'
);

select throws_ok(
  $$ delete from auditoria.bitacora $$,
  'P0001', 'La bitácora no se puede modificar ni borrar.',
  'Ni el dueño de la base puede borrar la bitácora'
);

select * from finish();
rollback;
