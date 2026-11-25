// POST /asistente/confirmar: token firmado → acciones en orden, sin modelo ni cupo. Todo con falsos.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { createHandler } from "../handler.ts";
import type { HandlerDeps } from "../handler.ts";
import { firmar } from "../skills/organizar/confirmacion.ts";
import type { Accion, Payload } from "../skills/organizar/confirmacion.ts";
import { escritorFalso, fallo, ok, SECRETO } from "./organizar_util.ts";
import type { Respuestas } from "./organizar_util.ts";

const TOKEN = "jwt-de-prueba";
const HOME = "42";
const AHORA = new Date("2026-11-25T10:00:00Z");
const EXP = Math.floor(AHORA.getTime() / 1000) + 600;

const montar = (o: { secreto?: string | null; resp?: Respuestas } = {}) => {
    const reg = { consume: 0, modelo: 0, enHogar: [] as (string | null)[] };
    const e = escritorFalso(o.resp);
    const secreto = o.secreto === undefined ? SECRETO : o.secreto;
    const d: HandlerDeps = {
        verifyUser: (t) => Promise.resolve(t === TOKEN ? { uid: "uid-1" } : null),
        appUserId: () => Promise.resolve("501"),
        checkHomeMember: () => Promise.resolve(true),
        runInHome: (h, fn) => {
            reg.enHogar.push(h);
            return fn();
        },
        usage: {
            consume: () => {
                reg.consume++;
                return Promise.resolve({ allowed: true, used: 1, limit: 50, day: "2026-11-25" });
            },
            record: () => Promise.resolve(),
        },
        callModel: () => {
            reg.modelo++;
            return Promise.reject(new Error("no debe llamarse"));
        },
        model: "m",
        skills: [],
        crearEscritor: () => e.escribir,
        env: (n) => (n === "KITO_CONFIRM_SECRET" ? (secreto ?? undefined) : n === "ANTHROPIC_API_KEY" ? "k" : undefined),
        now: () => AHORA,
        log: () => {},
    };
    return { d, reg, llamadas: e.llamadas };
};

const token = (acciones: Accion[], over: Partial<Payload> = {}, secreto = SECRETO) =>
    firmar({ v: 1, uid: "uid-1", home_id: HOME, exp: EXP, acciones, ...over }, secreto);

const confirmar = (d: HandlerDeps, body: unknown, over: { method?: string; home?: string } = {}) =>
    createHandler(d)(new Request("https://x.local/functions/v1/asistente/confirmar", {
        method: over.method ?? "POST",
        headers: { Authorization: `Bearer ${TOKEN}`, "X-Home-Id": over.home ?? HOME, "Content-Type": "application/json" },
        body: (over.method ?? "POST") === "GET" ? undefined : JSON.stringify(body),
    }));

const BORRAR: Accion = { op: "borrar_lista", args: { id: 3 }, nombre: "Pruebas" };

Deno.test("token válido: ejecuta las acciones en orden y devuelve {texto, cambios}", async () => {
    const { d, llamadas, reg } = montar();
    const t = await token([
        BORRAR,
        { op: "borrar_tarea", args: { id: 8 }, nombre: "Pan" },
        { op: "editar_lista", args: { id: 4, name: "X", color: "#ffffff", sort: "title", widget: true, dashboard: true }, nombre: "X" },
    ]);
    const res = await confirmar(d, { token: t, timezone: "Europe/Madrid" });
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(llamadas.map((l) => `${l.metodo} ${l.ruta}`), ["DELETE task-list/delete", "DELETE task/delete", "PATCH task-list/update"]);
    assertEquals(llamadas[0].cuerpo, { id: 3 });
    assertEquals(body.cambios, [
        { tipo: "lista", id: 3, op: "borrar" }, { tipo: "tarea", id: 8, op: "borrar" }, { tipo: "lista", id: 4, op: "editar" },
    ]);
    assert(body.texto.includes("Borrada la lista «Pruebas»"));
    assertEquals(Object.keys(body).sort(), ["cambios", "texto"]);
    assertEquals(reg.enHogar, [HOME]);
});

Deno.test("no consume cupo ni llama al modelo", async () => {
    const { d, reg } = montar();
    await confirmar(d, { token: await token([BORRAR]) });
    assertEquals([reg.consume, reg.modelo], [0, 0]);
});

Deno.test("403 sin ejecutar: caducado, manipulado, de otro uid y de otro hogar", async () => {
    const casos: [string, string, string?][] = [
        ["caducado", await token([BORRAR], { exp: EXP - 700 })],
        ["manipulado", (await token([BORRAR])).replace(/\.[^.]+$/, ".AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")],
        ["otro secreto", await token([BORRAR], {}, "otro")],
        ["otro uid", await token([BORRAR], { uid: "uid-2" })],
        ["otro hogar", await token([BORRAR], { home_id: "43" })],
    ];
    for (const [nombre, t] of casos) {
        const { d, llamadas } = montar();
        const res = await confirmar(d, { token: t });
        assertEquals(res.status, 403, nombre);
        await res.body?.cancel();
        assertEquals(llamadas.length, 0, nombre);
    }
});

Deno.test("un token de otro hogar no vale aunque el usuario sea miembro de los dos", async () => {
    const { d, llamadas } = montar();
    const res = await confirmar(d, { token: await token([BORRAR]) }, { home: "43" });
    assertEquals(res.status, 403);
    assertEquals((await res.json()).motivo, "token de otro hogar");
    assertEquals(llamadas.length, 0);
});

Deno.test("sin secreto: 503 y no se ejecuta nada (aunque el token sea de otro tiempo)", async () => {
    const { d, llamadas } = montar({ secreto: null });
    const res = await confirmar(d, { token: await token([BORRAR]) });
    assertEquals(res.status, 503);
    assertEquals((await res.json()).error, "Las confirmaciones no están disponibles");
    assertEquals(llamadas.length, 0);
});

Deno.test("autenticación primero: 405, 401, 400 de hogar y 404 de membresía antes que el 503", async () => {
    const { d } = montar({ secreto: null });
    assertEquals((await confirmar(d, {}, { method: "GET" })).status, 405);
    const sinAuth = await createHandler(d)(new Request("https://x.local/asistente/confirmar", { method: "POST", body: "{}" }));
    assertEquals(sinAuth.status, 401);
    assertEquals((await confirmar(d, {}, { home: "abc" })).status, 400);
    d.checkHomeMember = () => Promise.resolve(false);
    assertEquals((await confirmar(d, {})).status, 404);
});

Deno.test("body: sin JSON o sin token → 400", async () => {
    const { d } = montar();
    assertEquals((await confirmar(d, {})).status, 400);
    assertEquals((await confirmar(d, { token: 5 })).status, 400);
    const res = await createHandler(d)(new Request("https://x.local/asistente/confirmar", {
        method: "POST", headers: { Authorization: `Bearer ${TOKEN}`, "X-Home-Id": HOME }, body: "no-json",
    }));
    assertEquals(res.status, 400);
});

Deno.test("token reutilizado tras ya borrado → «Ya estaba hecho» y sin cambios", async () => {
    const { d } = montar({ resp: { "DELETE task-list/delete": fallo(500, "Not Found") } });
    const res = await confirmar(d, { token: await token([BORRAR]) });
    assertEquals(res.status, 200);
    const body = await res.json();
    assert(body.texto.includes("Ya estaba hecho"));
    assertEquals(body.cambios, []);
});

Deno.test("se para en la primera acción que falla y cuenta lo que sí se hizo", async () => {
    const { d, llamadas } = montar({ resp: { "DELETE task/delete": fallo(403, "Not Allowed") } });
    const t = await token([BORRAR, { op: "borrar_tarea", args: { id: 8 }, nombre: "Pan" }, { op: "borrar_tarea", args: { id: 9 }, nombre: "Leche" }]);
    const res = await confirmar(d, { token: t });
    assertEquals(res.status, 409);
    const body = await res.json();
    assertEquals(llamadas.length, 2);
    assertEquals(body.cambios, [{ tipo: "lista", id: 3, op: "borrar" }]);
    assert(body.texto.includes("Borrada la lista «Pruebas»") && body.texto.includes("No tienes permiso de edición en «Pan»."));
});

Deno.test("alta compuesta: el calendario creado y el fallo al compartir salen por separado", async () => {
    const { d } = montar({ resp: { "POST calendar/create": ok({ id: 40 }, 201), "PATCH calendar/user": fallo(403, "Not Allowed") } });
    const t = await token([{ op: "crear_calendario", args: { name: "Fútbol", color: "#6923E2", compartir: [{ user_id: 502, can_edit: false, nombre: "Lucía" }] }, nombre: "Fútbol" }]);
    const body = await (await confirmar(d, { token: t })).json();
    assertEquals(body.cambios, [{ tipo: "calendario", id: 40, op: "crear" }]);
    assert(body.texto.includes("No he podido compartirlo con Lucía"));
});
