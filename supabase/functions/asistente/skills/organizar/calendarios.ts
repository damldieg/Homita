// Herramientas de calendarios: crear_calendario, editar_calendario, borrar_calendario.
//
// «De quién es» un calendario = con quién se comparte: crear_calendario pregunta con quién (o «solo yo»).
// Se comparte por persona del hogar con `PATCH /calendar/user` (0029: agrega a la cuenta vinculada a esa
// persona, sin email): la persona debe tener cuenta en Homita. Por defecto el permiso es solo lectura.
import { fraseEdicion } from "./acciones.ts";
import type { Tool } from "../../core.ts";
import { personasDelHogar } from "../consulta/personas.ts";
import {
    booleano, despachar, entero, esquema, falta, filaPorId, filas, herramienta, lista, objeto, texto, YA_NO_EXISTE,
} from "./base.ts";
import type { Obj } from "./base.ts";
import { COLOR_DEFECTO, COLOR_RE, ERROR_COLOR } from "./listas.ts";

const crearCalendario: Tool = herramienta({
    name: "crear_calendario",
    description:
        "Crea un calendario. Indispensables: nombre y con quién se comparte (compartir_con con personas del hogar que tengan cuenta, o solo_yo = true si es solo para el usuario). Por defecto comparte en solo lectura; puede_editar da permiso de edición. Si falta con quién, pregúntalo.",
    input_schema: esquema({
        nombre: { type: "string", description: "Nombre del calendario." },
        solo_yo: { type: "boolean", description: "true si el calendario es solo para el usuario." },
        compartir_con: {
            type: "array",
            description: "Personas con las que se comparte (ids del contexto).",
            items: {
                type: "object",
                properties: {
                    persona_id: { type: "integer", description: "Id de la persona." },
                    puede_editar: { type: "boolean", description: "true para permiso de edición; por defecto solo lectura." },
                },
                required: ["persona_id"],
            },
        },
        color: { type: "string", description: "Color #RRGGBB, solo si lo piden." },
    }, ["nombre"]),
    run: async (input, ctx) => {
        const nombre = texto(input, "nombre");
        const soloYo = booleano(input, "solo_yo") === true;
        const compartir = lista(input, "compartir_con") ?? [];
        const faltan = [nombre ? "" : "nombre", soloYo || compartir.length > 0 ? "" : "con quién se comparte (o solo para ti)"].filter((x) => x);
        if (faltan.length) return falta(faltan);
        const color = texto(input, "color");
        if (color !== undefined && !COLOR_RE.test(color)) return ERROR_COLOR;

        const destinos: Obj[] = [];
        if (!soloYo) {
            const todas = await filas(ctx.leer, "person");
            if (todas === null) return { ok: false, error: "No he podido leer las personas del hogar ahora mismo." };
            const delHogar = personasDelHogar(todas, ctx.homeId);
            const sinCuenta: string[] = [];
            for (const c of compartir) {
                const o = objeto(c);
                const pid = entero(o, "persona_id");
                const p = delHogar.find((x) => Number(x.id) === pid);
                if (!p) return { ok: false, error: "Esa persona ya no existe en el hogar." };
                if (p.app_user_id === null || p.app_user_id === undefined) {
                    sinCuenta.push(String(p.name));
                } else if (String(p.app_user_id) !== ctx.appUserId) {
                    destinos.push({ user_id: p.app_user_id, can_edit: o.puede_editar === true, nombre: String(p.name) });
                }
            }
            if (sinCuenta.length > 0) {
                return {
                    ok: false,
                    sin_cuenta: sinCuenta,
                    error: `${sinCuenta.join(" y ")} no tiene cuenta en Homita, así que no puedo compartirlo con esa persona. No he creado nada.`,
                };
            }
        }
        const args: Obj = { name: nombre, color: color ?? COLOR_DEFECTO, compartir: destinos };
        const compartido = destinos.map((d) => `${d.nombre} (${d.can_edit ? "puede editar" : "solo lectura"})`);
        return despachar(
            ctx,
            { op: "crear_calendario", args, nombre },
            {
                frase: `Creo el calendario «${nombre}»${compartido.length ? ` compartido con ${compartido.join(", ")}` : " solo para ti"}`,
                extra: { compartido_con: compartido.length ? compartido : "solo contigo", color: args.color },
            },
        );
    },
});

const editarCalendario: Tool = herramienta({
    name: "editar_calendario",
    description:
        "Cambia el nombre o el color de un calendario. Indispensable: id del calendario (viene en el contexto) y al menos un cambio. Solo manda lo que cambia: el resto se conserva.",
    input_schema: esquema({
        id: { type: "integer", description: "Id del calendario." },
        nombre: { type: "string", description: "Nuevo nombre." },
        color: { type: "string", description: "Nuevo color #RRGGBB." },
    }, ["id"]),
    run: async (input, ctx) => {
        const id = entero(input, "id");
        const nombre = texto(input, "nombre");
        const color = texto(input, "color");
        const pide = [id === undefined ? "calendario" : "", nombre === undefined && color === undefined ? "qué cambiar" : ""].filter((x) => x);
        if (pide.length) return falta(pide);
        if (color !== undefined && !COLOR_RE.test(color)) return ERROR_COLOR;
        const cur = await filaPorId(ctx, "calendar", id!);
        if (cur === null) return YA_NO_EXISTE;
        // El api exige nombre y color, y pone widget/dashboard a true si faltan: se rellenan con lo actual.
        const args: Obj = {
            id,
            name: nombre ?? cur.name,
            color: color ?? cur.color,
            widget: Number(cur.widget) === 1 || cur.widget === true,
            dashboard: Number(cur.dashboard) === 1 || cur.dashboard === true,
        };
        const frase = fraseEdicion(`Edito el calendario «${cur.name}»`, [["nombre", cur.name, nombre], ["color", cur.color, color]]);
        return despachar(ctx, { op: "editar_calendario", args, nombre: String(cur.name) }, { frase });
    },
});

const borrarCalendario: Tool = herramienta({
    name: "borrar_calendario",
    description:
        "Pide borrar un calendario con sus eventos y rutinas. No borra: deja una confirmación en pantalla para el usuario. Indispensable: id del calendario.",
    input_schema: esquema({ id: { type: "integer", description: "Id del calendario." } }, ["id"]),
    run: async (input, ctx) => {
        const id = entero(input, "id");
        if (id === undefined) return falta(["calendario"]);
        const cur = await filaPorId(ctx, "calendar", id);
        if (cur === null) return YA_NO_EXISTE;
        return despachar(
            ctx,
            { op: "borrar_calendario", args: { id }, nombre: String(cur.name) },
            { frase: `Borro el calendario «${cur.name}» con todos sus eventos y rutinas` },
        );
    },
});

export const HERRAMIENTAS_CALENDARIOS: Tool[] = [crearCalendario, editarCalendario, borrarCalendario];
