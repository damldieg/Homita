"""
Datos ficticios para el backend de demo (scripts/demo.sh): una familia con 4 personas, 2 calendarios, eventos alrededor
de hoy, rutinas de lunes a viernes y 2 listas de tareas. Las fechas son relativas al día en que se ejecuta.

Uso: python3 scripts/demo/seed.py [url-del-backend]   (por defecto http://127.0.0.1:54321/functions/v1/api, la Edge local)
"""
import json, sys, urllib.request, datetime
T = datetime.date.today()
def d(n, hm): return f"{T + datetime.timedelta(days=n)} {hm}:00"
B = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "http://127.0.0.1:54321/functions/v1/api"
tok = None
def call(method, path, data=None):
    req = urllib.request.Request(B + path, data=json.dumps(data or {}).encode(), method=method,
                                 headers={"Content-Type": "application/json", **({"Authorization": "Bearer " + tok} if tok else {})})
    with urllib.request.urlopen(req) as r: return json.load(r)
u = call("POST", "/user/create", {"name": "Familia Demo", "email": "demo@homita.example", "password": "demo1234"})
tok = u["token"]
P = {n: call("POST", "/person/create", {"name": n, "color": c})["id"] for n, c in
     [("Ana", "#2563EB"), ("Marcos", "#16A34A"), ("Lucía", "#9333EA"), ("Pablo", "#EA580C")]}
fam = call("POST", "/calendar/create", {"name": "Familia", "color": "#6923E2"})["id"]
col = call("POST", "/calendar/create", {"name": "Colegio", "color": "#0EA5E9"})["id"]
for cal, title, at, who in [
    (fam, "Revisión médica", d(-12, "10:00"), ["Marcos"]),
    (col, "Tutoría", d(-8, "17:00"), ["Ana"]),
    (fam, "Cumpleaños del abuelo", d(-5, "13:30"), []),
    (fam, "Mercadillo", d(-2, "11:00"), ["Lucía", "Pablo"]),
    (fam, "Desayuno con la vecina", d(0, "09:00"), ["Ana"]),
    (fam, "Cena con los abuelos", d(0, "20:30"), ["Ana", "Marcos"]),
    (fam, "Dentista", d(1, "17:00"), ["Lucía"]),
    (fam, "Partido de fútbol", d(2, "10:30"), ["Pablo"]),
    (fam, "Comida familiar", d(3, "14:00"), []),
    (fam, "Revisión del coche", d(5, "09:00"), ["Marcos"]),
    (col, "Reunión de padres", d(6, "18:00"), ["Ana"]),
    (fam, "Cumpleaños de Lucía", d(7, "17:30"), ["Lucía"]),
    (col, "Excursión al museo", d(8, "09:30"), ["Pablo"]),
    (fam, "Cine en familia", d(9, "19:00"), []),
]:
    call("POST", "/event/create", {"calendar_id": cal, "title": title, "date_at": at, "person_ids": [P[w] for w in who]})
for title, days, time, who in [
    ("Recoger a los niños", [1, 2, 3, 4, 5], "16:00", ["Ana"]),
    ("Piano", [4], "16:45", ["Lucía"]),
    ("Natación", [2, 4], "18:00", ["Pablo"]),
    ("Inglés", [1, 3], "17:30", ["Lucía"]),
    ("Fútbol", [5], "17:00", ["Pablo"]),
    ("Sacar al perro", [1, 2, 3, 4, 5, 6, 7], "19:30", ["Marcos"]),
    ("Paseo en bici", [6, 7], "11:00", ["Pablo"]),
]:
    call("POST", "/routine/create?timezone=Europe/Madrid", {"calendar_id": col, "title": title, "days": days, "time": time,
         "start_date": str(T - datetime.timedelta(days=30)), "active": True, "person_ids": [P[w] for w in who]})
for name, color, tasks in [("Compra", "#F59E0B", ["Leche", "Pan", "Huevos", "Fruta", "Café"]),
                           ("Casa", "#10B981", ["Cambiar la bombilla del pasillo", "Llamar al fontanero", "Regar las plantas"])]:
    lid = call("POST", "/task-list/create", {"name": name, "color": color})["id"]
    for t in tasks: call("POST", "/task/create", {"task_list_id": lid, "title": t})
# Menú de la semana (plan aceptado, lunes de esta semana) y compra: los platos con receta generan la compra de menú
# (con «Para: …») al sincronizar; el resto de la compra se añade a mano con algún estado distinto.
lunes = T - datetime.timedelta(days=T.weekday())
def dia(n): return str(lunes + datetime.timedelta(days=n))
recetas = {
    "Lentejas con chorizo": [("Lentejas", 500, "g"), ("Chorizo", 300, "g")],
    "Garbanzos con espinacas": [("Garbanzos", 400, "g"), ("Espinacas", 500, "g")],
    "Pollo asado con ensalada": [("Pollo", 1, "kg"), ("Lechuga", 1, "ud")],
    "Ensalada César": [("Lechuga", 1, "ud"), ("Queso rallado", 150, "g")],
}
# Alimentos con su sección de la tienda: sin ella, la compra de menú cae en «otros».
secciones = {"Lentejas": "legumbres", "Chorizo": "embutido", "Garbanzos": "legumbres", "Espinacas": "verdura",
             "Pollo": "carne", "Lechuga": "verdura", "Queso rallado": "lacteos"}
alimentos = {}
for nombre, seccion in secciones.items():
    alimentos[nombre] = call("POST", "/food/create", {"name": nombre, "section": seccion})["id"]
ids_receta = {}
for nombre, ingredientes in recetas.items():
    ids_receta[nombre] = call("POST", "/recipe/create", {"name": nombre, "ingredients": [
        {"food_id": alimentos[n], "quantity": c, "unit": u} for n, c, u in ingredientes]})["id"]
platos = [
    (0, "breakfast", "free_text", "Tostadas con aceite y tomate"), (0, "lunch", "recipe", "Lentejas con chorizo"),
    (0, "dinner", "free_text", "Tortilla francesa y ensalada"), (1, "breakfast", "free_text", "Yogur con fruta"),
    (1, "lunch", "leftovers", "Sobras de lentejas"), (1, "dinner", "free_text", "Pescado al horno con patatas"),
    (2, "lunch", "eat_out", "Comida fuera"), (2, "snack", "free_text", "Fruta de temporada"),
    (2, "dinner", "free_text", "Crema de calabacín"), (3, "lunch", "free_text", "Arroz con verduras"),
    (3, "snack", "free_text", "Plátano y nueces"), (3, "dinner", "free_text", "Pizza casera"),
    (4, "breakfast", "free_text", "Avena con leche"), (4, "lunch", "recipe", "Pollo asado con ensalada"),
    (4, "dinner", "free_text", "Revuelto de champiñones"), (5, "lunch", "recipe", "Garbanzos con espinacas"),
    (5, "dinner", "free_text", "Sopa de verduras"), (6, "lunch", "free_text", "Paella de verduras"),
    (6, "dinner", "recipe", "Ensalada César"),
]
items = []
for n, s_, k, t in platos:
    it = {"day": dia(n), "slot": s_, "position": 0, "kind": k, "title": t}
    if k == "recipe": it["recipe_id"] = ids_receta[t]
    items.append(it)
plan = call("PATCH", "/meal/plan/items", {"week_start": str(lunes), "expected_revision": 0, "items": items})
call("POST", "/meal/plan/accept", {"plan_id": plan["id"], "expected_revision": plan["revision"]})
call("POST", "/shopping/sync", {"plan_id": plan["id"]})
import uuid
compra_a_mano = [
    ("Manzana", 4, "ud", "fruta", None), ("Jamón", 200, "g", "embutido", None), ("Leche", 2, "l", "lacteos", None),
    ("Pan de molde", 1, "ud", "panaderia", None), ("Tomate frito", 1, "ud", "despensa", None),
    ("Aceite de oliva", 1, "l", "aceites", None), ("Pimentón", 2, "cdta", "especias", None),
    ("Agua mineral", 6, "ud", "bebidas", None), ("Guisantes", 500, "g", "congelados", "checked"),
    ("Queso rallado", 150, "g", "lacteos", "skipped"), ("Huevos", 12, "ud", "huevos", None),
]
for label, cantidad, unidad, seccion, estado in compra_a_mano:
    creado = call("POST", "/shopping/item/create", {"label": label, "quantity": cantidad, "unit": unidad, "section": seccion,
                                                  "client_request_id": str(uuid.uuid4())})
    if estado: call("PATCH", "/shopping/item/check", {"id": creado["id"], "state": estado})
for item in call("GET", "/shopping")["items"]:
    if item.get("origin") == "menu" and item.get("label") in ("Lentejas", "Chorizo"):
        call("PATCH", "/shopping/item/check", {"id": item["id"], "state": "checked"})
print("ok", len(call("GET", "/event?dashboard=true&routine=false&timezone=Europe/Madrid")), "eventos")
