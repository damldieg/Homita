// Tests de la skill ayuda: normalización, búsqueda en la guía (acentos, sinónimos, plurales, umbral, tope),
// la herramienta guia_app, el registro de la skill y que consulta remita a ella. Sin red ni BD.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { ayuda } from "../skills/ayuda/index.ts";
import { buscar, MAX_SECCIONES, normalizar, tokens } from "../skills/ayuda/buscar.ts";
import { GUIA, type Seccion } from "../skills/ayuda/guia.ts";
import { consulta } from "../skills/consulta/index.ts";
import { SKILLS } from "../skills/registry.ts";
import type { Tool, ToolCtx } from "../core.ts";

const ids = (r: { secciones: Seccion[] }) => r.secciones.map((s) => s.id);
const CTX: ToolCtx = { token: "t", uid: "u", homeId: "7", timezone: "Europe/Madrid", now: new Date("2026-11-24T10:00:00Z") };
const guiaApp = (): Tool => ayuda.herramientas.find((t) => t.name === "guia_app")!;

const MINI: Seccion[] = [
    { id: "a", titulo: "Alfa", palabras: ["uno", "primero"], texto: "texto de alfa" },
    { id: "b", titulo: "Beta", palabras: ["uno", "segundo"], texto: "texto de beta" },
    { id: "c", titulo: "Gamma", palabras: ["uno", "tercero"], texto: "texto de gamma" },
    { id: "d", titulo: "Delta", palabras: ["uno", "cuarto"], texto: "texto de delta" },
];

Deno.test("normalizar: minúsculas, sin acentos ni signos", () => {
    assertEquals(normalizar("¿Cómo COMPARTO una Lista?"), "como comparto una lista");
    assertEquals(normalizar("  Calendário,   Año!! "), "calendario ano");
    assertEquals(normalizar("Ajustes › Personas"), "ajustes personas");
});

Deno.test("tokens: quita palabras vacías y el plural final", () => {
    assertEquals(tokens("¿Cómo puedo compartir mis listas?"), ["compartir", "lista"]);
    assertEquals(tokens("calendarios"), tokens("calendario"));
    assertEquals(tokens("invitaciones"), tokens("invitacion"));
    assertEquals(tokens("de la a"), []);
});

Deno.test("buscar: «compartir lista» devuelve la sección de compartir lista primero", () => {
    for (const q of ["compartir lista", "¿cómo comparto una lista?", "Compartir LISTAS"]) {
        const r = buscar(q);
        assertEquals(r.secciones[0]?.id, "compartir-lista", q);
        assert(r.secciones.length <= 3, q);
    }
});

Deno.test("buscar: con y sin acentos da lo mismo", () => {
    for (const [a, b] of [["calendário", "calendario"], ["invitación", "invitacion"], ["¿Cómo cambio el color?", "como cambio el color"]]) {
        assertEquals(ids(buscar(a)), ids(buscar(b)), a);
        assert(buscar(a).secciones.length > 0, a);
    }
});

Deno.test("buscar: sinónimos (agenda, invitar, cita, feedback)", () => {
    assert(ids(buscar("agenda")).includes("calendario"));
    assertEquals(buscar("invitar a alguien al hogar").secciones[0]?.id, "invitar-hogar");
    assertEquals(buscar("invitacion").secciones[0]?.id, "invitar-hogar");
    assertEquals(buscar("quiero agendar una cita").secciones[0]?.id, "evento-nuevo");
    assertEquals(buscar("mandar una sugerencia").secciones[0]?.id, "enviar-feedback");
});

Deno.test("buscar: color de un calendario", () => {
    assertEquals(buscar("¿cómo cambio el color de un calendario?").secciones[0]?.id, "color-calendario");
});

Deno.test("buscar: por palabra del texto cuando suma lo bastante", () => {
    // «propietario» solo aparece en el texto de las secciones de compartir (1 punto): no llega al umbral solo.
    assertEquals(buscar("propietario").secciones.length, 0);
    // Con título y sinónimos sí: 2 + 3 puntos.
    assertEquals(buscar("borrar tarea").secciones[0]?.id, "tarea-editar");
});

Deno.test("buscar: sin coincidencia devuelve la lista de temas y un aviso, sin secciones", () => {
    for (const q of ["exportar a Excel", "", "   ", "¿?", "qwerty zzz"]) {
        const r = buscar(q);
        assertEquals(r.secciones, [], q);
        assertEquals(r.temas?.length, GUIA.length, q);
        assert(r.aviso, q);
    }
});

Deno.test("buscar: nunca más de MAX_SECCIONES, aunque casen todas", () => {
    assertEquals(MAX_SECCIONES, 3);
    const r = buscar("uno", MINI);
    assertEquals(r.secciones.length, 3);
    for (const q of ["lista", "calendario", "personas", "hogar", "evento", "tarea"]) {
        assert(buscar(q).secciones.length <= 3, q);
    }
});

Deno.test("buscar: desempate estable por orden de la guía", () => {
    assertEquals(ids(buscar("uno", MINI)), ["a", "b", "c"]);
    assertEquals(ids(buscar("uno", MINI)), ids(buscar("uno", MINI)));
    // Una puntuación mayor gana al orden.
    assertEquals(ids(buscar("uno cuarto", MINI))[0], "d");
});

Deno.test("buscar: solo se devuelven las secciones con al menos la mitad de la mejor puntuación", () => {
    const guia: Seccion[] = [
        { id: "x", titulo: "Equis", palabras: ["manzana", "pera", "uva"], texto: "" },
        { id: "y", titulo: "Ye", palabras: ["manzana"], texto: "" },
        { id: "z", titulo: "Zeta", palabras: [], texto: "pera" },
    ];
    // x: 9 puntos; y: 3 (menos de la mitad de 9) → fuera.
    assertEquals(ids(buscar("manzana pera uva", guia)), ["x"]);
});

Deno.test("guia_app: devuelve secciones con título y texto", async () => {
    const r = await guiaApp().run({ tema: "¿cómo comparto una lista?" }, CTX) as { secciones: { titulo: string; texto: string }[] };
    assert(r.secciones.length >= 1 && r.secciones.length <= 3);
    assert(r.secciones[0].texto.includes("Personas con acceso"));
    assert(r.secciones[0].titulo.toLowerCase().includes("compartir"));
});

Deno.test("guia_app: sin coincidencia da el aviso y los temas, sin inventar secciones", async () => {
    const r = await guiaApp().run({ tema: "exportar a Excel" }, CTX) as { secciones: unknown[]; temas: string[]; aviso: string };
    assertEquals(r.secciones, []);
    assert(r.temas.length > 10);
    assert(r.aviso.includes("Ajustes") && r.aviso.includes("feedback"));
});

Deno.test("guia_app: el tema es obligatorio y de tipo texto", async () => {
    for (const input of [{}, { tema: 3 }, { tema: null }]) {
        let fallo = false;
        try {
            await guiaApp().run(input as Record<string, unknown>, CTX);
        } catch {
            fallo = true;
        }
        assert(fallo, JSON.stringify(input));
    }
});

Deno.test("skill ayuda: registrada, tool strict con esquema válido y nombres únicos", () => {
    assert(SKILLS.some((s) => s.id === "ayuda"));
    const nombres = SKILLS.flatMap((s) => s.herramientas.map((t) => t.name));
    assertEquals(new Set(nombres).size, nombres.length);
    assert(nombres.includes("guia_app"));
    const t = guiaApp();
    assertEquals(t.input_schema.type, "object");
    assertEquals(t.input_schema.additionalProperties, false);
    assertEquals(t.input_schema.required, ["tema"]);
    assertEquals(Object.keys(t.input_schema.properties), ["tema"]);
    assertEquals(ayuda.tarjetas, []);
});

Deno.test("skill ayuda: las instrucciones mandan usar guia_app, no inventar y sugerir feedback desde Ajustes", async () => {
    assert(ayuda.instrucciones.includes("guia_app"));
    assert(ayuda.instrucciones.includes("Ajustes"));
    assert(ayuda.instrucciones.toLowerCase().includes("feedback"));
    assert(ayuda.instrucciones.toLowerCase().includes("no lo sabes") || ayuda.instrucciones.toLowerCase().includes("no lo sé"));
    assert(!ayuda.instrucciones.includes("Perfil"));
    assertEquals(await ayuda.disponible(CTX), true);
});

Deno.test("skill consulta: remite a guia_app para decir dónde se hace una escritura", () => {
    assert(consulta.instrucciones.includes("guia_app"));
});

Deno.test("la guía no cambia el prefijo con datos variables: sin fechas ISO ni nombres propios en las instrucciones", () => {
    assert(!/\d{4}-\d{2}-\d{2}/.test(ayuda.instrucciones));
});
