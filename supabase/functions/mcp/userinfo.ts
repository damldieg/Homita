// `GET /auth/v1/user` con el Bearer: Supabase Auth valida firma, caducidad y sesión y devuelve el usuario.
// Solo 401/403 significan «token inválido» (`null`). 5xx, 429 u otro fallo: Auth no está disponible
// (`AuthNoDisponible`) y el handler responde 503 para que el cliente reintente en vez de reconectar.
import { AuthNoDisponible } from "./auth.ts";
import type { UserInfo } from "./auth.ts";

export const userInfoReal = (supabaseUrl: string, anonKey: string): UserInfo => async (token) => {
    const res = await fetch(`${supabaseUrl}/auth/v1/user`, {
        headers: { apikey: anonKey, Authorization: `Bearer ${token}` },
    });
    if (res.status === 401 || res.status === 403) {
        await res.body?.cancel();
        return null;
    }
    if (!res.ok) {
        await res.body?.cancel();
        throw new AuthNoDisponible(`auth ${res.status}`);
    }
    const who = await res.json() as { id?: unknown };
    return typeof who.id === "string" ? { id: who.id } : null;
};
