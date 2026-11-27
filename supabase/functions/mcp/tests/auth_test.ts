// Verificador solo-OAuth (R4): sin token, sesión sin client_id, aud incorrecto, sub distinto, token válido.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { AuthNoDisponible, verificarToken } from "../auth.ts";
import { createHandler } from "../handler.ts";
import { userInfoReal } from "../userinfo.ts";
import { CLIENTE, crearMundo, jwt, peticion, rpcDe, TOKEN, UID, URL_MCP } from "./util.ts";

const LIST = { jsonrpc: "2.0", id: 1, method: "tools/list" };
const ok = (id = UID) => ({ userInfo: () => Promise.resolve({ id }), audience: "authenticated" });

Deno.test("sin token -> 401 + cabecera exacta", async () => {
    const { deps } = crearMundo();
    const res = await createHandler(deps)(peticion(LIST, null));
    assertEquals(res.status, 401);
    assertEquals(res.headers.get("WWW-Authenticate"), `Bearer resource_metadata="${URL_MCP}/.well-known/oauth-protected-resource"`);
    assertEquals(res.headers.get("Access-Control-Expose-Headers"), "WWW-Authenticate");
    await res.body?.cancel();
});

Deno.test("token de sesión (sin client_id) -> 401 y ni se pregunta a Auth", async () => {
    const mundo = crearMundo();
    const sesion = jwt({ client_id: undefined });
    const res = await createHandler(mundo.deps)(peticion(LIST, sesion));
    assertEquals(res.status, 401);
    assert(res.headers.get("WWW-Authenticate")!.startsWith('Bearer error="invalid_token", resource_metadata="'));
    assertEquals(mundo.userInfoLlamadas.length, 0);
    await res.body?.cancel();
});

Deno.test("token OAuth con aud incorrecto -> 401", async () => {
    const mundo = crearMundo();
    for (const aud of ["otro-proyecto", "", undefined, 7, ["otra"]]) {
        const res = await createHandler(mundo.deps)(peticion(LIST, jwt({ aud })));
        assertEquals(res.status, 401, String(aud));
        await res.body?.cancel();
    }
});

Deno.test("token sin client_id (ausente, vacío o no cadena) -> 401", async () => {
    const mundo = crearMundo();
    for (const client_id of [undefined, "", "   ", 5, null, { a: 1 }]) {
        const res = await createHandler(mundo.deps)(peticion(LIST, jwt({ client_id })));
        assertEquals(res.status, 401, JSON.stringify(client_id));
        await res.body?.cancel();
    }
});

Deno.test("sub distinto del que devuelve /auth/v1/user -> 401", async () => {
    const mundo = crearMundo({}, { userInfo: () => Promise.resolve({ id: "99999999-9999-9999-9999-999999999999" }) });
    const res = await createHandler(mundo.deps)(peticion(LIST));
    assertEquals(res.status, 401);
    await res.body?.cancel();
});

Deno.test("Auth rechaza el token (firma, caducidad o sesión) -> 401", async () => {
    const mundo = crearMundo({}, { userInfo: () => Promise.resolve(null) });
    const res = await createHandler(mundo.deps)(peticion(LIST));
    assertEquals(res.status, 401);
    await res.body?.cancel();
});

Deno.test("Auth no responde (5xx, 429 o red) -> 503 con Retry-After, sin WWW-Authenticate ni invalid_token", async () => {
    for (const fallo of [new AuthNoDisponible("auth 500"), new AuthNoDisponible("auth 429"), new Error("red")]) {
        const mundo = crearMundo({}, { userInfo: () => Promise.reject(fallo) });
        const res = await createHandler(mundo.deps)(peticion(LIST));
        assertEquals(res.status, 503);
        assertEquals(res.headers.get("Retry-After"), "5");
        assertEquals(res.headers.get("WWW-Authenticate"), null);
        assertEquals((await res.json()).error, "temporarily_unavailable");
    }
});

Deno.test("userInfo de index.ts: 401/403 -> inválido; 5xx y 429 -> no disponible", async () => {
    const original = globalThis.fetch;
    try {
        for (const [status, esperado] of [[401, "null"], [403, "null"], [500, "no"], [503, "no"], [429, "no"]] as const) {
            globalThis.fetch = (() => Promise.resolve(new Response("{}", { status }))) as typeof fetch;
            
            let r: string;
            try {
                r = (await userInfoReal("http://x.test", "k")("t")) === null ? "null" : "dato";
            } catch (e) {
                r = e instanceof AuthNoDisponible ? "no" : "otro";
            }
            assertEquals(r, esperado, String(status));
        }
    } finally {
        globalThis.fetch = original;
    }
});

Deno.test("tokens mal formados -> 401", async () => {
    const mundo = crearMundo();
    for (const t of ["abc", "a.b.c", "a.%%%.c", `x.${btoa("[]")}.y`]) {
        const res = await createHandler(mundo.deps)(peticion(LIST, t));
        assertEquals(res.status, 401, t);
        await res.body?.cancel();
    }
});

Deno.test("token OAuth válido -> pasa y llega al protocolo", async () => {
    const mundo = crearMundo();
    const res = await createHandler(mundo.deps)(peticion(LIST));
    assertEquals(res.status, 200);
    const rpc = await rpcDe(res);
    assert(Array.isArray((rpc.result as { tools: unknown[] }).tools));
    assertEquals(mundo.userInfoLlamadas, [TOKEN]);
});

Deno.test("verificarToken: devuelve uid y client_id; acepta aud como lista", async () => {
    assertEquals(await verificarToken(TOKEN, ok()), { uid: UID, clientId: CLIENTE });
    assertEquals(await verificarToken(jwt({ aud: ["x", "authenticated"] }), ok()), { uid: UID, clientId: CLIENTE });
    assertEquals(await verificarToken(TOKEN, { ...ok(), audience: "otra" }), null);
});
