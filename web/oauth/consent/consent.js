// Página de consentimiento OAuth de Homita (MCP de Claude). Supabase Auth redirige aquí con
// ?authorization_id=…; la persona entra con su cuenta, elige su hogar predeterminado y aprueba o deniega.
// Sin secretos: solo la URL y la clave anónima de config.js. Todo el texto de otros se pone con textContent.
(function () {
  "use strict";

  var cfg = window.HOMITA_CONFIG || {};
  var $ = function (id) { return document.getElementById(id); };
  var estado = $("estado");

  function mensaje(texto, esError) {
    estado.textContent = texto;
    estado.className = esError ? "error" : "";
    estado.hidden = texto === "";
  }

  function mostrar(id, visible) { $(id).hidden = !visible; }

  if (!cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY) {
    mensaje("Falta config.js con la URL y la clave anónima de Supabase (ver config.example.js).", true);
    return;
  }
  var authorizationId = new URLSearchParams(window.location.search).get("authorization_id");
  if (!authorizationId) {
    mensaje("Falta authorization_id: abre esta página desde la conexión de Claude con Homita.", true);
    return;
  }
  if (!window.supabase || !window.supabase.createClient) {
    mensaje("No se ha podido cargar supabase-js.", true);
    return;
  }

  var client = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
    auth: { storage: window.sessionStorage, persistSession: true, autoRefreshToken: true, detectSessionInUrl: false },
  });
  var apiBase = cfg.SUPABASE_URL.replace(/\/+$/, "") + "/functions/v1/api";
  var homes = [];
  var predeterminado = null;

  function api(metodo, ruta, cuerpo, token) {
    var headers = { Authorization: "Bearer " + token, apikey: cfg.SUPABASE_ANON_KEY };
    if (cuerpo !== undefined) headers["Content-Type"] = "application/json";
    return fetch(apiBase + ruta, { method: metodo, headers: headers, body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo) })
      .then(function (res) {
        if (!res.ok) throw new Error("api " + res.status);
        return res.json();
      });
  }

  function hostDe(url) {
    try { return new URL(url).host; } catch (e) { return "(dirección no válida)"; }
  }

  // Un redirect_url solo se sigue si es http(s).
  function irA(url) {
    var u;
    try { u = new URL(url); } catch (e) { mensaje("La dirección de vuelta no es válida.", true); return; }
    if (u.protocol !== "https:" && u.protocol !== "http:") { mensaje("La dirección de vuelta no es válida.", true); return; }
    window.location.assign(u.toString());
  }

  function rellenarHogares() {
    var sel = $("hogar");
    sel.textContent = "";
    homes.forEach(function (h) {
      var o = document.createElement("option");
      o.value = String(h.home_id);
      o.textContent = String(h.name) + (h.is_default ? " (actual)" : "");
      if (h.is_default) { o.selected = true; predeterminado = String(h.home_id); }
      sel.appendChild(o);
    });
    if (predeterminado === null && homes.length > 0) sel.value = String(homes[0].home_id);
  }

  function mostrarConsentimiento(session) {
    return client.auth.oauth.getAuthorizationDetails(authorizationId).then(function (r) {
      if (r.error) throw r.error;
      var d = r.data || {};
      // Consentimiento ya dado antes: solo viene la redirección.
      if (d.redirect_url && !d.client) { irA(d.redirect_url); return; }
      return api("GET", "/home", undefined, session.access_token).then(function (lista) {
        homes = Array.isArray(lista) ? lista : [];
        rellenarHogares();
        $("titulo").textContent = "«" + String((d.client && d.client.name) || "Una aplicación") + "» quiere conectarse a Homita";
        $("cuenta").textContent = (d.user && d.user.email) || session.user.email || "";
        $("destino").textContent = hostDe(d.redirect_uri);
        $("alcances").textContent = d.scope ? "Alcances de la conexión: " + d.scope : "";
        mostrar("login", false);
        mostrar("consent", true);
        mensaje("", false);
      });
    });
  }

  function iniciar() {
    mensaje("Cargando…", false);
    client.auth.getSession().then(function (r) {
      var session = r.data && r.data.session;
      if (!session) {
        mostrar("consent", false);
        mostrar("login", true);
        mensaje("", false);
        return;
      }
      return mostrarConsentimiento(session);
    }).catch(function () {
      mensaje("No he podido cargar la solicitud de conexión. Puede que haya caducado: vuelve a empezar desde Claude.", true);
    });
  }

  $("login").addEventListener("submit", function (ev) {
    ev.preventDefault();
    mensaje("Entrando…", false);
    client.auth.signInWithPassword({ email: $("email").value, password: $("password").value }).then(function (r) {
      $("password").value = "";
      if (r.error || !r.data.session) { mensaje("Correo o contraseña incorrectos.", true); return; }
      return mostrarConsentimiento(r.data.session);
    }).catch(function () {
      mensaje("No he podido continuar. Vuelve a empezar desde Claude.", true);
    });
  });

  $("cambiar").addEventListener("click", function () {
    client.auth.signOut().then(function () {
      mostrar("consent", false);
      mostrar("login", true);
    });
  });

  function bloquear(bloqueado) {
    $("aprobar").disabled = bloqueado;
    $("denegar").disabled = bloqueado;
  }

  $("aprobar").addEventListener("click", function () {
    bloquear(true);
    mensaje("Conectando…", false);
    client.auth.getSession().then(function (r) {
      var session = r.data && r.data.session;
      if (!session) throw new Error("sin sesión");
      var elegido = $("hogar").value;
      var cambio = elegido !== "" && elegido !== predeterminado
        ? api("PATCH", "/home/default", { home_id: Number(elegido) }, session.access_token)
        : Promise.resolve();
      return cambio.then(function () {
        return client.auth.oauth.approveAuthorization(authorizationId, { skipBrowserRedirect: true });
      });
    }).then(function (r) {
      if (r.error || !r.data || !r.data.redirect_url) throw new Error("no aprobado");
      irA(r.data.redirect_url);
    }).catch(function () {
      bloquear(false);
      mensaje("No he podido aprobar la conexión. Inténtalo otra vez o vuelve a empezar desde Claude.", true);
    });
  });

  $("denegar").addEventListener("click", function () {
    bloquear(true);
    client.auth.oauth.denyAuthorization(authorizationId, { skipBrowserRedirect: true }).then(function (r) {
      if (r.error || !r.data || !r.data.redirect_url) throw new Error("no denegado");
      irA(r.data.redirect_url);
    }).catch(function () {
      bloquear(false);
      mensaje("No he podido denegar la conexión. Cierra esta página.", true);
    });
  });

  iniciar();
})();
