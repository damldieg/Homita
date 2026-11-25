// UUID derivado del tool_use.id para client_request_id (0035).
import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";
import { clientRequestId, uuidDe } from "../skills/organizar/uuid.ts";
import { clientRequestIdOf } from "../../api/_shared/validate.ts";

const V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

Deno.test("uuidDe: determinista, con forma de UUID v4", async () => {
    const a = await uuidDe("501|7|toolu_1|0");
    assertEquals(a, await uuidDe("501|7|toolu_1|0"));
    assert(V4.test(a), a);
});

Deno.test("clientRequestId: cambia con el tool_use.id, el índice, el usuario y el hogar", async () => {
    const base = await clientRequestId("501", "7", "toolu_1", 0);
    assertEquals(base, await clientRequestId("501", "7", "toolu_1", 0));
    for (const otro of [
        await clientRequestId("501", "7", "toolu_2", 0),
        await clientRequestId("501", "7", "toolu_1", 1),
        await clientRequestId("502", "7", "toolu_1", 0),
        await clientRequestId("501", "8", "toolu_1", 0),
    ]) assertNotEquals(otro, base);
});

Deno.test("el UUID derivado pasa la validación de client_request_id del api", async () => {
    const id = await clientRequestId("501", "7", "toolu_01ABC", 0);
    assertEquals(clientRequestIdOf({ client_request_id: id }), id);
});
