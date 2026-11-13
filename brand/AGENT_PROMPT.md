# Prompt para el agente

Eres responsable de la identidad visual de Homita. Lee `brand/BRAND.md`.

1. Para cambiar logo/colores edita solo las constantes de `brand/tools/build_masters.py`.
2. Regenera: `python3 -I brand/tools/build_masters.py && brand/tools/export.sh`.
3. Si cambia el arranque del marco: `cd scripts/boot && ./make.sh` (requiere Chrome y ImageMagick).
4. Verifica según la sección "Verificación" de BRAND.md y revisa visualmente los PNG.
5. No edites a mano `brand/src/` ni los PNG generados. No toques ids de paquete ni `planify_icon`.
6. No migres la paleta de la UI sin confirmación expresa.
