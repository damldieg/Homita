| Modelo | Hogares | Fallos | Casillas | Conflictos (hogares) | Repeticiones (semana / historial) | Menús mostrados | Tokens entrada | Tokens salida | Caché leída / escrita | Coste estimado |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku-5-5 | 10 | 0 | 143 | 6 (2) | 15 / 0 | 10/10 | 96107 | 26357 | 179157 / 5429 | 0.2526 USD |
| claude-sonnet-5-5 | 10 | 0 | 141 | 5 (2) | 15 / 0 | 10/10 | 76492 | 13722 | 173728 / 5429 | 0.5078 USD |

Detalle por hogar:

| Hogar | Modelo | OK | Casillas | Conflictos | Rep. semana | Rep. historial | Menú mostrado | Llamadas | Entrada | Salida |
|---|---|---|---|---|---|---|---|---|---|---|
| 01-gluten-ninos | claude-haiku-5-5 | sí | 14 | 0 | 1 | 0 | sí | 4 | 13212 | 2784 |
| 02-vegetariana-lactosa | claude-haiku-5-5 | sí | 14 | 4 | 1 | 0 | sí | 5 | 16044 | 3823 |
| 03-solo-sin-repetir | claude-haiku-5-5 | sí | 14 | 0 | 1 | 0 | sí | 3 | 6805 | 1754 |
| 04-cacahuete-huevo | claude-haiku-5-5 | sí | 14 | 0 | 0 | 0 | sí | 3 | 7365 | 2142 |
| 05-cinco-personas | claude-haiku-5-5 | sí | 14 | 2 | 6 | 0 | sí | 3 | 10068 | 4410 |
| 06-pareja-merienda-postre | claude-haiku-5-5 | sí | 17 | 0 | 5 | 0 | sí | 3 | 7180 | 1784 |
| 07-marisco-japon | claude-haiku-5-5 | sí | 14 | 0 | 1 | 0 | sí | 4 | 12909 | 2986 |
| 08-frutos-secos-sesamo | claude-haiku-5-5 | sí | 14 | 0 | 0 | 0 | sí | 3 | 7444 | 2113 |
| 09-halal-tres-adultos | claude-haiku-5-5 | sí | 14 | 0 | 0 | 0 | sí | 3 | 8114 | 2722 |
| 10-sin-alergias-repetir | claude-haiku-5-5 | sí | 14 | 0 | 0 | 0 | sí | 3 | 6966 | 1839 |
| 01-gluten-ninos | claude-sonnet-5-5 | sí | 14 | 0 | 1 | 0 | sí | 4 | 11564 | 1981 |
| 02-vegetariana-lactosa | claude-sonnet-5-5 | sí | 14 | 2 | 2 | 0 | sí | 4 | 9866 | 1613 |
| 03-solo-sin-repetir | claude-sonnet-5-5 | sí | 14 | 0 | 0 | 0 | sí | 3 | 6506 | 1576 |
| 04-cacahuete-huevo | claude-sonnet-5-5 | sí | 14 | 0 | 0 | 0 | sí | 4 | 10630 | 1734 |
| 05-cinco-personas | claude-sonnet-5-5 | sí | 14 | 3 | 5 | 0 | sí | 3 | 6907 | 1363 |
| 06-pareja-merienda-postre | claude-sonnet-5-5 | sí | 15 | 0 | 3 | 0 | sí | 3 | 6085 | 785 |
| 07-marisco-japon | claude-sonnet-5-5 | sí | 14 | 0 | 4 | 0 | sí | 3 | 6378 | 1548 |
| 08-frutos-secos-sesamo | claude-sonnet-5-5 | sí | 14 | 0 | 0 | 0 | sí | 3 | 6210 | 1022 |
| 09-halal-tres-adultos | claude-sonnet-5-5 | sí | 14 | 0 | 0 | 0 | sí | 3 | 6430 | 1101 |
| 10-sin-alergias-repetir | claude-sonnet-5-5 | sí | 14 | 0 | 0 | 0 | sí | 3 | 5916 | 999 |

Conflictos detectados:

- 02-vegetariana-lactosa (claude-haiku-5-5): 2030-01-11 lunch Chili sin carne persona 1: diet vegetarian
- 02-vegetariana-lactosa (claude-haiku-5-5): 2030-01-11 lunch Chili sin carne persona 2: diet vegetarian
- 02-vegetariana-lactosa (claude-haiku-5-5): 2030-01-11 dinner Pad thai con cacahuetes persona 1: diet vegetarian
- 02-vegetariana-lactosa (claude-haiku-5-5): 2030-01-11 dinner Pad thai con cacahuetes persona 2: diet vegetarian
- 05-cinco-personas (claude-haiku-5-5): 2030-01-10 lunch Chili sin carne persona 1: diet vegan
- 05-cinco-personas (claude-haiku-5-5): 2030-01-13 dinner Chili sin carne persona 1: diet vegan
- 02-vegetariana-lactosa (claude-sonnet-5-5): 2030-01-10 lunch Chili sin carne persona 1: diet vegetarian
- 02-vegetariana-lactosa (claude-sonnet-5-5): 2030-01-10 lunch Chili sin carne persona 2: diet vegetarian
- 05-cinco-personas (claude-sonnet-5-5): 2030-01-11 lunch Chili sin carne persona 1: diet vegan
- 05-cinco-personas (claude-sonnet-5-5): 2030-01-13 lunch Pad thai con cacahuetes persona 1: diet vegan
- 05-cinco-personas (claude-sonnet-5-5): 2030-01-13 dinner Chili sin carne persona 1: diet vegan

## Nota sobre el criterio de dieta

Los conflictos de dieta de este informe vienen de una heurística del script (título y alérgenos de la receta), no de `check_meal_plan`, que en producción mira la sección de cada ingrediente. El mundo de pruebas del script no evalúa dieta, así que ambos criterios no son idénticos. Las menciones de «Chili sin carne» de la tabla anterior eran falsos positivos por no tratar las negaciones (corregido en el script); los de «Pad thai» son reales (lleva marisco y huevo). El informe debe repetirse para reflejar el criterio corregido.
