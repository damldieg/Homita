import XCTest
@testable import ControlKit

/// Frases de auditoría en español (E4-10, P-23).
final class AuditPhraseTests: XCTestCase {
    func testPermissionGrantWithMember() {
        XCTAssertEqual(
            AuditPhrase.sentence(action: "home.permission.grant", actor: "Ana",
                                 payload: ["permission": "task.edit", "member_name": "Lucía"]),
            "Ana activó «Editar y ordenar tareas» para Lucía"
        )
    }

    func testInvitationCreateWithType() {
        XCTAssertEqual(
            AuditPhrase.sentence(action: "home.invitation.create", actor: "Familia Demo", payload: ["type": "Invitado"]),
            "Familia Demo creó una invitación de tipo Invitado"
        )
    }

    func testUnknownActionKeepsTechnicalCodeAndSystemActor() {
        XCTAssertEqual(
            AuditPhrase.sentence(action: "foo.bar", actor: nil, payload: [:]),
            "Sistema realizó «foo.bar»"
        )
    }

    func testMissingPayloadFallsBackToGenericPhrase() {
        XCTAssertEqual(
            AuditPhrase.sentence(action: "home.permission.grant", actor: "Ana", payload: [:]),
            "Ana realizó «home.permission.grant»"
        )
    }
}
