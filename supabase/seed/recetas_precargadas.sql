-- recetas_precargadas.sql — Recetas comunes precargadas (home_id nulo) por país. GENERADO por
-- scripts/menus/recetas_seed.py a partir de supabase/seed/recetas/lote-*.json: no editar a mano.
-- NO forma parte de la migración 0047: se carga aparte (CI: scripts/supabase/ci.sh; producción:
-- paso manual tras revisar el lote, ver supabase/README.md). Requiere food_es.sql cargado antes para
-- enlazar los ingredientes con el catálogo (los que no existen quedan en texto libre).
-- Idempotente: on conflict (name, country) where home_id is null do nothing; los ingredientes solo se
-- insertan para las recetas nuevas, así que una segunda carga inserta 0 filas.

-- Tortilla de patatas (ES)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Tortilla de patatas', 'ES', 4, 45, array['lunch', 'dinner']::text[],
        array[
            'Pela las patatas y la cebolla y córtalas en láminas finas. Sálalas.',
            'Fríe las patatas y la cebolla en abundante aceite a fuego medio-bajo unos 20 minutos, hasta que estén tiernas sin dorarse.',
            'Escúrrelas bien del aceite y mézclalas con los huevos batidos y una pizca de sal. Déjalas reposar 5 minutos.',
            'Calienta una sartén con un poco de aceite y vierte la mezcla. Cuaja a fuego medio unos 4 minutos.',
            'Da la vuelta a la tortilla con ayuda de un plato y cuaja otros 3 minutos por el otro lado. Sírvela templada.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Patatas'::text, 'Patata'::text, 600::numeric, 'g'::text),
    (1, 'Huevos'::text, 'Huevos'::text, 6::numeric, 'ud'::text),
    (2, 'Cebolla'::text, 'Cebolla'::text, 1::numeric, 'ud'::text),
    (3, 'Aceite de oliva'::text, 'Aceite de oliva'::text, 200::numeric, 'ml'::text),
    (4, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Paella valenciana (ES)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Paella valenciana', 'ES', 4, 70, array['lunch']::text[],
        array[
            'Sofríe en la paella con aceite el pollo y el conejo troceados y salados hasta que se doren bien.',
            'Añade las judías verdes y el tomate rallado y rehoga unos 5 minutos.',
            'Incorpora el pimentón dulce, remueve un momento y cubre con 1,2 litros de agua caliente. Añade el azafrán y cuece 30 minutos a fuego medio.',
            'Echa el arroz en forma de cruz, repártelo y cuece 10 minutos a fuego fuerte y otros 8 a fuego suave, sin remover.',
            'Retira del fuego y deja reposar 5 minutos tapada con un paño antes de servir.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Arroz bomba'::text, 'Arroz bomba'::text, 400::numeric, 'g'::text),
    (1, 'Muslo de pollo troceado'::text, 'Muslo de pollo'::text, 500::numeric, 'g'::text),
    (2, 'Conejo troceado'::text, 'Conejo'::text, 400::numeric, 'g'::text),
    (3, 'Judías verdes'::text, 'Judías verdes'::text, 200::numeric, 'g'::text),
    (4, 'Tomate maduro rallado'::text, 'Tomate'::text, 2::numeric, 'ud'::text),
    (5, 'Pimentón dulce'::text, 'Pimentón dulce'::text, 1::numeric, 'cdta'::text),
    (6, 'Azafrán'::text, 'Azafrán'::text, 1::numeric, 'pizca'::text),
    (7, 'Aceite de oliva'::text, 'Aceite de oliva'::text, 80::numeric, 'ml'::text),
    (8, 'Agua'::text, 'Agua'::text, 1.2::numeric, 'l'::text),
    (9, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Gazpacho andaluz (ES)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Gazpacho andaluz', 'ES', 4, 15, array['lunch', 'dinner']::text[],
        array[
            'Lava las hortalizas. Trocea los tomates, el pepino, el pimiento y el ajo.',
            'Tritura todo con el pan remojado en agua, el aceite, el vinagre y sal hasta obtener una crema fina.',
            'Pasa el gazpacho por un colador chino si quieres una textura más suave.',
            'Rectifica de sal y vinagre y enfría en la nevera al menos 2 horas. Sirve muy frío.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Tomates maduros'::text, 'Tomate'::text, 1::numeric, 'kg'::text),
    (1, 'Pepino'::text, 'Pepino'::text, 1::numeric, 'ud'::text),
    (2, 'Pimiento verde'::text, 'Pimiento verde'::text, 1::numeric, 'ud'::text),
    (3, 'Ajo'::text, 'Ajo'::text, 1::numeric, 'ud'::text),
    (4, 'Pan del día anterior'::text, 'Barra de pan'::text, 60::numeric, 'g'::text),
    (5, 'Aceite de oliva virgen extra'::text, 'Aceite de oliva virgen extra'::text, 80::numeric, 'ml'::text),
    (6, 'Vinagre de Jerez'::text, 'Vinagre de Jerez'::text, 2::numeric, 'cda'::text),
    (7, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Cocido madrileño (ES)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Cocido madrileño', 'ES', 6, 180, array['lunch']::text[],
        array[
            'Pon los garbanzos, remojados la noche anterior, en una olla grande con agua fría, la carne de ternera, el tocino, el hueso y el pollo.',
            'Lleva a ebullición, espuma y cuece a fuego suave 1 hora y media.',
            'Añade el chorizo, la morcilla, las zanahorias y las patatas y cuece 30 minutos más.',
            'Cuece aparte la col en agua con sal y rehógala con ajo en aceite.',
            'Con parte del caldo cuece los fideos como primer plato. Sirve después los garbanzos, las verduras y las carnes.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Garbanzos'::text, 'Garbanzos'::text, 400::numeric, 'g'::text),
    (1, 'Ternera para cocido'::text, 'Ternera'::text, 500::numeric, 'g'::text),
    (2, 'Pollo entero'::text, 'Pollo entero'::text, 1::numeric, 'ud'::text),
    (3, 'Chorizo'::text, 'Chorizo'::text, 200::numeric, 'g'::text),
    (4, 'Morcilla'::text, 'Morcilla'::text, 200::numeric, 'g'::text),
    (5, 'Tocino'::text, null::text, 100::numeric, 'g'::text),
    (6, 'Zanahorias'::text, 'Zanahoria'::text, 3::numeric, 'ud'::text),
    (7, 'Patatas'::text, 'Patata'::text, 4::numeric, 'ud'::text),
    (8, 'Col'::text, 'Col'::text, 1::numeric, 'ud'::text),
    (9, 'Fideos'::text, 'Fideos'::text, 150::numeric, 'g'::text),
    (10, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Fabada asturiana (ES)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Fabada asturiana', 'ES', 6, 150, array['lunch']::text[],
        array[
            'Deja las fabes en remojo en agua fría la noche anterior.',
            'Ponlas en una olla con agua fría, el lacón, el chorizo, la morcilla y la panceta. Añade un chorrito de aceite.',
            'Lleva a ebullición, retira la espuma y asusta las fabes con un poco de agua fría un par de veces.',
            'Cuece a fuego muy suave 2 horas sin remover, moviendo la olla de vez en cuando.',
            'Añade el azafrán y sal al final, comprueba que las fabes estén tiernas y deja reposar 15 minutos antes de servir.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Fabes (alubias blancas)'::text, 'Alubias blancas'::text, 500::numeric, 'g'::text),
    (1, 'Chorizo'::text, 'Chorizo'::text, 200::numeric, 'g'::text),
    (2, 'Morcilla'::text, 'Morcilla'::text, 200::numeric, 'g'::text),
    (3, 'Panceta'::text, 'Panceta'::text, 200::numeric, 'g'::text),
    (4, 'Lacón'::text, null::text, 300::numeric, 'g'::text),
    (5, 'Azafrán'::text, 'Azafrán'::text, 1::numeric, 'pizca'::text),
    (6, 'Aceite de oliva'::text, 'Aceite de oliva'::text, 2::numeric, 'cda'::text),
    (7, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Lentejas estofadas con chorizo (ES)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Lentejas estofadas con chorizo', 'ES', 4, 60, array['lunch', 'dinner']::text[],
        array[
            'Sofríe en una olla con aceite la cebolla, el pimiento, el ajo y la zanahoria picados durante 10 minutos.',
            'Añade el pimentón dulce, remueve y agrega el chorizo en rodajas.',
            'Incorpora las lentejas, las patatas troceadas y el laurel. Cubre con agua o caldo.',
            'Cuece a fuego suave unos 40 minutos, hasta que las lentejas estén tiernas, y rectifica de sal.',
            'Deja reposar 10 minutos antes de servir.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Lentejas'::text, 'Lentejas'::text, 300::numeric, 'g'::text),
    (1, 'Chorizo'::text, 'Chorizo'::text, 150::numeric, 'g'::text),
    (2, 'Cebolla'::text, 'Cebolla'::text, 1::numeric, 'ud'::text),
    (3, 'Pimiento verde'::text, 'Pimiento verde'::text, 1::numeric, 'ud'::text),
    (4, 'Zanahoria'::text, 'Zanahoria'::text, 2::numeric, 'ud'::text),
    (5, 'Patatas'::text, 'Patata'::text, 2::numeric, 'ud'::text),
    (6, 'Ajo'::text, 'Ajo'::text, 2::numeric, 'ud'::text),
    (7, 'Pimentón dulce'::text, 'Pimentón dulce'::text, 1::numeric, 'cdta'::text),
    (8, 'Laurel'::text, 'Laurel'::text, 1::numeric, 'ud'::text),
    (9, 'Aceite de oliva'::text, 'Aceite de oliva'::text, 3::numeric, 'cda'::text),
    (10, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Croquetas de jamón (ES)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Croquetas de jamón', 'ES', 6, 60, array['lunch', 'dinner']::text[],
        array[
            'Derrite la mantequilla con un chorrito de aceite y sofríe la cebolla picada muy fina hasta que esté transparente.',
            'Añade el jamón picado y la harina y tuesta 2 minutos removiendo.',
            'Vierte la leche caliente poco a poco sin dejar de remover hasta obtener una bechamel espesa. Sazona con nuez moscada.',
            'Extiéndela en una fuente y deja enfriar en la nevera al menos 4 horas.',
            'Forma las croquetas, pásalas por huevo batido y pan rallado y fríelas en aceite caliente hasta que estén doradas.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Jamón serrano picado'::text, 'Jamón serrano'::text, 150::numeric, 'g'::text),
    (1, 'Leche entera'::text, 'Leche entera'::text, 800::numeric, 'ml'::text),
    (2, 'Harina de trigo'::text, 'Harina de trigo'::text, 80::numeric, 'g'::text),
    (3, 'Mantequilla'::text, 'Mantequilla'::text, 80::numeric, 'g'::text),
    (4, 'Cebolla'::text, 'Cebolla'::text, 0.5::numeric, 'ud'::text),
    (5, 'Nuez moscada'::text, 'Nuez moscada'::text, 1::numeric, 'pizca'::text),
    (6, 'Huevos'::text, 'Huevos'::text, 2::numeric, 'ud'::text),
    (7, 'Pan rallado'::text, 'Pan rallado'::text, 150::numeric, 'g'::text),
    (8, 'Aceite de girasol para freír'::text, 'Aceite de girasol'::text, 500::numeric, 'ml'::text)
) as v(pos, label, food, qty, unit);

-- Merluza en salsa verde (ES)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Merluza en salsa verde', 'ES', 4, 35, array['lunch', 'dinner']::text[],
        array[
            'Dora los ajos laminados en una cazuela de barro con aceite y retíralos antes de que se quemen.',
            'Añade la harina y rehoga medio minuto. Agrega el caldo de pescado o agua poco a poco y remueve hasta ligar la salsa.',
            'Incorpora el perejil picado y las rodajas de merluza salpimentadas.',
            'Cuece a fuego suave 5 minutos moviendo la cazuela en círculos, da la vuelta a la merluza y añade los guisantes y las almejas.',
            'Cuece 4 minutos más hasta que se abran las almejas y sirve enseguida.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Rodajas de merluza'::text, 'Merluza'::text, 4::numeric, 'ud'::text),
    (1, 'Almejas'::text, 'Almejas'::text, 250::numeric, 'g'::text),
    (2, 'Guisantes'::text, 'Guisantes'::text, 100::numeric, 'g'::text),
    (3, 'Ajo'::text, 'Ajo'::text, 4::numeric, 'ud'::text),
    (4, 'Perejil fresco'::text, 'Perejil'::text, 1::numeric, 'ud'::text),
    (5, 'Harina de trigo'::text, 'Harina de trigo'::text, 1::numeric, 'cda'::text),
    (6, 'Aceite de oliva'::text, 'Aceite de oliva'::text, 5::numeric, 'cda'::text),
    (7, 'Caldo de pescado o agua'::text, null::text, 300::numeric, 'ml'::text),
    (8, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Pisto manchego con huevo (ES)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Pisto manchego con huevo', 'ES', 4, 50, array['lunch', 'dinner']::text[],
        array[
            'Pica la cebolla, los pimientos, el calabacín y la berenjena en dados pequeños.',
            'Sofríe la cebolla con aceite a fuego medio 5 minutos y añade los pimientos. Cocina 10 minutos.',
            'Agrega el calabacín y la berenjena y sigue cocinando 10 minutos más.',
            'Incorpora el tomate triturado y una pizca de azúcar y cuece a fuego suave 20 minutos hasta que espese. Sazona.',
            'Fríe los huevos aparte y sírvelos sobre el pisto caliente.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Cebolla'::text, 'Cebolla'::text, 1::numeric, 'ud'::text),
    (1, 'Pimiento rojo'::text, 'Pimiento rojo'::text, 1::numeric, 'ud'::text),
    (2, 'Pimiento verde'::text, 'Pimiento verde'::text, 1::numeric, 'ud'::text),
    (3, 'Calabacín'::text, 'Calabacín'::text, 1::numeric, 'ud'::text),
    (4, 'Berenjena'::text, 'Berenjena'::text, 1::numeric, 'ud'::text),
    (5, 'Tomate triturado'::text, 'Tomate triturado'::text, 400::numeric, 'g'::text),
    (6, 'Huevos'::text, 'Huevos'::text, 4::numeric, 'ud'::text),
    (7, 'Aceite de oliva'::text, 'Aceite de oliva'::text, 4::numeric, 'cda'::text),
    (8, 'Azúcar'::text, 'Azúcar'::text, 1::numeric, 'pizca'::text),
    (9, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Pollo al ajillo (ES)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Pollo al ajillo', 'ES', 4, 45, array['lunch', 'dinner']::text[],
        array[
            'Sala y pimienta el pollo troceado.',
            'Dóralo en una sartén grande con aceite a fuego medio-alto hasta que tome color por todos los lados.',
            'Añade los dientes de ajo sin pelar, machacados, y la hoja de laurel.',
            'Vierte el vino blanco y deja que reduzca 5 minutos.',
            'Tapa y cocina a fuego suave unos 20 minutos, hasta que el pollo esté hecho. Espolvorea con perejil picado y sirve.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Muslos de pollo troceados'::text, 'Muslo de pollo'::text, 1::numeric, 'kg'::text),
    (1, 'Ajo'::text, 'Ajo'::text, 8::numeric, 'ud'::text),
    (2, 'Vino blanco'::text, 'Vino blanco'::text, 100::numeric, 'ml'::text),
    (3, 'Aceite de oliva'::text, 'Aceite de oliva'::text, 5::numeric, 'cda'::text),
    (4, 'Laurel'::text, 'Laurel'::text, 1::numeric, 'ud'::text),
    (5, 'Perejil fresco'::text, 'Perejil'::text, 1::numeric, 'cda'::text),
    (6, 'Pimienta negra'::text, 'Pimienta negra'::text, 1::numeric, 'pizca'::text),
    (7, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Milanesa napolitana (AR)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Milanesa napolitana', 'AR', 4, 40, array['lunch', 'dinner']::text[],
        array[
            'Sazona los filetes de ternera con sal, pimienta y ajo picado.',
            'Pásalos por huevo batido y luego por pan rallado, presionando para que se adhiera.',
            'Fríe las milanesas en aceite caliente 3 minutos por lado y escúrrelas sobre papel absorbente.',
            'Colócalas en una fuente de horno, cúbrelas con salsa de tomate, jamón cocido y mozzarella.',
            'Gratina en el horno a 220 grados unos 8 minutos, hasta que el queso se derrita y burbujee.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Filetes de ternera'::text, 'Filete de ternera'::text, 4::numeric, 'ud'::text),
    (1, 'Huevos'::text, 'Huevos'::text, 2::numeric, 'ud'::text),
    (2, 'Pan rallado'::text, 'Pan rallado'::text, 200::numeric, 'g'::text),
    (3, 'Ajo'::text, 'Ajo'::text, 2::numeric, 'ud'::text),
    (4, 'Salsa de tomate'::text, 'Salsa de tomate'::text, 300::numeric, 'g'::text),
    (5, 'Jamón cocido'::text, 'Jamón cocido'::text, 4::numeric, 'ud'::text),
    (6, 'Queso mozzarella'::text, 'Queso mozzarella'::text, 200::numeric, 'g'::text),
    (7, 'Aceite de girasol para freír'::text, 'Aceite de girasol'::text, 400::numeric, 'ml'::text),
    (8, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Asado de tira a la parrilla (AR)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Asado de tira a la parrilla', 'AR', 6, 150, array['lunch', 'dinner']::text[],
        array[
            'Saca la carne de la nevera 1 hora antes para que se atempere.',
            'Prepara las brasas hasta que estén cubiertas de ceniza blanca y la parrilla muy caliente.',
            'Coloca el asado de tira con el hueso hacia abajo y cocínalo a fuego medio-bajo unos 90 minutos, sin pincharlo.',
            'Dale la vuelta y cocina 30 a 40 minutos más. Sala con sal gorda al darle la vuelta.',
            'Deja reposar 10 minutos tapado antes de cortar y sirve con chimichurri y ensalada.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Asado de tira de ternera'::text, 'Ternera'::text, 2::numeric, 'kg'::text),
    (1, 'Sal gorda'::text, 'Sal gorda'::text, 2::numeric, 'cda'::text),
    (2, 'Chimichurri (perejil, ajo y orégano)'::text, null::text, null::numeric, 'al gusto'::text),
    (3, 'Carbón o leña'::text, null::text, 3::numeric, 'kg'::text)
) as v(pos, label, food, qty, unit);

-- Empanadas de carne (AR)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Empanadas de carne', 'AR', 6, 75, array['lunch', 'dinner']::text[],
        array[
            'Sofríe la cebolla y la cebolleta picadas en aceite hasta que estén blandas. Añade el pimentón dulce y el comino.',
            'Agrega la carne picada y cocina 10 minutos desmenuzándola. Sazona con sal y deja enfriar.',
            'Mezcla el relleno con los huevos duros picados y las aceitunas en rodajas.',
            'Corta círculos de masa, pon una cucharada de relleno en cada uno y cierra con el repulgue.',
            'Pinta con huevo batido y hornea a 200 grados unos 20 minutos, hasta que estén doradas.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Tapas de empanada (discos de masa)'::text, null::text, 12::numeric, 'ud'::text),
    (1, 'Ternera picada'::text, 'Ternera picada'::text, 500::numeric, 'g'::text),
    (2, 'Cebolla'::text, 'Cebolla'::text, 2::numeric, 'ud'::text),
    (3, 'Cebolleta'::text, 'Cebolleta'::text, 2::numeric, 'ud'::text),
    (4, 'Huevo duro'::text, 'Huevo duro'::text, 3::numeric, 'ud'::text),
    (5, 'Aceitunas'::text, 'Aceitunas'::text, 12::numeric, 'ud'::text),
    (6, 'Pimentón dulce'::text, 'Pimentón dulce'::text, 1::numeric, 'cda'::text),
    (7, 'Comino'::text, 'Comino'::text, 1::numeric, 'cdta'::text),
    (8, 'Aceite de oliva'::text, 'Aceite de oliva'::text, 3::numeric, 'cda'::text),
    (9, 'Huevo para pintar'::text, 'Huevos'::text, 1::numeric, 'ud'::text),
    (10, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Locro criollo (AR)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Locro criollo', 'AR', 8, 180, array['lunch']::text[],
        array[
            'Remoja el maíz blanco y las alubias la noche anterior.',
            'Cuece el maíz y las alubias en una olla grande con agua durante 1 hora.',
            'Añade la panceta, el chorizo, la ternera troceada y la calabaza en dados.',
            'Cuece a fuego suave 1 hora y media más, removiendo de vez en cuando, hasta que espese y todo esté tierno.',
            'Prepara aparte una salsa con aceite, pimentón picante y cebolleta y sírvela sobre cada plato.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Maíz blanco seco'::text, null::text, 400::numeric, 'g'::text),
    (1, 'Alubias blancas'::text, 'Alubias blancas'::text, 200::numeric, 'g'::text),
    (2, 'Ternera para guiso'::text, 'Ternera'::text, 500::numeric, 'g'::text),
    (3, 'Panceta'::text, 'Panceta'::text, 200::numeric, 'g'::text),
    (4, 'Chorizo'::text, 'Chorizo'::text, 200::numeric, 'g'::text),
    (5, 'Calabaza'::text, 'Calabaza'::text, 500::numeric, 'g'::text),
    (6, 'Cebolla'::text, 'Cebolla'::text, 2::numeric, 'ud'::text),
    (7, 'Cebolleta'::text, 'Cebolleta'::text, 2::numeric, 'ud'::text),
    (8, 'Pimentón picante'::text, 'Pimentón picante'::text, 1::numeric, 'cda'::text),
    (9, 'Aceite de oliva'::text, 'Aceite de oliva'::text, 3::numeric, 'cda'::text),
    (10, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Tarta de manzana (AR)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Tarta de manzana', 'AR', 8, 80, array['lunch']::text[],
        array[
            'Mezcla la harina, la mantequilla fría en dados, el azúcar y una pizca de sal hasta obtener un arenado. Añade el huevo y 2 cucharadas de agua fría.',
            'Forma una bola, envuélvela y déjala reposar 30 minutos en la nevera.',
            'Pela las manzanas, córtalas en láminas y mézclalas con el zumo de limón, la canela y 2 cucharadas de azúcar.',
            'Estira dos tercios de la masa, forra un molde y rellénalo con las manzanas. Cubre con el resto de la masa y haz unos cortes.',
            'Pinta con huevo y hornea a 190 grados unos 40 minutos, hasta que esté dorada.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Harina de trigo'::text, 'Harina de trigo'::text, 300::numeric, 'g'::text),
    (1, 'Mantequilla fría'::text, 'Mantequilla'::text, 150::numeric, 'g'::text),
    (2, 'Azúcar'::text, 'Azúcar'::text, 100::numeric, 'g'::text),
    (3, 'Huevos'::text, 'Huevos'::text, 2::numeric, 'ud'::text),
    (4, 'Manzanas'::text, 'Manzana'::text, 5::numeric, 'ud'::text),
    (5, 'Limón (zumo)'::text, 'Limón'::text, 1::numeric, 'ud'::text),
    (6, 'Canela'::text, 'Canela'::text, 1::numeric, 'cdta'::text),
    (7, 'Sal'::text, 'Sal'::text, 1::numeric, 'pizca'::text)
) as v(pos, label, food, qty, unit);

-- Guiso de lentejas criollo (AR)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Guiso de lentejas criollo', 'AR', 6, 75, array['lunch', 'dinner']::text[],
        array[
            'Sofríe la cebolla, el pimiento rojo y el ajo picados con aceite en una olla grande.',
            'Añade la panceta y el chorizo en trozos y dóralos 5 minutos.',
            'Incorpora la zanahoria, la patata y el boniato en dados, el tomate triturado y el pimentón dulce.',
            'Agrega las lentejas y cubre con caldo. Cuece a fuego suave unos 45 minutos hasta que todo esté tierno.',
            'Rectifica de sal y sirve bien caliente.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Lentejas'::text, 'Lentejas'::text, 400::numeric, 'g'::text),
    (1, 'Chorizo'::text, 'Chorizo'::text, 200::numeric, 'g'::text),
    (2, 'Panceta'::text, 'Panceta'::text, 150::numeric, 'g'::text),
    (3, 'Cebolla'::text, 'Cebolla'::text, 1::numeric, 'ud'::text),
    (4, 'Pimiento rojo'::text, 'Pimiento rojo'::text, 1::numeric, 'ud'::text),
    (5, 'Zanahoria'::text, 'Zanahoria'::text, 2::numeric, 'ud'::text),
    (6, 'Patata'::text, 'Patata'::text, 2::numeric, 'ud'::text),
    (7, 'Boniato'::text, 'Boniato'::text, 1::numeric, 'ud'::text),
    (8, 'Tomate triturado'::text, 'Tomate triturado'::text, 300::numeric, 'g'::text),
    (9, 'Caldo de carne'::text, 'Caldo de carne'::text, 1.2::numeric, 'l'::text),
    (10, 'Pimentón dulce'::text, 'Pimentón dulce'::text, 1::numeric, 'cda'::text),
    (11, 'Aceite de oliva'::text, 'Aceite de oliva'::text, 3::numeric, 'cda'::text),
    (12, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Ñoquis con salsa de tomate (AR)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Ñoquis con salsa de tomate', 'AR', 4, 60, array['lunch', 'dinner']::text[],
        array[
            'Cuece las patatas con piel en agua con sal hasta que estén tiernas. Pélalas y tritúralas en caliente.',
            'Mezcla el puré con la harina, el huevo y sal hasta formar una masa suave sin amasar de más.',
            'Forma churros finos y córtalos en trocitos. Marca cada ñoqui con un tenedor si quieres.',
            'Prepara la salsa sofriendo ajo en aceite, añade el tomate triturado, sal y albahaca y cuece 15 minutos.',
            'Cuece los ñoquis en agua hirviendo; cuando suban a la superficie, escúrrelos y mézclalos con la salsa. Sirve con queso rallado.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Patatas'::text, 'Patata'::text, 1::numeric, 'kg'::text),
    (1, 'Harina de trigo'::text, 'Harina de trigo'::text, 250::numeric, 'g'::text),
    (2, 'Huevos'::text, 'Huevos'::text, 1::numeric, 'ud'::text),
    (3, 'Tomate triturado'::text, 'Tomate triturado'::text, 500::numeric, 'g'::text),
    (4, 'Ajo'::text, 'Ajo'::text, 2::numeric, 'ud'::text),
    (5, 'Albahaca'::text, 'Albahaca'::text, 1::numeric, 'cda'::text),
    (6, 'Aceite de oliva'::text, 'Aceite de oliva'::text, 3::numeric, 'cda'::text),
    (7, 'Queso rallado'::text, 'Queso rallado'::text, 60::numeric, 'g'::text),
    (8, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Pastel de papa (AR)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Pastel de papa', 'AR', 6, 80, array['lunch', 'dinner']::text[],
        array[
            'Cuece las patatas peladas en agua con sal, escúrrelas y haz un puré con la mantequilla y la leche.',
            'Sofríe la cebolla picada en aceite, añade la carne picada, el comino y el pimentón dulce y cocina 10 minutos. Sazona.',
            'Mezcla la carne con las pasas y los huevos duros picados.',
            'En una fuente de horno pon una capa de puré, el relleno y cubre con el resto del puré.',
            'Hornea a 200 grados unos 25 minutos hasta que la superficie esté dorada.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Patatas'::text, 'Patata'::text, 1.2::numeric, 'kg'::text),
    (1, 'Ternera picada'::text, 'Ternera picada'::text, 600::numeric, 'g'::text),
    (2, 'Cebolla'::text, 'Cebolla'::text, 2::numeric, 'ud'::text),
    (3, 'Huevo duro'::text, 'Huevo duro'::text, 3::numeric, 'ud'::text),
    (4, 'Pasas'::text, 'Pasas'::text, 40::numeric, 'g'::text),
    (5, 'Mantequilla'::text, 'Mantequilla'::text, 50::numeric, 'g'::text),
    (6, 'Leche entera'::text, 'Leche entera'::text, 150::numeric, 'ml'::text),
    (7, 'Comino'::text, 'Comino'::text, 1::numeric, 'cdta'::text),
    (8, 'Pimentón dulce'::text, 'Pimentón dulce'::text, 1::numeric, 'cda'::text),
    (9, 'Aceite de oliva'::text, 'Aceite de oliva'::text, 2::numeric, 'cda'::text),
    (10, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Matambre a la pizza (AR)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Matambre a la pizza', 'AR', 4, 90, array['lunch', 'dinner']::text[],
        array[
            'Sazona el matambre con sal, ajo picado y orégano.',
            'Hiérvelo o cuécelo al horno envuelto en papel de aluminio a 180 grados durante 1 hora hasta que esté tierno.',
            'Colócalo en una fuente de horno y cúbrelo con salsa de tomate.',
            'Añade encima las lonchas de mozzarella y unas aceitunas.',
            'Gratina 10 minutos a 220 grados hasta que el queso se funda y sirve cortado en porciones.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Matambre de ternera'::text, 'Ternera'::text, 1::numeric, 'kg'::text),
    (1, 'Salsa de tomate'::text, 'Salsa de tomate'::text, 300::numeric, 'g'::text),
    (2, 'Queso mozzarella'::text, 'Queso mozzarella'::text, 250::numeric, 'g'::text),
    (3, 'Ajo'::text, 'Ajo'::text, 2::numeric, 'ud'::text),
    (4, 'Orégano'::text, 'Orégano'::text, 1::numeric, 'cda'::text),
    (5, 'Aceitunas'::text, 'Aceitunas'::text, 10::numeric, 'ud'::text),
    (6, 'Sal'::text, 'Sal'::text, null::numeric, 'al gusto'::text)
) as v(pos, label, food, qty, unit);

-- Flan casero con dulce de leche (AR)
with nueva as (
    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (
        null, 'Flan casero con dulce de leche', 'AR', 6, 90, array['lunch', 'dinner']::text[],
        array[
            'Haz un caramelo con 100 g de azúcar y un chorrito de agua y viértelo en el fondo del molde.',
            'Bate los huevos con el resto del azúcar y la vainilla sin hacer espuma.',
            'Añade la leche templada y mezcla. Cuela sobre el molde caramelizado.',
            'Cuece al baño maría en el horno a 160 grados durante 50 minutos, hasta que cuaje.',
            'Deja enfriar y refrigera al menos 4 horas. Desmolda y sirve con dulce de leche y nata montada.'
        ]::text[])
    on conflict (name, country) where home_id is null do nothing
    returning id)
insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)
select nueva.id, null, v.pos,
       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),
       v.label, v.qty, v.unit
from nueva cross join (values
    (0, 'Huevos'::text, 'Huevos'::text, 5::numeric, 'ud'::text),
    (1, 'Leche entera'::text, 'Leche entera'::text, 500::numeric, 'ml'::text),
    (2, 'Azúcar'::text, 'Azúcar'::text, 180::numeric, 'g'::text),
    (3, 'Esencia de vainilla'::text, null::text, 1::numeric, 'cdta'::text),
    (4, 'Dulce de leche'::text, null::text, 150::numeric, 'g'::text),
    (5, 'Nata montada'::text, 'Nata montada'::text, 100::numeric, 'g'::text)
) as v(pos, label, food, qty, unit);
