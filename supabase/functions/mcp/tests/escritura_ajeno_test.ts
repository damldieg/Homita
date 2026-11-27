// Cada herramienta de escritura, con `hogar` de otro hogar: error claro, sin leer datos ni escribir (criterio 15/16).
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { NOMBRES_ESCRITURA } from "../tools/registro.ts";
import { crearMundo, llamarTool } from "./util.ts";

/** Argumentos mínimos válidos de cada herramienta de escritura (sin `hogar`). */
export const ARGS_MINIMOS: Record<string, Record<string, unknown>> = {};

Deno.test("hogar ajeno en las herramientas de escritura: error claro, sin leer ni escribir", async () => {
    for (const nombre of NOMBRES_ESCRITURA) {
        const args = ARGS_MINIMOS[nombre];
        assert(args !== undefined, `falta ARGS_MINIMOS de ${nombre}`);
        const m = crearMundo();
        m.miembroDe.delete("8");
        const { resultado } = await llamarTool(m, nombre, { ...args, hogar: "8" });
        assertEquals(resultado?.isError, true, nombre);
        assertStringIncludes(resultado?.content?.[0]?.text ?? "", "No tienes acceso a ese hogar");
        assertEquals(m.comprobaciones, ["8"], nombre);
        assertEquals(m.llamadas, [], nombre);
        assertEquals(m.escrituras, [], nombre);
    }
});
