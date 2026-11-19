// trello.ts — Cliente mínimo de la API REST de Trello para procesar-feedback (change feedback-trello-gate).
// Sin efectos al importar: `fetch` se inyecta (tests con mocks, sin red).
//
// Supuestos (T0, 2026-11-19). Sin acceso a la doc en vivo durante el build: lo que sigue sale de la
// documentación conocida de Trello y queda PENDIENTE de confirmar en la doc oficial antes del smoke (P7):
//   - Auth por cabecera `Authorization: OAuth oauth_consumer_key="<key>", oauth_token="<token>"`
//     (alternativa a key/token en la query; así no viajan en la URL ni en logs de proxies).
//   - GET  /1/lists/{id}/cards?fields=…  devuelve solo tarjetas abiertas (filtro por defecto `open`),
//     sin paginación relevante por debajo de 1000 tarjetas.
//   - POST /1/cards {idList, name, desc}            crea la tarjeta y devuelve {id, shortUrl, …}.
//   - POST /1/cards/{id}/actions/comments {text}    añade un comentario.
//   - PUT  /1/cards/{id} {closed: true}             archiva (nunca se usa DELETE).
// Los errores (`TrelloError`) llevan solo la operación y el status HTTP: nunca URL, cabeceras ni cuerpo.

export type FetchFn = typeof fetch;

/** Tarjeta abierta de la lista de Feedback (solo los campos pedidos). */
export interface TrelloCard {
    id: string;
    name: string;
    desc: string;
    shortUrl: string;
    dateLastActivity: string;
}

/** Fallo de una llamada a Trello. `status` 0 = error de red o timeout. */
export class TrelloError extends Error {
    constructor(readonly op: string, readonly status: number) {
        super(`trello ${op}: status ${status}`);
        this.name = "TrelloError";
    }
}

export interface TrelloConfig {
    key: string;
    token: string;
    listId: string;
    fetch: FetchFn;
    /** Timeout por llamada (ms). Por defecto 8000. */
    timeoutMs?: number;
}

export interface Trello {
    listCards(): Promise<TrelloCard[]>;
    createCard(name: string, desc: string): Promise<{ id: string; shortUrl: string }>;
    addComment(cardId: string, text: string): Promise<void>;
    archiveCard(cardId: string): Promise<void>;
}

const BASE = "https://api.trello.com/1";
const str = (v: unknown): string => (typeof v === "string" ? v : "");

/** Crea el cliente. La key y el token solo viajan en la cabecera Authorization. */
export function createTrello(cfg: TrelloConfig): Trello {
    const timeoutMs = cfg.timeoutMs ?? 8000;
    const auth = `OAuth oauth_consumer_key="${cfg.key}", oauth_token="${cfg.token}"`;

    const call = async (op: string, method: string, path: string, body?: unknown): Promise<unknown> => {
        const headers: Record<string, string> = { Authorization: auth, Accept: "application/json" };
        if (body !== undefined) headers["Content-Type"] = "application/json";
        let res: Response;
        try {
            res = await cfg.fetch(`${BASE}${path}`, {
                method,
                headers,
                body: body === undefined ? undefined : JSON.stringify(body),
                signal: AbortSignal.timeout(timeoutMs),
            });
        } catch {
            // El error original puede incluir la URL: no se propaga.
            throw new TrelloError(op, 0);
        }
        if (!res.ok) {
            await res.body?.cancel();
            throw new TrelloError(op, res.status);
        }
        try {
            return await res.json();
        } catch {
            throw new TrelloError(op, res.status);
        }
    };

    const cardPath = (cardId: string) => `/cards/${encodeURIComponent(cardId)}`;

    return {
        async listCards() {
            const data = await call(
                "listCards",
                "GET",
                `/lists/${encodeURIComponent(cfg.listId)}/cards?fields=id,name,desc,shortUrl,dateLastActivity`,
            );
            if (!Array.isArray(data)) throw new TrelloError("listCards", 200);
            return data
                .filter((c) => c && typeof c === "object" && typeof (c as { id?: unknown }).id === "string")
                .map((c) => {
                    const o = c as Record<string, unknown>;
                    return {
                        id: str(o.id),
                        name: str(o.name),
                        desc: str(o.desc),
                        shortUrl: str(o.shortUrl),
                        dateLastActivity: str(o.dateLastActivity),
                    };
                });
        },
        async createCard(name, desc) {
            const data = await call("createCard", "POST", "/cards", { idList: cfg.listId, name, desc });
            const o = (data ?? {}) as Record<string, unknown>;
            if (typeof o.id !== "string" || o.id === "") throw new TrelloError("createCard", 200);
            return { id: o.id, shortUrl: str(o.shortUrl) };
        },
        async addComment(cardId, text) {
            await call("addComment", "POST", `${cardPath(cardId)}/actions/comments`, { text });
        },
        async archiveCard(cardId) {
            await call("archiveCard", "PUT", cardPath(cardId), { closed: true });
        },
    };
}
