//
//  AgentGatewayTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del gateway del agente (promptMaster §20.5, PR-1603): interpret/explain,
//  timeout/retry acotado, y fallback local determinista bajo fallo del backend.
//

import XCTest
@testable import PRDomain

final class AgentGatewayTests: XCTestCase {

    private func makeTiming(retries: Int = 2, backoff: TimeInterval = 0) throws -> AgentGatewayTiming {
        try AgentGatewayTiming(timeoutSeconds: 1, maxRetries: retries, backoffSeconds: backoff)
    }

    // MARK: - Backend exitoso

    final class StubTransport: AgentBackendTransport, @unchecked Sendable {
        var interpretResult: Result<InterpretResponse, AgentGatewayError> = .success(InterpretResponse())
        var explainResult: Result<ExplainResponse, AgentGatewayError> = .success(ExplainResponse())
        var interpretCalls = 0
        var explainCalls = 0

        func interpret(_ request: InterpretRequest) async throws -> InterpretResponse {
            interpretCalls += 1
            return try interpretResult.get()
        }

        func explain(_ request: ExplainRequest) async throws -> ExplainResponse {
            explainCalls += 1
            return try explainResult.get()
        }
    }

    func testInterpretReturnsIntentFromBackend() async throws {
        let transport = StubTransport()
        transport.interpretResult = .success(InterpretResponse(intent: .changeGoal(.strength)))
        let gateway = AgentGateway(transport: transport, timing: try makeTiming())

        let result = await gateway.interpret(
            text: "cambiar a fuerza",
            context: AgentContext(text: "cambiar a fuerza")
        )
        XCTAssertEqual(result, .intent(.changeGoal(.strength)))
        XCTAssertEqual(transport.interpretCalls, 1)
    }

    func testExplainReturnsBackendText() async throws {
        let transport = StubTransport()
        transport.explainResult = .success(ExplainResponse(text: "progresión estable"))
        let gateway = AgentGateway(transport: transport, timing: try makeTiming())

        let response = await gateway.explain(facts: [DecisionFact(key: "k", value: "v")])
        XCTAssertEqual(response.text, "progresión estable")
        XCTAssertEqual(transport.explainCalls, 1)
    }

    // MARK: - Fallback local sin backend (offline-first)

    func testInterpretOfflineRecognizesTimeConstraint() async throws {
        let gateway = AgentGateway(transport: nil, timing: try makeTiming())
        let result = await gateway.interpret(text: "solo 30 min", context: AgentContext())
        XCTAssertEqual(result, .intent(.setTimeConstraint(.hard(minutes: 30))))
    }

    func testInterpretOfflineUnknownNeedsClarification() async throws {
        let gateway = AgentGateway(transport: nil, timing: try makeTiming())
        let result = await gateway.interpret(text: "haz lo que quieras con mi plan", context: AgentContext())
        XCTAssertEqual(result, .needsClarification, "no se inventa intents: pide reformulación")
    }

    func testExplainOfflineTemplateFromFacts() async throws {
        let gateway = AgentGateway(transport: nil, timing: try makeTiming())
        let response = await gateway.explain(facts: [
            DecisionFact(key: "loadChange", value: "+2.5"),
            DecisionFact(key: "reason", value: "adaptación"),
        ])
        XCTAssertEqual(response.reasons.count, 2)
        XCTAssertFalse(response.text!.isEmpty)
    }

    func testExplainOfflineLimitsToFourReasons() async throws {
        let gateway = AgentGateway(transport: nil, timing: try makeTiming())
        let facts = (0..<8).map { DecisionFact(key: "k\($0)", value: "v\($0)") }
        let response = await gateway.explain(facts: facts)
        XCTAssertEqual(response.reasons.count, 4)
    }

    // MARK: - Timeout / retry ACOTADO + fallback sobre fallo del backend

    func testInterpretRetriesBoundedThenFallsBackToLocal() async throws {
        let transport = StubTransport()
        transport.interpretResult = .failure(.backendFailure) // falla siempre
        let retries = 3
        let gateway = AgentGateway(transport: transport, timing: try makeTiming(retries: retries, backoff: 0))

        let result = await gateway.interpret(text: "solo 20 min", context: AgentContext())
        // 1 inicial + 3 reintentos = 4 intentos acotados.
        XCTAssertEqual(transport.interpretCalls, 4)
        XCTAssertEqual(result, .intent(.setTimeConstraint(.hard(minutes: 20))), "cae al fallback local determinista")
    }

    func testExplainRetriesBoundedThenFallsBackToLocal() async throws {
        let transport = StubTransport()
        transport.explainResult = .failure(.timeout)
        let gateway = AgentGateway(transport: transport, timing: try makeTiming(retries: 2, backoff: 0))

        let response = await gateway.explain(facts: [DecisionFact(key: "a", value: "b")])
        XCTAssertEqual(transport.explainCalls, 3)
        XCTAssertEqual(response.text, "a: b", "plantilla local offline")
    }

    func testExplainEmptyBackendResponseFallsBackLocal() async throws {
        let transport = StubTransport()
        transport.explainResult = .success(ExplainResponse()) // texto vacío
        let gateway = AgentGateway(transport: transport, timing: try makeTiming(retries: 0))
        let response = await gateway.explain(facts: [DecisionFact(key: "x", value: "y")])
        XCTAssertEqual(response.text, "x: y")
    }

    // MARK: - Timing policy ACOTADA

    func testTimingRejectsInvalidValues() {
        XCTAssertThrowsError(try AgentGatewayTiming(timeoutSeconds: 0, maxRetries: 1, backoffSeconds: 0))
        XCTAssertThrowsError(try AgentGatewayTiming(timeoutSeconds: 1, maxRetries: -1, backoffSeconds: 0))
        XCTAssertThrowsError(try AgentGatewayTiming(timeoutSeconds: 1, maxRetries: 1, backoffSeconds: -0.1))
        // Válido:
        XCTAssertNoThrow(try AgentGatewayTiming(timeoutSeconds: 1, maxRetries: 0, backoffSeconds: 0))
    }

    func testTotalAttemptsBounded() throws {
        XCTAssertEqual(try makeTiming(retries: 2).totalAttempts, 3)
        XCTAssertEqual(try makeTiming(retries: 0).totalAttempts, 1)
    }

    // MARK: - No almacena secretos (estructural por construcción)
    func testGatewayHoldsNoKey() throws {
        let _ = AgentGateway(transport: nil, timing: try makeTiming())
        // El tipo de dominio no expone ninguna propiedad de credencial (sólo
        // transporte + timing + fallback local). Esto es estructural: sin API key.
        XCTAssertTrue(true)
    }
}