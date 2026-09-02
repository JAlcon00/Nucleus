//
//  AgentReadOnlyToolsTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del tool gateway read-only (NEMOTRON §13-§15, Phase N3): allow-list estricta,
//  ejecución determinista de tools de lectura tipo al LLM (que el LLM no escribe) y
//  fallo seguro ante tools fuera de la lista o argumentos inválidos.
//

import XCTest
@testable import PRDomain

final class AgentReadOnlyToolsTests: XCTestCase {

    private func makeGateway(
        today: String = "Sesión: Fuerza",
        history: String = "3 sesiones esta semana",
        restrictions: Int = 2,
        gym: String = "Gym Central",
        painGate: Bool = false
    ) -> AgentReadOnlyToolGateway {
        AgentReadOnlyToolGateway(context: AgentReadOnlyContext(
            todaySummary: today,
            trainingHistorySummary: history,
            activeRestrictionCount: restrictions,
            gymProfileSummary: gym,
            painGateActive: painGate
        ))
    }

    // MARK: - Allow-list estricta

    func testCatalogContainsOnlyReadOnlyTools() {
        let names = AgentReadOnlyToolName.allCases.map(\.rawValue).sorted()
        XCTAssertEqual(names, ["getActiveRestrictions", "getGymProfile", "getTodayContext", "getTrainingHistory"])
        // Son 4 tools de LECTURA (promptMaster §20.4, primeras 4).
        XCTAssertEqual(names.count, 4)
    }

    func testUnknownToolRejectedFailsafe() throws {
        let gateway = makeGateway()
        // Una tool fuera de la allow-list (p. ej. una escritura inventada) se NIEGA.
        XCTAssertFalse(gateway.isAllowListed("writeToDatabase"))
        XCTAssertFalse(gateway.isAllowListed("replaceExercise"))
        XCTAssertThrowsError(try gateway.execute(name: "writeToDatabase")) { error in
            XCTAssertEqual(error as? AgentToolError, .unknownTool(name: "writeToDatabase"))
        }
    }

    func testAllAllowListed() {
        let gateway = makeGateway()
        for name in AgentReadOnlyToolName.allCases {
            XCTAssertTrue(gateway.isAllowListed(name.rawValue))
        }
    }

    // MARK: - Ejecución determinista read-only

    func testGetTodayContextReturnsTypedSummary() throws {
        let gateway = makeGateway(today: "Sesión: Fuerza", painGate: true)
        let result = try gateway.execute(name: "getTodayContext", arguments: "{}")
        XCTAssertEqual(result.name, "getTodayContext")
        XCTAssertTrue(result.payload.contains("Sesión: Fuerza"))
        XCTAssertTrue(result.payload.contains("true"))
    }

    func testGetActiveRestrictionsCount() throws {
        let gateway = makeGateway(restrictions: 2)
        let result = try gateway.execute(name: "getActiveRestrictions")
        XCTAssertTrue(result.payload.contains("\"activeRestrictionCount\":\"2\""))
    }

    func testGetGymProfile() throws {
        let gateway = makeGateway(gym: "Gym Central")
        let result = try gateway.execute(name: "getGymProfile")
        XCTAssertTrue(result.payload.contains("Gym Central"))
    }

    func testGetTrainingHistory() throws {
        let gateway = makeGateway(history: "3 sesiones esta semana")
        let result = try gateway.execute(name: "getTrainingHistory")
        XCTAssertTrue(result.payload.contains("3 sesiones esta semana"))
    }

    // MARK: - Argumentos inválidos → fail-safe

    func testInvalidArgumentsRejected() throws {
        let gateway = makeGateway()
        XCTAssertThrowsError(try gateway.execute(name: "getTodayContext", arguments: "not json")) { error in
            XCTAssertEqual(error as? AgentToolError, .invalidArguments(name: "getTodayContext"))
        }
    }

    func testEmptyOrObjectArgumentsAccepted() throws {
        let gateway = makeGateway()
        XCTAssertNoThrow(try gateway.execute(name: "getTodayContext", arguments: ""))
        XCTAssertNoThrow(try gateway.execute(name: "getTodayContext", arguments: "{\"ignored\":1}"))
    }
}
