// Mundo falso de la skill `menus`: lector y escritor que imitan al api del menú (revisión, client_request_id,
// origin kito, estados rejected/locked, plan aceptado) sin BD ni red. Los casos de uso reales los cubre ci.sh.
import type { Escribir, Leer, RespuestaApi, ToolCtx } from "../core.ts";

export type Obj = Record<string, unknown>;
export const ok = (data: unknown, status = 200): RespuestaApi => ({ ok: true, status, data });
export const fallo = (status: number, error: string): RespuestaApi => ({ ok: false, status, data: { error }, error });

export const SEMANA = "2030-01-07"; // lunes
export const ANA = 1; // alergia al gluten
export const LEO = 2; // niño

export const perfilBase = (over: Obj = {}): Obj => ({
    home_id: 7, timezone: "Europe/Madrid", can_edit: true,
    profile: { week_start_day: 1, shopping_day: 6, cook_minutes_weekday: 30, cook_minutes_weekend: 60, cook_skill: "medium", repeat_policy: "some", leftovers: "yes", dessert: "no", equipment: ["horno"], preferences: {} },
    slots: [{ slot: "lunch", enabled: true, time: "14:00" }, { slot: "dinner", enabled: true, time: "21:00" }, { slot: "snack", enabled: false, time: "17:00" }],
    members: [
        { home_member_id: ANA, name: "Ana", kind: "adult", age_band: "adult", portion_size: "normal", allergies_answered: true,
            allergies: [{ allergen: "gluten", severity: "avoid_ingredient" }], diet: null, diet_note: "secreto-salud", goals: "perder peso",
            dislikes: ["coliflor"], favorites: [], quirks: null, spice: 1 },
        { home_member_id: LEO, name: "Leo", kind: "child", age_band: "child", portion_size: "small", allergies_answered: true,
            allergies: [], diet: null, dislikes: [], favorites: ["pasta"], quirks: null, spice: 0 },
    ],
    // miércoles (3): Leo come fuera a mediodía
    schedule: [{ home_member_id: LEO, weekday: 3, slot: "lunch", status: "out" }],
    candidates: [],
    ...over,
});

export interface Mundo {
    leer: Leer;
    escribir: Escribir;
    /** Llamadas de escritura recibidas (método, ruta, cuerpo). */
    escrituras: { metodo: string; ruta: string; cuerpo: Obj }[];
    /** Lecturas recibidas (ruta, params). */
    lecturas: { ruta: string; params: Obj }[];
    plan: () => Obj | null;
    /** Pone el plan de la semana (para preparar escenarios). */
    ponerPlan: (p: Obj | null) => void;
    /** Simula que la persona cambia el plan en la app (revisión +1). */
    editarComoPersona: (fn: (items: Obj[]) => void) => void;
    recetas: Obj[];
    claves: Map<string, Obj>;
}

interface Opciones {
    perfil?: Obj;
    /** receta_id → alérgenos de sus ingredientes (para el check). */
    alergenos?: Record<number, string[]>;
    recetas?: Obj[];
    alimentos?: Obj[];
    /** Planes de otras semanas por week_start (historial). */
    historial?: Record<string, Obj>;
    eventos?: Obj[];
    /** receta_id → ingredientes de `recipe/detail` (por defecto, todos enlazados a un alimento del catálogo). */
    ingredientes?: Record<number, Obj[]>;
    /** Recetas que el servidor da por no comprobables en el plan (ingredientes sin food_id). */
    recetasSinComprobar?: number[];
    /** Falla la comprobación. */
    checkFalla?: boolean;
}

export const crearMundo = (o: Opciones = {}): Mundo => {
    const perfil = o.perfil ?? perfilBase();
    const recetas = o.recetas ?? [
        { id: 10, name: "Pasta con tomate", servings: 4, minutes: 25, slots: ["lunch", "dinner"] },
        { id: 11, name: "Ensalada de lentejas", servings: 4, minutes: 20, slots: ["lunch"] },
        { id: 12, name: "Tortilla de patatas", servings: 4, minutes: 30, slots: ["dinner"] },
    ];
    const alergenos = o.alergenos ?? { 10: ["gluten"], 11: [], 12: [] };
    let plan: Obj | null = null;
    let siguienteId = 100;
    const claves = new Map<string, Obj>();
    const escrituras: Mundo["escrituras"] = [];
    const lecturas: Mundo["lecturas"] = [];

    const clonar = <T>(x: T): T => JSON.parse(JSON.stringify(x));
    const sinComprobar = (items: Obj[]) => items.filter((i) => i.kind !== "recipe" || o.recetasSinComprobar?.includes(i.recipe_id as number)).map((i) => i.id);

    const miembrosPorDefecto = (dia: string, slot: string): number[] => {
        const wd = new Date(`${dia}T00:00:00Z`).getUTCDay() || 7;
        const fuera = new Set((perfil.schedule as Obj[]).filter((e) => e.weekday === wd && e.slot === slot && e.status !== "home").map((e) => e.home_member_id));
        return (perfil.members as Obj[]).map((m) => m.home_member_id as number).filter((id) => !fuera.has(id));
    };

    const leer: Leer = (ruta, params = {}) => {
        lecturas.push({ ruta, params });
        switch (ruta) {
            case "meal/profile": return Promise.resolve(clonar(perfil));
            case "meal/plan": {
                const sem = params.week_start;
                if (sem === SEMANA) return Promise.resolve(plan === null ? null : clonar(plan));
                return Promise.resolve(o.historial?.[String(sem)] ?? null);
            }
            case "meal/plan/check": {
                if (o.checkFalla || plan === null || String(plan.id) !== params.plan_id) return Promise.resolve({ error: 500 });
                const out: Obj[] = [];
                for (const it of plan.items as Obj[]) {
                    for (const m of it.members as number[]) {
                        const miem = (perfil.members as Obj[]).find((x) => x.home_member_id === m)!;
                        const al = (miem.allergies as Obj[]) ?? [];
                        for (const a of al) {
                            if (it.kind === "recipe" && alergenos[it.recipe_id as number]?.includes(String(a.allergen))) {
                                out.push({ item_id: it.id, day: it.day, slot: it.slot, member_id: m, code: "allergen", detail: { allergen: a.allergen } });
                            }
                        }
                        const wd = new Date(`${it.day}T00:00:00Z`).getUTCDay() || 7;
                        if ((perfil.schedule as Obj[]).some((e) => e.home_member_id === m && e.weekday === wd && e.slot === it.slot && e.status !== "home")) {
                            out.push({ item_id: it.id, day: it.day, slot: it.slot, member_id: m, code: "member_out", detail: {} });
                        }
                    }
                }
                return Promise.resolve(out);
            }
            case "recipe": {
                const q = String(params.q ?? "").toLowerCase();
                return Promise.resolve(recetas.filter((r) => q === "" || String(r.name).toLowerCase().includes(q)));
            }
            case "recipe/detail": {
                const id = Number(params.id);
                return Promise.resolve({ id, ingredients: o.ingredientes?.[id] ?? [{ food_id: 1, label: "ingrediente" }] });
            }
            case "food": {
                const q = String(params.q ?? "").toLowerCase();
                return Promise.resolve((o.alimentos ?? []).filter((f) => String(f.name).toLowerCase().includes(q)));
            }
            case "event": return Promise.resolve(o.eventos ?? []);
            default: return Promise.resolve({ error: "ruta no permitida" });
        }
    };

    const escribir: Escribir = (metodo, ruta, cuerpo = {}) => {
        escrituras.push({ metodo, ruta, cuerpo: clonar(cuerpo) });
        if (metodo === "POST" && ruta === "recipe/create") {
            const cr = String(cuerpo.client_request_id ?? "");
            if (cr && claves.has(cr)) return Promise.resolve(ok(claves.get(cr), 201));
            if (cuerpo.origin === "kito" && (!Array.isArray(cuerpo.steps) || cuerpo.steps.length === 0)) return Promise.resolve(fallo(400, "Invalid recipe"));
            const r = { id: siguienteId++, name: cuerpo.name, servings: cuerpo.servings, steps: cuerpo.steps, origin: cuerpo.origin ?? "user" };
            recetas.push({ id: r.id, name: r.name, servings: r.servings, minutes: null, slots: [] });
            if (cr) claves.set(cr, r);
            return Promise.resolve(ok(r, 201));
        }
        if (metodo === "POST" && ruta === "shopping/item/create") {
            const cr = String(cuerpo.client_request_id ?? "");
            if (cr && claves.has(cr)) return Promise.resolve(ok(claves.get(cr), 201));
            const it = { id: siguienteId++, label: cuerpo.label };
            if (cr) claves.set(cr, it);
            return Promise.resolve(ok(it, 201));
        }
        if (metodo === "PATCH" && ruta === "meal/profile/member") {
            const m = (perfil.members as Obj[]).find((x) => x.home_member_id === cuerpo.home_member_id);
            if (!m) return Promise.resolve(fallo(400, "Invalid member"));
            Object.assign(m, { ...cuerpo, home_member_id: m.home_member_id });
            return Promise.resolve(ok({ success: true }));
        }
        if (metodo === "PATCH" && ruta === "meal/plan/items") {
            const cr = String(cuerpo.client_request_id ?? "");
            if (cr && claves.has(cr)) return Promise.resolve(ok(clonar(claves.get(cr))));
            const rev = cuerpo.expected_revision as number;
            const origen = (cuerpo.origin as string) ?? "user";
            if (plan === null) {
                if (rev !== 0) return Promise.resolve(fallo(409, "Stale meal plan revision"));
                plan = { id: siguienteId++, week_start: cuerpo.week_start, status: "draft", revision: 0, origin: origen, items: [], unchecked_item_ids: [] };
            } else if (plan.revision !== rev) {
                return Promise.resolve(fallo(409, "Stale meal plan revision"));
            }
            const items = plan.items as Obj[];
            if (origen === "kito" && plan.status === "accepted") return Promise.resolve(fallo(400, "Invalid meal plan"));
            const borrar = (cuerpo.delete_ids as number[]) ?? [];
            if (origen === "kito" && items.some((i) => borrar.includes(i.id as number) && i.state === "locked")) return Promise.resolve(fallo(400, "Invalid meal plan"));
            const siguiente = items.filter((i) => !borrar.includes(i.id as number));
            for (const e of (cuerpo.items as Obj[]) ?? []) {
                if (e.id !== undefined) {
                    const viejo = siguiente.find((i) => i.id === e.id);
                    if (!viejo || (origen === "kito" && viejo.state === "locked")) return Promise.resolve(fallo(400, "Invalid meal plan"));
                    const rec = e.kind === "recipe" ? recetas.find((r) => r.id === e.recipe_id) : null;
                    Object.assign(viejo, {
                        day: e.day, slot: e.slot, position: e.position ?? 0, kind: e.kind, recipe_id: e.recipe_id ?? null,
                        title: rec ? rec.name : e.title ?? "", state: "state" in e ? e.state : viejo.state,
                    });
                } else {
                    const rec = e.kind === "recipe" ? recetas.find((r) => r.id === e.recipe_id) : null;
                    if (e.kind === "recipe" && !rec) return Promise.resolve(fallo(400, "Invalid meal plan"));
                    if (origen === "kito" && e.state === "locked") return Promise.resolve(fallo(400, "Invalid meal plan"));
                    siguiente.push({
                        id: siguienteId++, day: e.day, slot: e.slot, position: e.position ?? 0, kind: e.kind, recipe_id: e.recipe_id ?? null,
                        title: rec ? rec.name : e.title ?? "", servings: null, cook_member_id: null, state: e.state ?? null,
                        members: e.members ?? miembrosPorDefecto(String(e.day), String(e.slot)),
                    });
                }
            }
            plan.items = siguiente;
            plan.status = "draft";
            plan.revision = (plan.revision as number) + 1;
            plan.unchecked_item_ids = sinComprobar(siguiente);
            const respuesta = clonar(plan);
            if (cr) claves.set(cr, respuesta);
            return Promise.resolve(ok(respuesta));
        }
        return Promise.resolve(fallo(400, "ruta no permitida"));
    };

    return {
        leer, escribir, escrituras, lecturas, recetas, claves,
        plan: () => (plan === null ? null : clonar(plan)),
        ponerPlan: (p) => {
            plan = p === null ? null : clonar(p);
        },
        editarComoPersona: (fn) => {
            fn(plan!.items as Obj[]);
            plan!.revision = (plan!.revision as number) + 1;
        },
    };
};

export const ctxDe = (m: Mundo, over: Partial<ToolCtx> = {}): ToolCtx => ({
    token: "jwt", uid: "uid-1", homeId: "7", timezone: "Europe/Madrid", now: new Date("2030-01-03T10:00:00Z"),
    appUserId: "501", leer: m.leer, escribir: m.escribir, ...over,
});

/** Casilla de plan lista para `ponerPlan`. */
export const casilla = (id: number, day: string, slot: string, title: string, over: Obj = {}): Obj => ({
    id, day, slot, position: 0, kind: "free_text", recipe_id: null, title, servings: null, cook_member_id: null, state: null,
    members: [ANA, LEO], ...over,
});

/** Separa el valor para el modelo de los efectos (tarjeta, cambios) que `conEfectos` esconde en un símbolo. */
export const abrir = (r: unknown): { valor: Obj; tarjeta?: Obj; cambios?: Obj[] } => {
    const o = r as Obj;
    const sim = Object.getOwnPropertySymbols(o)[0];
    if (sim === undefined) return { valor: o };
    const ef = (o as unknown as Record<symbol, Obj>)[sim];
    return { valor: o.valor as Obj, tarjeta: ef.tarjeta as Obj | undefined, cambios: ef.cambios as Obj[] | undefined };
};
