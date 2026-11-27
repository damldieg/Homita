#!/bin/bash
# Publica una versión de la app de las pantallas (dashboard-actualizacion-remota). La firma la hace Damian en su Mac:
# este script solo sube el APK ya firmado y el manifiesto del canal al bucket privado `display-releases`.
#
# Uso: scripts/dashboard/publish.sh --apk <ruta.apk> --code <versionCode> --name <versionName> --channel estable|pruebas [--dry-run]
#
# Entorno (nunca en el repo ni en la salida del script):
#   HOMITA_SUPABASE_URL          URL del proyecto (https://<ref>.supabase.co o http://127.0.0.1:54321 en local)
#   HOMITA_SERVICE_ROLE_KEY      clave de servicio (sube objetos al bucket). Solo para la publicación.
#
# Vuelta atrás: PackageInstaller no baja versiones; para volver a una versión buena, se publica esa misma APK con un
# versionCode mayor (--code N+1). Ver docs/SETUP.md, «Publicar una versión».
set -euo pipefail

BUCKET="display-releases"
APK=""; CODE=""; NAME=""; CHANNEL=""; DRY_RUN=0

die() { echo "publish.sh: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --apk) APK="${2:-}"; shift 2 ;;
        --code) CODE="${2:-}"; shift 2 ;;
        --name) NAME="${2:-}"; shift 2 ;;
        --channel) CHANNEL="${2:-}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        *) die "argumento desconocido: $1" ;;
    esac
done

[ -n "$APK" ] && [ -f "$APK" ] || die "--apk: archivo no encontrado"
[[ "$CODE" =~ ^[1-9][0-9]{0,8}$ ]] || die "--code: entero positivo"
[[ "$NAME" =~ ^[A-Za-z0-9._-]{1,40}$ ]] || die "--name: 1-40 caracteres [A-Za-z0-9._-]"
case "$CHANNEL" in estable|pruebas) ;; *) die "--channel: estable o pruebas" ;; esac

# Firma: no se publica una APK firmada con la clave debug (es pública; ver plan.md, punto 2).
APKSIGNER="$(command -v apksigner || true)"
if [ -z "$APKSIGNER" ]; then
    SDK="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
    APKSIGNER="$(ls -1d "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1 || true)"
fi
if [ -n "$APKSIGNER" ] && [ -x "$APKSIGNER" ]; then
    CERT="$("$APKSIGNER" verify --print-certs "$APK" 2>/dev/null || true)"
    echo "$CERT" | grep -q "Android Debug" && die "la APK está firmada con la clave debug: no se publica"
    echo "$CERT" | grep -q "Signer #1" || die "la APK no está firmada (apksigner no encuentra firma)"
else
    die "no se encuentra apksigner (PATH o Android SDK build-tools): no se puede comprobar la firma"
fi

# El versionCode y el paquete del APK deben ser los que se declaran (R1-06): si no, Android rechazaría la instalación.
AAPT2="$(ls -1d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/*/aapt2 2>/dev/null | sort -V | tail -1 || true)"
if [ -n "$AAPT2" ] && [ -x "$AAPT2" ]; then
    BADGING="$("$AAPT2" dump badging "$APK" 2>/dev/null || true)"
    echo "$BADGING" | grep -q "package: name='com.dld.homita.dashboard'" || die "el APK no es el paquete com.dld.homita.dashboard"
    echo "$BADGING" | grep -q "versionCode='${CODE}'" || die "el versionCode del APK no es $CODE"
else
    die "no se encuentra aapt2 (Android SDK build-tools): no se puede comprobar el versionCode"
fi

SHA="$(shasum -a 256 "$APK" | cut -d' ' -f1)"
SIZE="$(wc -c < "$APK" | tr -d ' ')"
# Tope del bucle (ver la migración 0052): por encima no se sube.
[ "$SIZE" -le 104857600 ] || die "el APK pesa más de 100 MiB (límite del bucle display-releases)"
# La ruta lleva el hash: otro binario con el mismo versionCode no pisa al publicado (R1-06).
FILE="v${CODE}-${SHA:0:12}/homita.apk"
MANIFEST="$(python3 -I -c '
import json, sys
print(json.dumps({"version_code": int(sys.argv[1]), "version_name": sys.argv[2], "sha256": sys.argv[3],
                  "size": int(sys.argv[4]), "file": sys.argv[5]}, indent=2))
' "$CODE" "$NAME" "$SHA" "$SIZE" "$FILE")"

if [ "$DRY_RUN" = 1 ]; then
    echo "# Manifiesto que se escribiría en ${CHANNEL}.json (dry-run, nada subido):"
    echo "$MANIFEST"
    echo "# APK: $FILE ($SIZE bytes)"
    exit 0
fi

[ -n "${HOMITA_SUPABASE_URL:-}" ] || die "falta HOMITA_SUPABASE_URL"
[ -n "${HOMITA_SERVICE_ROLE_KEY:-}" ] || die "falta HOMITA_SERVICE_ROLE_KEY"

upload() { # $1 = ruta en el bucket, $2 = tipo, $3 = fichero, $4 = 'overwrite' para el manifiesto
    local status upsert="false"
    [ "${4:-}" = "overwrite" ] && upsert="true"
    # Las cabeceras con la clave van por stdin a curl -K: no aparecen en la línea de comandos (ps) (R1-14).
    status="$(printf 'header = "apikey: %s"\nheader = "Authorization: Bearer %s"\nheader = "x-upsert: %s"\nheader = "Content-Type: %s"\n' \
        "$HOMITA_SERVICE_ROLE_KEY" "$HOMITA_SERVICE_ROLE_KEY" "$upsert" "$2" \
        | curl -sS -K - -o /dev/null -w '%{http_code}' -X POST \
            "${HOMITA_SUPABASE_URL%/}/storage/v1/object/${BUCKET}/$1" --data-binary "@$3")"
    # 409 en el APK: ya estaba con este mismo hash (la ruta lo lleva): se da por bueno.
    if [ "$status" = "409" ] && [ "$4" != "overwrite" ]; then return 0; fi
    [ "$status" = "200" ] || die "subida de $1 fallida (HTTP $status)"
}

# Primero el APK (el manifiesto apunta a él); después el manifiesto del canal.
upload "$FILE" "application/vnd.android.package-archive" "$APK"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
printf '%s\n' "$MANIFEST" > "$TMP"
upload "${CHANNEL}.json" "application/json" "$TMP" overwrite
echo "Publicada la versión $NAME ($CODE) en el canal $CHANNEL: $FILE ($SIZE bytes, sha256 $SHA)."
