-- =====================================================================
-- Esquemas por área (equivalente a los filegroups de SQL Server).
-- Ver docs/DISENO_BD.md, sección 6.4.
-- =====================================================================

create schema if not exists seguridad;
create schema if not exists catalogo;
create schema if not exists ventas;
create schema if not exists inventario;
create schema if not exists auditoria;

comment on schema seguridad  is 'Usuarios de la familia, roles y permisos.';
comment on schema catalogo   is 'Personas, clientes, proveedores y productos.';
comment on schema ventas     is 'Ventas, cobros y cuentas de clientes.';
comment on schema inventario is 'Compras, producción y movimientos de inventario.';
comment on schema auditoria  is 'Bitácora inmutable de cambios.';

-- Fail-closed: nadie tiene acceso hasta que se le da explícitamente.
revoke all on schema seguridad, catalogo, ventas, inventario, auditoria from public, anon;

-- La app (rol authenticated) puede usar los esquemas expuestos.
-- auditoria NO se expone: se consulta por la vista auditoria.v_bitacora.
grant usage on schema seguridad, catalogo, ventas, inventario to authenticated;
grant usage on schema auditoria to authenticated;
grant usage on schema seguridad, catalogo, ventas, inventario, auditoria to service_role;
