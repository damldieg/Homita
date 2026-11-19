// Tests de validateEventEndDate (0030, event-end-date): formato, rango y ausente vs null vs ''.
// Sin BD ni red.
import { assert, assertEquals } from "jsr:@std/assert@1";

Deno.env.set("SUPABASE_URL", "http://stub.local");
Deno.env.set("SUPABASE_ANON_KEY", "anon");
Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service");

const { validateEventEndDate } = await import("../_shared/validate.ts");

const START = "2026-11-10 09:00:00";

const errOf = async (r: ReturnType<typeof validateEventEndDate>): Promise<{ status: number; error: string }> => {
    assert("err" in r);
    return { status: r.err.status, error: (await r.err.json()).error };
};

Deno.test("ausente: present false y value null (conservar en update)", () => {
    assertEquals(validateEventEndDate({}, START), { present: false, value: null });
});

Deno.test("null y '' explícitos: present true y value null (borrar en update)", () => {
    assertEquals(validateEventEndDate({ end_date: null }, START), { present: true, value: null });
    assertEquals(validateEventEndDate({ end_date: "" }, START), { present: true, value: null });
});

Deno.test("fecha válida: mismo día y posterior", () => {
    assertEquals(validateEventEndDate({ end_date: "2026-11-10" }, START), { present: true, value: "2026-11-10" });
    assertEquals(validateEventEndDate({ end_date: "2026-11-20" }, START), { present: true, value: "2026-11-20" });
});

Deno.test("fin anterior al día de inicio: 400 con mensaje claro", async () => {
    assertEquals(await errOf(validateEventEndDate({ end_date: "2026-11-05" }, START)), {
        status: 400,
        error: "End date cannot be before start date",
    });
});

Deno.test("formato inválido, fecha inexistente o tipo no string: 400 Invalid end date", async () => {
    for (const bad of ["20/11/2026", "2026-11-20 10:00:00", "2026-02-30", "2026-13-01", 20261120, true, {}]) {
        assertEquals(await errOf(validateEventEndDate({ end_date: bad }, START)), {
            status: 400,
            error: "Invalid end date",
        });
    }
});
