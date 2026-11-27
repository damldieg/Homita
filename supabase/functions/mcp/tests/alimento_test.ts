// crear_alimento (criterio 10): nuevo funciona, existente se reutiliza, la carrera por el índice único se resuelve.
import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { crearMundo, llamarTool } from "./util.ts";

Deno.test("alimento nuevo: POST food/create con el cuerpo del api y creado: true", async () => {
    const m = crearMundo({ food: [] }, {}, {}, { "POST food/create": { ok: true, status: 201, data: { id: 50, name: "Azafrán" } } });
    const { resultado, datos } = await llamarTool(m, "crear_alimento", { nombre: "Azafrán", seccion: "especias", unidad: "g", alergenos: [] });
    assertEquals(resultado?.isError, undefined);
    assertEquals(datos, { ok: true, alimento_id: 50, nombre: "Azafrán", creado: true });
    assertEquals(m.escrituras.length, 1);
    assertEquals(m.escrituras[0].cuerpo, { name: "Azafrán", section: "especias", default_unit: "g" });
    assertEquals(m.escrituras[0].hogar, "7");
});

Deno.test("alimento existente (mismo nombre sin acentos ni mayúsculas): se reutiliza y no se escribe", async () => {
    const m = crearMundo({ food: [{ id: 9, home_id: null, name: "Azafrán" }] });
    const { datos } = await llamarTool(m, "crear_alimento", { nombre: "azafran" });
    assertEquals(datos, { ok: true, alimento_id: 9, nombre: "Azafrán", creado: false });
    assertEquals(m.escrituras, []);
});

Deno.test("carrera: el alta da 400 por duplicado y al releer ya existe -> se reutiliza", async () => {
    let n = 0;
    const m = crearMundo({}, {
        leerRuta: (ruta) => {
            if (ruta === "home") return Promise.resolve({ ok: true, status: 200, body: [{ home_id: 7, name: "Casa", role: "admin", is_default: true }], texto: "", json: true });
            n++;
            const body = n === 1 ? [] : [{ id: 77, home_id: 7, name: "Sal" }];
            return Promise.resolve({ ok: true, status: 200, body, texto: "", json: true });
        },
    }, {}, { "POST food/create": { ok: false, status: 400, data: { error: "Invalid food" }, error: "Invalid food" } });
    const { resultado, datos } = await llamarTool(m, "crear_alimento", { nombre: "Sal" });
    assertEquals(resultado?.isError, undefined);
    assertEquals(datos, { ok: true, alimento_id: 77, nombre: "Sal", creado: false });
});

Deno.test("400 sin que exista al releer, 403 y unidad inválida: error y sin cuerpo crudo", async () => {
    const m = crearMundo({ food: [] }, {}, {}, { "POST food/create": { ok: false, status: 400, data: null, error: "Invalid food" } });
    const r = await llamarTool(m, "crear_alimento", { nombre: "Sal" });
    assertEquals(r.resultado?.isError, true);
    assertStringIncludes(r.resultado?.content[0].text ?? "", "Invalid food");
    const p = crearMundo({ food: [] }, {}, {}, { "POST food/create": { ok: false, status: 403, data: null } });
    assertStringIncludes((await llamarTool(p, "crear_alimento", { nombre: "Sal" })).resultado?.content[0].text ?? "", "No tienes permiso");
});
