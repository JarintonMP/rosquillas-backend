# App Rosquillas: pautas del proyecto

Borrador 2 (22 de noviembre de 2026). Este archivo explica para qué existe la app, con qué se construye y qué reglas siguen el código y el diseño. Cuando existan los repositorios, irá en `docs/PAUTAS.md` de ambos.

## 1. Para qué existe la app

El negocio necesita saber **quién debe cuánto**, **qué se vendió** y **cuánto producto hay**, sin depender de cuadernos ni de memoria.

Objetivos, en orden de prioridad:

1. **Control de ventas y crédito.** Registrar cada venta, sea de contado o fiada. Ver el saldo de cada cliente y registrar sus abonos.
2. **Inventario.** Entradas de producto o insumos (de proveedores) y salidas (cada venta descuenta del inventario automáticamente).
3. **Bitácora y reportes.** Ver qué clientes compran más en el mes y sacar promedios de ventas y de entradas, por cliente y en general.

## 2. Quién la usa

| Rol | Quién | Qué puede hacer |
|---|---|---|
| **Super admin** | Jarinton | Todo, incluido **borrar** registros y gestionar usuarios. |
| **Admin** | Familiar de confianza | Crear, editar y **deshabilitar** clientes, proveedores y productos. Ver reportes. |
| **Familiar** | Otros familiares | Registrar ventas, cobros, compras y producción. Ver clientes activos y sus saldos. |

Los únicos usuarios con cuenta son de la familia y usan **Android**. Los clientes y proveedores no inician sesión: son registros. Se usa Expo para que el mismo código sirva en iPhone si algún día hace falta.

## 3. Reglas del negocio

- **Clientes y proveedores**: pueden ser persona **física** o **jurídica**, con su cédula. Una misma persona puede ser cliente y proveedor.
- **Tipo de cliente**: *esporádico* es una venta sin cliente registrado, siempre de contado. *Recurrente* o *casual* se calcula según la frecuencia de compra. A cada cliente se le indica si se le puede fiar y hasta cuánto.
- **Pagos**: no hay métodos de pago. Solo se registra cada pago o abono a la cuenta del cliente y quién lo registró.
- **Deshabilitar y borrar**: deshabilitar oculta el registro de las listas, pero sigue en la base y en los reportes. Solo el super admin puede "borrar", y aun así el dato **no se elimina físicamente**: se marca como borrado (`deleted_at`) y queda respaldado.
- **Nada se pierde**: las ventas y los movimientos de inventario nunca se editan en silencio. Para corregir uno se anula y se registra de nuevo, y queda constancia de quién lo hizo.
- **Crédito**: el saldo de un cliente es la suma de sus ventas a crédito menos sus abonos.
- **Sin internet**: la app debe permitir registrar ventas sin conexión y sincronizarlas al volver la señal.

## 4. Tecnología (todo gratis para empezar)

| Pieza | Elección | Por qué |
|---|---|---|
| App móvil (frontend) | **Expo (React Native) + TypeScript** | Un solo código para Android e iPhone. Se parece a programar para la web, que es lo que ya conoces. Se prueba en el celular con la app gratuita *Expo Go*. |
| Backend y base de datos | **Supabase** (plan gratis) | Base de datos PostgreSQL, inicio de sesión, permisos por rol (RLS) y funciones en el servidor (Edge Functions). Se maneja desde código con la CLI de Supabase. |
| Datos sin internet | **SQLite local** (`expo-sqlite`) con cola de sincronización | Las ventas se guardan en el celular y se suben cuando hay conexión. |
| Código | **Git + GitHub + VS Code** | Lo que ya usas. |

**Sobre costos:** en Android se puede instalar la app (APK) gratis. En iPhone se puede usar gratis con Expo Go mientras sea para la familia. Publicarla en la App Store cuesta 99 USD al año, y en Google Play hay un pago único de 25 USD. No hace falta publicar para empezar.

### Dos repositorios

| Repositorio | Contiene |
|---|---|
| `rosquillas-frontend` (frontend) | La app Expo: pantallas, componentes, base local y sincronización. |
| `rosquillas-backend` (backend) | El proyecto de Supabase como código: migraciones SQL, reglas RLS, vistas de reportes, funciones en el servidor, datos de prueba y pruebas de la base. |

El contrato entre los dos son los **tipos generados**: el backend genera `database.types.ts` con `supabase gen types` y el frontend lo copia en `src/lib/database.types.ts`. Si cambia la base, se regeneran los tipos.

## 5. Código limpio y ordenado

### Estructura del frontend (`rosquillas-frontend`)

```
app/                  Pantallas (Expo Router: cada archivo es una ruta)
  (auth)/             Inicio de sesión
  (tabs)/             Ventas, Clientes, Inventario, Reportes
src/
  features/           Un folder por módulo: ventas/, clientes/, proveedores/, inventario/, reportes/
    ventas/
      components/     Piezas de pantalla del módulo
      hooks/          Lógica reutilizable (useVentas, useSaldoCliente…)
      api.ts          Acceso a datos del módulo
      types.ts        Tipos del módulo
  components/         Componentes compartidos (botones, listas, formularios)
  lib/                Cliente de Supabase, base local, sincronización, tipos generados
  i18n/               Textos de pantalla (es-CR)
  theme/              Colores, tamaños, tipografía
docs/
```

### Estructura del backend (`rosquillas-backend`)

```
supabase/
  migrations/         Cambios a la base, en orden y versionados (tablas, RLS, vistas)
  functions/          Edge Functions (por ejemplo, cierre de mes o reportes pesados)
  seed.sql            Datos de prueba
  tests/              Pruebas de la base (pgTAP): permisos, saldos, existencias
  config.toml
docs/
```

### Reglas

- **TypeScript estricto** (`strict: true`). Nada de `any`.
- **ESLint + Prettier** para que el formato sea siempre igual. Se revisa antes de cada commit.
- **Nombres en español** (tablas, funciones, variables y archivos de dominio: `ventas`, `registrarVenta`, `useSaldoCliente`). En inglés solo lo que imponen las librerías. Componentes en `PascalCase`, funciones y variables en `camelCase`, y tablas y columnas en `snake_case`.
- **Pantallas delgadas**: la pantalla solo muestra; la lógica va en `hooks/` y el acceso a datos en `api.ts`.
- **Dinero en enteros** (colones, sin decimales flotantes) para evitar errores de redondeo.
- **La base de datos se cambia solo con migraciones** en el repo de backend, nunca a mano en el panel.
- **Permisos en la base, no solo en la app**: las reglas de rol se aplican con RLS en Supabase.
- **Ninguna clave secreta en el frontend**: la app solo usa la clave pública (`anon`). La clave `service_role` vive únicamente en el backend.
- **Commits pequeños** con mensajes claros (`feat: registrar abono de cliente`). Una rama por función y fusión a `main` con pull request.
- **Pruebas** para los cálculos importantes (saldos, promedios, existencias), tanto en la app como en la base.

## 6. Diseño de la interfaz

Basado en el material del curso de Diseño de Interfaces de Usuario (UNA, II ciclo 2026).

- **Diseño centrado en las personas**: investigar, definir, idear, prototipar, probar e iterar. Antes de programar cada módulo, se hace un *User Flow* y un prototipo sencillo que se prueba con un familiar.
- **Trazabilidad**: cada decisión de pantalla se justifica con la cadena *evidencia → necesidad → requisito → decisión*. Lo que no se ha comprobado se anota como supuesto pendiente.
- **Heurísticas de Nielsen** como lista de revisión de cada pantalla. Las más importantes aquí son:
  - *Visibilidad del estado*: mostrar siempre si una venta está guardada, pendiente de sincronizar o con error.
  - *Prevención de errores*: no aceptar montos negativos ni cantidades mayores a la existencia; confirmar antes de anular una venta o deshabilitar un cliente.
  - *Reconocer antes que recordar*: elegir cliente y producto de una lista con búsqueda, no escribirlos a mano.
  - *Consistencia*: un mismo botón se llama y se ve igual en todas las pantallas.
  - *Control de la persona*: poder cancelar o deshacer cuando sea razonable.
- **Estados de cada pantalla**: vacío, cargando, éxito, error, deshabilitado y sin conexión. Ninguna pantalla debe quedarse "en blanco".
- **Accesibilidad (WCAG 2.2, principios POUR)**: contraste suficiente, botones grandes y bien separados (mínimo 44 × 44 puntos en móvil), texto que crece con el tamaño de letra del celular, etiquetas para lectores de pantalla y nunca usar solo el color para indicar algo (por ejemplo, saldo pendiente con color **y** texto).
- **Localización**: la app arranca en `es-CR`. Los textos van en `src/i18n/` y no escritos directamente en las pantallas. Los montos se muestran en colones (₡1 500), las fechas en formato día/mes/año y todo se formatea con `Intl`, nunca a mano.
- **Tarea principal primero**: registrar una venta debe tomar pocos toques desde la pantalla inicial.

## 7. Modelo de datos

El diseño completo está en `DISENO_BD.md`: supertipo `parties` para personas físicas y jurídicas, cuentas de clientes basadas en ventas y pagos, inventario como libro de movimientos, auditoría y permisos por rol.

## 8. Plan por etapas

1. **Base de los dos repos**: crear `rosquillas-backend` con el proyecto de Supabase (tablas, roles, RLS, inicio de sesión y datos de prueba) y `rosquillas-frontend` con Expo, TypeScript, reglas de estilo, tema visual accesible y pantalla de inicio de sesión.
2. **Ventas y crédito** (prioridad): User Flow y prototipo, luego clientes, productos, ventas de contado o a crédito, abonos y saldo por cliente. Funciona sin internet.
3. **Inventario y proveedores**: proveedores con sus productos, entradas, descuento automático por venta y existencias.
4. **Bitácora y reportes**: ranking mensual de clientes, promedios de ventas y entradas, revisión heurística final e instalación en los celulares de la familia.

## 9. Pendiente de decidir

- Nombre definitivo de la app.
- Lista inicial de productos y precios.

## 10. Forma de trabajo (tomada de tus proyectos anteriores)

- **Ramas**: `main` (estable) y `development` (integración). Cada tarea en su rama (`feature/registrar-venta`) y se integra a `development` con pull request.
- **Commits** con Conventional Commits en español: `feat(ventas): registrar venta a crédito`, `fix(inventario): …`.
- **Backlog en GitHub Projects** (gratis, en lugar de Azure DevOps): cada historia como issue con "Como … quiero … para …", criterios de aceptación y etiqueta `FE` o `BE`.
- **Una sola fuente por regla**: roles, validaciones, colores y formato de errores viven en un solo archivo cada uno.
- **Tokens de diseño en `src/theme/`** con una prueba de contraste WCAG AA (4.5:1) que falla si alguien usa un color que no cumple.
- **Lógica pura en `src/lib/`** (cálculos, formatos) para probarla sin la interfaz.
- **UX con evidencia real**: problema en una frase, tarea principal, pruebas con familiares reales, severidad de Nielsen (0 a 4) y registro "problema → cambio → heurística". Nunca se inventan participantes ni resultados, y lo que no se ha probado se marca como pendiente. Va en `docs/ux/` del frontend.
- **Nombres en el código**: en SIAPB usaron todo en español. Aquí se hace igual (decidido el 22 de noviembre de 2026).
