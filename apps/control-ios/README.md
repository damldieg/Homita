# Planify Control iOS (`apps/control-ios`)

App gestora de Planify para iPhone (v1). Swift 5 + SwiftUI, iOS 17+, sin dependencias de terceros. La lógica y la UI viven en el paquete SPM **`ControlKit`** (`Sources/ControlKit`; tests en `Tests/ControlTests`); el `.xcodeproj` de la app se crea una vez en Xcode (ver «Instalar en el iPhone»). Consume la misma Edge Function que el dashboard y la app Android (`https://<ref>.supabase.co/functions/v1/api`, contrato PHP-compat de 43 rutas; ver [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md)).

## Configuración

La URL y la clave anon nunca se commitean: se generan en `Config.xcconfig` (git-ignorado) desde `~/.homita/supabase.env`:

```sh
apps/control-ios/scripts/gen-config.sh   # escribe Config.xcconfig (permisos 600; no imprime valores)
```

`scripts/check-config.sh` va como Run Script del target (antes de compilar) y falla el build si falta `Config.xcconfig` o quedan placeholders — equivalente de `checkPlanifyBaseUrl` del dashboard. Si cambias `~/.homita/supabase.env`, vuelve a ejecutar `gen-config.sh`.

## Compilar y testar

```sh
cd apps/control-ios
swift build    # compila ControlKit en el Mac (macOS está solo para esto y swift test; la app es iOS)
swift test     # 102 tests XCTest: Flex, fechas PHP, reloj local, modelos, red/auth, contexto de hogar, reglas de rutina
```

**Contexto de hogar (1.11).** Tras el login/arranque `HomeContextStore` carga `GET home` y fija el hogar activo (persistido en Keychain bajo `active_home_id` si sigue en la lista; si no el `is_default`; si no el primero). `APIClient` envía `X-Home-Id` solo en rutas autenticadas `home/*`, excepto `GET home`, `POST home/create` y `PATCH home/default`. Sin hogares, las pestañas Tareas y Calendario muestran «Crear hogar»; Perfil siempre está accesible. El cierre de sesión pasa por `AppServices.signOut()`, que limpia el hogar activo. Sin selector de hogar hasta 1.12.

Con el proyecto Xcode creado: `xcodebuild -scheme ControlApp -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` y `xcodebuild test` en un simulador iOS 17+.

## Instalar en el iPhone (firma gratuita)

Firma gratuita con tu Apple ID (equipo «Personal Team») vía **AltStore** o **Sideloadly**. La instalación **caduca a los 7 días**: hay que re-instalar cada semana (AltStore la renueva en la misma red; con Sideloadly, repetir la instalación). Al reinstalar puede borrarse la sesión (Keychain) y hay que volver a entrar; la sesión en uso se renueva sola (refresh GoTrue).

1. Xcode › File › New › Project… › **App** (plataforma iOS, SwiftUI, Swift), nombre `ControlApp`.
2. Añadir el paquete local `apps/control-ios` (File › Add Package Dependencies › Add Local…) y enlazar el producto **`ControlKit`** al target.
3. Cablear el entry point: el `@main` de la app debe crear `RootView()` de ControlKit (`WindowGroup { RootView() }`; ver `Sources/ControlKit/App/RootView.swift`).
4. Signing & Capabilities › Team: tu Apple ID (Personal Team).
5. Bundle Identifier: `com.lito.planify.control.ios`; Deployment Target: **iOS 17.0**.
6. Activar el **Modo Desarrollador** en el iPhone (Ajustes › Privacidad y seguridad) e instalar el build con AltStore o Sideloadly.

## Alcance v1

- Auth: login, registro (solo si `GET /config` → `allow_registration`), perfil (nombre, email, contraseña) y logout.
- Tareas y listas: CRUD, orden (`updated_at`/`title`/`custom`), completar/descompletar, reordenar, compartir por email (owner) y flags propios.
- Calendarios: CRUD, color, compartir por email. Eventos: CRUD, personas asignadas.
- Rutinas: daily / weekly (cada N semanas, días ISO) / monthly (cada N meses), inicio/fin, activa/pausa, personas. Sesiones individuales solo lectura.
- Personas: CRUD; las compartidas, solo lectura.
- Sesiones de rutina (solo lectura): lista plana «Próximas sesiones» (10 siguientes) en la pestaña de Rutinas.

## Límites de v1 (lo que NO hace)

- **Sin notificaciones ni avisos:** las alarmas de eventos y rutinas se guardan en el servidor, pero el iPhone **no avisa** en v1.
- Sin vista de calendario mensual/semanal (queda para un pulido posterior): v1 solo lista las próximas sesiones de rutina.
- Sin widgets, sin push, sin pantalla de alarma, sin actualización en segundo plano.
- Sin «modo IA» (texto → evento): crear evento exige `title` + `date_at`.
- Sin iPad, Mac Catalyst ni TestFlight: la distribución es solo side-load.

Suite de contrato de lectura (solo GET, contra la Edge): `scripts/ios_read_suite.py` (creds por variables de entorno; ver su cabecera).
