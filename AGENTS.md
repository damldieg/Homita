# AGENTS.md

## Project

Planify dashboard for a photo frame device: Android app (Kotlin + Jetpack Compose) plus bash/Python tooling. Docs, comments and commit messages are Spanish; code identifiers are English.

### Stack

- **Apps** (`apps/`): dos proyectos Gradle independientes: `apps/dashboard` (este dashboard) y `apps/control` (app gestora, Planify-APP).
- **Dashboard** (`apps/dashboard/`): Kotlin 2.4.21 + Jetpack Compose (BOM `2026.09.00`, Material3, Lottie `6.7.1`), Gradle wrapper 9.8.1, AGP 9.4.1, JDK 17, `minSdk 29` / `targetSdk 37` / `compileSdk 37`. Package/app id `com.lito.planify.dashboard`. Retrofit `3.0.0` + converter-gson, JUnit `4.13.2`. No native libs.
- **API** (backend único: la Edge Function `supabase/functions/api`, ver `supabase/`): contrato PHP-compat (D-008), 43 rutas; migraciones en `supabase/migrations/`.
- **Scripts** (`scripts/`): bash (`#!/bin/bash`, `set -euo pipefail`) and Python 3 stdlib (`scripts/meteocons.py`, `scripts/demo/seed.py`). No web/Node project, no Makefile.
- Release build requires `planify.baseUrl` via `apps/dashboard/planify.properties`, `-Pplanify.baseUrl=…` or `PLANIFY_BASE_URL`; task `checkPlanifyBaseUrl` fails `preReleaseBuild` if absent. Debug defaults to `http://10.0.2.2:54321/functions/v1/api/` (local Edge).
- Prereqs (README): JDK 17+, Android SDK (compileSdk 37), `adb`, `sha256sum`/`gzip`; `mtools`/`dosfstools` only for boot logo; npm + Python 3 only for icon regen; Supabase CLI + Docker for the local Edge (demo).

### Commands

Gradle commands run from `apps/dashboard/` (or `apps/control/` for the manager app):

```sh
cd apps/dashboard
./gradlew :app:assembleDebug          # build (debug)
./gradlew :app:assembleRelease        # build (release; needs planify.baseUrl)
./gradlew :app:testDebugUnitTest      # test (JUnit4 unit tests)
./gradlew :app:lintDebug              # lint (AGP defaults; no lint.xml)
```

Repo level:

```sh
scripts/install.sh --build            # install: release build + install on frame (needs adb/device); also --no-backup
scripts/demo.sh app [--no-build]      # demo: local Edge + emulator + debug build/install
scripts/meteocons.py                  # regenerate weather icons (needs npm + Python 3)
scripts/frame/backup.sh               # eMMC backup
```

### Structure

```
apps/dashboard/           Gradle project (build.gradle.kts, settings.gradle.kts, gradlew, app/)
  app/src/main/java/com/lito/planify/dashboard/
    MainActivity.kt, DashboardViewModel.kt
    data/                 Api.kt, Models.kt, Store.kt, ReferenceClock.kt, HttpError.kt, WifiStatus.kt
    data/cache/           DiskCache.kt, CachedResource.kt
    data/repository/      ContentRepository.kt, WeatherRepository.kt, CalendarRepository.kt
    admin/                Kiosk.kt, PowerMenuService.kt, ReturnButton.kt
    power/                ScreenSchedule.kt
    ui/                   App.kt + screens, WeatherUi/WeatherIcons/MeteoconFrames, FlipClock, RollingText, theme/
  app/src/main/res/       raw/ (meteocon Lottie JSON), drawable/, font/ (Geist), values/, xml/
  app/src/test/java/…     JUnit4 unit tests: DiskCacheTest, CachedResourceTest, ReferenceClockTest,
                          CalendarRepositoryTest, ForecastTest, ScreenScheduleTest
apps/control/             app gestora (Planify-APP): Gradle project (app/), design/, docs/, README.md
supabase/                 backend único: Edge Function api (supabase/functions/api), migrations/, config.toml, README.md
scripts/                  install.sh, demo.sh, meteocons.py, config.example
  frame/                  backup.sh, planify-frame.sh, planify-frame.rc
  boot/                   boot.html, make.sh, install.sh, out/
  demo/                   seed.py, seed_supabase.py
docs/                     FRAME.md, SETUP.md, ARCHITECTURE.md, ANDROID.md, README.md, inventory/, images/
third_party/meteocons/    LICENSE
licenses/                 Geist-OFL.txt
```

### Conventions

- Docs and code comments are Spanish; identifiers/code are English. Commit messages Spanish, `Área: frase` style (e.g. `Hoy: la tarjeta destacada solo con lo de hoy o mañana`).
- Kotlin: ktlint-ish 4-space indent, KDoc `/** … */` on public/domain classes, `runCatching` style, no wildcard imports.
- UI is designed in native pixels: `Density(1f)` fixed; do not change system density.
- Data layer: every remote datum cached on disk, stale-if-error (`DiskCache` + `CachedResource`); HTTP errors as `HttpError`; 401 clears session.
- Tests are plain JUnit4 unit tests under `app/src/test`; no instrumentation tests.
- No CI: tests and lint run manually (`:app:testDebugUnitTest`, `:app:lintDebug`).
- `supabase/functions/api` es el backend único y canónico desde el corte (función Deno por casos de uso, contrato PHP-compat D-008); producción apunta a Supabase desde el corte 2026-11-08. El PHP legacy se retiró del repo (tag `legacy-php-final`, change remove-php-legacy).
- `apps/control` es un git subtree de https://github.com/eusonlito/Planify-APP (su `android/` aplanado a la raíz con `git mv`); sincronía upstream: `git subtree pull --prefix=apps/control …` y re-aplano manual si upstream añade rutas nuevas bajo `android/`.
