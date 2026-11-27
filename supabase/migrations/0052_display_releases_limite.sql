-- 0052_display_releases_limite.sql — dashboard-actualizacion-remota (revisión R1-07): tope de tamaño del bucle de
-- publicaciones. Un APK de 64 MiB no cabía en el límite global de 50 MiB; el bucle lleva su propio tope de 100 MiB.
-- Aditiva: solo cambia el bucle que creó 0051. Idempotente.

update storage.buckets set file_size_limit = 104857600 where id = 'display-releases';
