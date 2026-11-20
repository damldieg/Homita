// handler.ts — Lógica de procesar-feedback (change feedback-trello-gate, D-021). Sin efectos al importar:
// BD, fetch, entorno, reloj y log se inyectan (index.ts hace el cableado; los tests usan falsos).
//
// Orden (cada paso corta si falla):
//   1. Secreto: FEEDBACK_WEBHOOK_SECRET vacío -> 500 (falla cerrado); cabecera x-feedback-secret ausente o
//      distinta -> 401. Comparación en tiempo constante (SHA-256 + XOR). Antes de leer el body.
//   2. Body JSON con record.id entero seguro > 0 (del payload solo se usa el id) -> si no, 400.
//      Configuración de Trello/Anthropic incompleta -> 500 sin reservar (la fila sigue pendiente).
//   3. Reserva atómica (db.claim). 0 filas -> 404 si no existe, 200 «ya procesado o en curso» si existe.
//   4. Tarjetas abiertas de la lista. 5. Si una lleva el marcador de este id, se reutiliza (sin modelo).
//   6. Gate del modelo (gate.ts). 7. Crear tarjeta o comentar. 8. db.finalize (RPC atómica). 9. 200 ok.
// Fallos: antes del efecto en Trello -> markError + 500. finalize falla tras crear -> relectura del estado
// (db.getEstado) y archivar (PUT closed=true, nunca DELETE) solo si sigue 'pendiente'; si ya está procesado
// o la relectura falla, no se archiva y se registra la inconsistencia; después markError. Tras vincular ->
// markError (el comentario queda).
// Logs: solo operación, status e ids; nunca URL, cabeceras, body, texto del reporte ni secretos.

import { DbError } from "./db.ts";
import type { FeedbackDb, FeedbackEstado, FinalizeArgs } from "./db.ts";
import {
    buildGateRequest,
    cardDesc,
    commentText,
    findMarkedCard,
    GateError,
    MAX_DESCRIPCION,
    MAX_TITLE,
    parseDecision,
    sanitizeTitle,
    stripMarker,
    truncate,
} from "./gate.ts";
import type { FeedbackRow } from "./gate.ts";
import { createTrello, TrelloError } from "./trello.ts";
import type { FetchFn, TrelloCard } from "./trello.ts";

export interface HandlerDeps {
    db: FeedbackDb;
    fetch: FetchFn;
    env: (name: string) => string | undefined;
    now: () => Date;
    /** Destino de logs (por defecto console.error). */
    log?: (msg: string) => void;
}

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const DEFAULT_MODEL = "claude-haiku-5-5";
const TRELLO_TIMEOUT_MS = 8000;
const ANTHROPIC_TIMEOUT_MS = 20000;

const text = (status: number, body: string) =>
    new Response(body, { status, headers: { "Content-Type": "text/plain; charset=utf-8" } });

/** Igualdad en tiempo constante: compara los SHA-256 de ambos lados byte a byte. */
export async function safeEqual(a: string, b: string): Promise<boolean> {
    const enc = new TextEncoder();
    const [ha, hb] = await Promise.all([
        crypto.subtle.digest("SHA-256", enc.encode(a)),
        crypto.subtle.digest("SHA-256", enc.encode(b)),
    ]);
    const x = new Uint8Array(ha);
    const y = new Uint8Array(hb);
    let diff = 0;
    for (let i = 0; i < x.length; i++) diff |= x[i] ^ y[i];
    return diff === 0;
}

/** Describe un error para el log sin mensajes externos (pueden llevar URL o datos). */
const describe = (e: unknown): string => {
    if (e instanceof TrelloError) return `trello ${e.op} status=${e.status}`;
    if (e instanceof GateError) return `gate ${e.reason}`;
    if (e instanceof DbError) return `db ${e.op} code=${e.code}`;
    if (e instanceof DOMException && (e.name === "TimeoutError" || e.name === "AbortError")) return "timeout";
    return "error inesperado";
};

export function createHandler(deps: HandlerDeps): (req: Request) => Promise<Response> {
    const log = deps.log ?? ((m: string) => console.error(m));

    return async (req: Request): Promise<Response> => {
        // 1. Secreto, antes de leer el body.
        const secret = deps.env("FEEDBACK_WEBHOOK_SECRET") ?? "";
        if (secret === "") {
            log("procesar-feedback: secreto no configurado");
            return text(500, "secreto no configurado");
        }
        const given = req.headers.get("x-feedback-secret");
        if (given === null || !(await safeEqual(given, secret))) {
            await req.body?.cancel();
            return text(401, "no autorizado");
        }

        // 2. Body: solo record.id.
        let id: unknown;
        try {
            id = ((await req.json()) as { record?: { id?: unknown } })?.record?.id;
        } catch {
            return text(400, "body inválido");
        }
        if (typeof id !== "number" || !Number.isSafeInteger(id) || id <= 0) return text(400, "record.id inválido");

        const cfg = {
            key: deps.env("TRELLO_KEY") ?? "",
            token: deps.env("TRELLO_TOKEN") ?? "",
            listId: deps.env("TRELLO_LIST_ID") ?? "",
            anthropicKey: deps.env("ANTHROPIC_API_KEY") ?? "",
        };
        const missing = Object.entries(cfg).filter(([, v]) => v === "").map(([k]) => k);
        if (missing.length > 0) {
            log(`procesar-feedback: feedback=${id} configuración incompleta (${missing.join(",")})`);
            return text(500, "configuración incompleta");
        }
        const model = deps.env("CLAUDE_MODEL") || DEFAULT_MODEL;
        const trello = createTrello({ ...cfg, fetch: deps.fetch, timeoutMs: TRELLO_TIMEOUT_MS });

        const markError = async (why: string): Promise<Response> => {
            log(`procesar-feedback: feedback=${id} ${why}`);
            try {
                await deps.db.markError(id as number);
            } catch (e) {
                log(`procesar-feedback: feedback=${id} markError falló (${describe(e)}); fila atascada`);
            }
            return text(500, "error");
        };

        // 3. Reserva atómica.
        let row: FeedbackRow | null;
        try {
            row = await deps.db.claim(id, deps.now());
            if (!row) {
                if (!(await deps.db.exists(id))) return text(404, "no existe");
                return text(200, "ya procesado o en curso");
            }
        } catch (e) {
            log(`procesar-feedback: feedback=${id} reserva falló (${describe(e)})`);
            return text(500, "error");
        }

        // 4–7. Tarjetas, dedupe, gate y efecto en Trello.
        let fin: FinalizeArgs;
        let created: string | null = null;
        try {
            const cards = await trello.listCards();
            const marked = findMarkedCard(cards, id);
            if (marked) {
                log(`procesar-feedback: feedback=${id} reutiliza tarjeta con marcador card=${marked.id}`);
                fin = finalizeArgs(id, true, marked);
            } else {
                const gate = buildGateRequest(row, cards, model);
                const res = await deps.fetch(ANTHROPIC_URL, {
                    method: "POST",
                    headers: {
                        "x-api-key": cfg.anthropicKey,
                        "anthropic-version": "2023-06-01",
                        "content-type": "application/json",
                    },
                    body: JSON.stringify(gate.body),
                    signal: AbortSignal.timeout(ANTHROPIC_TIMEOUT_MS),
                });
                let json: unknown = null;
                try {
                    json = await res.json();
                } catch {
                    json = null;
                }
                const decision = parseDecision(res.status, json, gate.sentIds);
                if (decision.kind === "crear") {
                    const card = await trello.createCard(decision.titulo, cardDesc(decision.descripcion, row));
                    created = card.id;
                    fin = {
                        feedbackId: id,
                        crear: true,
                        cardId: card.id,
                        cardUrl: card.shortUrl,
                        titulo: decision.titulo,
                        descripcion: decision.descripcion,
                    };
                } else {
                    const target = cards.find((c) => c.id === decision.cardId)!;
                    await trello.addComment(target.id, commentText(row));
                    fin = finalizeArgs(id, false, target);
                }
            }
        } catch (e) {
            return await markError(`antes de escribir en BD (${describe(e)})`);
        }

        // 8. Final atómico.
        try {
            await deps.db.finalize(fin);
        } catch (e) {
            if (created) {
                // El error puede llegar tras el COMMIT (red, corte de PostgREST): se relee la fila y solo se
                // archiva si sigue 'pendiente'. Si ya está procesada, o no se puede releer, la tarjeta queda.
                let actual: FeedbackEstado | null = null;
                let leida = false;
                try {
                    actual = await deps.db.getEstado(id);
                    leida = true;
                } catch (e3) {
                    log(`procesar-feedback: feedback=${id} inconsistencia: relectura tras finalize falló ` +
                        `(${describe(e3)}); no se archiva card=${created}`);
                }
                if (leida && actual?.estado === "pendiente") {
                    try {
                        await trello.archiveCard(created);
                    } catch (e2) {
                        log(`procesar-feedback: feedback=${id} no se pudo archivar card=${created} (${describe(e2)})`);
                    }
                } else if (leida) {
                    log(`procesar-feedback: feedback=${id} inconsistencia: finalize devolvió error pero la fila ` +
                        `está en estado=${actual?.estado ?? "inexistente"} backlog=${actual?.backlogId ?? "null"}; ` +
                        `no se archiva card=${created}`);
                }
            }
            return await markError(`finalize falló card=${fin.cardId} (${describe(e)})`);
        }
        log(`procesar-feedback: feedback=${id} ok ${fin.crear ? "crear" : "vincular"} card=${fin.cardId}`);
        return text(200, "ok");
    };
}

/** Argumentos de finalize a partir de una tarjeta existente (vinculada o reutilizada por marcador). */
const finalizeArgs = (id: number, crear: boolean, c: TrelloCard): FinalizeArgs => ({
    feedbackId: id,
    crear,
    cardId: c.id,
    cardUrl: c.shortUrl,
    titulo: sanitizeTitle(c.name) || truncate(`Tarjeta ${c.id}`, MAX_TITLE),
    descripcion: truncate(stripMarker(c.desc), MAX_DESCRIPCION),
});
