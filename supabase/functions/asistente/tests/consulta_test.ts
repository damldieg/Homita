// Tests de la skill consulta: fechas (medianoche local, día siguiente) y registro de herramientas.
// Importa los casos de uso de `api`, que leen el entorno al cargar: se ejecuta con --allow-env.
import { assertEquals } from "jsr:@std/assert@1";
import { consulta, diaSiguiente, localMidnightUnix } from "../skills/consulta/index.ts";

Deno.test("medianoche local: Madrid en noviembre (UTC+1) es 23:00 UTC del día anterior", () => {
    assertEquals(localMidnightUnix("2026-11-20", "Europe/Madrid"), Date.UTC(2026, 10, 19, 23, 0, 0) / 1000);
});

Deno.test("medianoche local: UTC no desplaza nada", () => {
    assertEquals(localMidnightUnix("2026-11-20", "UTC"), Date.UTC(2026, 10, 20) / 1000);
});

Deno.test("medianoche local: Madrid en verano (UTC+2)", () => {
    assertEquals(localMidnightUnix("2026-07-01", "Europe/Madrid"), Date.UTC(2026, 6, 0, 22, 0, 0) / 1000);
});

Deno.test("día siguiente cruza fin de mes y de año", () => {
    assertEquals(diaSiguiente("2026-02-28"), "2026-03-01");
    assertEquals(diaSiguiente("2026-12-31"), "2027-01-01");
    assertEquals(diaSiguiente("2028-02-28"), "2028-02-29");
});

Deno.test("la skill consulta expone solo herramientas de lectura", () => {
    const nombres = consulta.herramientas.map((t) => t.name).sort();
    assertEquals(nombres, ["fecha_actual", "ver_eventos", "ver_listas", "ver_personas", "ver_rutinas", "ver_tareas"]);
    assertEquals(consulta.tarjetas, []);
});
