import XCTest

/// Auditoría funcional de Control iOS (change `control-ios-auditoria`).
///
/// Recorre la app contra el stack LOCAL (127.0.0.1) con la cuenta demo y adjunta una captura por
/// pantalla. Las capturas se extraen del `.xcresult` con `xcresulttool` (ver docs/ios-funcional.md).
/// La app no tiene `accessibilityIdentifier`: los controles se localizan por el texto visible.
final class ControlAppAuditTests: XCTestCase {
    private var app: XCUIApplication!

    private let demoEmail = "demo@homita.example"
    private let demoPassword = "demo1234"

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uiTestingResetSession"]
        app.launch()
    }

    // MARK: - Helpers

    /// Adjunta una captura de pantalla completa con nombre estable (sirve para extraerla del xcresult).
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Toca el primer control visible con ese texto (botón, barra de navegación, celda o texto).
    /// Si no aparece, desliza hacia arriba una vez y reintenta.
    @discardableResult
    private func tap(_ label: String, timeout: TimeInterval = 8, required: Bool = true) -> Bool {
        for attempt in 0..<2 {
            let candidates: [XCUIElement] = [
                app.buttons[label].firstMatch,
                app.navigationBars.buttons[label].firstMatch,
                app.cells.buttons[label].firstMatch,
                app.staticTexts[label].firstMatch,
                app.tabBars.buttons[label].firstMatch,
            ]
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if let hit = candidates.first(where: { $0.exists && $0.isHittable }) {
                    hit.tap()
                    return true
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
            if attempt == 0 { app.swipeUp() }
        }
        if required { XCTFail("No encontré el control «\(label)»") }
        return false
    }

    /// Toca un segmento de la cabecera de la pantalla (no la pestaña inferior del mismo nombre).
    /// Los segmentos de la app son controles propios, así que se buscan por texto en la mitad superior.
    private func tapSegment(_ label: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let candidates = app.buttons.allElementsBoundByIndex.filter { $0.label == label }
            + app.staticTexts.allElementsBoundByIndex.filter { $0.label == label }
        guard let segment = candidates.first(where: { $0.exists && $0.isHittable && $0.frame.minY < 400 }) else {
            XCTFail("No encontré el segmento «\(label)»")
            return
        }
        segment.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    /// Entra con la cuenta demo local si aún no hay sesión; espera a que aparezcan las pestañas.
    private func ensureLoggedIn() {
        if app.tabBars.buttons["Inicio"].waitForExistence(timeout: 3) { return }
        tap("Iniciar sesión")
        let email = app.textFields["Email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 8), "No aparece el campo Email")
        email.tap()
        email.typeText(demoEmail)
        let password = app.secureTextFields["Contraseña"].firstMatch
        password.tap()
        password.typeText(demoPassword)
        tap("Iniciar sesión")
        XCTAssertTrue(app.tabBars.buttons["Inicio"].waitForExistence(timeout: 25), "El login demo no llegó a las pestañas")
    }

    private func openTab(_ name: String) {
        let tab = app.tabBars.buttons[name]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "Falta la pestaña \(name)")
        tab.tap()
        RunLoop.current.run(until: Date().addingTimeInterval(1.0))
    }

    private func back() {
        let nav = app.navigationBars.buttons.firstMatch
        if nav.exists && nav.isHittable { nav.tap() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    private func cancelSheet() {
        tap("Cancelar", timeout: 3)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
    }

    // MARK: - 1. Entrada sin sesión

    func test01_WelcomeLoginRegister() {
        XCTAssertTrue(app.buttons["Iniciar sesión"].waitForExistence(timeout: 15), "No aparece la bienvenida")
        shot("01-bienvenida")

        tap("Iniciar sesión")
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 8))
        shot("02-login")
        back()

        tap("Registrarse")
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 8) || app.textFields["Nombre"].waitForExistence(timeout: 2))
        shot("03-registro")
    }

    func test02_LoginInvalidoMuestraError() {
        XCTAssertTrue(app.buttons["Iniciar sesión"].waitForExistence(timeout: 15))
        tap("Iniciar sesión")
        let email = app.textFields["Email"].firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 8))
        email.tap(); email.typeText("nadie@homita.example")
        let password = app.secureTextFields["Contraseña"].firstMatch
        password.tap(); password.typeText("incorrecta")
        tap("Iniciar sesión")
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        shot("04-login-error")
    }

    // MARK: - 2. Pestañas con sesión

    func test03_Pestanas() {
        ensureLoggedIn()
        for (index, name) in ["Inicio", "Tareas", "Calendario", "Hogar", "Ajustes"].enumerated() {
            openTab(name)
            shot(String(format: "1%02d-pestana-%@", index, name.lowercased()))
        }
    }

    // MARK: - 3. Tareas y listas

    func test04_TareasListasYAltas() {
        ensureLoggedIn()
        openTab("Tareas")
        shot("20-tareas-lista")

        // El segmento «Listas» contiene «Nueva lista»; «Nueva tarea» vive en el segmento «Tareas».
        tapSegment("Listas")
        shot("23-tareas-listas")
        tap("Nueva lista")
        shot("21-form-nueva-lista")
        cancelSheet()

        tapSegment("Tareas")
        tap("Nueva tarea")
        shot("22-form-nueva-tarea")
        cancelSheet()
    }

    // MARK: - 4. Calendario, eventos y rutinas

    func test05_CalendarioSegmentosYAltas() {
        ensureLoggedIn()
        openTab("Calendario")
        shot("30-calendario-eventos")

        if app.buttons["Rutinas"].exists { tap("Rutinas") }
        shot("31-calendario-rutinas")

        if app.buttons["Calendarios"].exists { tap("Calendarios") }
        shot("32-calendario-calendarios")

        tap("Nuevo calendario")
        shot("33-form-nuevo-calendario")
        cancelSheet()
    }

    func test06_FormulariosEventoYRutina() {
        ensureLoggedIn()
        openTab("Calendario")
        if app.buttons["Eventos"].exists { tap("Eventos") }
        tap("Nuevo evento")
        shot("34-form-nuevo-evento")
        cancelSheet()

        if app.buttons["Rutinas"].exists { tap("Rutinas") }
        tap("Nueva rutina")
        shot("35-form-nueva-rutina")
        cancelSheet()
    }

    // MARK: - 5. Inicio

    func test07_InicioYAccesosRapidos() {
        ensureLoggedIn()
        openTab("Inicio")
        shot("10-inicio")
        if tap("+ Evento", timeout: 3, required: false) {
            shot("11-inicio-form-evento")
            cancelSheet()
        }
    }

    // MARK: - 6. Hogar y administración

    func test08_HogarYAdministracion() {
        ensureLoggedIn()
        openTab("Hogar")
        shot("40-hogar")

        // Cada sección se abre desde cero (Hogar → Administración → sección) para no depender del historial de navegación.
        let sections = ["Configuración", "Administradores", "Miembros", "Invitaciones", "Accesos", "Auditoría"]
        for (index, section) in sections.enumerated() {
            openTab("Hogar")
            guard tap("Administración", timeout: 4, required: false) else { break }
            if index == 0 { shot("41-administracion") }
            if tap(section, timeout: 4, required: false) {
                shot(String(format: "5%d-admin-%@", index, section.lowercased()))
            }
        }
    }

    // MARK: - 7. Perfil y ajustes

    func test09_PerfilYAjustes() {
        ensureLoggedIn()
        openTab("Ajustes")
        shot("60-perfil")
        tap("Personas", timeout: 4)
        shot("61-personas")
        back()
        if tap("Unirse a un hogar con un código", timeout: 4, required: false) {
            shot("62-unirse-hogar")
        }
    }
}
