#!/usr/bin/env bash
# Rasteriza los SVG maestros de brand/src/ a todos los PNG que usa el repo.
# Uso:  brand/tools/build_masters.py && brand/tools/export.sh
# Requiere: rsvg-convert (librsvg) e ImageMagick (convert o magick). En macOS: brew install librsvg imagemagick
set -euo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SRC="$ROOT/brand/src"
command -v rsvg-convert >/dev/null || { echo "Falta rsvg-convert (librsvg)"; exit 1; }
IM=$(command -v magick || command -v convert) || { echo "Falta ImageMagick"; exit 1; }

png() { # png <svg> <ancho> <alto> <destino>   (conserva transparencia)
    mkdir -p "$(dirname "$4")"
    rsvg-convert -w "$2" -h "$3" "$SRC/$1" -o "$4"
}
opaque() { # opaque <svg> <lado> <destino>   (sin canal alfa: exigido por App Store)
    local tmp; tmp="$(mktemp --suffix=.png 2>/dev/null || mktemp -t homita).png"
    png "$1" "$2" "$2" "$tmp"
    "$IM" "$tmp" -alpha off -type TrueColor "$3"; rm -f "$tmp"
}

# iOS: un solo tamaño (1024) por apariencia; Xcode genera el resto
APPICON="$ROOT/apps/control-ios/ControlApp/Assets.xcassets/AppIcon.appiconset"
opaque icon-sage.svg      1024 "$APPICON/AppIcon-1024.png"
opaque icon-ios-dark.svg  1024 "$APPICON/AppIcon-1024-dark.png"
opaque icon-ios-tinted.svg 1024 "$APPICON/AppIcon-1024-tinted.png"
cat > "$APPICON/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "AppIcon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "AppIcon-1024-dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "AppIcon-1024-tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# Android (control y dashboard): primer plano del icono adaptativo, lienzo 108 dp
for app in control dashboard; do
    RES="$ROOT/apps/$app/app/src/main/res"
    png android-foreground.svg 108 108 "$RES/drawable-mdpi/ic_launcher_foreground.png"
    png android-foreground.svg 162 162 "$RES/drawable-hdpi/ic_launcher_foreground.png"
    png android-foreground.svg 216 216 "$RES/drawable-xhdpi/ic_launcher_foreground.png"
    png android-foreground.svg 324 324 "$RES/drawable-xxhdpi/ic_launcher_foreground.png"
    png android-foreground.svg 432 432 "$RES/drawable-xxxhdpi/ic_launcher_foreground.png"
done
# Pantalla de login del marco (se pinta a 144 dp; 288 px = nítido a 2x)
png icon-sage-rounded.svg 288 288 "$ROOT/apps/dashboard/app/src/main/res/drawable-nodpi/planify_icon.png"

# README y docs
mkdir -p "$ROOT/docs/images"; cp "$SRC/lockup-horizontal-light.svg" "$ROOT/docs/images/homita-logo.svg"

# Exportaciones listas para usar fuera del repo (tiendas, redes, presentaciones)
EX="$ROOT/brand/exports"
opaque icon-sage.svg 512 "$EX/play-store-512.png"
png icon-sage-rounded.svg       512 512 "$EX/icon-sage-512.png"
png icon-terracota-rounded.svg  512 512 "$EX/icon-terracota-512.png"
png icon-light-rounded.svg      512 512 "$EX/icon-light-512.png"
png lockup-horizontal-light.svg 1209 288 "$EX/lockup-horizontal-light@3x.png"
png lockup-horizontal-dark.svg  1209 288 "$EX/lockup-horizontal-dark@3x.png"
png lockup-stacked-light.svg    1200 840 "$EX/lockup-stacked-light@3x.png"
echo "Exportado. Revisa con: git status --short"
