# Planify - Backend

Backend robusto construido con PHP 8.5+, siguiendo una arquitectura orientada a acciones y tipado estricto.

> **Nota:** Este es el repositorio exclusivo para el Backend (API) de Planify. Si buscas el código fuente de la aplicación móvil (Android/Kotlin), visita el repositorio oficial [Planify-APP (GitHub)](https://github.com/eusonlito/Planify-APP).

## 🧩 Ecosistema Planify

| Repositorio | Qué es |
|---|---|
| [Planify-Backend](https://github.com/eusonlito/Planify-Backend) | API en PHP y SQLite con los datos de todos |
| [Planify-APP](https://github.com/eusonlito/Planify-APP) | App Android para crear y gestionar calendarios, eventos, rutinas y tareas |
| [Planify-Dashboard](https://github.com/eusonlito/Planify-Dashboard) | Pantalla de pared de solo lectura en un marco digital Android, con la misma cuenta |

## Requisitos

- **PHP 8.5+**
- Extensiones PHP: `pdo_sqlite`, `json`, `reflection`.
- Servidor Web (Apache/Nginx) apuntando a `public/`.
- SQLite3.

## Instalación y Configuración

1.  **Configuración de Entorno**:
    Copia los archivos de configuración base para crear tus versiones locales (ignoradas por Git):
    ```bash
    cp config/private.json config/private.local.json
    cp config/public.json config/public.local.json
    ```
    Edita `config/private.local.json` para añadir tu `gemini_api_key` y otros secretos.

2.  **Base de Datos**:
    El sistema utiliza SQLite. Para ejecutar las migraciones y crear las tablas:
    ```bash
    php src/Commands/Migrate.php
    ```

3.  **Servidor de Desarrollo**:
    Puedes usar el servidor embebido de PHP para pruebas rápidas:
    ```bash
    php -S localhost:8000 -t public
    ```

## Despliegue con el script local

Cuando esté disponible, `scripts/install.sh` sincroniza este backend con el servidor, ejecuta las migraciones y ajusta los permisos. Resuelve la carpeta del backend desde su propia ubicación y puede ejecutarse desde cualquier directorio:

```bash
./scripts/install.sh
```

El script conserva la base de datos, los logs y la configuración local del servidor. Detiene el despliegue si falla la sincronización, la migración o el ajuste de permisos. `scripts/` está excluido de Git porque contiene configuración de despliegue local.

## Arquitectura

- **Action-Based Controllers**: Cada endpoint es una clase independiente en `src/Controllers/` que hereda de `ControllerAbstract`.
- **Modelos (Active Record)**: Ubicados en `src/Models/`, utilizan reflexión para mapear propiedades públicas a columnas de la BD.
- **Manejo de Errores**: Centralizado en `src/Utils/Router.php`. No se usan `try/catch` en controladores; las excepciones se propagan y el router las convierte en respuestas JSON 500.
- **Autenticación**: Basada en Bearer Token via el header `Authorization`.

## Documentación Detallada

- [Documentación de la API](docs/API.md): Endpoints, inputs y formatos de respuesta.
- [Estándares de Calidad](docs/APP.md): Guía de estilo, principios de código limpio y arquitectura técnica.

## Estructura de Directorios

- `config/`: Archivos JSON de configuración por scope (public/private).
- `db/`: Almacenamiento de la base de datos SQLite.
- `migrations/`: Scripts SQL de evolución de esquema.
- `public/`: Punto de entrada único (`index.php`) y activos públicos.
- `src/`: Código fuente (Controladores, Modelos, Utils).
