# Planify Control iOS (`apps/control-ios`)

App gestora de Planify para iPhone (v1). Swift 5 + SwiftUI, iOS 17+, sin dependencias de terceros. La lógica y la UI viven en el paquete SPM **`ControlKit`** (`Sources/ControlKit`; tests en `Tests/ControlTests`); el `.xcodeproj` de la app se crea una vez en Xcode (ver «Instalar en el iPhone»). Consume la misma Edge Function que el dashboard y la app Android (`https://<ref>.supabase.co/functions/v1/api`, contrato PHP-compat de 43 rutas; ver [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md)).

## Configuración

La URL y la clave anon nunca se commitean: se generan en dos ficheros git-ignorados: `Config.prod.xcconfig` (desde `~/.homita/supabase.env`, para Release) y `Config.local.xcconfig` (desde `supabase status`, para Debug):

```sh
apps/control-ios/scripts/gen-config.sh prod    # escribe Config.prod.xcconfig (permisos 600; no imprime valores)
apps/control-ios/scripts/gen-config.sh local   # escribe Config.local.xcconfig (requiere `supabase start`)
```

`scripts/check-config.sh` va como Run Script del target (antes de compilar) y elige el xcconfig según `CONFIGURATION` (Debug → `Config.local.xcconfig`, Release → `Config.prod.xcconfig`) y falla el build si falta, tiene placeholders o el host no encaja con la configuración — equivalente de `checkPlanifyBaseUrl` del dashboard. Si cambias `~/.homita/supabase.env`, vuelve a ejecutar `gen-config.sh`.

## Compilar y testar

```sh
cd apps/control-ios
swift build    # compila ControlKit en el Mac (macOS está solo para esto y swift test; la app es iOS)
swift test     # 154 tests XCTest: Flex, fechas PHP, reloj local, modelos, red/auth, contexto de hogar, administración del hogar, reglas de rutina
```

**Contexto de hogar (1.11).** Tras el login/arranque `HomeContextStore` carga `GET home` y fija el hogar activo (persistido en Keychain bajo `active_home_id` si sigue en la lista; si no el `is_default`; si no el primero). `APIClient` envía `X-Home-Id` solo en rutas autenticadas `home/*`, excepto `GET home`, `POST home/create` y `PATCH home/default`. Sin hogares, las pestañas Tareas y Calendario muestran «Crear hogar»; Perfil siempre está accesible. El cierre de sesión pasa por `AppServices.signOut()`, que limpia el hogar activo. El selector de hogar vive en la pestaña Hogar.

**Pestañas (B4).** Inicio · Tareas · Calendario · Hogar · Perfil. Inicio resume el día (eventos de hoy, tareas pendientes, rutinas de hoy calculadas en cliente, accesos rápidos) con `event`, `task` y `routine`. Hogar tiene selector de hogar, miembros con tipo y permisos, invitar por código y enlace a Administración. Detalle en `docs/control-ios/B4-inicio-hogar.md`. UI sin verificar en simulador.

**Administración del hogar (1.12).** La pestaña Hogar > Administración (solo con hogar activo) abre Configuración (nombre y zona IANA; edita solo admin), Administradores (rol, transferir, quitar, salir con confirmación), Accesos (permisos por miembro, solo admin) y Auditoría (solo admin, «Cargar más» por `before_id`). Un miembro ve configuración y administradores sin acciones. El cliente solo oculta; el servidor decide (403 con mensaje de administrador). Tras salir, transferir o cambiar el propio rol se recarga `homeContext`. Hogar personal: se puede renombrar; transferir, quitar y salir no se ofrecen. UI sin verificar en simulador (no hay `.xcodeproj`).

**Miembros del hogar (1.13).** En Administración del hogar, «Miembros» lista las personas del hogar (color, tipo, estado, «Vinculada»/«Sin cuenta»); la ve cualquier rol y solo un admin puede agregar y editar (nombre, color, tipo, activar/desactivar). `pet` no se ofrece para miembros vinculados y cambiar el tipo de un vinculado pide confirmación (restablece sus permisos). La recarga de `homeContext` por editar la propia fila queda cableada pero inactiva hasta 1.15 (el payload no identifica al caller). UI sin verificar en simulador.

**Invitar desde la app (1.15b).** En Administración del hogar, «Invitaciones» (visible para admin o para quien tenga `home.invite` en su fila de `home/membership`) lista las pendientes, crea una (tipo y, opcional, miembro sin cuenta) y revoca con confirmación. `adult` solo lo ofrece a un admin (D-017) y `pet` nunca. El código se muestra una sola vez con «Copiar»; vive solo en memoria, no se persiste ni se loguea y se borra al cerrar. `create`, `list` y `revoke` llevan `X-Home-Id`; `accept` no. UI sin verificar en simulador.

Con el proyecto Xcode creado: `xcodebuild -scheme ControlApp -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build` y `xcodebuild test` en un simulador iOS 17+.

## Instalar en el iPhone (firma gratuita)

Firma gratuita con tu Apple ID (equipo «Personal Team») vía **AltStore** o **Sideloadly**. La instalación **caduca a los 7 días**: hay que re-instalar cada semana (AltStore la renueva en la misma red; con Sideloadly, repetir la instalación). Al reinstalar puede borrarse la sesión (Keychain) y hay que volver a entrar; la sesión en uso se renueva sola (refresh GoTrue).

1. Xcode › File › New › Project… › **App** (plataforma iOS, SwiftUI, Swift), nombre `ControlApp`.
2. Añadir el paquete local `apps/control-ios` (File › Add Package Dependencies › Add Local…) y enlazar el producto **`ControlKit`** al target.
3. Cablear el entry point: el `@main` de la app debe crear `RootView()` de ControlKit (`WindowGroup { RootView() }`; ver `Sources/ControlKit/App/RootView.swift`).
4. Signing & Capabilities › Team: tu Apple ID (Personal Team).
5. Bundle Identifier: `com.lito.planify.control.ios`; Deployment Target: **iOS 17.0**.
6. Activar el **Modo Desarrollador** en el iPhone (Ajustes › Privacidad y seguridad) e instalar el build con AltStore o Sideloadly.

## Notificaciones, widgets y pantalla de bloqueo

Todo se enciende o apaga en **Ajustes › Notificaciones** (`NotificationSettingsView`); las preferencias viven en el App Group para que los widgets las lean.

- **Avisos locales** (`UNUserNotificationCenter`, sin servidor): evento o rutina con alarma → aviso «minutos antes» (0 = a la hora; sin alarma no avisa). Las rutinas solo avisan a la persona asignada con su cuenta (requiere migración 0028); los eventos, a todo el hogar. Como en Calendario: suena, sale como banner y **queda en el panel de notificaciones** (reprogramar no borra los ya entregados). Opcional: resumen diario de tareas pendientes a la hora elegida. `NotificationPlanner` (puro, con tests) decide qué programar: eventos de los próximos 7 días y rutinas por su regla; iOS admite 64 pendientes, se programan 60. Tocar un aviso abre su pestaña.
- **Widgets** (extensión `HomitaWidgets`): *Rutinas de hoy* (pequeño, mediano, grande, rectangular e inline de pantalla de bloqueo; cambia de fase sola en cada hora de inicio/fin) y *Accesos rápidos* (mediano: **+ Tarea**, **+ Evento**, **+ Rutina**), más un widget por acción (*Nueva tarea*, *Nuevo evento*, *Nueva rutina*; pequeño y de bloqueo). Abren la app con `homita://nueva-tarea`, `nuevo-evento`, `nueva-rutina`; Inicio y Calendario › Rutinas abren el formulario directamente (un widget no admite escribir texto).
- **Live Activity de rutinas** (pantalla de bloqueo y Dynamic Island): la rutina en curso o la próxima (≤ 60 min) con cuenta atrás y barra de tiempo del sistema. **Solo sale para la persona asignada a la rutina** con su cuenta iniciada: se compara `home_member.app_user_id` de cada persona (campo `app_user_id` de `GET person`, migración 0028) con la cuenta de la sesión; rutina sin asignar o cuenta sin persona vinculada = no hay Live Activity.
- **Datos compartidos:** la app escribe un `HomitaSnapshot` JSON (solo títulos, horas y colores, sin secretos) en el App Group `group.com.lito.planify.control.ios` (`Entitlements/*.entitlements`); la extensión solo enlaza `HomitaShared` (módulo sin dependencias del paquete).
- **Cuándo se actualiza** (`HomitaSync`): al abrir la app, al volver a primer plano, al cambiar de hogar o de toggle y en segundo plano (`BGAppRefreshTask`, lo decide iOS). Cerrar sesión borra avisos, snapshot y Live Activity.

Límites (sin cuenta de pago ni servidor de push):

- La Live Activity **solo puede iniciarse con la app abierta** (sin APNs); una vez en marcha, la cuenta atrás y la barra siguen solas, pero con la app cerrada no pasa sola a la rutina siguiente hasta que se abra la app o iOS dé tiempo de refresco. Para tiempo real puro hace falta APNs (cuenta de pago + envío desde la Edge Function).
- **Requiere aplicar la migración `0028_person_app_user_id`** en Supabase (`supabase db push`); sin ella el servidor no envía `app_user_id` y la Live Activity no sale nunca.
- Los widgets muestran lo último que dejó la app; si no se abre en todo el día, «Abre Homita para actualizar».
- Firma gratuita: la extensión es un segundo App ID (AltStore/Sideloadly limitan IDs y apps activas) y el App Group lo registra la herramienta de firma; si no hay grupo, los widgets muestran «Abre Homita para cargar tus rutinas». Si cambias de equipo de firma, ajusta `appGroupId` en `HomitaShared/SharedConfig.swift` y en los dos `.entitlements`.
- UI, widgets y Live Activity sin verificar en simulador ni en dispositivo.

## Alcance v1

- Auth: login, registro (solo si `GET /config` → `allow_registration`), perfil (nombre, email, contraseña) y logout.
- Tareas y listas: CRUD, orden (`updated_at`/`title`/`custom`), completar/descompletar, reordenar, compartir por email (owner) y flags propios.
- Calendarios: CRUD, color, compartir por email. Eventos: CRUD, personas asignadas.
- Rutinas: daily / weekly (cada N semanas, días ISO) / monthly (cada N meses), inicio/fin, activa/pausa, personas. Sesiones individuales solo lectura.
- Personas: CRUD; las compartidas, solo lectura.
- Sesiones de rutina (solo lectura): lista plana «Próximas sesiones» (10 siguientes) en la pestaña de Rutinas.

## Límites de v1 (lo que NO hace)

- **Avisos solo locales:** el iPhone avisa con notificaciones locales (ver «Notificaciones, widgets y pantalla de bloqueo»); no hay push remoto (APNs).
- Sin vista de calendario mensual/semanal (queda para un pulido posterior): v1 solo lista las próximas sesiones de rutina.
- Sin push remoto ni pantalla de alarma a pantalla completa.
- Sin «modo IA» (texto → evento): crear evento exige `title` + `date_at`.
- Sin iPad, Mac Catalyst ni TestFlight: la distribución es solo side-load.

Suite de contrato de lectura (solo GET, contra la Edge): `scripts/ios_read_suite.py` (creds por variables de entorno; ver su cabecera).
