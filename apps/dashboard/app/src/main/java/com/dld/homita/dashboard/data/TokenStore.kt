package com.dld.homita.dashboard.data

/** Lo que la renovación de sesión necesita del almacén: [Store] en la app, un doble en los tests. */
interface TokenStore {
    var token: String?
    var refreshToken: String?
}
