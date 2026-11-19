// Tests de trello.ts (change feedback-trello-gate). Sin red: fetch inyectado que registra las llamadas.
import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1";
import { createTrello, TrelloError } from "../trello.ts";

type Call = { url: string; method: string; headers: Record<string, string>; body: unknown; signal: boolean };

const KEY = "kkk-test";
const TOKEN = "ttt-test";

const fakeFetch = (respond: (c: Call) => Response | Promise<Response>) => {
    const calls: Call[] = [];
    const fn = ((input: string | URL | Request, init?: RequestInit) => {
        const c: Call = {
            url: String(input),
            method: init?.method ?? "GET",
            headers: (init?.headers ?? {}) as Record<string, string>,
            body: init?.body ? JSON.parse(String(init.body)) : undefined,
            signal: init?.signal instanceof AbortSignal,
        };
        calls.push(c);
        return Promise.resolve(respond(c));
    }) as typeof fetch;
    return { fn, calls };
};

const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

const client = (f: typeof fetch) => createTrello({ key: KEY, token: TOKEN, listId: "LIST1", fetch: f });
const AUTH = `OAuth oauth_consumer_key="${KEY}", oauth_token="${TOKEN}"`;

Deno.test("listCards: GET a la lista con fields, cabecera OAuth y timeout; sin key/token en la URL", async () => {
    const { fn, calls } = fakeFetch(() =>
        json(200, [
            { id: "c1", name: "A", desc: "d", shortUrl: "https://trello.com/c/x", dateLastActivity: "2026-01-01T00:00:00Z" },
            { name: "sin id" },
        ])
    );
    const cards = await client(fn).listCards();
    assertEquals(calls.length, 1);
    assertEquals(calls[0].method, "GET");
    assertEquals(
        calls[0].url,
        "https://api.trello.com/1/lists/LIST1/cards?fields=id,name,desc,shortUrl,dateLastActivity",
    );
    assertEquals(calls[0].headers.Authorization, AUTH);
    assert(calls[0].signal);
    assert(!calls[0].url.includes(KEY) && !calls[0].url.includes(TOKEN));
    assertEquals(cards, [
        { id: "c1", name: "A", desc: "d", shortUrl: "https://trello.com/c/x", dateLastActivity: "2026-01-01T00:00:00Z" },
    ]);
});

Deno.test("createCard: POST /cards con idList, name y desc", async () => {
    const { fn, calls } = fakeFetch(() => json(200, { id: "new1", shortUrl: "https://trello.com/c/n" }));
    const r = await client(fn).createCard("Título", "Desc");
    assertEquals(r, { id: "new1", shortUrl: "https://trello.com/c/n" });
    assertEquals(calls[0].method, "POST");
    assertEquals(calls[0].url, "https://api.trello.com/1/cards");
    assertEquals(calls[0].headers.Authorization, AUTH);
    assertEquals(calls[0].headers["Content-Type"], "application/json");
    assertEquals(calls[0].body, { idList: "LIST1", name: "Título", desc: "Desc" });
});

Deno.test("addComment: POST /cards/{id}/actions/comments con text", async () => {
    const { fn, calls } = fakeFetch(() => json(200, { id: "a1" }));
    await client(fn).addComment("c/1", "hola");
    assertEquals(calls[0].method, "POST");
    assertEquals(calls[0].url, "https://api.trello.com/1/cards/c%2F1/actions/comments");
    assertEquals(calls[0].body, { text: "hola" });
});

Deno.test("archiveCard: PUT /cards/{id} closed=true (nunca DELETE)", async () => {
    const { fn, calls } = fakeFetch(() => json(200, { id: "c1", closed: true }));
    await client(fn).archiveCard("c1");
    assertEquals(calls[0].method, "PUT");
    assertEquals(calls[0].url, "https://api.trello.com/1/cards/c1");
    assertEquals(calls[0].body, { closed: true });
    assert(calls.every((c) => c.method !== "DELETE"));
});

Deno.test("HTTP no 2xx -> TrelloError(op, status) sin URL, key ni token", async () => {
    const { fn } = fakeFetch(() => json(401, { message: "invalid token" }));
    const err = await assertRejects(() => client(fn).createCard("x", "y"), TrelloError);
    assertEquals(err.op, "createCard");
    assertEquals(err.status, 401);
    for (const s of [err.message, String(err), err.stack ?? ""]) {
        assert(!s.includes(KEY) && !s.includes(TOKEN) && !s.includes("api.trello.com"));
    }
});

Deno.test("error de red -> TrelloError(op, 0) sin el mensaje original (que lleva la URL)", async () => {
    const fn = (() => Promise.reject(new TypeError(`error sending request for url (https://api.trello.com/1/cards?key=${KEY})`))) as typeof fetch;
    const err = await assertRejects(() => client(fn).listCards(), TrelloError);
    assertEquals(err.status, 0);
    assert(!err.message.includes(KEY) && !err.message.includes("api.trello.com"));
});

Deno.test("respuestas con forma inesperada -> TrelloError", async () => {
    await assertRejects(() => client(fakeFetch(() => json(200, { no: "array" })).fn).listCards(), TrelloError);
    await assertRejects(() => client(fakeFetch(() => json(200, {})).fn).createCard("a", "b"), TrelloError);
    await assertRejects(
        () => client(fakeFetch(() => new Response("no json", { status: 200 })).fn).listCards(),
        TrelloError,
    );
});
