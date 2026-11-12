import XCTest
@testable import ControlKit

/// Presentación de los estados vacíos (E0-04, T6). Las vistas no se prueban sin snapshot: el
/// contenido y la regla de la acción viven en `HomitaEmptyContent`/`HomitaEmptyNoteText`, que
/// usan `HomitaEmptyState` y `HomitaEmptyNote`.
final class HomitaEmptyStateTests: XCTestCase {
    /// `docs/design/ios/code-facts.md` (inventario del código real) desde la raíz del repo.
    private func codeFacts() throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // ControlTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // control-ios
            .deletingLastPathComponent() // apps
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent("docs/design/ios/code-facts.md"), encoding: .utf8)
    }

    func testScreenEmptyStatesKeepRealTexts() {
        XCTAssertEqual(HomitaEmptyContent.tasks(filtered: false), HomitaEmptyContent(
            illustration: .tasks, title: "Sin tareas",
            message: "Crea tu primera tarea y ponle una lista para tenerla a mano.", actionTitle: "Nueva tarea"
        ))
        XCTAssertEqual(HomitaEmptyContent.tasks(filtered: true).message, "Esta lista no tiene tareas todavía.")
        XCTAssertEqual(HomitaEmptyContent.tasks(filtered: true).actionTitle, "Nueva tarea")
        XCTAssertEqual(HomitaEmptyContent.taskLists, HomitaEmptyContent(
            illustration: .lists, title: "Sin listas",
            message: "Las listas agrupan tus tareas: compra, casa, trabajo…", actionTitle: "Nueva lista"
        ))
        XCTAssertEqual(HomitaEmptyContent.routines, HomitaEmptyContent(
            illustration: .routines, title: "Sin rutinas",
            message: "Las rutinas repiten eventos cada día, semana o mes sin que las vuelvas a escribir.",
            actionTitle: "Nueva rutina"
        ))
        XCTAssertEqual(HomitaEmptyContent.calendars, HomitaEmptyContent(
            illustration: .calendars, title: "Sin calendarios",
            message: "Los calendarios agrupan eventos y rutinas por color, como Trabajo o Familia.",
            actionTitle: "Nuevo calendario"
        ))
    }

    func testCardEmptyNotesKeepRealTexts() {
        XCTAssertEqual(HomitaEmptyNoteText.todayEvents, "Sin eventos hoy")
        XCTAssertEqual(HomitaEmptyNoteText.pendingTasks, "Sin tareas pendientes")
        XCTAssertEqual(HomitaEmptyNoteText.todayRoutines, "Sin rutinas hoy")
        XCTAssertEqual(HomitaEmptyNoteText.listTasks, "Sin tareas")
        XCTAssertEqual(HomitaEmptyNoteText.members, "Sin miembros")
        XCTAssertEqual(HomitaEmptyNoteText.persons, "Sin personas")
    }

    /// Cada texto (salvo «Sin rutinas hoy», que el inventario no recoge) aparece en code-facts.md.
    func testTextsMatchCodeFacts() throws {
        let facts = try codeFacts()
        let screens: [HomitaEmptyContent] = [
            .tasks(filtered: false), .tasks(filtered: true), .taskLists, .routines, .calendars
        ]
        var texts = screens.flatMap { [$0.title, $0.message, $0.actionTitle ?? ""] }
        texts += [
            HomitaEmptyNoteText.todayEvents, HomitaEmptyNoteText.pendingTasks, HomitaEmptyNoteText.listTasks,
            HomitaEmptyNoteText.members, HomitaEmptyNoteText.persons
        ]
        for text in texts {
            XCTAssertTrue(facts.contains("«\(text)»"), "«\(text)» no está en code-facts.md")
        }
    }

    /// Una acción como mucho, y solo con título y acción.
    func testActionShownOnlyWithTitleAndAction() {
        XCTAssertTrue(HomitaEmptyContent.showsAction(actionTitle: "Nueva tarea", hasAction: true))
        XCTAssertFalse(HomitaEmptyContent.showsAction(actionTitle: "Nueva tarea", hasAction: false))
        XCTAssertFalse(HomitaEmptyContent.showsAction(actionTitle: nil, hasAction: true))
        XCTAssertFalse(HomitaEmptyContent.showsAction(actionTitle: nil, hasAction: false))
    }
}
