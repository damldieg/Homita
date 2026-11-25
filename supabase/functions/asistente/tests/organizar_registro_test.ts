// Registro de la skill `organizar` y forma de sus esquemas de herramienta.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { indexTools } from "../core.ts";
import type { Tool } from "../core.ts";
import { SKILLS } from "../skills/registry.ts";
import { organizar } from "../skills/organizar/index.ts";
import { OPS } from "../skills/organizar/acciones.ts";

const INDISPENSABLES: Record<string, string[]> = {
    crear_lista: ["nombre"], editar_lista: ["id"], borrar_lista: ["id"],
    crear_tarea: ["titulo"], editar_tarea: ["id"], completar_tarea: ["id"], borrar_tarea: ["id"],
    crear_evento: ["titulo", "inicio"], editar_evento: ["id"], borrar_evento: ["id"],
    crear_rutina: ["titulo", "hora", "frecuencia"], editar_rutina: ["id"], borrar_rutina: ["id"],
    crear_calendario: ["nombre"], editar_calendario: ["id"], borrar_calendario: ["id"],
};

Deno.test("organizar está registrada, es siempre disponible y los nombres de herramienta no chocan", async () => {
    assert(SKILLS.includes(organizar));
    assertEquals(await organizar.disponible({} as never), true);
    assertEquals(indexTools(SKILLS).size, SKILLS.reduce((n, s) => n + s.herramientas.length, 0));
    assertEquals(organizar.tarjetas, ["confirmacion"]);
});

Deno.test("hay una herramienta por operación del registro y todas son de escritura", () => {
    assertEquals(organizar.herramientas.map((t) => t.name).sort(), Object.keys(INDISPENSABLES).sort());
    for (const t of organizar.herramientas) {
        assertEquals(t.escritura, true, t.name);
        assertEquals(t.strict, false, t.name);
    }
    // Toda herramienta con una operación equivalente tiene su acción en el registro de confirmación.
    for (const op of Object.keys(OPS)) assert(organizar.herramientas.some((t) => t.name === op), op);
});

Deno.test("esquemas: indispensables en required, sin uniones con null y sin propiedades extra", () => {
    for (const t of organizar.herramientas) {
        const s = t.input_schema;
        assertEquals(s.type, "object", t.name);
        assertEquals(s.additionalProperties, false, t.name);
        assertEquals([...(s.required ?? [])].sort(), [...INDISPENSABLES[t.name]].sort(), t.name);
        for (const k of s.required ?? []) assert(k in s.properties, `${t.name}.${k}`);
        assert(!JSON.stringify(s).includes('"null"'), `${t.name} sin null`);
    }
});

// Límites de la API para las herramientas `strict` de toda la petición: 20 herramientas, 24 parámetros
// opcionales y 16 con tipo unión. `organizar` queda fuera (strict: false); consulta y ayuda siguen dentro.
Deno.test("las herramientas strict de toda la petición caben en los límites de la API", () => {
    const strict: Tool[] = SKILLS.flatMap((s) => s.herramientas).filter((t) => t.strict !== false);
    assert(strict.length <= 20, `${strict.length} herramientas strict`);
    let opcionales = 0;
    let uniones = 0;
    for (const t of strict) {
        const props = t.input_schema.properties as Record<string, { type?: unknown; anyOf?: unknown }>;
        for (const [k, p] of Object.entries(props)) {
            if (!(t.input_schema.required ?? []).includes(k)) opcionales++;
            if (Array.isArray(p.type) || p.anyOf !== undefined) uniones++;
        }
    }
    assert(opcionales <= 24, `${opcionales} opcionales`);
    assert(uniones <= 16, `${uniones} uniones`);
});

Deno.test("las instrucciones piden los indispensables juntos, no inventan y explican la confirmación", () => {
    const i = organizar.instrucciones;
    for (const frase of ["en una sola frase", "No inventes", "Hecho:", "confirmación en pantalla", "empieza hoy", "morado"]) {
        assert(i.includes(frase), frase);
    }
});
