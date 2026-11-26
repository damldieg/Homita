// Skill `menus` (kito-menus): Kito propone el menú semanal como borrador, la persona marca lo que cambiar y la app
// lo acepta. Kito nunca acepta. Las herramientas y el prompt se añaden por tareas (ver el resto de ficheros).
import type { Skill } from "../../core.ts";
import { INTENCION_MENUS } from "./intencion.ts";

export const menus: Skill = {
    id: "menus",
    nombre: "Menús",
    descripcion: "Propone el menú semanal del hogar como borrador, repropone lo que la persona rechaza y apunta recetas y compra.",
    instrucciones: "Skill «menus»: en construcción.",
    herramientas: [],
    modelo: "KITO_MODEL_MENUS",
    intencion: INTENCION_MENUS,
    maxRondas: 8,
    tarjetas: ["menu"],
    disponible: (ctx) => ctx.homeId !== null,
};
