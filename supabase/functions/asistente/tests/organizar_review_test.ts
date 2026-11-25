// Correcciones de la revisión de riesgo (R1-02..R1-05): secreto, excepciones del escritor, caducidad y frases de edición.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { createHandler } from "../handler.ts";
import type { HandlerDeps } from "../handler.ts";
import { crearEscritor } from "../skills/organizar/api.ts";
import { firmar, secretoDe, TTL_SEGUNDOS } from "../skills/organizar/confirmacion.ts";
import { HERRAMIENTAS_LISTAS } from "../skills/organizar/listas.ts";
import { HERRAMIENTAS_TAREAS } from "../skills/organizar/tareas.ts";
import { ctxDe, escritorFalso, lectorFalso, ok, SECRETO } from "./organizar_util.ts";

const AHORA = new Date("2026-11-25T10:00:00Z");
const HOME = "42";

const montar = (secretoEnv: string | undefined, escribir = escritorFalso().escribir) => {
    const d: HandlerDeps = {
        verifyUser: () => Promise.resolve({ uid: "uid-1" }),
        appUserId: () => Promise.resolve("501"),
        checkHomeMember: () => Promise.resolve(true),
        runInHome: (_h, fn) => fn(),
        usage: { consume: () => Promise.resolve({ allowed: true, used: 1, limit: 50, day: "2026-11-25" }), record: () => Promise.resolve() },
        callModel: () => Promise.reject(new Error("no")),
        model: "m",
        skills: [],
        crearEscritor: () => escribir,
        env: (n) => (n === "KITO_CONFIRM_SECRET" ? secretoEnv : n === "ANTHROPIC_API_KEY" ? "k" : undefined),
        now: () => AHORA,
        log: () => {},
    };
    return d;
};
const confirmar = (d: HandlerDeps, token: string) =>
    createHandler(d)(new Request("https://x.local/asistente/confirmar", {
        method: "POST", headers: { Authorization: "Bearer j", "X-Home-Id": HOME, "Content-Type": "application/json" },
        body: JSON.stringify({ token }),
    }));
const exp = Math.floor(AHORA.getTime() / 1000) + TTL_SEGUNDOS;
const BORRAR = { op: "borrar_lista", args: { id: 3 }, nombre: "Pruebas" };

Deno.test("R1-02 secretoDe: recorta los extremos y vacío o solo espacios = ausente", () => {
    assertEquals(secretoDe(() => `  ${SECRETO}\n`), SECRETO);
    assertEquals(secretoDe(() => "   \n"), undefined);
    assertEquals(secretoDe(() => undefined), undefined);
});

Deno.test("R1-02 secreto con espacios: lo que se firma con secretoDe se verifica en /confirmar (no 403)", async () => {
    const env = `\n ${SECRETO} `;
    const t = await firmar({ v: 1, uid: "uid-1", home_id: HOME, exp, acciones: [BORRAR] }, secretoDe(() => env)!);
    const res = await confirmar(montar(env), t);
    assertEquals(res.status, 200);
    await res.body?.cancel();
    assertEquals((await confirmar(montar("   "), t)).status, 503);
});

Deno.test("R1-03 crearEscritor: una excepción del caso de uso sale como {ok:false, status:500}, sin lanzar", async () => {
    // Sin entorno de base de datos, el caso de uso real lanza al tocar la conexión.
    const r = await crearEscritor("jwt-malo", "uid-1", "UTC")("POST", "task-list/create", { name: 1 });
    assertEquals(r.ok, false);
    assert(r.status >= 400);
});

Deno.test("R1-03 /confirmar: una excepción tras acciones hechas → 409 con los cambios hechos y mensaje claro", async () => {
    let n = 0;
    const e = escritorFalso({ "DELETE task-list/delete": ok({}) });
    const escribir: typeof e.escribir = (m, r, c) => {
        if (++n === 2) throw new Error("detalle interno");
        return e.escribir(m, r, c);
    };
    const t = await firmar({
        v: 1, uid: "uid-1", home_id: HOME, exp,
        acciones: [BORRAR, { op: "borrar_tarea", args: { id: 8 }, nombre: "Pan" }],
    }, SECRETO);
    const res = await confirmar(montar(SECRETO, escribir), t);
    assertEquals(res.status, 409);
    const b = await res.json();
    assertEquals(b.cambios, [{ tipo: "lista", id: 3, op: "borrar" }]);
    assert(b.texto.includes("Borrada la lista «Pruebas»") && b.texto.includes("No he podido hacerlo ahora mismo."));
    assert(!JSON.stringify(b).includes("detalle interno"));
});

const efectos = (r: unknown) => (r as Record<symbol, { tarjeta: Record<string, unknown> }>)[Object.getOwnPropertySymbols(r as object)[0]];
const LISTAS = [{ id: 3, name: "Compra", color: "#112233", sort: "title", widget: 1, dashboard: 1, pending_task_count: 0, can_edit: true }];
const ctxLote = (resp = {}) => {
    const e = escritorFalso(resp);
    const ctx = ctxDe({
        escribir: e.escribir, leer: lectorFalso({ "task-list": LISTAS }), secretoConfirmacion: SECRETO, now: AHORA, turno: { escrituras: 2 },
    });
    return { ...e, ctx };
};

Deno.test("R1-04 la caducidad del token es de 2 minutos", async () => {
    assertEquals(TTL_SEGUNDOS, 120);
    const { ctx } = ctxLote();
    const r = await HERRAMIENTAS_LISTAS[2].run({ id: 3 }, ctx);
    assertEquals(efectos(r).tarjeta.caduca, new Date(AHORA.getTime() + 120_000).toISOString());
});

Deno.test("R1-05 editar_lista en un lote: la frase dice campo, antes y después", async () => {
    const { ctx, llamadas } = ctxLote();
    const r = await HERRAMIENTAS_LISTAS[1].run({ id: 3, nombre: "Súper", color: "#aabbcc" }, ctx);
    assertEquals(llamadas.length, 0);
    assertEquals(efectos(r).tarjeta.texto, "¿Edito la lista «Compra»: nombre «Compra» → «Súper»; color «#112233» → «#aabbcc»?");
});

Deno.test("R1-05 editar_tarea en un lote: prioridad y fecha con antes → después", async () => {
    const { ctx } = ctxLote({ "GET task/detail": ok({ id: 5, title: "Llamar", priority: "baja", due_at: null }) });
    const r = await HERRAMIENTAS_TAREAS[1].run({ id: 5, prioridad: "alta" }, ctx);
    assertEquals(efectos(r).tarjeta.texto, "¿Edito la tarea «Llamar»: prioridad «baja» → «alta»?");
});
