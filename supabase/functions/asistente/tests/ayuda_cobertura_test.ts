// Cobertura de la guía de la app: cada pestaña, pantalla y formulario de apps/control-ios debe tener su sección.
// La lista es fija (no lee docs/ios-funcional.md: leerlo exigiría --allow-read en scripts/supabase/ci.sh) y sigue el
// CÓDIGO de la app, no el doc, que va por detrás (ver .dorch/changes/kito-ayuda). Si se añade o quita una
// pantalla en la app, se cambia aquí y en skills/ayuda/guia.ts. «§» = sección de docs/ios-funcional.md.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { buscar, tokens } from "../skills/ayuda/buscar.ts";
import { GUIA } from "../skills/ayuda/guia.ts";

const ESPERADAS: Record<string, string> = {
    // Pestañas (§3, §4.2). Código: Inicio, Tareas, Calendario, Menú y Hogar; Ajustes es una hoja (RootView.swift).
    "navegacion": "barra de pestañas y Ajustes como hoja",
    "inicio": "pestaña Inicio (§4.3)",
    "tareas": "pestaña Tareas (§4.4)",
    "calendario": "pestaña Calendario (§4.5)",
    "menu": "pestaña Menú: Semana, Compra, Recetas (no está en el doc)",
    "hogar": "pestaña Hogar (§4.6)",
    // Tareas y listas (§4.4, §5 Tarea y Lista)
    "listas": "Tareas › Listas",
    "lista-nueva": "Nueva lista (§5 Lista)",
    "lista-editar": "Editar lista / Eliminar lista",
    "tarea-nueva": "Nueva tarea (§5 Tarea)",
    "tarea-editar": "Editar tarea / Eliminar tarea / completar",
    "tarea-prioridad-fecha": "Prioridad y Fecha límite del editor de tarea",
    // Calendario (§4.5, §5 Evento, Rutina, Calendario)
    "evento-nuevo": "Nuevo evento (§5 Evento)",
    "evento-editar": "Editar evento / Eliminar evento",
    "rutinas": "Calendario › Rutinas",
    "rutina-nueva": "Nueva rutina (§5 Rutina)",
    "rutina-editar": "Editar rutina / Eliminar rutina",
    "calendarios": "Calendario › Calendarios",
    "calendario-nuevo": "Nuevo calendario (§5 Calendario)",
    "calendario-editar": "Editar calendario / Eliminar calendario",
    "color-calendario": "Color de calendario, lista y persona",
    // Compartir y asignar
    "compartir-lista": "Personas con acceso de una lista; permiso Lectura/Edición",
    "compartir-calendario": "Personas con acceso de un calendario; permiso Lectura/Edición",
    "asignar-personas": "panel Personas de tarea, evento y rutina",
    // Avisos
    "avisos": "Aviso de evento/rutina y Ajustes › Avisos, widgets y pantalla de bloqueo",
    "resumen-tareas": "Resumen de tareas pendientes",
    // Hogar y administración (§4.6, §5 Invitación)
    "cambiar-hogar": "Hogar › Hogar activo",
    "invitar-hogar": "Hogar › Crear invitación (§5 Invitación)",
    "unirse-hogar": "Ajustes › Unirse a un hogar con un código (§4.7)",
    "vincular-persona": "Nueva invitación › Vincular a un miembro",
    "administracion": "Administración y sus seis secciones (§4.6)",
    "admin-miembro": "admin frente a miembro (§2)",
    // Ajustes (el doc lo llama Perfil, §4.7) y personas (§5 Persona)
    "ajustes": "Ajustes: cuenta, cerrar sesión (§4.7)",
    "personas": "Ajustes › Personas (§4.7)",
    "persona-nueva": "Nueva persona (§5 Persona)",
    "enviar-feedback": "Ajustes › Enviar feedback (no está en el doc)",
    "kito": "Kito y su límite diario",
    // Entrada sin sesión y sin hogar (§4.1)
    "bienvenida": "Bienvenida",
    "login": "Iniciar sesión",
    "registro": "Registrarse",
    "sin-hogar": "No tienes ningún hogar",
};

Deno.test("cobertura: cada pantalla y formulario esperado tiene su sección en la guía", () => {
    const ids = new Set(GUIA.map((s) => s.id));
    const faltan = Object.keys(ESPERADAS).filter((id) => !ids.has(id));
    assertEquals(faltan, [], `Secciones sin cubrir: ${faltan.map((id) => `${id} (${ESPERADAS[id]})`).join(", ")}`);
});

Deno.test("cobertura: toda sección de la guía está en la lista esperada (no hay secciones huérfanas)", () => {
    const sobran = GUIA.map((s) => s.id).filter((id) => !(id in ESPERADAS));
    assertEquals(sobran, [], "Añádelas a ESPERADAS con la pantalla que cubren");
});

Deno.test("guía: ids únicos, palabras no vacías, título y texto presentes, texto ≤ 650 caracteres", () => {
    assertEquals(new Set(GUIA.map((s) => s.id)).size, GUIA.length);
    for (const s of GUIA) {
        assert(s.palabras.length > 0, `${s.id}: sin palabras`);
        assert(s.titulo.trim() !== "" && s.texto.trim() !== "", `${s.id}: vacía`);
        assert(s.texto.length <= 650, `${s.id}: ${s.texto.length} caracteres`);
        assert(s.palabras.every((p) => tokens(p).length > 0), `${s.id}: palabra vacía tras normalizar`);
    }
});

Deno.test("guía: cada sección se encuentra buscando su propio título", () => {
    for (const s of GUIA) {
        const r = buscar(s.titulo);
        assert(r.secciones.some((x) => x.id === s.id), `${s.id}: «${s.titulo}» no la devuelve (${r.secciones.map((x) => x.id).join(",")})`);
    }
});

Deno.test("guía: nada de «Perfil» como pestaña (la app tiene Menú y Ajustes) ni de «Invitar» como botón", () => {
    for (const s of GUIA) {
        assert(!/pesta[ñn]a Perfil/i.test(s.texto), s.id);
        assert(!/bot[oó]n «Invitar» de Hogar/i.test(s.texto), s.id);
    }
});
