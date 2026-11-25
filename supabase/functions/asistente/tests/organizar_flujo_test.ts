// Integración de petición completa: núcleo + skill real `organizar` + modelo falso (y el handler).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { runKito } from "../core.ts";
import { createHandler } from "../handler.ts";
import type { HandlerDeps } from "../handler.ts";
import { organizar } from "../skills/organizar/index.ts";
import { verificar } from "../skills/organizar/confirmacion.ts";
import { ctxDe, escritorFalso, lectorFalso, modeloFalso, ok, SECRETO, texto, usa } from "./organizar_util.ts";

const mensajes = [{ role: "user" as const, content: "borra la lista Pruebas" }];
const LISTAS = [{ id: 3, name: "Pruebas", color: "#112233", sort: "title", widget: 1, dashboard: 1, pending_task_count: 2, can_edit: true }];

const montar = (secreto: string | null = SECRETO, resp = {}) => {
    const e = escritorFalso(resp);
    const ctx = ctxDe({ escribir: e.escribir, leer: lectorFalso({ "task-list": LISTAS }), secretoConfirmacion: secreto ?? undefined });
    return { ...e, ctx };
};
const correr = (ctx: ReturnType<typeof ctxDe>, ...respuestas: ReturnType<typeof usa>[]) => {
    const m = modeloFalso([...respuestas, texto("Listo.")]);
    return { m, res: runKito({ mensajes, ctx, skills: [organizar], callModel: m.call, model: "m" }) };
};

Deno.test("«borra la lista Pruebas»: tarjeta de confirmación con token verificable, sin cambios ni llamada", async () => {
    const { ctx, llamadas } = montar();
    const { m, res } = correr(ctx, usa({ name: "borrar_lista", input: { id: 3 } }));
    const r = await res;
    assertEquals(llamadas.length, 0);
    assertEquals(r.cambios, []);
    assertEquals(r.tarjetas.length, 1);
    const t = r.tarjetas[0] as Record<string, unknown>;
    assertEquals([t.tipo, t.texto], ["confirmacion", "¿Borro la lista «Pruebas» y sus tareas (2 pendientes)?"]);
    assert(typeof t.caduca === "string" && Array.isArray(t.acciones));
    const v = await verificar(t.token, SECRETO, { uid: "uid-1", homeId: "7", ahora: ctx.now.getTime() });
    assert(v.ok);
    // El modelo no ve nunca el token ni las acciones.
    const alModelo = JSON.stringify(m.cuerpos[1].messages);
    assert(!alModelo.includes(String(t.token)) && !alModelo.includes('"acciones"') && !alModelo.includes("borrar_lista\",\"args"));
    assert(alModelo.includes("propuesta enviada al usuario para confirmar"));
});

Deno.test("dos escrituras en una vuelta → una sola tarjeta con las dos acciones y sin llamadas", async () => {
    const { ctx, llamadas } = montar();
    const { res } = correr(ctx, usa(
        { name: "crear_lista", input: { nombre: "Viaje" } },
        { name: "borrar_lista", input: { id: 3 } },
    ));
    const r = await res;
    assertEquals(llamadas.length, 0);
    assertEquals(r.tarjetas.length, 1);
    const t = r.tarjetas[0] as { acciones: { op: string }[] };
    assertEquals(t.acciones.map((a) => a.op), ["crear_lista", "borrar_lista"]);
});

Deno.test("una sola alta se ejecuta al momento y la respuesta lleva cambios", async () => {
    const { ctx, llamadas } = montar(SECRETO, { "POST task-list/create": ok({ id: 11 }, 201) });
    const { res } = correr(ctx, usa({ name: "crear_lista", input: { nombre: "Viaje" } }));
    const r = await res;
    assertEquals(llamadas.length, 1);
    assertEquals(r.cambios, [{ tipo: "lista", id: 11, op: "crear" }]);
    assertEquals(r.tarjetas, []);
});

Deno.test("sin secreto: borrar se niega y las altas siguen", async () => {
    const { ctx, llamadas } = montar(null, { "POST task-list/create": ok({ id: 11 }, 201) });
    const { m, res } = correr(ctx, usa({ name: "borrar_lista", input: { id: 3 } }), usa({ name: "crear_lista", input: { nombre: "Viaje" } }));
    const r = await res;
    assertEquals(llamadas.map((l) => l.ruta), ["task-list/create"]);
    assertEquals(r.tarjetas, []);
    assert(JSON.stringify(m.cuerpos[1].messages).includes("No puedo borrar desde aquí ahora mismo."));
});

Deno.test("reintento del bucle con el mismo tool_use.id: misma client_request_id", async () => {
    const a = montar();
    const b = montar();
    for (const x of [a, b]) {
        const { res } = correr(x.ctx, usa({ name: "crear_lista", input: { nombre: "Viaje" }, id: "toolu_repetido" }));
        await res;
    }
    assertEquals(a.llamadas[0].cuerpo.client_request_id, b.llamadas[0].cuerpo.client_request_id);
});

Deno.test("handler: la respuesta lleva tarjetas y cambios, con escritor y secreto inyectados", async () => {
    const e = escritorFalso();
    const m = modeloFalso([usa({ name: "borrar_lista", input: { id: 3 } }), texto("Te dejo la confirmación.")]);
    const d: HandlerDeps = {
        verifyUser: () => Promise.resolve({ uid: "uid-1" }),
        appUserId: () => Promise.resolve("501"),
        crearLector: () => lectorFalso({ "task-list": LISTAS }),
        crearEscritor: () => e.escribir,
        checkHomeMember: () => Promise.resolve(true),
        runInHome: (_h, fn) => fn(),
        usage: { consume: () => Promise.resolve({ allowed: true, used: 1, limit: 50, day: "d" }), record: () => Promise.resolve() },
        callModel: m.call,
        model: "m",
        skills: [organizar],
        env: (n) => (n === "KITO_CONFIRM_SECRET" ? SECRETO : n === "ANTHROPIC_API_KEY" ? "k" : undefined),
        now: () => new Date("2026-11-25T10:00:00Z"),
        log: () => {},
    };
    const res = await createHandler(d)(new Request("https://x.local/asistente", {
        method: "POST",
        headers: { Authorization: "Bearer t", "X-Home-Id": "7", "Content-Type": "application/json" },
        body: JSON.stringify({ messages: mensajes, timezone: "Europe/Madrid" }),
    }));
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(body.tarjetas[0].tipo, "confirmacion");
    assertEquals(body.cambios, []);
    assertEquals(e.llamadas.length, 0);
});
