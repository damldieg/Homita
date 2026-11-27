// UUID determinista para `client_request_id` (0035: tareas y listas). `uuidDe` vive en `_shared/homita/uuid.ts`.
import { uuidDe } from "../../../_shared/homita/uuid.ts";

export { uuidDe };

/** Clave de idempotencia de una alta: misma petición del bucle (mismo tool_use.id) → mismo UUID. */
export const clientRequestId = (
    quien: string,
    homeId: string | null,
    toolUseId: string,
    indice = 0,
): Promise<string> => uuidDe(`${quien}|${homeId ?? ""}|${toolUseId}|${indice}`);
