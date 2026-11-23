# rosquillas-backend

Backend de la app de inventario y ventas del negocio familiar de rosquillas, tanelas y empanadas. Es un proyecto personal.

El backend es un proyecto de **Supabase (PostgreSQL)** manejado como código: migraciones SQL, permisos con RLS, funciones de negocio y pruebas pgTAP. La app móvil está en [`rosquillas-frontend`](https://github.com/JarintonMP/rosquillas-frontend).

- Pautas del proyecto: [`docs/PAUTAS.md`](docs/PAUTAS.md)
- Diseño de la base de datos: [`docs/DISENO_BD.md`](docs/DISENO_BD.md)

## Estructura

```
supabase/
  config.toml                 Configuración de Supabase CLI (local)
  migrations/                 Cambios a la base, en orden. Única forma de cambiar el esquema.
  tests/database/             Pruebas pgTAP (*.test.sql)
  seed.sql                    Datos de ejemplo solo para desarrollo local
scripts/local/
  probar.sh                   Corre migraciones y pruebas en un PostgreSQL normal, sin Docker
  stub_supabase.sql           Lo mínimo de Supabase (auth.uid, roles) para ese PostgreSQL
docs/                         Pautas y diseño
```

### Esquemas

| Esquema | Contenido |
|---|---|
| `seguridad` | Perfiles de la familia, roles, permisos y matriz `rol_permisos` |
| `catalogo` | Personas (físicas y jurídicas), clientes, proveedores y productos |
| `ventas` | Ventas, cobros y cuentas de clientes *(paso 2)* |
| `inventario` | Compras, recetas, producción y movimientos *(paso 3)* |
| `auditoria` | Bitácora inmutable de cambios |

## Reglas que hace cumplir la base

- **Fail-closed:** RLS está activo en todas las tablas. Sin perfil activo o sin permiso, no se ve ni se cambia nada.
- **Permisos como datos:** `seguridad.tiene_permiso('modulo.accion')` revisa la matriz en cada petición, así que un cambio de rol aplica de inmediato.
- **Nunca hay borrado físico:** deshabilitar es `activo = false` y borrar es `eliminado_en` (solo super admin). El dato queda respaldado y en la bitácora.
- **Validaciones de Costa Rica:** cédula física (9 dígitos), jurídica (10), DIMEX (11 o 12) y teléfono de 8 dígitos. Deben ser idénticas a `src/lib/validaciones.ts` del frontend.
- **Errores en español con código:** `message` es para la persona y `detail` trae el código (`SIN_PERMISO`, `DATOS_INVALIDOS`, `DUPLICADO`, `OPERACION_NO_PERMITIDA`, `NO_ENCONTRADO`).

## Desarrollo local

### Opción A: Supabase CLI (recomendada, necesita Docker)

```bash
npm install -g supabase        # o: brew install supabase/tap/supabase
supabase start                 # levanta Supabase local y aplica migraciones y seed
supabase test db               # corre las pruebas pgTAP
supabase db reset              # vuelve a crear la base desde cero
```

### Opción B: PostgreSQL normal, sin Docker

Necesita `psql`, `pg_prove` y la extensión `pgtap` (en Ubuntu: `sudo apt install postgresql-16-pgtap`).

```bash
PGHOST=localhost PGUSER=postgres scripts/local/probar.sh
```

## Conectar con el proyecto de Supabase en la nube

1. Crear el proyecto en [supabase.com](https://supabase.com) (plan gratis).
2. En **Project Settings > API > Exposed schemas**, agregar `seguridad`, `catalogo`, `ventas`, `inventario` y `auditoria`.
3. En **Authentication > Providers > Email**, desactivar el registro público (*Allow new users to sign up*).
4. Enlazar y subir las migraciones:
   ```bash
   supabase login
   supabase link --project-ref <ref-del-proyecto>
   supabase db push
   ```
5. Crear tu usuario en **Authentication > Users** y activarte como super admin una sola vez desde el **SQL Editor**:
   ```sql
   update seguridad.perfiles
      set rol = 'super_admin', activo = true
    where id = (select id from auth.users where email = 'tu-correo@ejemplo.com');
   ```
   Desde ahí, los demás usuarios se activan con `seguridad.actualizar_perfil()` desde la app.

**Nunca** pongas la clave `service_role` en la app ni en el repositorio.

## Forma de trabajo

- Ramas: `main` (estable) y `development` (integración). Cada tarea en su rama desde `development` y se integra con pull request.
- Commits en español con Conventional Commits: `feat(catalogo): …`, `fix(seguridad): …`, `test(auditoria): …`.
- Cada pull request corre las pruebas en GitHub Actions (`.github/workflows/pruebas.yml`).
