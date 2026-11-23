-- Datos de ejemplo SOLO para desarrollo local (`supabase db reset`).
-- No se cargan en producción.

insert into catalogo.productos (nombre, clase, unidad, precio_venta, stock_minimo) values
  ('Rosquilla',        'producto_terminado', 'unidad', 300, 50),
  ('Tanela',           'producto_terminado', 'unidad', 500, 30),
  ('Empanada',         'producto_terminado', 'unidad', 800, 20),
  ('Harina de maíz',   'insumo',             'kg',     null, 10),
  ('Queso seco',       'insumo',             'kg',     null, 5),
  ('Manteca',          'insumo',             'kg',     null, 2),
  ('Tapa dulce',       'insumo',             'unidad', null, 5),
  ('Bolsa plástica',   'insumo',             'paquete', null, 2);
