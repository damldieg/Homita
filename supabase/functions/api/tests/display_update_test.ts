// Tests de la actualización remota de las pantallas (0051, dashboard-actualizacion-remota). Sin BD ni red: fetch se
// sustituye por un stub que responde según la URL. El canal, el informe y el permiso los comprueba
// scripts/supabase/tests/actualizacion_remota_check.sql y cross_tenant_check.py (DU1–DU2).
import { assertEquals, assertFalse, assertStringIncludes } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const {
    displayReportOf, isDisplayRelease, releaseNewerThan, handleDisplayReleaseCheck, handleDisplaySetChannel, handleDisplayConfig,
} = await import("../usecases/displays.ts");
const { runWithHome } = await import("../_shared/home.ts");

type Call = { url: string; method: string; body: unknown; auth: string | null };
type Reply = { status: number; body: unknown };

const jsonRes = (status: number, body: unknown): Response =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

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

const SHA = "a".repeat(64);
const release = { version_code: 7, version_name: "1.1", sha256: SHA, size: 12345, file: "v7/homita.apk" };

const getReq = (headers: Record<string, string>): Request => new Request("http://x/display/update", { method: "GET", headers });

Deno.test("manifiesto: solo versión entera, hash hex de 64, tamaño y ruta .apk sin ..", () => {
    assertEquals(isDisplayRelease(release), true);
    assertFalse(isDisplayRelease({ ...release, sha256: "xyz" }));
    assertFalse(isDisplayRelease({ ...release, sha256: "A".repeat(64) }));
    assertFalse(isDisplayRelease({ ...release, version_code: 0 }));
    assertFalse(isDisplayRelease({ ...release, version_code: 1.5 }));
    assertFalse(isDisplayRelease({ ...release, size: 0 }));
    assertFalse(isDisplayRelease({ ...release, file: "../secreto.apk" }));
    assertFalse(isDisplayRelease({ ...release, file: "homita.zip" }));
    assertFalse(isDisplayRelease(null));
});

Deno.test("versión nueva solo si es estrictamente mayor", () => {
    assertEquals(releaseNewerThan(release, 6), true);
    assertEquals(releaseNewerThan(release, 7), false);
    assertEquals(releaseNewerThan(release, 8), false);
});

Deno.test("cabeceras de la pantalla: versión, nombre y resultado; sin cabecera, nada", () => {
    const r = displayReportOf(getReq({ "X-Display-App-Version": "3", "X-Display-App-Name": " 1.0 ", "X-Display-Update-Result": "instalada 3" }));
    assertEquals(r, { code: 3, name: "1.0", result: "instalada 3" });
    assertEquals(displayReportOf(getReq({ "X-Display-App-Version": "3x" })).code, null);
    assertEquals(displayReportOf(getReq({})), { code: null, name: null, result: null });
});

Deno.test("comprobación: hay versión nueva → URL firmada del APK, y la pantalla deja su versión y la marca", async () => {
    await withStub([
        ["/rpc/fn_display_report", { status: 200, body: { channel: "pruebas" } }],
        ["/storage/v1/object/display-releases/pruebas.json", { status: 200, body: release }],
        ["/storage/v1/object/sign/display-releases/v7/homita.apk", { status: 200, body: { signedURL: "/object/sign/display-releases/v7/homita.apk?token=t" } }],
    ], async (calls) => {
        const res = await handleDisplayReleaseCheck(getReq({ "X-Display-App-Version": "6" }), "tok");
        assertEquals(res.status, 200);
        const body = await res.json();
        assertEquals(body.update, true);
        assertEquals(body.channel, "pruebas");
        assertEquals(body.version_code, 7);
        assertEquals(body.sha256, SHA);
        assertEquals(body.url, "/storage/v1/object/sign/display-releases/v7/homita.apk?token=t");
        const report = calls.find((c) => c.url.includes("fn_display_report"))!;
        assertEquals(report.body, { p_version_code: 6, p_version_name: null, p_result: null, p_checked: true });
        assertEquals(report.auth, "Bearer tok");
        // El manifiesto y la firma se piden con la clave de servicio, nunca con el token de la pantalla
        const manifest = calls.find((c) => c.url.includes("pruebas.json"))!;
        assertEquals(manifest.auth, "Bearer service");
    });
});

Deno.test("comprobación: ya está en la última versión → sin URL y sin firmar nada", async () => {
    await withStub([
        ["/rpc/fn_display_report", { status: 200, body: { channel: "estable" } }],
        ["/storage/v1/object/display-releases/estable.json", { status: 200, body: release }],
    ], async (calls) => {
        const body = await (await handleDisplayReleaseCheck(getReq({ "X-Display-App-Version": "7" }), "tok")).json();
        assertEquals(body, { channel: "estable", update: false });
        assertEquals(calls.some((c) => c.url.includes("/object/sign/")), false);
    });
});

Deno.test("comprobación: sin publicación en el canal, o sin versión reportada → nada que instalar", async () => {
    await withStub([
        ["/rpc/fn_display_report", { status: 200, body: { channel: "estable" } }],
        ["/storage/v1/object/display-releases/estable.json", { status: 404, body: { message: "not found" } }],
    ], async () => {
        assertEquals(await (await handleDisplayReleaseCheck(getReq({ "X-Display-App-Version": "1" }), "tok")).json(), { channel: "estable", update: false });
    });
    await withStub([
        ["/rpc/fn_display_report", { status: 200, body: { channel: "estable" } }],
        ["/storage/v1/object/display-releases/estable.json", { status: 200, body: release }],
    ], async (calls) => {
        assertEquals(await (await handleDisplayReleaseCheck(getReq({}), "tok")).json(), { channel: "estable", update: false });
        assertEquals(calls.some((c) => c.url.includes("/object/sign/")), false);
    });
});

Deno.test("comprobación: manifiesto corrupto o canal desconocido → no se ofrece nada", async () => {
    await withStub([
        ["/rpc/fn_display_report", { status: 200, body: { channel: "estable" } }],
        ["/storage/v1/object/display-releases/estable.json", { status: 200, body: { ...release, sha256: "mal" } }],
    ], async () => {
        assertEquals(await (await handleDisplayReleaseCheck(getReq({ "X-Display-App-Version": "1" }), "tok")).json(), { channel: "estable", update: false });
    });
    await withStub([["/rpc/fn_display_report", { status: 200, body: { channel: "otro" } }]], async () => {
        assertEquals((await handleDisplayReleaseCheck(getReq({ "X-Display-App-Version": "1" }), "tok")).status, 500);
    });
});

Deno.test("cambio de canal: valida antes de llamar a la BD y pasa el canal a la RPC", async () => {
    await runWithHome("1", async () => {
        await withStub([], async (calls) => {
            const req = new Request("http://x/home/display/channel", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id: 9, channel: "beta" }) });
            assertEquals((await handleDisplaySetChannel(req, "tok")).status, 400);
            assertEquals(calls.length, 0);
        });
        await withStub([["/rpc/fn_display_set_channel", { status: 200, body: { id: 9, channel: "pruebas" } }]], async (calls) => {
            const req = new Request("http://x/home/display/channel", { method: "PATCH", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ id: 9, channel: "pruebas" }) });
            const res = await handleDisplaySetChannel(req, "tok");
            assertEquals(res.status, 200);
            assertEquals(calls[0].body, { p_home_id: 1, p_display_id: 9, p_channel: "pruebas" });
        });
    });
});

Deno.test("configuración: si la app reporta versión o resultado, se guarda antes de leer la configuración", async () => {
    await withStub([
        ["/rpc/fn_display_report", { status: 200, body: { channel: "estable" } }],
        ["/rpc/fn_display_config", { status: 200, body: { id: 9, name: "Salón", calendar_ids: [] } }],
    ], async (calls) => {
        const req = new Request("http://x/display/config", { headers: { "X-Display-App-Version": "4", "X-Display-Update-Result": "al-dia" } });
        assertEquals((await handleDisplayConfig(req, "tok")).status, 200);
        const report = calls.find((c) => c.url.includes("fn_display_report"))!;
        assertEquals(report.body, { p_version_code: 4, p_version_name: null, p_result: "al-dia", p_checked: false });
    });
    await withStub([["/rpc/fn_display_config", { status: 200, body: { id: 9 } }]], async (calls) => {
        await handleDisplayConfig(new Request("http://x/display/config"), "tok");
        assertEquals(calls.some((c) => c.url.includes("fn_display_report")), false);
    });
});
