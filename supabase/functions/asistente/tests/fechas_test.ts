// Tests de fechas de la skill consulta (Q1/Q3): rango de pared, DST e ISO local.
import { assertEquals } from "jsr:@std/assert@1";
import {
    diaSiguiente, dueAtALocal, epochPared, finRango, inicioRango, isoDeInstante, isoDeParedLocal,
} from "../skills/consulta/fechas.ts";

const texto = (epoch: number): string => new Date(epoch * 1000).toISOString().slice(0, 19).replace("T", " ");

Deno.test("día siguiente cruza fin de mes y de año", () => {
    assertEquals(diaSiguiente("2026-02-28"), "2026-03-01");
    assertEquals(diaSiguiente("2026-12-31"), "2027-01-01");
    assertEquals(diaSiguiente("2028-02-28"), "2028-02-29");
});

Deno.test("epoch de pared: su texto UTC es la hora local, sin importar la zona", () => {
    assertEquals(texto(inicioRango("2026-11-24")), "2026-11-24 00:00:00");
    assertEquals(texto(finRango("2026-11-24")), "2026-11-24 23:59:59");
    assertEquals(epochPared("2026-11-24", 18, 30), Date.UTC(2026, 10, 24, 18, 30) / 1000);
});

Deno.test("rango: 23:30 del último día entra y 00:00 del siguiente queda fuera; 22:30 del día previo no entra", () => {
    const ini = texto(inicioRango("2026-11-24"));
    const fin = texto(finRango("2026-11-24"));
    const dentro = (p: string) => p >= ini && p <= fin;
    assertEquals(dentro("2026-11-24 23:30:00"), true);
    assertEquals(dentro("2026-11-25 00:00:00"), false);
    assertEquals(dentro("2026-11-23 22:30:00"), false);
});

Deno.test("ISO local de una hora de pared: Madrid invierno +01:00 y verano +02:00", () => {
    assertEquals(isoDeParedLocal("2026-11-24 18:30:00", "Europe/Madrid"), "2026-11-24T18:30:00+01:00");
    assertEquals(isoDeParedLocal("2026-07-01 09:00:00", "Europe/Madrid"), "2026-07-01T09:00:00+02:00");
    assertEquals(isoDeParedLocal("2026-11-24 18:30:00", "UTC"), "2026-11-24T18:30:00+00:00");
});

Deno.test("DST de Madrid: cambios de marzo (29) y octubre (25) de 2026", () => {
    assertEquals(isoDeParedLocal("2026-03-28 12:00:00", "Europe/Madrid"), "2026-03-28T12:00:00+01:00");
    assertEquals(isoDeParedLocal("2026-03-29 12:00:00", "Europe/Madrid"), "2026-03-29T12:00:00+02:00");
    assertEquals(isoDeParedLocal("2026-10-24 12:00:00", "Europe/Madrid"), "2026-10-24T12:00:00+02:00");
    assertEquals(isoDeParedLocal("2026-10-25 12:00:00", "Europe/Madrid"), "2026-10-25T12:00:00+01:00");
});

Deno.test("due_at es UTC: ayer 23:00 UTC en Madrid son las 00:00 de hoy (+01:00)", () => {
    assertEquals(dueAtALocal("2026-11-23 23:00:00", "Europe/Madrid"), "2026-11-24T00:00:00+01:00");
    assertEquals(dueAtALocal("2026-07-01 22:00:00", "Europe/Madrid"), "2026-07-02T00:00:00+02:00");
    assertEquals(dueAtALocal(null, "Europe/Madrid"), null);
    assertEquals(dueAtALocal("basura", "Europe/Madrid"), null);
});

Deno.test("isoDeInstante usa el desfase de la zona", () => {
    assertEquals(isoDeInstante(Date.UTC(2026, 10, 24, 17, 30), "Europe/Madrid"), "2026-11-24T18:30:00+01:00");
});
