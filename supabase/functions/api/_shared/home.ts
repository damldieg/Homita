// Contexto del hogar activo (X-Home-Id, diseño §2.2; plan 1.4 §4.1). La Edge valida la cabecera
// antes del handler y fija el hogar en un AsyncLocalStorage (node:async_hooks, soportado por el
// runtime Edge de Supabase; prueba de concurrencia en T4/RK1) para que el transporte
// (_shared/supabase.ts) lo propague a PostgREST sin parámetro en los ~60 call sites de las RPC.
// Sin variable global: las peticiones concurrentes con distinto X-Home-Id no se mezclan.
import { AsyncLocalStorage } from "node:async_hooks";
import { rpc } from "./supabase.ts";

const homeContext = new AsyncLocalStorage<string | null>();

export type HomeHeader = { present: false } | { present: true; id: string } | "INVALID";

// Cabecera opcional X-Home-Id: ausente o vacía (A9) = sin contexto; formato ^[0-9]{1,18}$ y
// normalización BigInt (evita "007"); el resto → "INVALID" (400 Invalid home).
export const parseHomeHeader = (req: Request): HomeHeader => {
    const raw = req.headers.get("X-Home-Id");
    if (raw === null || raw === "") return { present: false };
    if (!/^[0-9]{1,18}$/.test(raw)) return "INVALID";
    return { present: true, id: BigInt(raw).toString() };
};

// Ejecuta fn con el hogar activo (o null) en el contexto de la petición
export const runWithHome = <T>(homeId: string | null, fn: () => T): T => homeContext.run(homeId, fn);

// Hogar activo de la petición en curso, o null (sin filtro)
export const currentHome = (): string | null => homeContext.getStore() ?? null;

// Membresía del hogar de cabecera contra get_homes() (§3.1 #5; se llama ANTES de fijar el
// contexto, así la RPC no lleva cabecera de hogar). Comparación como string: get_homes devuelve
// home_id numérico y el contexto es texto (R1-03).
export const checkHomeMember = async (homeId: string, token: string): Promise<boolean> => {
    const res = await rpc("get_homes", {}, token);
    if (!res.ok) return false;
    const rows: { home_id: number }[] = await res.json().catch(() => []);
    return rows.some((h) => String(h.home_id) === homeId);
};
