import { createClient } from "npm:@supabase/supabase-js@2";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const tools = [
  {
    name: "vincular_existente",
    description: "Usar si el reporte ya existe en el backlog.",
    input_schema: {
      type: "object",
      properties: { backlog_id: { type: "integer" } },
      required: ["backlog_id"],
    },
  },
  {
    name: "crear_item",
    description: "Usar si no hay nada similar en el backlog.",
    input_schema: {
      type: "object",
      properties: {
        titulo: { type: "string" },
        descripcion: { type: "string" },
      },
      required: ["titulo", "descripcion"],
    },
  },
];

Deno.serve(async (req) => {
  const { record } = await req.json();

  const { data: items } = await db
    .from("backlog").select("id,titulo,descripcion")
    .eq("seccion", record.seccion).limit(200);

  const prompt = `Eres el Product Owner de Homita. Llega un reporte.
Sección: ${record.seccion} / ${record.subseccion ?? "-"}
Tipo: ${record.tipo}
Texto: ${record.texto}

Backlog actual de esa sección:
${JSON.stringify(items)}

Si ya existe algo equivalente, llama a vincular_existente.
Si no, llama a crear_item con un título corto y una descripción clara.`;

  const r = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model: Deno.env.get("CLAUDE_MODEL") ?? "claude-haiku-5-5",
      max_tokens: 1024,
      tools,
      messages: [{ role: "user", content: prompt }],
    }),
  });
  const res = await r.json();
  const call = res.content?.find((b: any) => b.type === "tool_use");

  if (!call) {
    await db.from("feedback").update({ estado: "error" }).eq("id", record.id);
    return new Response("sin herramienta", { status: 500 });
  }

  let backlogId: number;
  if (call.name === "vincular_existente") {
    backlogId = call.input.backlog_id;
    const { data: it } = await db.from("backlog").select("votos").eq("id", backlogId).single();
    await db.from("backlog").update({ votos: (it?.votos ?? 1) + 1 }).eq("id", backlogId);
  } else {
    const { data: nuevo } = await db.from("backlog").insert({
      titulo: call.input.titulo,
      descripcion: call.input.descripcion,
      seccion: record.seccion,
      subseccion: record.subseccion,
      tipo: record.tipo,
    }).select("id").single();
    backlogId = nuevo!.id;
  }

  await db.from("feedback")
    .update({ estado: "procesado", backlog_id: backlogId })
    .eq("id", record.id);
  return new Response("ok");
});