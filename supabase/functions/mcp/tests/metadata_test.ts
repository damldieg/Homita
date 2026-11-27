// Metadatos OAuth del recurso protegido (RFC 9728): sin autenticación, con y sin MCP_PUBLIC_URL / MCP_AUTH_URL.
import { assertEquals } from "jsr:@std/assert@1";
import { createHandler } from "../handler.ts";
import { crearMundo, URL_MCP } from "./util.ts";

const META = "/.well-known/oauth-protected-resource";

Deno.test("metadatos: 200 JSON sin token, con la URL y el servidor de autorización configurados", async () => {
    const { deps } = crearMundo();
    const res = await createHandler(deps)(new Request(`${URL_MCP}${META}`));
    assertEquals(res.status, 200);
    assertEquals(res.headers.get("Content-Type"), "application/json");
    assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
    const cuerpo = await res.json();
    assertEquals(cuerpo.resource, URL_MCP);
    assertEquals(cuerpo.authorization_servers, ["https://x.test/auth/v1"]);
});

Deno.test("metadatos: la barra final de la configuración se quita", async () => {
    const { deps } = crearMundo({}, { publicUrl: `${URL_MCP}/`, authUrl: "https://auth.test/auth/v1/" });
    const cuerpo = await (await createHandler(deps)(new Request(`${URL_MCP}${META}`))).json();
    assertEquals(cuerpo.resource, URL_MCP);
    assertEquals(cuerpo.authorization_servers, ["https://auth.test/auth/v1"]);
});

Deno.test("metadatos: sin variables se deduce de x-forwarded-* (puerto omitido si es el de por defecto)", async () => {
    const { deps } = crearMundo({}, { publicUrl: undefined, authUrl: undefined });
    const h = createHandler(deps);
    const local = await (await h(new Request(`http://127.0.0.1:8081/mcp${META}`, {
        headers: { "x-forwarded-host": "127.0.0.1", "x-forwarded-proto": "http", "x-forwarded-port": "54321" },
    }))).json();
    assertEquals(local.resource, "http://127.0.0.1:54321/functions/v1/mcp");
    assertEquals(local.authorization_servers, ["http://127.0.0.1:54321/auth/v1"]);
    const nube = await (await h(new Request(`http://10.0.0.2:8081/mcp${META}`, {
        headers: { "x-forwarded-host": "abc.supabase.co", "x-forwarded-proto": "https", "x-forwarded-port": "443" },
    }))).json();
    assertEquals(nube.resource, "https://abc.supabase.co/functions/v1/mcp");
    assertEquals(nube.authorization_servers, ["https://abc.supabase.co/auth/v1"]);
});

Deno.test("metadatos: un x-forwarded-host raro se ignora y se usa el de la petición", async () => {
    const { deps } = crearMundo({}, { publicUrl: undefined, authUrl: undefined });
    const cuerpo = await (await createHandler(deps)(new Request(`http://127.0.0.1:8081/mcp${META}`, {
        headers: { "x-forwarded-host": 'evil.test/"><script>', "x-forwarded-proto": "http" },
    }))).json();
    assertEquals(cuerpo.resource, "http://127.0.0.1:8081/functions/v1/mcp");
});

Deno.test("metadatos: solo GET; OPTIONS responde CORS", async () => {
    const { deps } = crearMundo();
    const h = createHandler(deps);
    const post = await h(new Request(`${URL_MCP}${META}`, { method: "POST" }));
    assertEquals(post.status, 405);
    await post.body?.cancel();
    const opt = await h(new Request(URL_MCP, { method: "OPTIONS" }));
    assertEquals(opt.status, 204);
    assertEquals(opt.headers.get("Access-Control-Allow-Headers"), "authorization, content-type, mcp-protocol-version, accept");
});
