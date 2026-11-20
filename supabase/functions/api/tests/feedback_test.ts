// Tests de POST /feedback (change control-ios-feedback). Sin BD ni red: fetch se sustituye por un stub.
import { assertEquals } from "jsr:@std/assert@1";
import fixture from "./fixtures/feedback_catalog.json" with { type: "json" };

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const { validateFeedback, FEEDBACK_CATALOG, FEEDBACK_SUBSECCION_MAX } = await import("../_shared/validate.ts");
const { handleFeedbackCreate } = await import("../usecases/feedback.ts");

const valid = { seccion: "Inicio", subseccion: "Tareas pendientes: Ver más", tipo: "bug", texto: "  Falla al abrir  " };

Deno.test("validateFeedback: válido recorta texto", () => {
    const v = validateFeedback(valid);
    assertEquals(v instanceof Response, false);
    assertEquals(v, { seccion: "Inicio", subseccion: "Tareas pendientes: Ver más", tipo: "bug", texto: "Falla al abrir" });
});

Deno.test("validateFeedback: subseccion opcional", () => {
    const v = validateFeedback({ ...valid, subseccion: undefined });
    assertEquals((v as { subseccion: string | null }).subseccion, null);
});

const status = (v: unknown): number | null => (v instanceof Response ? v.status : null);

Deno.test("validateFeedback: rechazos 400", () => {
    assertEquals(status(validateFeedback({ ...valid, texto: "   " })), 400);
    assertEquals(status(validateFeedback({ ...valid, texto: "x".repeat(2001) })), 400);
    assertEquals(status(validateFeedback({ ...valid, tipo: "otro" })), 400);
    assertEquals(status(validateFeedback({ ...valid, tipo: undefined })), 400);
    assertEquals(status(validateFeedback({ ...valid, seccion: "Otra" })), 400);
    assertEquals(status(validateFeedback({ ...valid, seccion: "__proto__" })), 400);
    assertEquals(status(validateFeedback({ ...valid, subseccion: "sin accion" })), 400);
    assertEquals(status(validateFeedback({ ...valid, subseccion: "Tareas pendientes: volar" })), 400);
    assertEquals(status(validateFeedback({ ...valid, subseccion: "Tareas pendientes: " })), 400);
    assertEquals(status(validateFeedback({ ...valid, subseccion: ": Ver más" })), 400);
    assertEquals(status(validateFeedback({ ...valid, subseccion: "a".repeat(100) + ": Ver" })), 400);
});

// ── catálogo nuevo vs fixture compartido ──

type Fixture = { secciones: { nombre: string; pantallas: { nombre: string; acciones: string[] }[] }[] };
const secciones = (fixture as Fixture).secciones;

Deno.test("FEEDBACK_CATALOG es igual al fixture compartido (orden y contenido)", () => {
    assertEquals(FEEDBACK_CATALOG, secciones);
});

Deno.test("fixture: invariantes del catálogo", () => {
    const dup = (xs: string[]) => new Set(xs).size !== xs.length;
    assertEquals(dup(secciones.map((s) => s.nombre)), false);
    for (const s of secciones) {
        assertEquals(s.pantallas.length > 0, true, s.nombre);
        assertEquals(dup(s.pantallas.map((p) => p.nombre)), false, s.nombre);
        for (const p of s.pantallas) {
            assertEquals(p.acciones.length > 0, true, p.nombre);
            assertEquals(dup(p.acciones), false, p.nombre);
            for (const n of [s.nombre, p.nombre, ...p.acciones]) {
                assertEquals(n.includes(": "), false, n);
                assertEquals(n, n.trim());
                assertEquals(n.length > 0, true);
            }
            for (const a of p.acciones) {
                const par = `${p.nombre}: ${a}`;
                assertEquals(par.length <= FEEDBACK_SUBSECCION_MAX, true, par);
            }
        }
    }
});

Deno.test("validateFeedback: todo par del fixture es válido", () => {
    for (const s of secciones) {
        for (const p of s.pantallas) {
            for (const a of p.acciones) {
                const subseccion = `${p.nombre}: ${a}`;
                const v = validateFeedback({ ...valid, seccion: s.nombre, subseccion });
                assertEquals(status(v), null, `${s.nombre} / ${subseccion}`);
                assertEquals((v as { subseccion: string }).subseccion, subseccion);
            }
        }
    }
});

Deno.test("validateFeedback: acciones con espacios y pantallas con camino son válidas", () => {
    assertEquals(
        status(validateFeedback({ ...valid, seccion: "Tareas", subseccion: "Detalle de lista › Editar tarea: Guardar" })),
        null,
    );
    assertEquals(status(validateFeedback({ ...valid, seccion: "Acceso", subseccion: "No tienes ningún hogar: Aceptar invitación" })), null);
    assertEquals(status(validateFeedback({ ...valid, seccion: "General / otro", subseccion: "Otro: General" })), null);
});

Deno.test("validateFeedback: combinaciones inexistentes o cruzadas -> 400", () => {
    assertEquals(status(validateFeedback({ ...valid, seccion: "Tareas" })), 400); // pantalla de Inicio
    assertEquals(status(validateFeedback({ ...valid, subseccion: "resumen del día: crear" })), 400);
    assertEquals(status(validateFeedback({ ...valid, subseccion: "Inicio: Eliminar tarea" })), 400); // acción de otra pantalla
    assertEquals(status(validateFeedback({ ...valid, seccion: "Tareas", subseccion: "Tareas: Ver más" })), 400);
    assertEquals(status(validateFeedback({ ...valid, seccion: "Tareas", subseccion: "Tareas: Editar tarea" })), null);
    assertEquals(status(validateFeedback({ ...valid, subseccion: "Tareas: Editar tarea" })), 400); // pantalla de otra sección
    assertEquals(status(validateFeedback({ ...valid, subseccion: "inventada: Ver" })), 400);
    assertEquals(status(validateFeedback({ ...valid, subseccion: "__proto__: constructor" })), 400);
});

// ── compat transitoria con el catálogo 2026-11-19 (lista literal, copia independiente del código) ──

const LEGACY_PAIRS: [string, string][] = [
    ["Inicio", "resumen del día: ver"], ["Inicio", "eventos de hoy: ver"], ["Inicio", "rutinas de hoy: crear"],
    ["Tareas", "listas: crear"], ["Tareas", "tareas: editar"],
    ["Calendario", "eventos: ver"], ["Calendario", "rutinas: eliminar"], ["Calendario", "calendarios: ver"],
    ["Hogar", "miembros: ver"], ["Hogar", "invitaciones: crear"], ["Hogar", "administradores: editar"],
    ["Hogar", "permisos: ver"],
    ["Ajustes", "perfil: editar"], ["Ajustes", "notificaciones: ver"], ["Ajustes", "cuenta: eliminar"],
];

Deno.test("validateFeedback: pares del catálogo viejo siguen válidos (transitorio)", () => {
    for (const [seccion, subseccion] of LEGACY_PAIRS) {
        assertEquals(status(validateFeedback({ ...valid, seccion, subseccion })), null, `${seccion} / ${subseccion}`);
    }
});

Deno.test("validateFeedback: el catálogo viejo sigue rechazando pares cruzados", () => {
    assertEquals(status(validateFeedback({ ...valid, seccion: "Tareas", subseccion: "eventos: ver" })), 400);
    assertEquals(status(validateFeedback({ ...valid, seccion: "Ajustes", subseccion: "listas: crear" })), 400);
    assertEquals(status(validateFeedback({ ...valid, seccion: "Hogar", subseccion: "miembros: volar" })), 400);
    assertEquals(status(validateFeedback({ ...valid, seccion: "Acceso", subseccion: "listas: ver" })), 400);
});

Deno.test("validateFeedback: límite en UTF-16 code units, emoji = 2 (R1-01)", () => {
    assertEquals(status(validateFeedback({ ...valid, texto: "😀".repeat(1000) })), null); // 2000 unidades
    assertEquals(status(validateFeedback({ ...valid, texto: "😀".repeat(1000) + "a" })), 400);
    assertEquals(status(validateFeedback({ ...valid, texto: "😀".repeat(1001) })), 400);
});

type Call = { url: string; headers: Headers; body: unknown };

const withFetch = async (
    respond: () => Response,
    fn: (calls: Call[]) => Promise<void>,
): Promise<void> => {
    const original = globalThis.fetch;
    const calls: Call[] = [];
    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
        calls.push({
            url: String(input), headers: new Headers(init?.headers),
            body: init?.body ? JSON.parse(String(init.body)) : null,
        });
        return Promise.resolve(respond());
    }) as typeof fetch;
    try {
        await fn(calls);
    } finally {
        globalThis.fetch = original;
    }
};

const post = (body: unknown): Request =>
    new Request("http://x/feedback", {
        method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
    });

const jsonRes = (status: number, body: unknown): Response =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.test("handleFeedbackCreate: inserta con el JWT del usuario y devuelve 201 {ok}", async () => {
    await withFetch(() => new Response(null, { status: 201 }), async (calls) => {
        const res = await handleFeedbackCreate(post({ ...valid, user_id: "ajeno" }), "tok-user");
        assertEquals(res.status, 201);
        assertEquals(await res.json(), { ok: true });
        assertEquals(calls.length, 1);
        assertEquals(calls[0].url, "http://stub.local/rest/v1/feedback");
        assertEquals(calls[0].headers.get("Authorization"), "Bearer tok-user");
        assertEquals(calls[0].headers.get("Prefer"), "return=minimal");
        // no se reenvía user_id del cliente; se usa solo la whitelist
        assertEquals(calls[0].body, {
            seccion: "Inicio", subseccion: "Tareas pendientes: Ver más", tipo: "bug", texto: "Falla al abrir",
        });
    });
});

Deno.test("handleFeedbackCreate: validación 400 sin llamar a PostgREST", async () => {
    await withFetch(() => new Response(null, { status: 201 }), async (calls) => {
        const res = await handleFeedbackCreate(post({ ...valid, texto: "" }), "t");
        assertEquals(res.status, 400);
        assertEquals(calls.length, 0);
    });
});

Deno.test("handleFeedbackCreate: RLS denegada -> 403", async () => {
    await withFetch(() => jsonRes(403, { code: "42501", message: "new row violates row-level security policy" }), async () => {
        const res = await handleFeedbackCreate(post(valid), "t");
        assertEquals(res.status, 403);
        // R1-02: no debe ser «Not Allowed» (la app lo mostraría como «solo propietario»)
        assertEquals((await res.json()).error, "Feedback not allowed");
    });
});

Deno.test("handleFeedbackCreate: fallo de PostgREST 5xx -> 500", async () => {
    await withFetch(() => jsonRes(500, { message: "boom" }), async () => {
        const res = await handleFeedbackCreate(post(valid), "t");
        assertEquals(res.status, 500);
    });
});
