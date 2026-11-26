import XCTest
@testable import ControlKit

@MainActor
final class KitoMenuTests: XCTestCase {
    private let replyJSON = """
    {"texto":"Te propongo este menú","tarjetas":[
      {"tipo":"menu","id":"menu","semana":"2026-11-23","plan_id":9,"revision":3,"estado":"draft","origen":"kito",
       "conflictos":0,"sin_comprobar":[],
       "casillas":[
         {"id":11,"dia":"2026-11-24","franja":"dinner","franja_es":"cena","posicion":0,"tipo":"free_text",
          "titulo":"Tortilla","receta_id":null,"estado":"rejected","personas":[3],"comprobada":true,"motivo":"Ya la cené ayer"},
         {"id":10,"dia":"2026-11-23","franja":"lunch","franja_es":"comida","posicion":0,"tipo":"recipe",
          "titulo":"Lentejas","receta_id":5,"estado":null,"personas":[],"comprobada":true},
         {"id":12,"dia":"2026-11-23","franja":"dinner","franja_es":"cena","posicion":0,"tipo":"free_text",
          "titulo":"Sopa","receta_id":null,"estado":"locked","personas":[],"comprobada":true}
       ]},
      {"tipo":"tipo_nuevo_que_no_conozco","x":1}
    ]}
    """

    private func card(_ json: String) throws -> KitoCard {
        try JSONCoding.decoder().decode(KitoCard.self, from: Data(json.utf8))
    }

    func testDecodesValidMenuCard() throws {
        let reply = try JSONCoding.decoder().decode(KitoReply.self, from: Data(replyJSON.utf8))
        XCTAssertEqual(reply.tarjetas.count, 2, "la desconocida no rompe la respuesta")
        let menu = try XCTUnwrap(KitoMenu(card: reply.tarjetas[0]))
        XCTAssertEqual(menu.planId, 9)
        XCTAssertEqual(menu.revision, 3)
        XCTAssertEqual(menu.semana, "2026-11-23")
        XCTAssertEqual(menu.estadoPlan, "draft")
        XCTAssertEqual(menu.resultado, .pendiente)
        XCTAssertEqual(menu.casillas.count, 3)
        XCTAssertEqual(menu.rejected.map(\.titulo), ["Tortilla"])
        XCTAssertEqual(menu.rejected.first?.motivo, "Ya la cené ayer")
        XCTAssertEqual(menu.days.map(\.dia), ["2026-11-23", "2026-11-24"])
        XCTAssertEqual(menu.days[0].dishes.map(\.titulo), ["Lentejas", "Sopa"])
        XCTAssertEqual(menu.days[0].dishes[0].franjaEs, "comida")
    }

    func testUnknownCardTypeIsNotAMenu() throws {
        let reply = try JSONCoding.decoder().decode(KitoReply.self, from: Data(replyJSON.utf8))
        XCTAssertNil(KitoMenu(card: reply.tarjetas[1]))
    }

    func testMenuWithoutPlanOrRevisionIsRejected() throws {
        XCTAssertNil(KitoMenu(card: try card(#"{"tipo":"menu","semana":"2026-11-23","casillas":[]}"#)))
        XCTAssertNil(KitoMenu(card: try card(#"{"tipo":"menu","plan_id":9,"casillas":[]}"#)))
        XCTAssertNil(KitoMenu(card: try card(#"{"tipo":"menu","plan_id":"9","revision":1}"#)))
    }

    func testMalformedDishesAreSkipped() throws {
        let c = try card(#"{"tipo":"menu","plan_id":9,"revision":1,"casillas":[1,{"titulo":"sin dia"},{"dia":"2026-11-23","titulo":"Arroz"}]}"#)
        let menu = try XCTUnwrap(KitoMenu(card: c))
        XCTAssertEqual(menu.casillas.map(\.titulo), ["Arroz"])
        XCTAssertEqual(menu.casillas[0].franjaEs, "")
    }

    func testResultRoundTripsAndUnknownValueIsDesconocido() throws {
        let c = try card(#"{"tipo":"menu","plan_id":9,"revision":1}"#)
        let done = KitoMenu.card(c, resultado: .aceptado)
        XCTAssertEqual(KitoMenu(card: done)?.resultado, .aceptado)
        XCTAssertEqual(KitoMenuResult(rawValue: "raro"), .desconocido)
        XCTAssertFalse(KitoMenuResult.aceptado.canAccept)
        XCTAssertTrue(KitoMenuResult.pendiente.canAccept)
    }

    func testMealKindsReloadMealsTab() {
        let c = KitoChanges()
        c.publish([KitoChange(tipo: "menu", id: "9", op: "proponer"), KitoChange(tipo: "receta", id: "5", op: "crear")])
        XCTAssertEqual(c.counter(for: KitoReloadTargets.meals), 2)
        XCTAssertEqual(c.counter(for: KitoReloadTargets.tasks), 0)
    }
}
