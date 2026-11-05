# Scout findings — init

Date: 2026-11-05. Repo: `/Users/damiandiego/orca/Homita` (branch clean; `git status` shows only `?? .dorch/`).

## Stack

- **Android app** (`android/`): Kotlin + Jetpack Compose. No native libs (frame is 32-bit).
  - Package/namespace: `com.lito.planify.dashboard`; app id same.
  - `minSdk 29`, `targetSdk 37`, `compileSdk 37`, JDK 17 (`sourceCompatibility`/`targetCompatibility`).
  - Gradle wrapper **9.8.1** (`android/gradle/wrapper/gradle-wrapper.properties`).
  - AGP **9.4.1**, Kotlin **2.4.21** (`android/build.gradle.kts`), Compose plugin same version.
  - Deps: Compose BOM `2026.09.00`, Material3, Lottie `6.7.1`, Retrofit `3.0.0` + converter-gson, JUnit `4.13.2` (`testImplementation`).
  - Release build requires `planify.baseUrl` via `android/planify.properties`, `-Pplanify.baseUrl=…` or `PLANIFY_BASE_URL`; task `checkPlanifyBaseUrl` fails `preReleaseBuild` if absent. Debug defaults to `http://10.0.2.2:3000/`.
- **Shell tooling** (`scripts/`): bash (`#!/bin/bash`, `set -euo pipefail`), plus Python 3 stdlib scripts (`scripts/meteocons.py`, `scripts/demo/seed.py`). No package manifest/pyproject/lockfile.
- No web/frontend project, no Node manifest, no Makefile.

## Commands (exact)

All Gradle commands from `android/`:

```sh
cd android
./gradlew :app:assembleDebug
./gradlew :app:assembleRelease                                  # needs planify.baseUrl
./gradlew :app:testDebugUnitTest
./gradlew :app:lintDebug
./gradlew :app:testDebugUnitTest :app:lintDebug :app:assembleRelease   # documented "Pruebas" in docs/ARCHITECTURE.md:81
```

Repo-level:

```sh
scripts/install.sh --build        # build release + install on frame (needs adb/device); also --no-backup
scripts/demo.sh app [--no-build]  # demo backend + emulator + debug build/install
scripts/meteocons.py              # regenerate weather icons (needs npm + Python 3)
scripts/frame/backup.sh           # eMMC backup
```

Prereqs per README: JDK 17+, Android SDK (compileSdk 37), `adb`, `sha256sum`/`gzip`; `mtools`/`dosfstools` only for boot logo; npm/Python only for icon regen.

## Directory structure

```
android/                  Gradle project (build.gradle.kts, settings.gradle.kts, gradlew, app/)
  app/src/main/java/com/lito/planify/dashboard/
    MainActivity.kt, DashboardViewModel.kt
    data/                 Api.kt, Models.kt, Store.kt, ReferenceClock.kt, HttpError.kt, WifiStatus.kt
    data/cache/           DiskCache.kt, CachedResource.kt
    data/repository/      ContentRepository.kt, WeatherRepository.kt, CalendarRepository.kt
    admin/                Kiosk.kt, PowerMenuService.kt, ReturnButton.kt
    power/                ScreenSchedule.kt
    ui/                   App.kt + screens, WeatherUi/WeatherIcons/MeteoconFrames, FlipClock, RollingText, theme/
  app/src/main/res/       raw/ (meteocon Lottie JSON), drawable/, font/ (Geist), values/, xml/
  app/src/test/java/…     JUnit4: DiskCacheTest, CachedResourceTest, ReferenceClockTest,
                          CalendarRepositoryTest, ForecastTest, ScreenScheduleTest
scripts/                  install.sh, demo.sh, meteocons.py, config.example
  frame/                  backup.sh, planify-frame.sh, planify-frame.rc
  boot/                   boot.html, make.sh, install.sh, out/
  demo/                   seed.py
docs/                     FRAME.md, SETUP.md, ARCHITECTURE.md, ANDROID.md, README.md, inventory/, images/
third_party/meteocons/    LICENSE
licenses/                 Geist-OFL.txt
.dorch/                   changes/init/status.md only
```

## Conventions

- Docs and code comments are **Spanish**; identifiers/code are English. Commit messages Spanish, `Área: frase` style (e.g. `Hoy: la tarjeta destacada solo con lo de hoy o mañana`).
- Kotlin: `ktlint`-ish 4-space indent, KDoc with `/** … */` on public/domain classes (see `DiskCache.kt`), `runCatching` style, no wildcard imports visible.
- UI designed in native pixels: `Density(1f)` fixed; do not change system density (README/docs).
- Data layer: every remote datum cached on disk, *stale-if-error* (`DiskCache` + `CachedResource`); HTTP errors as `HttpError`; 401 clears session.
- Tests are plain JUnit4 unit tests under `app/src/test`, no instrumentation tests found.
- No `AGENTS.md`/`CLAUDE.md`/`CONTRIBUTING.md` in repo.

## Decision log / ADR

**None found.** No `ADR/`, `adr/`, `DECISIONS.md`, `docs/decisions/`, or any `*decision*` path.
`.dorch/` contains only `changes/init/status.md`; there is **no** `.dorch/memory.md` and **no** `.dorch/decisions.md`.

Exact paths if needed later (conventional defaults, not existing):
- `.dorch/memory.md`
- `.dorch/decisions.md`
- `.dorch/archive/`

## `.gitignore` (verbatim, `.gitignore` lines 1-13)

```
backups/
android/.gradle/
android/build/
android/app/build/
android/local.properties
android/.kotlin/
# Copia del repositorio de wesbos como referencia (tiene su propio git)
docs/photo-frame-dashboard/
android/planify.properties
scripts/config.local

# Entorno de demo (scripts/demo.sh)
.demo/
```

- **`.dorch/` is NOT covered.** It is currently untracked (`?? .dorch/`), not ignored. It will appear in commits unless added.
- No nested `.gitignore` files exist.

## Linter/ignore files

**None besides `.gitignore`.** Verified absence of:
`.eslintignore`, `.prettierignore`, `biome.json`, `.editorconfig`, `.ruffignore`, `ruff.toml`, `pyproject.toml`, `setup.cfg`, `tox.ini`, `requirements*.txt`, `lint.xml`, `detekt.yml`, `ktlint` config, `.shellcheckrc`, `.markdownlint*`, `Makefile`, `.github/` (no CI).

- Android lint is AGP default (`./gradlew :app:lintDebug`); no `lint { }` block in `android/app/build.gradle.kts`, no `lint.xml`. It scans the `android/` module only, so root `.dorch/` is not linted.
- Shell scripts carry only inline `# shellcheck source=/dev/null`; no shellcheck config or CI invocation.
- Python has no formatter/linter config.

## Risks / gaps

- No CI at all: tests/lint only run manually; nothing enforces them.
- Release assemble fails without `android/planify.properties` (or `-P`/env URL). CI runs would need debug/test or an injected dummy URL.
- `compileSdk 37`/AGP 9.4.1/Gradle 9.8.1 need a recent SDK+JDK; plain `./gradlew` may fail on older machines.
- If `.dorch/` is meant to be private/local, add it to `.gitignore`; currently it is commit-eligible.
- No decision log or memory file to extend; plan must create `.dorch/decisions.md` (or declare none) and possibly `.dorch/memory.md`.
- Repo is Spanish-first: new docs/comments should likely be Spanish to match.
