// db.ts — Acceso a BD de procesar-feedback (change feedback-trello-gate). La interfaz `FeedbackDb` la usa
// handler.ts (los tests la sustituyen por un falso); el adaptador supabase-js no tiene lógica: cada
// método es una sola llamada y comprueba `error`. La lógica de la escritura final vive en la RPC
// homita_feedback_finalize (0033), probada en B5–B7.

import type { SupabaseClient } from "npm:@supabase/supabase-js@2";
import type { FeedbackRow } from "./gate.ts";

export type { FeedbackRow };

export interface FinalizeArgs {
    feedbackId: number;
    crear: boolean;
    cardId: string;
    cardUrl: string;
    titulo: string;
    descripcion: string;
}

/** Estado actual de una fila de feedback (relectura tras un error de finalize). */
export interface FeedbackEstado {
    estado: string;
    backlogId: number | null;
}

export interface FeedbackDb {
    /** Reserva atómica: devuelve la fila si estaba pendiente y sin reservar; null si no. */
    claim(id: number, at: Date): Promise<FeedbackRow | null>;
    /** true si existe una fila de feedback con ese id. */
    exists(id: number): Promise<boolean>;
    /** Lee `estado` y `backlog_id` de la fila; null si no existe. */
    getEstado(id: number): Promise<FeedbackEstado | null>;
    /** `estado = 'error'` solo si sigue `pendiente`. */
    markError(id: number): Promise<void>;
    /** RPC homita_feedback_finalize; devuelve el backlog_id. */
    finalize(args: FinalizeArgs): Promise<number>;
}

/** Fallo de BD sin detalles (el mensaje de PostgREST puede llevar datos de la fila). */
export class DbError extends Error {
    constructor(readonly op: string, readonly code: string) {
        super(`db ${op}: ${code}`);
        this.name = "DbError";
    }
}

const fail = (op: string, error: { code?: string } | null): never => {
    throw new DbError(op, error?.code ?? "unknown");
};

export function createSupabaseDb(client: SupabaseClient): FeedbackDb {
    return {
        async claim(id, at) {
            // Una sola sentencia: UPDATE … WHERE estado = 'pendiente' AND procesando_desde IS NULL RETURNING.
            const { data, error } = await client
                .from("feedback")
                .update({ procesando_desde: at.toISOString() })
                .eq("id", id)
                .eq("estado", "pendiente")
                .is("procesando_desde", null)
                .select("id,texto,seccion,subseccion,tipo");
            if (error) fail("claim", error);
            const rows = (data ?? []) as FeedbackRow[];
            return rows.length === 1 ? rows[0] : null;
        },
        async exists(id) {
            const { data, error } = await client.from("feedback").select("id").eq("id", id).limit(1);
            if (error) fail("exists", error);
            return (data ?? []).length > 0;
        },
        async getEstado(id) {
            const { data, error } = await client
                .from("feedback")
                .select("estado,backlog_id")
                .eq("id", id)
                .limit(1);
            if (error) fail("getEstado", error);
            const rows = (data ?? []) as { estado: string; backlog_id: number | null }[];
            if (rows.length === 0) return null;
            return { estado: rows[0].estado, backlogId: rows[0].backlog_id ?? null };
        },
        async markError(id) {
            const { error } = await client
                .from("feedback")
                .update({ estado: "error" })
                .eq("id", id)
                .eq("estado", "pendiente");
            if (error) fail("markError", error);
        },
        async finalize(a) {
            const { data, error } = await client.rpc("homita_feedback_finalize", {
                p_feedback_id: a.feedbackId,
                p_crear: a.crear,
                p_card_id: a.cardId,
                p_card_url: a.cardUrl,
                p_titulo: a.titulo,
                p_descripcion: a.descripcion,
            });
            if (error) fail("finalize", error);
            if (typeof data !== "number") throw new DbError("finalize", "sin backlog_id");
            return data;
        },
    };
}
