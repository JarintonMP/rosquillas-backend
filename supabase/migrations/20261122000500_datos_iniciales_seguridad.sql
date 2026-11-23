-- =====================================================================
-- Datos iniciales de seguridad: roles, permisos y matriz.
-- Van en una migración (no en seed.sql) porque deben existir en todos
-- los ambientes, también en producción.
-- Ver docs/DISENO_BD.md, sección 4 (Permisos).
-- =====================================================================

insert into seguridad.roles (codigo, nombre, descripcion) values
  ('super_admin', 'Super admin', 'Dueño del sistema. Puede todo, incluido borrar registros y gestionar usuarios.'),
  ('admin',       'Admin',       'Familiar de confianza. Gestiona catálogos, anula ventas y ve todos los saldos.'),
  ('familiar',    'Familiar',    'Registra ventas, cobros, compras y producción. Ve clientes y sus saldos.');

insert into seguridad.permisos (codigo, modulo, descripcion) values
  ('catalogo.ver',                'catalogo',   'Ver personas, clientes, proveedores y productos'),
  ('catalogo.gestionar',          'catalogo',   'Crear, editar, deshabilitar y habilitar registros del catálogo'),
  ('catalogo.eliminar',           'catalogo',   'Borrar (lógicamente) y restaurar registros del catálogo'),
  ('ventas.registrar',            'ventas',     'Registrar ventas'),
  ('ventas.anular',               'ventas',     'Anular ventas'),
  ('ventas.revisar',              'ventas',     'Resolver ventas en revisión por falta de stock al sincronizar'),
  ('cobros.registrar',            'ventas',     'Registrar pagos y abonos de clientes'),
  ('cobros.anular',               'ventas',     'Anular cobros'),
  ('saldos_clientes.ver',         'ventas',     'Ver el saldo de los clientes'),
  ('compras.registrar',           'inventario', 'Registrar compras a proveedores'),
  ('compras.anular',              'inventario', 'Anular compras'),
  ('pagos_proveedores.registrar', 'inventario', 'Registrar pagos a proveedores'),
  ('saldos_proveedores.ver',      'inventario', 'Ver el saldo con los proveedores'),
  ('produccion.registrar',        'inventario', 'Registrar tandas de producción'),
  ('recetas.gestionar',           'inventario', 'Crear y editar recetas'),
  ('inventario.ajustar',          'inventario', 'Registrar ajustes manuales de inventario'),
  ('reportes.ver',                'reportes',   'Ver reportes y promedios'),
  ('bitacora.ver',                'auditoria',  'Consultar la bitácora de auditoría'),
  ('usuarios.gestionar',          'seguridad',  'Activar usuarios y cambiar roles');

-- super_admin: todos los permisos.
insert into seguridad.rol_permisos (rol, permiso)
select 'super_admin', codigo from seguridad.permisos;

-- admin: todo menos borrar y gestionar usuarios.
insert into seguridad.rol_permisos (rol, permiso)
select 'admin', codigo from seguridad.permisos
where codigo not in ('catalogo.eliminar', 'usuarios.gestionar');

-- familiar: operación diaria.
insert into seguridad.rol_permisos (rol, permiso) values
  ('familiar', 'catalogo.ver'),
  ('familiar', 'ventas.registrar'),
  ('familiar', 'cobros.registrar'),
  ('familiar', 'saldos_clientes.ver'),
  ('familiar', 'compras.registrar'),
  ('familiar', 'produccion.registrar');

-- Los roles base no se pueden borrar ni renombrar.
create or replace function seguridad.proteger_roles_base()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.es_base and (tg_op = 'DELETE' or new.codigo <> old.codigo) then
    perform seguridad.lanzar_error('OPERACION_NO_PERMITIDA', 'Los roles base no se pueden borrar ni renombrar.');
  end if;
  return coalesce(new, old);
end;
$$;

create trigger proteger_roles_base
  before update or delete on seguridad.roles
  for each row execute function seguridad.proteger_roles_base();

-- Cambios en la matriz de permisos quedan en la bitácora.
create trigger auditar after insert or update on seguridad.perfiles
  for each row execute function auditoria.registrar('id');
create trigger auditar after insert or update on seguridad.rol_permisos
  for each row execute function auditoria.registrar('rol');
