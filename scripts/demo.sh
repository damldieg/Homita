#!/bin/bash
# Entorno de demo para probar el dashboard en el emulador y hacer las capturas del README sin datos reales.
#
# Uso: scripts/demo.sh <orden>
#   up       Edge Function `api` en local para la demo: reset de la BD del stack local
#            (supabase db reset --local), env local propio (.demo/functions.env, git lo ignora) y
#            `supabase functions serve` con datos ficticios de hoy (scripts/demo/seed.py). Cada up
#            parte de cero (reset + seed), así que siempre está al día y es repetible.
#   app      además de up: arranca el emulador (si no lo está), le pone la hora del PC, compila e
#            instala la debug y entra con la cuenta de demo (sin teclear: escribe la sesión en las
#            preferencias de la app). Con --no-build, instala la última debug compilada.
#   down     para `functions serve`; la BD del stack local queda intacta (supabase stop es aparte).
#   reset    borra .demo/ y repite up.
#
# Prerrequisitos: Supabase CLI (o npx supabase@latest), Docker y el stack local levantado
# (supabase start). La demo es solo local: jamás usa ~/.homita/supabase.env (producción).
# Variables: DEMO_AVD (Frame_API_29), DEMO_EMULATOR_PORT (5556), ANDROID_SDK (~/Android/Sdk),
# DEMO_BASE_URL (base del dashboard para la build y el token; por defecto
# http://10.0.2.2:54321/functions/v1/api/), DEMO_SKIP_EDGE=1 (no toca la Edge: el token se pide a
# la que haya servida).
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO="$HERE/.demo"
AVD="${DEMO_AVD:-Frame_API_29}"
EMULATOR_PORT="${DEMO_EMULATOR_PORT:-5556}"
SDK="${ANDROID_SDK:-$HOME/Android/Sdk}"
URL="http://127.0.0.1:54321/functions/v1/api"    # sin barra final: $URL/user/auth no debe dar //
BASE_URL="${DEMO_BASE_URL:-http://10.0.2.2:54321/functions/v1/api/}"  # con barra final (Retrofit)
EMAIL=demo@homita.example
PASSWORD=demo1234
PKG=com.lito.planify.dashboard
export ANDROID_SERIAL="emulator-$EMULATOR_PORT"

step() { echo "==> $*"; }

# Supabase CLI: `supabase` en PATH o npx
if command -v supabase >/dev/null 2>&1; then SUPA=(supabase); else SUPA=(npx supabase@latest); fi
supa() { "${SUPA[@]}" "$@"; }

# Guard (R1): solo URLs locales; nunca el proyecto alojado
local_url() { case "$1" in http://127.0.0.1:*|http://localhost:*) return 0 ;; *) return 1 ;; esac; }

check() {
    command -v docker >/dev/null 2>&1 || { echo "Falta Docker (prerrequisito de la Edge local)"; exit 1; }
    docker info >/dev/null 2>&1 || { echo "Docker no responde (prerrequisito de la Edge local)"; exit 1; }
    supa --version >/dev/null 2>&1 || { echo "Falta la Supabase CLI (supabase o npx supabase@latest)"; exit 1; }
    local api_url
    api_url="$(supa status -o env 2>/dev/null | sed -n 's/^API_URL=//p' | tr -d '"' | head -1)" || true
    [ -n "$api_url" ] || { echo "El stack local de Supabase no está levantado: supabase start"; exit 1; }
    local_url "$api_url" || { echo "API_URL no es local ($api_url): la demo nunca toca producción"; exit 1; }
}

# La CLI es una cadena npm → node → binario: se lista el árbol entero (hijos primero)
tree_pids() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do tree_pids "$c"; done; echo "$1"; }

stop() {
    [ -f "$DEMO/functions.pid" ] || return 0
    local pid
    pid="$(cat "$DEMO/functions.pid")"
    if kill -0 "$pid" 2>/dev/null; then
        # shellcheck disable=SC2046 # lista de pids del árbol, sin comillas a propósito
        kill $(tree_pids "$pid") 2>/dev/null || true
        for _ in $(seq 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    fi
    rm -f "$DEMO/functions.pid"
}

up() {
    check
    stop
    step "Base de datos local nueva (supabase db reset --local)"
    supa db reset --local
    step "Env local de la demo ($DEMO/functions.env)"
    # Solo ALLOW_REGISTRATION=true: SUPABASE_URL/ANON_KEY/SERVICE_ROLE_KEY los inyecta el runtime
    # local (R1-01). Nunca --env-file ~/.homita/supabase.env: contiene producción.
    printf 'ALLOW_REGISTRATION=true\n' > "$DEMO/functions.env"
    chmod 600 "$DEMO/functions.env"
    step "Edge Function api en $URL"
    nohup "${SUPA[@]}" functions serve api --no-verify-jwt --env-file "$DEMO/functions.env" \
        > "$DEMO/serve.log" 2>&1 < /dev/null &
    echo $! > "$DEMO/functions.pid"
    for _ in $(seq 50); do curl -fsS -o /dev/null "$URL/config" 2>/dev/null && break; sleep 0.2; done
    curl -fsS -o /dev/null "$URL/config" \
        || { echo "La Edge no responde en $URL/config (ver $DEMO/serve.log)"; exit 1; }
    step "Datos de demo"
    python3 -I "$HERE/scripts/demo/seed.py" "$URL"
    date +%F > "$DEMO/seeded"
}

emulator() {
    if ! adb devices | grep -q "^$ANDROID_SERIAL\s*device"; then
        step "Arrancando el emulador $AVD"
        # Si el PC se apagó con el emulador abierto, quedan los bloqueos del AVD y no vuelve a arrancar
        pgrep -f "[q]emu.*-avd $AVD" >/dev/null || rm -f "$HOME/.android/avd/$AVD.avd/"*.lock
        setsid "$SDK/emulator/emulator" -avd "$AVD" -port "$EMULATOR_PORT" -no-snapshot-save > "$DEMO/emulator.log" 2>&1 < /dev/null &
        local pid=$!
        until adb devices | grep -q "^$ANDROID_SERIAL\s*device"; do
            kill -0 $pid 2>/dev/null || { echo "El emulador no arrancó:"; tail -5 "$DEMO/emulator.log"; exit 1; }
            sleep 1
        done
    fi
    until [ "$(adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 1; done
    adb root >/dev/null
    adb wait-for-device
    # Al arrancar de un snapshot, el emulador conserva la hora en la que se guardó
    adb shell date "$(date +%m%d%H%M%Y.%S)" >/dev/null
}

app() {
    local build=1
    for arg in "$@"; do
        case "$arg" in
            --no-build) build=0 ;;
            *) echo "Opción desconocida: $arg"; exit 1 ;;
        esac
    done
    [ "${DEMO_SKIP_EDGE:-}" = 1 ] || up
    emulator
    local apk="$HERE/apps/dashboard/app/build/outputs/apk/debug/app-debug.apk"
    if [ $build = 1 ]; then
        step "Compilando la debug"
        (cd "$HERE/apps/dashboard" && ./gradlew -q assembleDebug -Pplanify.debugBaseUrl="$BASE_URL")
    fi
    step "Instalando"
    adb install -r "$apk" >/dev/null

    step "Sesión de demo"
    local token prefs dir api="$BASE_URL"
    api="${api/10.0.2.2/127.0.0.1}"  # 10.0.2.2 es el PC visto desde el emulador: desde el PC es 127.0.0.1
    api="${api%/}"                   # sin barra final: la ruta se añade abajo
    token="$(curl -sf "$api/user/auth" -H 'Content-Type: application/json' \
        -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')"
    dir="/data/data/$PKG"
    prefs="$(adb shell cat "$dir/shared_prefs/dashboard.xml" 2>/dev/null | tr -d '\r' || true)"
    # Sesión y ubicación de demo; el resto de ajustes (horario, brillo…) se conserva. Sin la caché de otra cuenta.
    python3 -I - "$token" "$EMAIL" "$prefs" > "$DEMO/dashboard.xml" <<'EOF'
import json, sys, xml.etree.ElementTree as ET
text = sys.argv[3].strip()
root = ET.fromstring(text.encode()) if "<map" in text else ET.Element("map")
values = {
    "token": sys.argv[1],
    "email": sys.argv[2],
    "location": json.dumps({"detail": "Comunidad Autónoma de Madrid, España", "latitude": 40.4165,
                            "longitude": -3.70256, "name": "Madrid"}, ensure_ascii=False),
}
for name, value in values.items():
    node = root.find(f"*[@name='{name}']")
    if node is None:
        node = ET.SubElement(root, "string", name=name)
    node.text = value
print("<?xml version='1.0' encoding='utf-8' standalone='yes' ?>")
print(ET.tostring(root, encoding="unicode"))
EOF
    local owner
    owner="$(adb shell stat -c %u:%g "$dir" | tr -d '\r')"
    adb shell mkdir -p "$dir/shared_prefs"
    adb push "$DEMO/dashboard.xml" "$dir/shared_prefs/dashboard.xml" >/dev/null 2>&1
    adb shell chown -R "$owner" "$dir/shared_prefs"
    adb shell chmod 660 "$dir/shared_prefs/dashboard.xml"
    adb shell rm -rf "$dir/files/cache"
    # Es el launcher: al pararla se vuelve a abrir sola, ya con la sesión nueva
    adb shell am force-stop $PKG
    adb shell am start -n "$PKG/.MainActivity" >/dev/null 2>&1
    step "Listo: $EMAIL en $ANDROID_SERIAL"
}

mkdir -p "$DEMO"
case "${1:-}" in
    up) up ;;
    app) shift; app "$@" ;;
    down) stop; step "Edge de demo parada (la BD local queda intacta)" ;;
    reset) stop; rm -rf "$DEMO"; mkdir -p "$DEMO"; up ;;
    *) sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
