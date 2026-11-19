// feedback (change control-ios-feedback): POST /feedback inserta en public.feedback con el JWT del
// usuario (RLS «insertar mi feedback»; user_id lo pone el default auth.uid(), el cliente no lo
// envía). Sin service role. Cualquier miembro autenticado puede enviar.
import { contractBodyOnly, json } from "../_shared/contract.ts";
import { error } from "../_shared/errors.ts";
import { insertRow } from "../_shared/supabase.ts";
import { validateFeedback } from "../_shared/validate.ts";

export const handleFeedbackCreate = async (req: Request, token: string): Promise<Response> => {
    const input = await contractBodyOnly(req);
    const v = validateFeedback(input);
    if (v instanceof Response) return v;
    const res = await insertRow("feedback", {
        seccion: v.seccion, subseccion: v.subseccion, tipo: v.tipo, texto: v.texto,
    }, token);
    if (!res.ok) {
        const body = await res.json().catch(() => null) as { code?: string; message?: string } | null;
        // 42501 = RLS/privilegios denegados
        if (res.status === 401 || res.status === 403 || body?.code === "42501") return error("Not Allowed", 403);
        if (res.status >= 400 && res.status < 500) return error("Invalid feedback", 400);
        return error("Internal error", 500);
    }
    // Sin SELECT sobre feedback (RLS solo INSERT, como prod) no se puede devolver la fila: el insert
    // va con return=minimal y la respuesta es 201 {"ok": true}.
    return json({ ok: true }, 201);
};
