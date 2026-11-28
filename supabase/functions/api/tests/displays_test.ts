// Tests de las pantallas del hogar (0049, dashboard-pantalla-hogar): vinculación, sondeo, gestión y revocación.
// Sin BD ni red: fetch se sustituye por un stub que responde según la URL. Las reglas reales (un solo uso,
// caducidad, intentos, límite, permisos y selección) las comprueba scripts/supabase/tests/home_display_check.sql.
import { assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const { handleDisplayLinkStart, handleDisplayLinkPoll, handleDisplayLinkConfirm, handleDisplayRevoke, handleDisplayConfig } =
    await import("../usecases/displays.ts");
const { runWithHome } = await import("../_shared/home.ts");

type Call = { url: string; method: string; body: unknown; auth: string | null };
type Reply = { status: number; body: unknown };

const jsonRes = (status: number, body: unknown): Response =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

// Respuestas por fragmento de URL; la primera coincidencia gana. Sin coincidencia → 500.
const withStub = async (replies: Array<[string, Reply]>, fn: (calls: Call[]) => Promise<void>): Promise<void> => {
    const original = globalThis.fetch;
    const calls: Call[] = [];
    globalThis.fetch = ((input: string | URL | Request, init?: RequestInit) => {
        const url = String(input instanceof Request ? input.url : input);
        const body = init?.body ? JSON.parse(String(init.body)) : null;
        const auth = new Headers(init?.headers).get("authorization");
        calls.push({ url, method: init?.method ?? "GET", body, auth });
        const hit = replies.find(([frag]) => url.includes(frag));
        return Promise.resolve(hit ? jsonRes(hit[1].status, hit[1].body) : jsonRes(500, { message: "stub" }));
    }) as typeof fetch;
    try {
        await fn(calls);
    } finally {
        globalThis.fetch = original;
    }
};

const post = (path: string, body: unknown): Request =>
    new Request(`http://x/${path}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });

Deno.test("link-start devuelve código y secreto con la clave de servicio", async () => {
    await withStub([["/rpc/fn_display_link_start", { status: 200, body: { code: "123456", poll_secret: "ab", expires_at: "x" } }]], async (calls) => {
        const res = await handleDisplayLinkStart();
        assertEquals(res.status, 201);
        assertEquals((await res.json()).code, "123456");
        assertEquals(calls[0].auth, "Bearer service");
    });
});

Deno.test("link-start con demasiados pendientes → 429", async () => {
    await withStub([["/rpc/fn_display_link_start", { status: 500, body: { message: "Too many pending links" } }]], async () => {
        const res = await handleDisplayLinkStart();
        assertEquals(res.status, 429);
    });
});

Deno.test("link-poll: pendiente, listo con sesión (token y refresh_token) y no encontrado", async () => {
    await withStub([["/rpc/fn_display_link_poll", { status: 200, body: { status: "pending" } }]], async () => {
        assertEquals(await (await handleDisplayLinkPoll(post("x", { poll_secret: "s" }))).json(), { status: "pending" });
    });
    await withStub([["/rpc/fn_display_link_poll", {
        status: 200,
        body: { status: "ready", session: { access_token: "jwt", refresh_token: "rt" }, display: { id: 9, home_id: 1, name: "Salón" } },
    }]], async () => {
        const body = await (await handleDisplayLinkPoll(post("x", { poll_secret: "s" }))).json();
        assertEquals(body, { status: "ready", token: "jwt", refresh_token: "rt", display: { id: 9, home_id: 1, name: "Salón" } });
    });
    await withStub([["/rpc/fn_display_link_poll", { status: 500, body: { message: "Not Found" } }]], async () => {
        assertEquals((await handleDisplayLinkPoll(post("x", { poll_secret: "s" }))).status, 404);
    });
});

Deno.test("link-poll sin secreto → 400 sin llamar a la BD", async () => {
    await withStub([], async (calls) => {
        assertEquals((await handleDisplayLinkPoll(post("x", {}))).status, 400);
        assertEquals(calls.length, 0);
    });
});

const confirmReq = (body: unknown): Request => post("home/display/link-confirm", body);

Deno.test("confirm sin cabecera de hogar → 400", async () => {
    await withStub([], async (calls) => {
        const res = await handleDisplayLinkConfirm(confirmReq({ code: "123456", name: "Salón" }), "tok");
        assertEquals(res.status, 400);
        assertEquals(calls.length, 0);
    });
});

Deno.test("confirm con código incorrecto → 400 Invalid link code; con demasiados intentos → 429", async () => {
    await runWithHome("1", async () => {
        await withStub([["/rpc/fn_display_link_claim", { status: 200, body: { error: "Invalid link code" } }]], async () => {
            assertEquals((await handleDisplayLinkConfirm(confirmReq({ code: "123456", name: "Salón" }), "tok")).status, 400);
        });
        await withStub([["/rpc/fn_display_link_claim", { status: 200, body: { error: "Too many attempts" } }]], async () => {
            assertEquals((await handleDisplayLinkConfirm(confirmReq({ code: "123456", name: "Salón" }), "tok")).status, 429);
        });
    });
});

Deno.test("confirm con código mal formado → 400 sin llamar a la BD", async () => {
    await runWithHome("1", async () => {
        await withStub([], async (calls) => {
            assertEquals((await handleDisplayLinkConfirm(confirmReq({ code: "12a", name: "Salón" }), "tok")).status, 400);
            assertEquals(calls.length, 0);
        });
    });
});

Deno.test("confirm completo: claim, cuenta de GoTrue, sesión y complete → 201 con la pantalla", async () => {
    await runWithHome("1", async () => {
        await withStub([
            ["/rpc/fn_display_link_claim", { status: 200, body: { link_id: 7, home_id: 1, name: "Salón" } }],
            ["/auth/v1/admin/users", { status: 200, body: { id: "uid-1" } }],
            ["/auth/v1/token?grant_type=password", { status: 200, body: { access_token: "a", refresh_token: "r" } }],
            ["/rpc/fn_display_link_complete", { status: 200, body: { display_id: 9 } }],
        ], async (calls) => {
            const res = await handleDisplayLinkConfirm(confirmReq({ code: "123456", name: "Salón" }), "tok");
            assertEquals(res.status, 201);
            assertEquals(await res.json(), { id: 9, name: "Salón", home_id: 1 });
            // R1-01: la cuenta técnica nace con invitation_pending (sin hogar personal con rol admin)
            const create = calls.find((c) => c.url.endsWith("/auth/v1/admin/users") && c.method === "POST")!;
            assertEquals((create.body as { user_metadata: Record<string, unknown> }).user_metadata.invitation_pending, "true");
            const complete = calls.find((c) => c.url.includes("fn_display_link_complete"))!;
            assertEquals((complete.body as Record<string, unknown>).p_auth_uid, "uid-1");
            assertEquals((complete.body as Record<string, unknown>).p_link_id, 7);
            // La contraseña de la cuenta técnica no sale hacia la BD
            assertEquals(JSON.stringify(complete.body).includes("password"), false);
        });
    });
});

Deno.test("confirm con fallo al completar → borra la cuenta de GoTrue y aborta la vinculación", async () => {
    await runWithHome("1", async () => {
        await withStub([
            ["/rpc/fn_display_link_claim", { status: 200, body: { link_id: 7, home_id: 1, name: "Salón" } }],
            ["/auth/v1/admin/users", { status: 200, body: { id: "uid-2" } }],
            ["/auth/v1/token?grant_type=password", { status: 200, body: { access_token: "a", refresh_token: "r" } }],
            ["/rpc/fn_display_link_complete", { status: 500, body: { message: "Display limit reached" } }],
            ["/rpc/fn_display_link_abort", { status: 200, body: null }],
            ["/auth/v1/admin/users/uid-2", { status: 200, body: {} }],
        ], async (calls) => {
            const res = await handleDisplayLinkConfirm(confirmReq({ code: "123456", name: "Salón" }), "tok");
            assertEquals(res.status, 400);
            assertEquals(calls.some((c) => c.method === "DELETE" && c.url.endsWith("/auth/v1/admin/users/uid-2")), true);
            assertEquals(calls.some((c) => c.url.includes("fn_display_link_abort")), true);
        });
    });
});

Deno.test("revoke bloquea la cuenta en GoTrue y luego la borra con su auth_uid", async () => {
    await runWithHome("1", async () => {
        await withStub([
            ["/rpc/fn_display_revoke", { status: 200, body: { id: 9, auth_uid: "uid-9" } }],
            ["/auth/v1/admin/users/uid-9", { status: 200, body: {} }],
        ], async (calls) => {
            const res = await handleDisplayRevoke(post("home/display/revoke", { id: 9 }), "tok");
            assertEquals(res.status, 200);
            assertEquals(await res.json(), { id: 9, revoked: true });
            const ban = calls.find((c) => c.method === "PUT" && c.url.endsWith("/auth/v1/admin/users/uid-9"))!;
            assertEquals((ban.body as { ban_duration: string }).ban_duration, "876000h");
            assertEquals(calls.some((c) => c.method === "DELETE" && c.url.endsWith("/auth/v1/admin/users/uid-9")), true);
        });
    });
});

Deno.test("revoke: si no se puede bloquear la cuenta, error 500 y no se borra nada", async () => {
    await runWithHome("1", async () => {
        await withStub([
            ["/rpc/fn_display_revoke", { status: 200, body: { id: 9, auth_uid: "uid-9" } }],
            ["/auth/v1/admin/users/uid-9", { status: 500, body: {} }],
        ], async (calls) => {
            const res = await handleDisplayRevoke(post("home/display/revoke", { id: 9 }), "tok");
            assertEquals(res.status, 500);
            assertEquals(calls.some((c) => c.method === "DELETE"), false);
        });
    });
});

Deno.test("config devuelve la configuración de la pantalla con su sesión", async () => {
    await withStub([["/rpc/fn_display_config", { status: 200, body: { id: 9, name: "Salón", calendar_ids: [1] } }]], async () => {
        const res = await handleDisplayConfig(new Request("http://x/display/config"), "tok");
        assertEquals((await res.json()).calendar_ids, [1]);
    });
});
