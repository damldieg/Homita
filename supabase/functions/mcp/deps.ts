// Dependencias npm del MCP, con la versión exacta fijada (nada de `^`). Es el único sitio donde se fijan.
//  - SDK oficial de MCP v2 (`createMcpHandler`: un McpServer por petición, sin estado). No se mezcla con la v1.
//  - zod para los esquemas de entrada (Standard Schema).
// Probado en el Edge local (supabase-edge-runtime 1.78.1) en el spike de la fase 1.
export { createMcpHandler, McpServer } from "npm:@modelcontextprotocol/server@2.4.0";
export { z } from "npm:zod@4.6.7";
