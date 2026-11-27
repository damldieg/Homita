// Edge Function `mcp` (MCP remoto de Claude para Homita, fase 1: solo lectura). Solo cableado: la lógica está en
// handler.ts. Se despliega con --no-verify-jwt (auth manual: solo tokens OAuth de Supabase Auth, ver auth.ts).
// Variables opcionales: MCP_PUBLIC_URL, MCP_AUTH_URL, MCP_TOKEN_AUDIENCE (ver README). SUPABASE_URL y
// SUPABASE_ANON_KEY las inyecta el runtime. No usa la clave de servicio: todo va por los casos de uso de `api` con el JWT
// del usuario.
import { createHandler } from "./handler.ts";
import { AUDIENCIA_POR_DEFECTO } from "./auth.ts";
import { leerRuta } from "../_shared/homita/lector.ts";
import { appUserRow } from "../api/_shared/supabase.ts";
import { checkHomeMember, runWithHome } from "../api/_shared/home.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

Deno.serve(createHandler({
    // Supabase Auth valida firma, caducidad y sesión del token y devuelve el usuario.
    userInfo: async (token) => {
        const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
            headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}` },
        });
        if (!res.ok) return null;
        const who = await res.json() as { id?: unknown };
        return typeof who.id === "string" ? { id: who.id } : null;
    },
    audience: Deno.env.get("MCP_TOKEN_AUDIENCE") || AUDIENCIA_POR_DEFECTO,
    publicUrl: Deno.env.get("MCP_PUBLIC_URL") || undefined,
    authUrl: Deno.env.get("MCP_AUTH_URL") || undefined,
    leerRuta,
    checkHomeMember,
    runInHome: (homeId, fn) => runWithHome(homeId, fn),
    appUserId: async (uid, token) => {
        const row = await appUserRow(uid, token);
        return row === null ? null : String(row.id);
    },
    now: () => new Date(),
}));
