import XCTest
@testable import ControlKit

/// Kito (chat iOS): tarjetas tolerantes, textos de error, cupo, Markdown, saludo y estado del store.
final class KitoChatTests: XCTestCase {
    private func decodeReply(_ json: String) throws -> KitoReply {
        try JSONDecoder().decode(KitoReply.self, from: Data(json.utf8))
    }

    // MARK: - Tarjetas

    func testKnownCardDecodes() throws {
        let reply = try decodeReply(#"{"texto":"ok","tarjetas":[{"tipo":"tarea","titulo":"Comprar","n":2}]}"#)
        XCTAssertEqual(reply.tarjetas.count, 1)
        XCTAssertEqual(reply.tarjetas[0].tipo, "tarea")
        XCTAssertEqual(reply.tarjetas[0].datos["titulo"], .string("Comprar"))
        XCTAssertEqual(reply.tarjetas[0].datos["n"], .number(2))
    }

    func testUnknownCardTypeDoesNotBreakDecode() throws {
        let reply = try decodeReply(#"{"texto":"ok","tarjetas":[{"tipo":"futuro","x":[1,{"a":null}],"texto":"hola"}]}"#)
        XCTAssertEqual(reply.tarjetas.first?.tipo, "futuro")
        XCTAssertEqual(reply.tarjetas.first?.datos["texto"], .string("hola"))
    }

    func testMissingOrNullCardsAreEmpty() throws {
        XCTAssertEqual(try decodeReply(#"{"texto":"ok"}"#).tarjetas, [])
        XCTAssertEqual(try decodeReply(#"{"texto":"ok","tarjetas":null}"#).tarjetas, [])
    }

    func testMalformedCardIsDropped() throws {
        let reply = try decodeReply(#"{"texto":"ok","tarjetas":[5,{"sin":"tipo"},{"tipo":"a"}]}"#)
        XCTAssertEqual(reply.tarjetas.map(\.tipo), ["a"])
        XCTAssertEqual(reply.texto, "ok")
    }

    func testOldHistoryWithoutCardsLoads() throws {
        let json = #"[{"id":"\#(UUID().uuidString)","role":"user","text":"hola","date":0}]"#
        let messages = try JSONDecoder().decode([KitoMessage].self, from: Data(json.utf8))
        XCTAssertEqual(messages.count, 1)
        XCTAssertNil(messages[0].cards)
    }

    func testMessageWithCardRoundTrips() throws {
        let card = KitoCard(tipo: "prueba", datos: ["a": .bool(true), "b": .array([.number(1), .null])])
        let message = KitoMessage(role: .assistant, text: "t", cards: [card])
        let data = try JSONEncoder().encode(message)
        XCTAssertEqual(try JSONDecoder().decode(KitoMessage.self, from: data), message)
    }
}
