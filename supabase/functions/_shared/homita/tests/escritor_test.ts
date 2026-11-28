// Fábrica del escritor y rutas comunes: `accept`, `food/create` y `shopping/item/check` no están en las comunes.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { crearEscritorCon, RUTAS_MENUS_COMUNES } from "../escritor.ts";
import { crearEscritor } from "../../../asistente/skills/organizar/api.ts";

const sinRed = async (fn: () => Promise<void>): Promise<number> => {
    const original = globalThis.fetch;
    let llamadas = 0;
    globalThis.fetch = (() => {
        llamadas++;
        return Promise.resolve(new Response("{}", { status: 200 }));
    }) as typeof fetch;
    try {
        await fn();
        return llamadas;
    } finally {
        globalThis.fetch = original;
    }
};

Deno.test("las rutas comunes son las 4 de menús y no incluyen accept, food/create ni shopping/item/check", () => {
    assertEquals(Object.keys(RUTAS_MENUS_COMUNES).sort(), [
        "PATCH meal/plan/items", "PATCH meal/profile/member", "POST recipe/create", "POST shopping/item/create",
    ]);
    for (const k of Object.keys(RUTAS_MENUS_COMUNES)) assert(!/accept|food\/create|item\/check/.test(k), k);
});

Deno.test("ruta desconocida -> 400 ruta no permitida y sin tocar la red", async () => {
    const llamadas = await sinRed(async () => {
        const e = crearEscritorCon(RUTAS_MENUS_COMUNES, "jwt", "uid", "Europe/Madrid");
        for (const [m, r] of [["POST", "meal/plan/accept"], ["POST", "food/create"], ["PATCH", "shopping/item/check"], ["DELETE", "task/delete"]] as const) {
            assertEquals(await e(m, r, {}), { ok: false, status: 400, data: null, error: "ruta no permitida" });
        }
    });
    assertEquals(llamadas, 0);
});

Deno.test("una lista propia puede añadir rutas; el manejador recibe token y cuerpo con la zona", async () => {
    let visto: { token: string; uid: string; cuerpo: unknown; url: string } | null = null;
    const e = crearEscritorCon({
        "POST x": async (req, token, uid) => {
            visto = { token, uid, cuerpo: await req.json(), url: req.url };
            return new Response(JSON.stringify({ ok: 1 }), { status: 201 });
        },
    }, "jwt-1", "uid-1", "Europe/Madrid");
    const r = await e("POST", "x", { a: 1 });
    assertEquals(r, { ok: true, status: 201, data: { ok: 1 } });
    assertEquals(visto!.token, "jwt-1");
    assertEquals(visto!.uid, "uid-1");
    assertEquals(visto!.cuerpo, { timezone: "Europe/Madrid", a: 1 });
});

Deno.test("un manejador que lanza vuelve como 500 y un error JSON conserva su texto", async () => {
    const e = crearEscritorCon({
        "POST boom": () => Promise.reject(new Error("x")),
        "POST mal": () => Promise.resolve(new Response(JSON.stringify({ error: "Invalid recipe" }), { status: 400 })),
    }, "t", "u", "Europe/Madrid");
    assertEquals(await e("POST", "boom"), { ok: false, status: 500, data: null });
    assertEquals(await e("POST", "mal"), { ok: false, status: 400, data: { error: "Invalid recipe" }, error: "Invalid recipe" });
});

Deno.test("Kito sigue con 24 rutas y sin accept (comprobado por comportamiento)", async () => {
    const llamadas = await sinRed(async () => {
        const e = crearEscritor("jwt", "uid", "Europe/Madrid");
        assertEquals((await e("POST", "meal/plan/accept", { plan_id: 1, expected_revision: 1 })).error, "ruta no permitida");
        assertEquals((await e("POST", "food/create", { name: "x" })).error, "ruta no permitida");
        assertEquals((await e("PATCH", "shopping/item/check", { id: 1, state: "checked" })).error, "ruta no permitida");
    });
    assertEquals(llamadas, 0);
});

Deno.test("RUTAS_ORGANIZAR: 20 rutas (16 operaciones, compartir y 3 detalles), sin accept ni alarmas ni administración", async () => {
    const { RUTAS_ORGANIZAR } = await import("../escritor.ts");
    const { OPS } = await import("../organizar/acciones.ts");
    const claves = Object.keys(RUTAS_ORGANIZAR).sort();
    assertEquals(claves.length, 20);
    for (const o of Object.values(OPS)) assert(`${o.metodo} ${o.ruta}` in RUTAS_ORGANIZAR, o.ruta);
    assertEquals(claves.filter((k) => k.startsWith("GET ")), ["GET event/detail", "GET routine/detail", "GET task/detail"]);
    assert(claves.includes("PATCH calendar/user"));
    for (const k of claves) assert(!/accept|alarm|invit|membership|home\/|food|shopping|meal/.test(k), k);
});

Deno.test("Kito compone organizar + menús comunes: 24 rutas, sin accept", async () => {
    const { RUTAS } = await import("../../../asistente/skills/organizar/api.ts");
    const claves = Object.keys(RUTAS);
    assertEquals(claves.length, 24);
    assert(!claves.some((k) => /accept/.test(k)));
});
