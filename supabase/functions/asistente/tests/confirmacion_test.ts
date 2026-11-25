// Token de confirmación: firma HMAC, JSON canónico y verificación (puro, con secreto y reloj falsos).
import { assert, assertEquals } from "jsr:@std/assert@1";
import { canonico, firmar, MAX_ACCIONES, OPS_PERMITIDAS, verificar } from "../skills/organizar/confirmacion.ts";
import type { Payload } from "../skills/organizar/confirmacion.ts";
import { opsCoinciden } from "../skills/organizar/acciones.ts";

const SECRETO = "secreto-de-prueba";
const EXP = 1790000000;
const AHORA = (EXP - 60) * 1000;
const ESPERADO = { uid: "uid-1", homeId: "7", ahora: AHORA };
const PAYLOAD: Payload = {
    v: 1, uid: "uid-1", home_id: "7", exp: EXP,
    acciones: [{ op: "borrar_lista", args: { id: 3, z: { b: 1, a: 2 } }, nombre: "Pruebas" }],
};
const VECTOR =
    "eyJhY2Npb25lcyI6W3siYXJncyI6eyJpZCI6MywieiI6eyJhIjoyLCJiIjoxfX0sIm5vbWJyZSI6IlBydWViYXMiLCJvcCI6ImJvcnJhcl9saXN0YSJ9XSwiZXhwIjoxNzkwMDAwMDAwLCJob21lX2lkIjoiNyIsInVpZCI6InVpZC0xIiwidiI6MX0.Fj2dOS_r68rq5Kc9qJSutVy76bSczg9vsKXtVmFyZYw";

Deno.test("el registro de operaciones y la lista blanca del token coinciden", () => {
    assert(opsCoinciden());
    assertEquals(new Set(OPS_PERMITIDAS).size, OPS_PERMITIDAS.length);
});

Deno.test("canonico: ordena claves recursivamente y descarta undefined", () => {
    assertEquals(canonico({ b: 1, a: { d: [{ y: 1, x: 2 }], c: undefined } }), '{"a":{"d":[{"x":2,"y":1}]},"b":1}');
});

Deno.test("vector fijo: el token firmado es el esperado, con cualquier orden de claves en args", async () => {
    assertEquals(await firmar(PAYLOAD, SECRETO), VECTOR);
    const otroOrden: Payload = { ...PAYLOAD, acciones: [{ nombre: "Pruebas", op: "borrar_lista", args: { z: { a: 2, b: 1 }, id: 3 } }] };
    assertEquals(await firmar(otroOrden, SECRETO), VECTOR);
});

Deno.test("token válido: devuelve el payload", async () => {
    const r = await verificar(VECTOR, SECRETO, ESPERADO);
    assert(r.ok);
    if (r.ok) assertEquals(r.payload.acciones[0].op, "borrar_lista");
});

const rechaza = async (token: unknown, esperado = ESPERADO, secreto = SECRETO) => {
    const r = await verificar(token, secreto, esperado);
    assert(!r.ok);
    return r.ok ? "" : r.motivo;
};

Deno.test("caducado: se rechaza justo en exp", async () => {
    assertEquals(await rechaza(VECTOR, { ...ESPERADO, ahora: EXP * 1000 }), "token caducado");
    assertEquals(await rechaza(VECTOR, { ...ESPERADO, ahora: EXP * 1000 + 1 }), "token caducado");
});

Deno.test("manipulado: payload cambiado, firma cambiada y otro secreto", async () => {
    const [p, f] = VECTOR.split(".");
    const alterado = btoa(JSON.stringify({ ...PAYLOAD, home_id: "8" })).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
    assertEquals(await rechaza(`${alterado}.${f}`), "firma no válida");
    assertEquals(await rechaza(`${p}.${f.slice(0, -2)}AA`), "firma no válida");
    assertEquals(await rechaza(VECTOR, ESPERADO, "otro-secreto"), "firma no válida");
});

Deno.test("de otro uid o de otro hogar", async () => {
    assertEquals(await rechaza(VECTOR, { ...ESPERADO, uid: "uid-2" }), "token de otro usuario");
    assertEquals(await rechaza(VECTOR, { ...ESPERADO, homeId: "8" }), "token de otro hogar");
});

Deno.test("mal formado: sin punto, no base64, vacío y no string", async () => {
    for (const t of ["", "abc", "a.b.c", "%%%.%%%", ".", null, 5, undefined]) {
        assertEquals(await rechaza(t), "token mal formado");
    }
});

Deno.test("op fuera de la lista blanca, args que no son objeto y exceso de acciones", async () => {
    const firmado = (acciones: unknown[]) => firmar({ ...PAYLOAD, acciones } as Payload, SECRETO);
    assertEquals(await rechaza(await firmado([{ op: "borrar_todo", args: {} }])), "acción no permitida");
    assertEquals(await rechaza(await firmado([{ op: "borrar_lista", args: 5 }])), "acción no permitida");
    assertEquals(await rechaza(await firmado([])), "número de acciones no válido");
    const muchas = Array.from({ length: MAX_ACCIONES + 1 }, () => ({ op: "borrar_lista", args: { id: 1 } }));
    assertEquals(await rechaza(await firmado(muchas)), "número de acciones no válido");
});
