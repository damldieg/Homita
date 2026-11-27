#!/usr/bin/env python3
"""Comprobaciones estáticas (stdlib) de la página de consentimiento OAuth del MCP y de su workflow de Pages.

Uso: python3 -I scripts/supabase/tests/oauth_page_check.py
Sobre web/oauth/consent/: supabase-js fijado con SRI, sin innerHTML ni service_role, config.example.js solo con
URL + anon key, config.js ignorado por git, PATCH /home/default, aprobar y denegar, aviso de salud.
Sobre .github/workflows/pages.yml: solo workflow_dispatch, publica solo web, sin secretos.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
PAGE = ROOT / "web/oauth/consent"
WF = ROOT / ".github/workflows/pages.yml"
fallos, n = [], 0


def check(nombre, cond):
    global n
    n += 1
    if not cond:
        fallos.append(nombre)


html = (PAGE / "index.html").read_text()
js = (PAGE / "consent.js").read_text()
ejemplo = (PAGE / "config.example.js").read_text()
todo = html + js + ejemplo
wf = WF.read_text()

check("supabase-js con versión exacta", re.search(r"@supabase/supabase-js@\d+\.\d+\.\d+/", html) is not None)
check("supabase-js con SRI sha384", re.search(r'integrity="sha384-[A-Za-z0-9+/=]{64}"', html) is not None)
check("supabase-js con crossorigin", 'crossorigin="anonymous"' in html)
check("CSP por meta", 'http-equiv="Content-Security-Policy"' in html)
check("sin scripts en línea", not re.search(r"<script(?![^>]*\bsrc=)[^>]*>", html))
check("sin estilos en línea", "<style" not in html and " style=" not in html)
check("sin innerHTML/outerHTML/insertAdjacentHTML/document.write",
      not re.search(r"innerHTML|outerHTML|insertAdjacentHTML|document\.write|eval\(", js))
check("sin service_role ni secretos", not re.search(r"service_role|SERVICE_ROLE|sb_secret", todo, re.I))
check("config.example.js solo URL y anon key",
      sorted(re.findall(r"^\s+([A-Z_]+):", ejemplo, re.M)) == ["SUPABASE_ANON_KEY", "SUPABASE_URL"])
check("config.js en .gitignore", "web/oauth/consent/config.js" in (ROOT / ".gitignore").read_text().split())
check("PATCH /home/default", '"PATCH", "/home/default"' in js)
check("aprobar", "approveAuthorization" in js)
check("denegar", "denyAuthorization" in js)
check("detalles del cliente", "getAuthorizationDetails" in js)
check("login por contraseña", "signInWithPassword" in js)
check("muestra el host de redirect_uri", "hostDe(d.redirect_uri)" in js)
check("aviso de salud", "no recibe datos de salud" in html)
check("redirección solo http(s)", '"https:"' in js and '"http:"' in js)

on = re.search(r"^on:\n((?:[ \t]+.*\n|\n)+)", wf, re.M)
check("workflow: bloque on", on is not None)
bloque = on.group(1) if on else ""
check("workflow: solo workflow_dispatch", re.findall(r"^  (\w+):", bloque, re.M) == ["workflow_dispatch"])
check("workflow: sin push/pull_request/schedule", not re.search(r"^\s+(push|pull_request\w*|schedule)\b", bloque, re.M))
check("workflow: publica solo web", re.search(r"path: web\s*$", wf, re.M) is not None)
check("workflow: sin secrets.", "secrets." not in wf)
check("workflow: acciones fijadas por SHA", all(re.search(r"uses: \S+@[0-9a-f]{40}\b", l) for l in wf.splitlines() if "uses:" in l))

if fallos:
    print("FALLAN:", *fallos, sep="\n  ")
    sys.exit(1)
print(f"oauth_page_check: {n}/{n} casos ok")
