// Lector compartido: cada ruta llega al caso de uso correcto con el JWT del usuario; `leerRuta` no envuelve los
// errores y `crearLector` conserva el contrato de Kito. Sin red: `fetch` es falso.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { crearLector, leerRuta, RUTAS_COMPRA, RUTAS_KITO } from "../lector.ts";

interface Llamada {
    url: string;
    auth: string | undefined;
}

const conRed = async <T>(responder: (url: string) => Response, fn: (llamadas: Llamada[]) => Promise<T>): Promise<T> => {
    const original = globalThis.fetch;
    const llamadas: Llamada[] = [];
    globalThis.fetch = ((u: string | URL | Request, init?: RequestInit) => {
        const url = String(u);
        llamadas.push({ url, auth: (init?.headers as Record<string, string> | undefined)?.Authorization });
        return Promise.resolve(responder(url));
    }) as typeof fetch;
    try {
        return await fn(llamadas);
    } finally {
        globalThis.fetch = original;
    }
};

const ok = (url: string): Response => new Response(url.includes("app_user") ? '[{"id":1}]' : "[]");

// ruta -> [parámetros, RPC final del caso de uso]
const RUTAS: Record<string, [Record<string, string>, string]> = {
    "event": [{}, "get_events"],
    "routine": [{}, "get_routines"],
    "task": [{}, "get_tasks"],
    "task-list": [{}, "get_task_lists"],
    "person": [{}, "get_persons"],
    "calendar": [{}, "get_calendars"],
    "calendar/user": [{ calendar_id: "3" }, "get_calendar_users"],
    "home": [{}, "get_homes"],
    "meal/profile": [{}, "get_meal_profile"],
    "meal/plan": [{ week_start: "2026-11-23" }, "get_meal_plan"],
    "meal/plan/check": [{ plan_id: "1" }, "check_meal_plan"],
    "recipe": [{}, "list_recipes"],
    "recipe/detail": [{ id: "4" }, "get_recipe"],
    "food": [{ q: "pan" }, "search_food"],
    "shopping": [{}, "list_shopping"],
    "shopping/preview": [{ plan_id: "2" }, "preview_meal_shopping"],
};

Deno.test("la lista de rutas del lector es la de Kito más la compra", () => {
    assertEquals([...RUTAS_KITO, ...RUTAS_COMPRA].sort(), Object.keys(RUTAS).sort());
});

for (const [ruta, [params, rpc]] of Object.entries(RUTAS)) {
    Deno.test(`leerRuta ${ruta}: llama a ${rpc} con el JWT del usuario`, async () => {
        await conRed(ok, async (llamadas) => {
            const r = await leerRuta(ruta, params, "JWT-USUARIO", "uid-1", "Europe/Madrid");
            assertEquals(r.ok, true);
            assertEquals(r.status, 200);
            const ultima = llamadas[llamadas.length - 1];
            assert(ultima.url.endsWith(`/rest/v1/rpc/${rpc}`), `${ruta}: ${ultima.url}`);
            assertEquals(ultima.auth, "Bearer JWT-USUARIO");
        });
    });
}

Deno.test("leerRuta: un error del api vuelve con su estado y sin envolver", async () => {
    await conRed(() => new Response('{"message":"Not Allowed"}', { status: 400 }), async () => {
        const r = await leerRuta("task-list", {}, "t", "u", "Europe/Madrid");
        assertEquals({ ok: r.ok, status: r.status, body: r.body }, { ok: false, status: 403, body: { error: "Not Allowed" } });
    });
});

Deno.test("leerRuta: ruta desconocida -> ok false sin tocar la red", async () => {
    await conRed(ok, async (llamadas) => {
        for (const ruta of ["meal/plan/accept", "shopping/sync", "constructor", "__proto__", "task/delete"]) {
            const r = await leerRuta(ruta, {}, "t", "u", "Europe/Madrid");
            assertEquals(r.ok, false, ruta);
            assertEquals(r.body, { error: "ruta no permitida" }, ruta);
        }
        assertEquals(llamadas.length, 0);
    });
});

Deno.test("leerRuta: un cuerpo que no es JSON se devuelve como texto (json false)", async () => {
    await conRed(() => new Response("<html>", { status: 200 }), async () => {
        const r = await leerRuta("task-list", {}, "t", "u", "Europe/Madrid");
        assertEquals(r.json, false);
        assertEquals(r.body, "<html>");
    });
});

Deno.test("crearLector: error del api -> {error, detalle}; no JSON -> respuesta no válida; datos tal cual", async () => {
    await conRed(() => new Response('{"message":"Not Allowed"}', { status: 400 }), async () => {
        assertEquals(await crearLector("t", "u", "Europe/Madrid")("task-list"), { error: 403, detalle: '{"error":"Not Allowed"}' });
    });
    await conRed(() => new Response("<html>", { status: 200 }), async () => {
        assertEquals(await crearLector("t", "u", "Europe/Madrid")("task-list"), { error: "respuesta no válida" });
    });
    await conRed(() => new Response('[{"id":1}]', { status: 200 }), async () => {
        assertEquals(await crearLector("t", "u", "Europe/Madrid")("task-list"), [{ id: 1 }]);
    });
});

Deno.test("crearLector: la compra no está en el lector de Kito", async () => {
    await conRed(ok, async (llamadas) => {
        const l = crearLector("t", "u", "Europe/Madrid");
        for (const ruta of RUTAS_COMPRA) assertEquals(await l(ruta), { error: "ruta no permitida" }, ruta);
        assertEquals(llamadas.length, 0);
    });
});
