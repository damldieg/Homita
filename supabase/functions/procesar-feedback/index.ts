// procesar-feedback — Edge Function que dispara el trigger de feedback (0034: homita_feedback_notify →
// homita_feedback_dispatch). Solo cableado: la lógica está en handler.ts (change feedback-trello-gate).
// Se despliega con --no-verify-jwt: la auth es el secreto compartido x-feedback-secret.
import { createClient } from "npm:@supabase/supabase-js@2";
import { createSupabaseDb } from "./db.ts";
import { createHandler } from "./handler.ts";

const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
);

Deno.serve(createHandler({
    db: createSupabaseDb(client),
    fetch: (input, init) => fetch(input, init),
    env: (name) => Deno.env.get(name),
    now: () => new Date(),
}));
