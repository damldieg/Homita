# Homita · Sistema de marca

**Concepto — "h de hogar".** La `h` de Homita es a la vez una letra y una casa: el hombro de la h es el tejado y el punto mostaza es la luz encendida dentro. Paleta *salvia y terracota con luz*.

## Fuente única de verdad
- Geometría y colores: `brand/tools/build_masters.py` (constantes arriba). **No editar `brand/src/` a mano.**
- Flujo: `python3 -I brand/tools/build_masters.py && brand/tools/export.sh`
- Requisitos: Python 3 + `fonttools`, `rsvg-convert` (librsvg), ImageMagick.

## Colores
| Token | Hex | Uso |
|---|---|---|
| Salvia | `#4F7A63` | Fondo del icono principal |
| Bosque | `#2F4A3A` | Texto y trazos sobre claro (**nunca negro puro**) |
| Terracota | `#D9663B` | Acento, punto de la i sobre claro |
| Mostaza | `#E9B44C` | La luz (punto) sobre salvia/bosque |
| Mostaza clara | `#F6D58A` | Punto sobre terracota |
| Crema | `#F4EFE6` | Trazo de la h sobre salvia; fondos claros |
| Crema de arranque | `#F7EEE2` | Fondo del arranque del marco (**no cambiar**: enlaza con el dashboard) |

## Geometría (cuadrícula 120×120)
- Fuste `M36 24 V96`, hombro `M36 62 L60 42 L84 62 V96`, trazo 12 con extremos y uniones redondeados.
- Punto: centro (60,78), r=7. Esquina del icono redondeado: rx=27.
- Wordmark: Geist SemiBold convertido a trazados, tracking -12; el punto de la i es un círculo propio (r = mitad del fuste), 70 u sobre el fuste.

## Reglas
- Zona de respeto: ≥ 1/4 del ancho del icono alrededor del logo.
- Tamaño mínimo: icono 24 px; lockup horizontal 96 px de alto; wordmark solo, ≥ 64 px de ancho.
- Sobre fondo oscuro usar variantes `dark`; sobre una tinta, `glyph-mono-*`.
- No: rotar, estirar, cambiar colores fuera de las variantes, añadir sombras, usar negro puro, redibujar el wordmark con otra fuente.

## Matriz de activos → ruta en el repo
| Activo | Origen | Destino |
|---|---|---|
| Icono iOS claro/oscuro/tintado (1024, sin alfa) | `icon-sage`, `icon-ios-dark`, `icon-ios-tinted` | `apps/control-ios/ControlApp/Assets.xcassets/AppIcon.appiconset/` (+ `Contents.json` con apariencias) |
| Primer plano adaptativo Android 108–432 px | `android-foreground` (escala 0.62, zona segura) | `apps/{control,dashboard}/app/src/main/res/drawable-*dpi/ic_launcher_foreground.png` |
| Fondo adaptativo | — | `ic_launcher_background` = `#FF4F7A63` |
| Icono temático Android 13+ | foreground | `<monochrome>` en los `ic_launcher*.xml` |
| Login del marco | `icon-sage-rounded` 288 px | `apps/dashboard/.../drawable-nodpi/planify_icon.png` |
| Arranque del marco | `scripts/boot/boot.html` | `scripts/boot/out/*` (`scripts/boot/make.sh`) |
| README | `lockup-horizontal-light` | `docs/images/homita-logo.svg` |
| Tiendas / redes | — | `brand/exports/` |

## Verificación
1. iOS 1024 sin canal alfa (`identify -format '%[channels]'` → `srgb`, no `srgba`).
2. Android: el glifo cabe en el círculo seguro de 66 dp (ya comprobado con escala 0.62).
3. Abrir `AppIcon.appiconset` en Xcode 16+ y confirmar las tres apariencias (no probado aquí).
4. Probar un dispositivo Android 13+ con iconos temáticos.

## Fuera de alcance (decisión pendiente)
La paleta de la interfaz sigue siendo la antigua (acento rojo en iOS `Palette`, ciruela en control Android, violeta en `AccentColor`). Migrarla a salvia/terracota es opcional y no se ha tocado. Los ids de paquete `com.lito.planify` y el nombre del recurso `planify_icon` se mantienen para no romper código.
