// Intención de menú: cuándo la petición activa la skill `menus` (y con ella KITO_MODEL_MENUS). Se evalúa sobre los
// últimos mensajes ya sin acentos ni mayúsculas (ver `hayIntencion` en core.ts), así que aquí no hay tildes.
//
// Palabras clave: menú, comidas, cenas, almuerzos y «recetas de la semana». «Semana» suelta NO activa la skill:
// «mis eventos de esta semana» no es una petición de menú y saldría más caro con el modelo de menús. «Menú semanal»
// y «planifica la semana de comidas» sí entran por «menú» y «comidas».
export const INTENCION_MENUS = /\b(menus?|comidas?|cenas?|almuerzos?|recetas? de la semana)\b/;
