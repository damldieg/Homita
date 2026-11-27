// Cada herramienta de escritura, con `hogar` de otro hogar: error claro, sin leer datos ni escribir (criterio 15/16).
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { NOMBRES_ESCRITURA } from "../tools/registro.ts";
import { crearMundo, llamarTool } from "./util.ts";

/** Argumentos mínimos válidos de cada herramienta de escritura (sin `hogar`). */
export const ARGS_MINIMOS: Record<string, Record<string, unknown>> = {
    guardar_receta: { nombre: "x", pasos: ["a"], ingredientes: [{ alimento_id: 1 }] },
    crear_alimento: { nombre: "x" },
    apuntar_compra: { articulos: [{ etiqueta: "x" }] },
    marcar_comprado: { item_ids: [1], estado: "checked" },
    guardar_borrador: { rango: { desde: { fecha: "2030-01-07", franja: "lunch" }, hasta: { fecha: "2030-01-07", franja: "dinner" } }, casillas: [{ fecha: "2030-01-07", franja: "lunch", tipo: "texto", titulo: "x" }] },
    cambiar_casillas: { plan_id: 1, expected_revision: 0, cambios: [{ fecha: "2030-01-07", franja: "lunch", tipo: "texto", titulo: "x" }] },
    apuntar_preferencia: { persona_id: 1, campo: "picante", valor: "1", confirmado_por_usuario: true },
};

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
