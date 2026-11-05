# Decisions
<!-- Append-only, newest last. Number entries D-NNN in order. Only an entry's status may change later (active -> superseded). -->

## D-001 · 2026-11-05 · superseded
decision: Tratar Homita como monorepo y migrar el backend único a Node con NestJS; añadir clientes para gestionarlo desde iPhone (o web): calendario, planificador de comidas con menú semanal y recordatorios, además de lo que ya sirve el dashboard.
why: El marco es solo lectura contra Planify-Backend (PHP); para nuevas gestoras (comidas, recordatorios, móvil) hace falta un único backend y más clientes.
rejected: Seguir con Planify-Backend PHP — el usuario quiere Node/Nest como base común.
supersedes: none

## D-002 · 2026-11-05 · active
decision: Supabase será el backend completo del proyecto: esquema en Postgres (migrado desde SQLite), Auth (email+contraseña, JWT) sustituye la sesión de Planify, y los endpoints que la app del marco espera (`/event?dashboard=true`, `/task?dashboard=true`, semanas del calendario) se reproducen como Edge Functions. Sin Nest ni VPS. Supueseda D-001: Nest descartado; se mantiene la idea de monorepo y de añadir clientes iPhone/web (calendario, comidas/menú semanal, recordatorios).
why: Cero servidores que operar; Auth, Storage y Realtime integrados, útiles para recordatorios y sincronización en vivo de clientes iPhone/web y del marco.
rejected: Nest + Supabase como solo BD — exige VPS propio y más operación; mantener Planify-Backend PHP — no encaja con el plan de clientes propios.
supersedes: D-001

## D-003 · 2026-11-05 · active
decision: Homita es un monorepo con apps/dashboard (app del marco, hoy android/), apps/control (app gestora, hoy Planify-APP) y el contenido de Planify-Backend directamente en la raíz de api/. Marcas sin prefijo:/dashboard y control; Homita solo como nombre del proyecto. Fuera de alcance de la reestructuración: renombrar identificadores internos (com.lito.planify.dashboard), brand strings y paquetes — se decide después.
why: El usuario confirma la demo y pide juntar dashboard + gestora + backend en un solo repo con nombres propios (homita), sin prefijos redundantes y con api/ sin subcarpeta.
rejected: prefijo homita en las apps; api/homita-api o api/ backend con subcarpeta — el usuario eligió sin prefijo y raíz plana de api/.
supersedes: none
