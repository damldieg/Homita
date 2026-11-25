// POST /asistente/confirmar {token, timezone?}: ejecuta las acciones de una tarjeta de confirmación firmada.
// Mismo Bearer y X-Home-Id que Kito (los comprueba `autenticar` en handler.ts), pero sin modelo ni cupo.
//
// Orden tras autenticar: sin KITO_CONFIRM_SECRET → 503; body sin JSON → 400; sin token → 400; token no
// válido (firma, caducado, otro usuario u otro hogar) → 403 sin ejecutar nada. Después ejecuta las acciones en
// orden dentro del hogar activo y se para en la primera que falle: 200 {texto, cambios} si todo fue bien y
// 409 {error, texto, cambios} si no (con lo que sí se hizo, para que la app recargue).
import type { Autenticado, HandlerDeps } from "../../handler.ts";
import { validTimezone } from "../../handler.ts";
import type { Cambio } from "../../core.ts";
import { ejecutarAccion } from "./acciones.ts";
import { verificar } from "./confirmacion.ts";

const json = (status: number, body: unknown): Response =>
    new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json; charset=utf-8" } });

export const confirmar = async (
    req: Request,
    deps: HandlerDeps,
    auth: Autenticado,
    log: (m: string) => void,
): Promise<Response> => {
    const secreto = (deps.env("KITO_CONFIRM_SECRET") ?? "").trim();
    if (secreto === "") {
        log("asistente: KITO_CONFIRM_SECRET no configurado");
        return json(503, { error: "Las confirmaciones no están disponibles" });
    }
    let raw: unknown;
    try {
        raw = await req.json();
    } catch {
        return json(400, { error: "El cuerpo no es JSON válido" });
    }
    const body = raw !== null && typeof raw === "object" ? raw as { token?: unknown; timezone?: unknown } : {};
    if (typeof body.token !== "string" || body.token === "") return json(400, { error: "Falta token" });
    const tz = body.timezone === undefined ? "UTC" : body.timezone;
    if (!validTimezone(tz)) return json(400, { error: "Zona horaria no válida" });

    const v = await verificar(body.token, secreto, { uid: auth.who.uid, homeId: auth.homeId, ahora: deps.now().getTime() });
    if (!v.ok) {
        log("asistente: confirmación rechazada");
        return json(403, { error: "Confirmación no válida", motivo: v.motivo });
    }
    if (!deps.crearEscritor) return json(500, { error: "Error interno" });

    const escribir = deps.crearEscritor(auth.token, auth.who.uid, tz, auth.homeId);
    const hechos: string[] = [];
    const cambios: Cambio[] = [];
    let fallo: string | null = null;
    await deps.runInHome(auth.homeId, async () => {
        for (const accion of v.payload.acciones) {
            const r = await ejecutarAccion(escribir, accion);
            if (!r.ok) {
                fallo = r.texto;
                return;
            }
            hechos.push(r.texto, ...r.avisos);
            cambios.push(...r.cambios);
        }
    });
    const lista = (l: string[]) => (l.length === 1 ? `Hecho: ${l[0]}.` : `Hecho:\n${l.map((x) => `- ${x}.`).join("\n")}`);
    if (fallo !== null) {
        const hasta = hechos.length ? `${lista(hechos)}\n` : "";
        return json(409, { error: fallo, texto: `${hasta}No he podido seguir: ${fallo}`, cambios });
    }
    return json(200, { texto: lista(hechos), cambios });
};
