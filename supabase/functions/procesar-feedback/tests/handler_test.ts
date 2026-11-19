// Tests de handler.ts (change feedback-trello-gate): auth, body, reserva, gate, efectos en Trello, final
// atómico y compensación. Sin red ni BD: fetch y db falsos que registran las llamadas.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { createHandler } from "../handler.ts";
import { DbError } from "../db.ts";
import type { FeedbackDb, FinalizeArgs } from "../db.ts";
import type { FeedbackRow } from "../gate.ts";
import { markerLine } from "../gate.ts";
import type { TrelloCard } from "../trello.ts";

const SECRET = "local-test-no-real";
const REPORT = "TEXTO-SECRETO-DEL-USUARIO la lista no carga";
const ENV: Record<string, string> = {
    FEEDBACK_WEBHOOK_SECRET: SECRET,
    TRELLO_KEY: "kkk-test",
    TRELLO_TOKEN: "ttt-test",
    TRELLO_LIST_ID: "LIST1",
    ANTHROPIC_API_KEY: "aaa-test",
};

const ROW: FeedbackRow = { id: 7, texto: REPORT, seccion: "Compras", subseccion: null, tipo: "bug" };
const CARDS: TrelloCard[] = [
    { id: "c1", name: "Lista lenta", desc: "d1", shortUrl: "https://trello.com/c/1", dateLastActivity: "2026-01-02" },
    { id: "c2", name: "Otra", desc: "d2", shortUrl: "https://trello.com/c/2", dateLastActivity: "2026-01-01" },
];

// --- db falso -------------------------------------------------------------------------------------
type DbOpts = {
    claimable?: boolean;
    exists?: boolean;
    failFinalize?: boolean;
    /** finalize confirma (COMMIT) y después devuelve error de red: la fila queda 'procesado'. */
    finalizeCommitsThenFails?: boolean;
    failGetEstado?: boolean;
    failMarkError?: boolean;
    failClaim?: boolean;
};
const fakeDb = (o: DbOpts = {}) => {
    const calls: string[] = [];
    const finalized: FinalizeArgs[] = [];
    let available = o.claimable ?? true; // la reserva solo se concede una vez
    let estado = "pendiente";
    let backlogId: number | null = null;
    const db: FeedbackDb = {
        claim(id) {
            calls.push(`claim:${id}`);
            if (o.failClaim) return Promise.reject(new DbError("claim", "XX000"));
            if (!available) return Promise.resolve(null);
            available = false;
            return Promise.resolve({ ...ROW, id });
        },
        exists(id) {
            calls.push(`exists:${id}`);
            return Promise.resolve(o.exists ?? true);
        },
        markError(id) {
            calls.push(`markError:${id}`);
            return o.failMarkError ? Promise.reject(new DbError("markError", "57014")) : Promise.resolve();
        },
        getEstado(id) {
            calls.push(`getEstado:${id}`);
            if (o.failGetEstado) return Promise.reject(new TypeError("fetch failed https://db.example"));
            return Promise.resolve({ estado, backlogId });
        },
        finalize(a) {
            calls.push(`finalize:${a.feedbackId}`);
            if (o.failFinalize) return Promise.reject(new DbError("finalize", "P0001"));
            finalized.push(a);
            estado = "procesado";
            backlogId = 99;
            if (o.finalizeCommitsThenFails) return Promise.reject(new TypeError("fetch failed https://db.example"));
            return Promise.resolve(99);
        },
    };
    return { db, calls, finalized };
};

// --- fetch falso ----------------------------------------------------------------------------------
type Call = { method: string; url: string; body: unknown };
type FetchOpts = {
    cards?: TrelloCard[];
    listStatus?: number;
    anthropic?: () => Response;
    createStatus?: number;
    commentStatus?: number;
    archiveStatus?: number;
};
const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
const toolMsg = (name: string, input: unknown) => () =>
    json(200, { content: [{ type: "tool_use", id: "t", name, input }] });

const fakeFetch = (o: FetchOpts = {}) => {
    const calls: Call[] = [];
    const fn = ((input: string | URL | Request, init?: RequestInit) => {
        const url = String(input);
        const method = init?.method ?? "GET";
        const body = init?.body ? JSON.parse(String(init.body)) : undefined;
        calls.push({ method, url, body });
        if (url.startsWith("https://api.anthropic.com/")) {
            return Promise.resolve((o.anthropic ?? toolMsg("crear_tarjeta", { titulo: "Nueva", descripcion: "Desc" }))());
        }
        if (method === "GET" && url.includes("/lists/LIST1/cards")) {
            return Promise.resolve(json(o.listStatus ?? 200, o.cards ?? CARDS));
        }
        if (method === "POST" && url.endsWith("/1/cards")) {
            return Promise.resolve(json(o.createStatus ?? 200, { id: "new1", shortUrl: "https://trello.com/c/new1" }));
        }
        if (method === "POST" && url.includes("/actions/comments")) return Promise.resolve(json(o.commentStatus ?? 200, { id: "a" }));
        if (method === "PUT") return Promise.resolve(json(o.archiveStatus ?? 200, { closed: true }));
        return Promise.resolve(json(404, {}));
    }) as typeof fetch;
    return { fn, calls };
};

const isAnthropic = (c: Call) => c.url.startsWith("https://api.anthropic.com/");
const isCreate = (c: Call) => c.method === "POST" && c.url.endsWith("/1/cards");
const isComment = (c: Call) => c.url.includes("/actions/comments");
const isArchive = (c: Call) => c.method === "PUT";
const trelloWrites = (calls: Call[]) => calls.filter((c) => c.url.includes("trello.com") && c.method !== "GET");

const setup = (dbo: DbOpts = {}, fo: FetchOpts = {}, env: Record<string, string> = ENV) => {
    const d = fakeDb(dbo);
    const f = fakeFetch(fo);
    const logs: string[] = [];
    const handler = createHandler({
        db: d.db,
        fetch: f.fn,
        env: (k) => env[k],
        now: () => new Date("2026-11-19T00:00:00Z"),
        log: (m) => logs.push(m),
    });
    return { ...d, fetchCalls: f.calls, logs, handler };
};

const req = (body: unknown, secret: string | null = SECRET) => {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (secret !== null) headers["x-feedback-secret"] = secret;
    return new Request("http://x/procesar-feedback", {
        method: "POST",
        headers,
        body: typeof body === "string" ? body : JSON.stringify(body),
    });
};
const ok = (id = 7) => req({ type: "INSERT", record: { id } });

const assertCleanLogs = (logs: string[]) => {
    for (const l of logs) {
        assert(!l.includes("TEXTO-SECRETO"), `log con el reporte: ${l}`);
        for (const v of Object.values(ENV)) assert(!l.includes(v), `log con un secreto: ${l}`);
        assert(!l.includes("https://"), `log con URL: ${l}`);
    }
};

// --- auth -----------------------------------------------------------------------------------------
Deno.test("auth: sin cabecera -> 401 sin db ni fetch", async () => {
    const s = setup();
    const r = await s.handler(req({ record: { id: 7 } }, null));
    assertEquals(r.status, 401);
    assertEquals(s.calls, []);
    assertEquals(s.fetchCalls, []);
});

Deno.test("auth: cabecera incorrecta -> 401 sin db ni fetch", async () => {
    const s = setup();
    for (const bad of ["otro", "", `${SECRET}x`, SECRET.slice(0, -1)]) {
        const r = await s.handler(req({ record: { id: 7 } }, bad));
        assertEquals(r.status, 401);
    }
    assertEquals(s.calls, []);
    assertEquals(s.fetchCalls, []);
});

Deno.test("auth: secreto no configurado (o vacío) -> 500 sin efectos", async () => {
    for (const env of [{ ...ENV, FEEDBACK_WEBHOOK_SECRET: "" }, (({ FEEDBACK_WEBHOOK_SECRET: _, ...rest }) => rest)(ENV)]) {
        const s = setup({}, {}, env);
        const r = await s.handler(ok());
        assertEquals(r.status, 500);
        assertEquals(s.calls, []);
        assertEquals(s.fetchCalls, []);
    }
});

// --- body y reserva -------------------------------------------------------------------------------
Deno.test("body inválido o record.id no entero positivo -> 400 sin db", async () => {
    const s = setup();
    for (const b of ["no json", { record: {} }, { record: { id: "7" } }, { record: { id: 0 } }, { record: { id: 1.5 } }, { record: { id: 2 ** 60 } }, {}]) {
        assertEquals((await s.handler(req(b))).status, 400);
    }
    assertEquals(s.calls, []);
    assertEquals(s.fetchCalls, []);
});

Deno.test("configuración de Trello/Anthropic incompleta -> 500 sin reservar", async () => {
    const s = setup({}, {}, { ...ENV, TRELLO_LIST_ID: "" });
    assertEquals((await s.handler(ok())).status, 500);
    assertEquals(s.calls, []);
    assertEquals(s.fetchCalls, []);
});

Deno.test("id inexistente -> 404 sin fetch", async () => {
    const s = setup({ claimable: false, exists: false });
    assertEquals((await s.handler(ok())).status, 404);
    assertEquals(s.calls, ["claim:7", "exists:7"]);
    assertEquals(s.fetchCalls, []);
});

Deno.test("ya procesado o en curso -> 200 sin efectos", async () => {
    const s = setup({ claimable: false, exists: true });
    const r = await s.handler(ok());
    assertEquals(r.status, 200);
    assertEquals(await r.text(), "ya procesado o en curso");
    assertEquals(s.fetchCalls, []);
});

Deno.test("reserva concedida una vez: dos invocaciones -> 1 POST de tarjeta y 1 finalize", async () => {
    const s = setup();
    const [a, b] = await Promise.all([s.handler(ok()), s.handler(ok())]);
    assertEquals([a.status, b.status].sort(), [200, 200]);
    assertEquals(s.fetchCalls.filter(isCreate).length, 1);
    assertEquals(s.fetchCalls.filter(isAnthropic).length, 1);
    assertEquals(s.finalized.length, 1);
});

Deno.test("reserva falla -> 500 sin fetch ni markError", async () => {
    const s = setup({ failClaim: true });
    assertEquals((await s.handler(ok())).status, 500);
    assertEquals(s.calls, ["claim:7"]);
    assertEquals(s.fetchCalls, []);
});

// --- caminos felices ------------------------------------------------------------------------------
Deno.test("crear: GET tarjetas, Anthropic, POST tarjeta con marcador y reporte citado, finalize crear", async () => {
    const s = setup({}, { anthropic: toolMsg("crear_tarjeta", { titulo: "Lista\nno carga", descripcion: "La lista falla" }) });
    const r = await s.handler(ok());
    assertEquals(r.status, 200);
    assertEquals(await r.text(), "ok");
    const create = s.fetchCalls.find(isCreate)!;
    const body = create.body as { idList: string; name: string; desc: string };
    assertEquals(body.idList, "LIST1");
    assertEquals(body.name, "Lista no carga");
    assert(body.desc.split("\n").includes(markerLine(7)));
    assert(body.desc.includes(`> ${REPORT}`));
    assertEquals(s.finalized, [{
        feedbackId: 7, crear: true, cardId: "new1", cardUrl: "https://trello.com/c/new1",
        titulo: "Lista no carga", descripcion: "La lista falla",
    }]);
    const anth = s.fetchCalls.find(isAnthropic)!;
    assertEquals((anth.body as { tool_choice: unknown }).tool_choice, { type: "any", disable_parallel_tool_use: true });
    assertEquals(s.fetchCalls.filter(isComment).length, 0);
    assert(s.fetchCalls.every((c) => c.method !== "DELETE"));
    assertCleanLogs(s.logs);
});

Deno.test("vincular: comentario con reporte citado y finalize vincular con la tarjeta", async () => {
    const s = setup({}, { anthropic: toolMsg("vincular_tarjeta", { card_id: "c1" }) });
    assertEquals((await s.handler(ok())).status, 200);
    const comment = s.fetchCalls.find(isComment)!;
    assert(comment.url.endsWith("/1/cards/c1/actions/comments"));
    assert((comment.body as { text: string }).text.includes(`> ${REPORT}`));
    assertEquals(s.fetchCalls.filter(isCreate).length, 0);
    assertEquals(s.finalized, [{
        feedbackId: 7, crear: false, cardId: "c1", cardUrl: "https://trello.com/c/1", titulo: "Lista lenta", descripcion: "d1",
    }]);
    assertCleanLogs(s.logs);
});

Deno.test("marcador: tarjeta abierta con Homita-feedback-id -> sin Anthropic ni POST, finalize crear", async () => {
    const marked = { ...CARDS[1], id: "cm", desc: `x\n${markerLine(7)}\ny` };
    const s = setup({}, { cards: [CARDS[0], marked] });
    assertEquals((await s.handler(ok())).status, 200);
    assertEquals(s.fetchCalls.filter(isAnthropic).length, 0);
    assertEquals(trelloWrites(s.fetchCalls).length, 0);
    assertEquals(s.finalized.length, 1);
    assertEquals(s.finalized[0].crear, true);
    assertEquals(s.finalized[0].cardId, "cm");
    assertEquals(s.finalized[0].descripcion, "x\ny");
});

// --- fallos antes del efecto ----------------------------------------------------------------------
const assertErrorNoWrites = (s: ReturnType<typeof setup>, status: number) => {
    assertEquals(status, 500);
    assert(s.calls.includes("markError:7"));
    assertEquals(s.finalized.length, 0);
    assert(!s.calls.includes("finalize:7"));
    assertEquals(trelloWrites(s.fetchCalls).length, 0);
    assertCleanLogs(s.logs);
};

Deno.test("card_id inventado -> markError y 0 escrituras en Trello", async () => {
    const s = setup({}, { anthropic: toolMsg("vincular_tarjeta", { card_id: "zzz" }) });
    assertErrorNoWrites(s, (await s.handler(ok())).status);
});

Deno.test("card_id leído pero fuera de las 100 enviadas -> markError", async () => {
    const many = Array.from({ length: 101 }, (_, i) => ({
        ...CARDS[0], id: `k${i}`, dateLastActivity: new Date(Date.UTC(2026, 0, 1) + i * 1000).toISOString(),
    }));
    const s = setup({}, { cards: many, anthropic: toolMsg("vincular_tarjeta", { card_id: "k0" }) });
    assertErrorNoWrites(s, (await s.handler(ok())).status);
});

Deno.test("0 o 2 tool_use, o tool desconocido -> markError", async () => {
    const two = () => json(200, { content: [
        { type: "tool_use", name: "crear_tarjeta", input: { titulo: "a", descripcion: "b" } },
        { type: "tool_use", name: "vincular_tarjeta", input: { card_id: "c1" } },
    ] });
    for (const anthropic of [() => json(200, { content: [{ type: "text", text: "hola" }] }), two, toolMsg("borrar", {})]) {
        const s = setup({}, { anthropic });
        assertErrorNoWrites(s, (await s.handler(ok())).status);
    }
});

Deno.test("fallo de Trello GET -> markError sin Anthropic", async () => {
    const s = setup({}, { listStatus: 503 });
    assertErrorNoWrites(s, (await s.handler(ok())).status);
    assertEquals(s.fetchCalls.filter(isAnthropic).length, 0);
    assert(s.logs.some((l) => l.includes("trello listCards status=503")));
});

Deno.test("fallo de Anthropic (HTTP 529 o red) -> markError", async () => {
    for (const anthropic of [() => json(529, { error: "overloaded" }), () => { throw new TypeError("network https://api.anthropic.com"); }]) {
        const s = setup({}, { anthropic });
        assertErrorNoWrites(s, (await s.handler(ok())).status);
    }
});

Deno.test("fallo al crear la tarjeta o al comentar -> markError sin finalize", async () => {
    const s1 = setup({}, { createStatus: 500 });
    assertEquals((await s1.handler(ok())).status, 500);
    assert(s1.calls.includes("markError:7") && !s1.calls.includes("finalize:7"));
    const s2 = setup({}, { commentStatus: 500, anthropic: toolMsg("vincular_tarjeta", { card_id: "c1" }) });
    assertEquals((await s2.handler(ok())).status, 500);
    assert(s2.calls.includes("markError:7") && !s2.calls.includes("finalize:7"));
});

// --- fallos tras el efecto ------------------------------------------------------------------------
Deno.test("finalize falla tras crear -> PUT closed=true de la tarjeta creada y markError", async () => {
    const s = setup({ failFinalize: true });
    assertEquals((await s.handler(ok())).status, 500);
    const archive = s.fetchCalls.filter(isArchive);
    assertEquals(archive.length, 1);
    assert(archive[0].url.endsWith("/1/cards/new1"));
    assertEquals(archive[0].body, { closed: true });
    assert(s.calls.includes("markError:7"));
    assert(s.fetchCalls.every((c) => c.method !== "DELETE"));
    assertCleanLogs(s.logs);
});

Deno.test("finalize falla tras crear y la relectura dice 'pendiente' -> getEstado antes de archivar", async () => {
    const s = setup({ failFinalize: true });
    assertEquals((await s.handler(ok())).status, 500);
    const i = s.calls.indexOf("getEstado:7");
    assert(i > s.calls.indexOf("finalize:7"), "relee tras finalize");
    assert(i < s.calls.indexOf("markError:7"), "relee antes de markError");
    assertEquals(s.fetchCalls.filter(isArchive).length, 1);
    assertCleanLogs(s.logs);
});

Deno.test("error de red tras COMMIT de finalize (fila 'procesado') -> no archiva y log de inconsistencia", async () => {
    const s = setup({ finalizeCommitsThenFails: true });
    assertEquals((await s.handler(ok())).status, 500);
    assertEquals(s.finalized.length, 1);
    assert(s.calls.includes("getEstado:7"));
    assertEquals(s.fetchCalls.filter(isArchive).length, 0);
    assert(s.fetchCalls.every((c) => c.method !== "DELETE"));
    assert(s.logs.some((l) =>
        l.includes("inconsistencia") && l.includes("estado=procesado") && l.includes("backlog=99") && l.includes("card=new1")
    ));
    assertCleanLogs(s.logs);
});

Deno.test("finalize falla y la relectura del estado también falla -> no archiva y log de inconsistencia", async () => {
    const s = setup({ failFinalize: true, failGetEstado: true });
    assertEquals((await s.handler(ok())).status, 500);
    assertEquals(s.fetchCalls.filter(isArchive).length, 0);
    assert(s.logs.some((l) => l.includes("inconsistencia") && l.includes("relectura") && l.includes("card=new1")));
    assert(s.calls.includes("markError:7"));
    assertCleanLogs(s.logs);
});

Deno.test("finalize falla tras reutilizar tarjeta con marcador -> sin relectura ni archivado", async () => {
    const marked = { ...CARDS[1], id: "cm", desc: `x\n${markerLine(7)}\ny` };
    const s = setup({ failFinalize: true }, { cards: [CARDS[0], marked] });
    assertEquals((await s.handler(ok())).status, 500);
    assert(!s.calls.includes("getEstado:7"));
    assertEquals(s.fetchCalls.filter(isArchive).length, 0);
});

Deno.test("finalize falla tras vincular -> markError, sin archivar (el comentario queda)", async () => {
    const s = setup({ failFinalize: true }, { anthropic: toolMsg("vincular_tarjeta", { card_id: "c1" }) });
    assertEquals((await s.handler(ok())).status, 500);
    assertEquals(s.fetchCalls.filter(isArchive).length, 0);
    assertEquals(s.fetchCalls.filter(isComment).length, 1);
    assert(s.calls.includes("markError:7"));
});

Deno.test("archivado fallido -> se registra el id de la tarjeta y markError", async () => {
    const s = setup({ failFinalize: true }, { archiveStatus: 500 });
    assertEquals((await s.handler(ok())).status, 500);
    assert(s.logs.some((l) => l.includes("card=new1") && l.includes("archivar")));
    assert(s.calls.includes("markError:7"));
    assertCleanLogs(s.logs);
});

Deno.test("markError falla -> 500 y log de fila atascada", async () => {
    const s = setup({ failMarkError: true }, { listStatus: 500 });
    assertEquals((await s.handler(ok())).status, 500);
    assert(s.logs.some((l) => l.includes("atascada")));
    assertCleanLogs(s.logs);
});
