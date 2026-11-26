// Intención de menú: cuándo la petición activa la skill `menus` (y con ella KITO_MODEL_MENUS). Se evalúa sobre los
// últimos mensajes ya sin acentos ni mayúsculas (ver `hayIntencion` en core.ts), así que aquí no hay tildes.
//
// Palabras clave: menú, comidas, cenas, almuerzos y «recetas de la semana». «Semana» suelta NO activa la skill:
// «mis eventos de esta semana» no es una petición de menú y saldría más caro con el modelo de menús. «Menú semanal»
// y «planifica la semana de comidas» sí entran por «menú» y «comidas».
//
// Rangos de fechas («planifica desde esta noche hasta el viernes a mediodía»): una frase de rango solo activa la skill
// si habla de comer (noche, mediodía, comer/cenar/almorzar). «Desde», «hasta» o «esta noche» sueltos NO activan:
// «recuérdame esta noche que llame» o «eventos hasta el viernes» no son peticiones de menú.
export const INTENCION_MENUS = new RegExp(
    [
        String.raw`\b(menus?|comidas?|cenas?|almuerzos?|recetas? de la semana)\b`,
        String.raw`\bdesde\b[^.?!]{0,80}\bhasta\b[^.?!]{0,60}\b(noche|mediodia|comer|cenar|almorzar)\b`,
        String.raw`\b(esta noche|a mediodia)\b[^.?!]{0,60}\bhasta\b[^.?!]{0,40}\b(noche|mediodia|comer|cenar|almorzar)\b`,
    ].join("|"),
);
