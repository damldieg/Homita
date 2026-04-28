# Estándares de Calidad y Arquitectura del Backend (PHP 8.5)

Este documento detalla rigurosamente los patrones de diseño y estándares de codificación implementados en la aplicación, los cuales deben respetarse estrictamente para todo el desarrollo futuro.

## 1. Principios Fundamentales (Strict & Clean Code)

1.  **Tipado Estricto y PHP 8.5:** Todos los archivos deben comenzar con `<?php declare(strict_types=1);`. Se utilizan características modernas como `json_validate` (PHP 8.3+).
2.  **Cero Comentarios:** El código debe ser 100% autodocumentado a través de nombres expresivos, separación en funciones pequeñas (`private function`) y firmas fuertemente tipadas.
3.  **Encapsulamiento de Errores (Fail-Fast sin try/catch local):** Los Controladores **NUNCA** deben usar bloques `try/catch`. Si un dato no existe, se lanza una `Exception` (por ejemplo, desde `selectOneOrFail`) que se propaga libremente.
4.  **Manejador Global de Errores:** El archivo `Router.php` envuelve la ejecución del controlador y atrapa cualquier `Throwable`, delegando su reporte a `App\Utils\Error::report($e)` y devolviendo automáticamente un HTTP 500 con el mensaje de la excepción en formato JSON.

## 2. Arquitectura de Controladores (Action-Based)

Cada endpoint es un archivo/clase independiente que hereda de `ControllerAbstract`. Su único punto de entrada público es `public function handle(): void;`.

### 2.1 Extracción de Datos Segura
En lugar de manipular `php://input` o `$_GET` directamente, el controlador DEBE utilizar los métodos tipados heredados de `ControllerAbstract`, los cuales combinan ambas fuentes de datos:
- `$this->getInputString('key')`
- `$this->getInputInt('key')`
- `$this->getInputEmail('key')`
- `$this->getInputDateHour('key')` (valida formato `Y-m-d H:i:s`)
- `$this->getInputBool('key')`

Estos métodos garantizan que las variables siempre sean del tipo correcto o `null` / `default`.

### 2.2 Autenticación
Los controladores que requieren autenticación deben llamar a `$this->middlewareAuth()` en su constructor o al inicio de `handle()`. Esto establece `$this->user` extrayendo el token del encabezado `Authorization: Bearer <token>`.

### 2.3 Gestión de Respuestas
El método `$this->response($data, $status)` se encarga de:
- Detectar si `$data` es un objeto que implementa `toArray()` y extraer su array asociativo.
- Convertir arrays a JSON limpiamente, estableciendo el encabezado `Content-Type: application/json` y finalizando la ejecución (`die()`).
- Reportar automáticamente errores (status != 200) a través de `App\Utils\Error`.

## 3. Capa de Modelos (Active Record con Reflexión)

Todos los modelos heredan de `ModelAbstract`.

### 3.1 Instanciación por Reflexión
- Las propiedades públicas del modelo (`public int $id;`, `public string $name;`) se mapean automáticamente desde el fetch de PDO gracias a `ReflectionClass` dentro de `ModelAbstract`. Solo las propiedades públicas son mapeadas.

### 3.2 Acceso a la Base de Datos (`self::database()`)
- Las consultas a base de datos dentro del modelo se hacen estáticamente a través de `self::database()`.
- Se prefieren los métodos nativos del Wrapper `Database`: `selectOneOrFail`, `selectOne`, `select`, `insert`, `execute`.

### 3.3 Filtros y Lógica de Consulta
- Los modelos deben implementar métodos estáticos de búsqueda como `findWithFilters(int $userId, array $filters)`.
- Para procesar filtros de forma segura, se utilizan los métodos de `ModelAbstract`: `getFilterString`, `getFilterInt`, `getFilterBool`, `getFilterTimestamp`.
- **Nunca se debe iterar en PHP lo que se puede resolver en SQL.** Las consultas deben incluir los `JOIN` necesarios para traer datos relacionados (ej. colores de calendario en eventos).

## 4. Configuración (Scopes separados)

La configuración se divide en scopes mediante `App\Utils\Config::key(string $scope, string $key)`:
- `public` -> Extraído de `public.json` (ej. `allow_registration`).
- `private` -> Extraído de `private.json` (ej. `gemini_api_key`).
- Los archivos `.local.json` (ej. `private.local.json`) sobreescriben los valores del archivo base si existen, permitiendo configuraciones específicas por entorno sin afectar al repositorio.