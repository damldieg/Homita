// Verificador solo-OAuth (R4): sin token, sesión sin client_id, aud incorrecto, sub distinto, token válido.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { verificarToken } from "../auth.ts";
import { createHandler } from "../handler.ts";
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

Deno.test("Auth rechaza el token (firma, caducidad o sesión) o falla -> 401", async () => {
    for (const userInfo of [() => Promise.resolve(null), () => Promise.reject(new Error("red"))]) {
        const mundo = crearMundo({}, { userInfo });
        const res = await createHandler(mundo.deps)(peticion(LIST));
        assertEquals(res.status, 401);
        await res.body?.cancel();
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
