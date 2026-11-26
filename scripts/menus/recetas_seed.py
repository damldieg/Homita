#!/usr/bin/env python3
"""Valida los lotes de recetas precargadas y genera el seed SQL (0047, menus-recetas-precargadas).

Los lotes (`supabase/seed/recetas/lote-NN.json`) los escribe y revisa una persona (o Claude en el repo);
este script no llama a ninguna API. Solo Python 3 stdlib.

    scripts/menus/recetas_seed.py            valida y escribe supabase/seed/recetas_precargadas.sql
    scripts/menus/recetas_seed.py --check    valida y comprueba que el SQL escrito está al día (no escribe)

Si alguna receta no es válida, falla con el motivo y NO escribe el SQL. El SQL resultante es idempotente:
`on conflict (name, country) where home_id is null do nothing` sobre recipe_common_name_country_uq, y los
ingredientes solo se insertan para las recetas nuevas.
"""
import argparse
import glob
import json
import os
import re
import sys
import unicodedata

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
LOTES = os.path.join(ROOT, "supabase", "seed", "recetas", "lote-*.json")
FOOD_SQL = os.path.join(ROOT, "supabase", "seed", "food_es.sql")
OUT_SQL = os.path.join(ROOT, "supabase", "seed", "recetas_precargadas.sql")

COUNTRIES = {"ES", "AR"}
SLOTS = {"lunch", "dinner"}
UNITS = {"g", "kg", "ml", "l", "ud", "cda", "cdta", "pizca", "al gusto"}
MAX_NAME, MAX_LABEL, MAX_STEPS, MAX_STEP_CHARS = 120, 120, 50, 500
RECIPE_KEYS = {"name", "country", "servings", "minutes", "slots", "steps", "ingredients"}
ING_KEYS = {"label", "quantity", "unit", "food_name"}


def norm(text):
    """Equivale a fn_meal_norm: minúsculas, sin acentos (también la ñ) y sin espacios en los extremos."""
    decomposed = unicodedata.normalize("NFD", text)
    return "".join(c for c in decomposed if unicodedata.category(c) != "Mn").lower().strip()


def is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def catalog_names():
    with open(FOOD_SQL, encoding="utf-8") as f:
        return {norm(m.group(1).replace("''", "'")) for m in re.finditer(r"^\s*\(null, '((?:[^']|'')*)'", f.read(), re.M)}


def check_recipe(r, foods):
    """Devuelve la lista de problemas de una receta (vacía si es válida)."""
    if not isinstance(r, dict):
        return ["no es un objeto"]
    errs = []
    extra = set(r) - RECIPE_KEYS
    missing = RECIPE_KEYS - set(r)
    if extra:
        errs.append("campos desconocidos: %s" % ", ".join(sorted(extra)))
    if missing:
        errs.append("faltan campos: %s" % ", ".join(sorted(missing)))
        return errs
    if not isinstance(r["name"], str) or not r["name"].strip() or len(r["name"]) > MAX_NAME:
        errs.append("name debe ser texto no vacío de hasta %d caracteres" % MAX_NAME)
    if r["country"] not in COUNTRIES:
        errs.append("country debe ser uno de %s" % ", ".join(sorted(COUNTRIES)))
    if not is_int(r["servings"]) or not 1 <= r["servings"] <= 100:
        errs.append("servings debe ser un entero de 1 a 100")
    if not is_int(r["minutes"]) or not 0 <= r["minutes"] <= 1440:
        errs.append("minutes debe ser un entero de 0 a 1440")
    slots = r["slots"]
    if not isinstance(slots, list) or not slots or any(s not in SLOTS for s in slots) or len(set(slots)) != len(slots):
        errs.append("slots debe ser una lista sin repetidos con valores de %s" % ", ".join(sorted(SLOTS)))
    steps = r["steps"]
    if not isinstance(steps, list) or not steps or len(steps) > MAX_STEPS:
        errs.append("steps debe ser una lista de 1 a %d textos" % MAX_STEPS)
    else:
        for i, s in enumerate(steps, 1):
            if not isinstance(s, str) or not s.strip() or len(s) > MAX_STEP_CHARS:
                errs.append("steps[%d] debe ser texto no vacío de hasta %d caracteres" % (i, MAX_STEP_CHARS))
    ings = r["ingredients"]
    if not isinstance(ings, list) or not ings:
        errs.append("ingredients debe ser una lista no vacía")
        return errs
    for i, g in enumerate(ings, 1):
        pre = "ingredients[%d]" % i
        if not isinstance(g, dict):
            errs.append("%s no es un objeto" % pre)
            continue
        if set(g) - ING_KEYS:
            errs.append("%s: campos desconocidos: %s" % (pre, ", ".join(sorted(set(g) - ING_KEYS))))
        if not {"label", "quantity", "unit"} <= set(g):
            errs.append("%s: faltan label, quantity o unit" % pre)
            continue
        if not isinstance(g["label"], str) or not g["label"].strip() or len(g["label"]) > MAX_LABEL:
            errs.append("%s: label debe ser texto no vacío de hasta %d caracteres" % (pre, MAX_LABEL))
        q = g["quantity"]
        if q is not None and (not is_num(q) or q < 0 or q > 99999999.99):
            errs.append("%s: quantity debe ser un número >= 0 o null" % pre)
        if g["unit"] not in UNITS:
            errs.append("%s: unit debe ser una de %s" % (pre, ", ".join(sorted(UNITS))))
        fn = g.get("food_name")
        if fn is not None and (not isinstance(fn, str) or norm(fn) not in foods):
            errs.append("%s: food_name %r no existe en el catálogo común (food_es.sql)" % (pre, fn))
    return errs


def load_recipes():
    files = sorted(glob.glob(LOTES))
    if not files:
        sys.exit("recetas_seed: no hay lotes en %s" % LOTES)
    foods = catalog_names()
    recipes, problems, seen = [], [], {}
    for path in files:
        rel = os.path.relpath(path, ROOT)
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError) as e:
            problems.append("%s: JSON ilegible: %s" % (rel, e))
            continue
        items = data.get("recetas") if isinstance(data, dict) else None
        if not isinstance(items, list) or not items:
            problems.append("%s: debe ser {\"recetas\": [...]} con al menos una receta" % rel)
            continue
        for n, r in enumerate(items, 1):
            label = "%s receta %d (%s)" % (rel, n, r.get("name") if isinstance(r, dict) else "?")
            errs = check_recipe(r, foods)
            if not errs:
                key = (norm(r["name"]), r["country"])
                if key in seen:
                    errs.append("nombre repetido para el país %s (ya está en %s)" % (r["country"], seen[key]))
                else:
                    seen[key] = label
            problems.extend("%s: %s" % (label, e) for e in errs)
            if not errs:
                recipes.append(r)
    if problems:
        sys.stderr.write("recetas_seed: %d problema(s), no se escribe el SQL:\n" % len(problems))
        for p in problems:
            sys.stderr.write("  - %s\n" % p)
        sys.exit(1)
    return recipes


def q(text):
    return "'" + text.replace("'", "''") + "'"


def num(v):
    if v is None:
        return "null::numeric"
    return "%s::numeric" % (repr(round(float(v), 2)).rstrip("0").rstrip(".") if not float(v).is_integer() else str(int(v)))


def build_sql(recipes):
    out = [
        "-- recetas_precargadas.sql — Recetas comunes precargadas (home_id nulo) por país. GENERADO por",
        "-- scripts/menus/recetas_seed.py a partir de supabase/seed/recetas/lote-*.json: no editar a mano.",
        "-- NO forma parte de la migración 0047: se carga aparte (CI: scripts/supabase/ci.sh; producción:",
        "-- paso manual tras revisar el lote, ver supabase/README.md). Requiere food_es.sql cargado antes para",
        "-- enlazar los ingredientes con el catálogo (los que no existen quedan en texto libre).",
        "-- Idempotente: on conflict (name, country) where home_id is null do nothing; los ingredientes solo se",
        "-- insertan para las recetas nuevas, así que una segunda carga inserta 0 filas.",
        "",
    ]
    for r in recipes:
        out.append("-- %s (%s)" % (r["name"], r["country"]))
        out.append("with nueva as (")
        out.append("    insert into recipe (home_id, name, country, servings, minutes, slots, steps) values (")
        out.append("        null, %s, %s, %d, %d, array[%s]::text[],"
                   % (q(r["name"]), q(r["country"]), r["servings"], r["minutes"], ", ".join(q(s) for s in r["slots"])))
        out.append("        array[")
        out.append(",\n".join("            " + q(s) for s in r["steps"]))
        out.append("        ]::text[])")
        out.append("    on conflict (name, country) where home_id is null do nothing")
        out.append("    returning id)")
        out.append("insert into recipe_ingredient (recipe_id, home_id, position, food_id, label, quantity, unit)")
        out.append("select nueva.id, null, v.pos,")
        out.append("       (select f.id from food f where f.home_id is null and f.name_norm = fn_meal_norm(v.food)),")
        out.append("       v.label, v.qty, v.unit")
        out.append("from nueva cross join (values")
        rows = []
        for pos, g in enumerate(r["ingredients"]):
            food = "null::text" if g.get("food_name") is None else q(g["food_name"]) + "::text"
            rows.append("    (%d, %s::text, %s, %s, %s::text)" % (pos, q(g["label"]), food, num(g["quantity"]), q(g["unit"])))
        out.append(",\n".join(rows))
        out.append(") as v(pos, label, food, qty, unit);")
        out.append("")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true", help="solo valida y comprueba que el SQL está al día")
    args = ap.parse_args()
    recipes = load_recipes()
    sql = build_sql(recipes)
    by = {}
    for r in recipes:
        by[r["country"]] = by.get(r["country"], 0) + 1
    resumen = ", ".join("%s %d" % (k, v) for k, v in sorted(by.items()))
    if args.check:
        try:
            with open(OUT_SQL, encoding="utf-8") as f:
                actual = f.read()
        except OSError:
            actual = None
        if actual != sql:
            sys.exit("recetas_seed: %s no existe o no está al día; ejecuta scripts/menus/recetas_seed.py"
                     % os.path.relpath(OUT_SQL, ROOT))
        print("recetas_seed: %d recetas válidas (%s) y SQL al día" % (len(recipes), resumen))
        return
    with open(OUT_SQL, "w", encoding="utf-8") as f:
        f.write(sql)
    print("recetas_seed: %d recetas válidas (%s); escrito %s" % (len(recipes), resumen, os.path.relpath(OUT_SQL, ROOT)))


if __name__ == "__main__":
    main()
