# MCP de Claude para Homita

Plan (2026-11-27) para que Claude (claude.ai web, escritorio y móvil) use Homita con el usuario de cada persona:
menú semanal (borrador → ajustes → aceptar), recetas de fuera del recetario, compra, listas, tareas, eventos,
rutinas y calendarios. Servidor MCP remoto (Edge Function `mcp`) con OAuth 2.1 de Supabase Auth, sobre los casos
de uso existentes de `api`. Nada implementado todavía.

- Informe de diseño: https://claude.ai/artifact/KEJ9wNPZRzCNYX1StzzVCf
- [brief.md](brief.md): arquitectura, decisiones de Damian y herramientas.
- [prompts/](prompts/): un prompt dorch por change, en orden.

## Cómo lanzarlo (claude CLI + dorch-claude)

1. En el Mac, `cd` al repo y `git fetch`.
2. Para cada fase, en orden, abre dorch-claude y pásale el prompt de la fase y `brief.md`.
3. Cuando dorch termine, revisa su informe. Para push y PR añade `authorized: push pr gh` al `status.md` del change.
4. No empieces una fase hasta que la anterior esté en master. La 3 puede ir en paralelo a la 2.

| Orden | Change | Prompt |
| --- | --- | --- |
| 1 | `mcp-base-lectura` | [01-mcp-base-lectura.md](prompts/01-mcp-base-lectura.md) |
| 2 | `mcp-menus-escritura` | [02-mcp-menus-escritura.md](prompts/02-mcp-menus-escritura.md) |
| 3 | `mcp-organizar` | [03-mcp-organizar.md](prompts/03-mcp-organizar.md) |
| 4 | `mcp-produccion` | [04-mcp-produccion.md](prompts/04-mcp-produccion.md) |

Ninguna fase toca producción: la config de Auth, el deploy y GitHub Pages los aplica Damian con el runbook de la fase 4.
