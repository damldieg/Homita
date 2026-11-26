// T3 kito-menus: rutas del api que puede llamar Kito. Aceptar el menú NO es una de ellas (Kito nunca acepta).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { crearLector } from "../skills/consulta/api.ts";
import { crearEscritor } from "../skills/organizar/api.ts";
import { OPS_PERMITIDAS } from "../skills/organizar/confirmacion.ts";

const sinRed = async (fn: () => Promise<void>) => {
    const original = globalThis.fetch;
    let llamadas = 0;
    globalThis.fetch = (() => {
        llamadas++;
        return Promise.resolve(new Response(JSON.stringify({ ok: true }), { status: 200 }));
    }) as typeof fetch;
    try {
        await fn();
        return llamadas;
    } finally {
        globalThis.fetch = original;
    }
};

Deno.test("accept no es invocable desde Kito: ni el escritor ni el lector, y sin tocar la red", async () => {
    const llamadas = await sinRed(async () => {
        const e = crearEscritor("jwt", "uid-1", "Europe/Madrid", "7");
        for (const [m, r] of [
            ["POST", "meal/plan/accept"], ["POST", "meal/plan/archive"], ["POST", "meal/plan/copy"],
            ["PATCH", "meal/profile"], ["PUT", "meal/schedule"], ["DELETE", "recipe/delete"], ["PATCH", "recipe/update"],
            ["POST", "shopping/sync"], ["DELETE", "shopping/item/delete"],
        ] as const) {
            const res = await e(m as "POST", r, { plan_id: 1, expected_revision: 1 });
            assertEquals(res.ok, false, `${m} ${r}`);
            assertEquals(res.status, 400, `${m} ${r}`);
            assertEquals(res.error, "ruta no permitida", `${m} ${r}`);
        }
        const l = crearLector("jwt", "uid-1", "Europe/Madrid");
        for (const r of ["meal/plan/accept", "meal/plan/archive", "meal/schedule", "shopping", "recipe/delete"]) {
            assertEquals(await l(r), { error: "ruta no permitida" }, r);
        }
    });
    assertEquals(llamadas, 0);
});

Deno.test("accept no entra en las operaciones de la confirmación firmada de organizar", () => {
    for (const op of OPS_PERMITIDAS) assert(!/accept|aceptar|menu|meal/i.test(op), op);
});

Deno.test("las rutas de escritura de la skill menus sí están permitidas (llegan al caso de uso, no se rechazan por ruta)", async () => {
    await sinRed(async () => {
        const e = crearEscritor("jwt", "uid-1", "Europe/Madrid", "7");
        for (const [m, r] of [
            ["PATCH", "meal/plan/items"], ["POST", "recipe/create"], ["POST", "shopping/item/create"],
            ["PATCH", "meal/profile/member"],
        ] as const) {
            const res = await e(m, r, {});
            assert(res.error !== "ruta no permitida", `${m} ${r}`);
        }
    });
});

Deno.test("las rutas de lectura de la skill menus están en el lector", async () => {
    await sinRed(async () => {
        const l = crearLector("jwt", "uid-1", "Europe/Madrid");
        for (const r of ["meal/profile", "meal/plan", "meal/plan/check", "recipe", "recipe/detail", "food"]) {
            const res = await l(r, { week_start: "2030-01-07", plan_id: "1", id: "1" });
            assert(!(typeof res === "object" && res !== null && (res as { error?: unknown }).error === "ruta no permitida"), r);
        }
    });
});
