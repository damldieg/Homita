// Registro de skills de Kito. Añadir una skill = crear su carpeta y añadirla aquí; el núcleo (core.ts)
// y el handler no cambian.
import type { Skill } from "../core.ts";
import { consulta } from "./consulta/index.ts";

export const SKILLS: Skill[] = [consulta];
