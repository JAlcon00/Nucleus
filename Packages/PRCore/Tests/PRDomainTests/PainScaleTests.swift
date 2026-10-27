//
//  PainScaleTests.swift
//  PRDomainTests
//
//  SCRUM-32: una sola escala de dolor (ninguno, leve, moderado, alto). La forma anterior
//  (severidad 1–5 + molestia/punzante) se traduce con la tabla conservadora de
//  `LegacyPainScale`, se guarda siempre la escala única y los tres motores aplican la
//  misma regla: moderado o alto no sube la carga.
//

import Foundation
import Testing
@testable import PRDomain

private func decode(_ json: String) throws -> PainFeedback {
    try JSONDecoder().decode(PainFeedback.self, from: Data(json.utf8))
}

/// Los campos que pueden aparecer en el JSON de un dolor, de cualquier versión.
private struct StoredPainShape: Decodable {
    let level: Int?
    let muscle: String?
    let kind: String?
    let severity: Int?
}

@Suite("SCRUM-32 · Una sola escala de dolor")
struct PainScaleTests {

    // MARK: - Tabla de la escala anterior

    @Test(
        "Tabla conservadora: 1 leve, 2 y 3 moderado, 4 y 5 alto",
        arguments: zip([1, 2, 3, 4, 5], [PainLevel.mild, .moderate, .moderate, .high, .high])
    )
    func legacyTable(severity: Int, expected: PainLevel) {
        #expect(LegacyPainScale.level(severity: severity, sharp: false) == expected)
    }

    @Test("Un dolor punzante nunca queda por debajo de moderado", arguments: LegacyPainScale.severities)
    func sharpIsAtLeastModerate(severity: Int) {
        let sharp = LegacyPainScale.level(severity: severity, sharp: true)
        #expect(sharp >= .moderate)
        #expect(sharp >= LegacyPainScale.level(severity: severity, sharp: false))
        #expect(PainFeedback(level: sharp).blocksProgression)
    }

    // MARK: - Lectura y guardado

    @Test("Lee la forma anterior con la tabla y conserva el músculo")
    func decodesLegacyShape() throws {
        #expect(try decode(#"{"kind":"discomfort","severity":3,"muscle":"chest"}"#) == PainFeedback(level: .moderate, muscleGroup: .chest))
        #expect(try decode(#"{"kind":"discomfort","severity":1,"muscle":"chest"}"#) == PainFeedback(level: .mild, muscleGroup: .chest))
        #expect(try decode(#"{"kind":"sharpPain","severity":1,"muscle":"chest"}"#) == PainFeedback(level: .moderate, muscleGroup: .chest))
        #expect(try decode(#"{"kind":"sharpPain","severity":5,"muscle":"shoulders"}"#) == PainFeedback(level: .high, muscleGroup: .shoulders))
        #expect(try decode(#"{"kind":"none"}"#) == .none)
    }

    @Test("Lee la escala única, con y sin músculo")
    func decodesNewShape() throws {
        #expect(try decode(#"{"level":2,"muscle":"chest"}"#) == PainFeedback(level: .moderate, muscleGroup: .chest))
        #expect(try decode(#"{"level":0}"#) == .none)
    }

    @Test("Una severidad fuera de 1–5 o un tipo desconocido no se adivina")
    func rejectsInvalidLegacy() {
        #expect(throws: DomainValidationError.invalidSeverity(value: 0)) {
            try decode(#"{"kind":"discomfort","severity":0,"muscle":"chest"}"#)
        }
        #expect(throws: DomainValidationError.invalidSeverity(value: 6)) {
            try decode(#"{"kind":"sharpPain","severity":6,"muscle":"chest"}"#)
        }
        #expect(throws: DecodingError.self) { try decode(#"{"kind":"cramp","severity":2}"#) }
        #expect(throws: DecodingError.self) { try decode(#"{"level":7}"#) }
    }

    @Test("Siempre guarda la escala única, sin los campos de la anterior")
    func encodesOnlyNewShape() throws {
        let legacy = try decode(#"{"kind":"sharpPain","severity":4,"muscle":"shoulders"}"#)
        let data = try JSONEncoder().encode(legacy)
        let shape = try JSONDecoder().decode(StoredPainShape.self, from: data)
        #expect(shape.level == PainLevel.high.rawValue)
        #expect(shape.muscle == "shoulders")
        #expect(shape.kind == nil)
        #expect(shape.severity == nil)
        #expect(try JSONDecoder().decode(PainFeedback.self, from: data) == legacy)
    }

    // MARK: - Una sola regla en los tres motores

    @Test("Moderado y alto bloquean la progresión; ninguno y leve no", arguments: PainLevel.allCases)
    func blocksProgression(level: PainLevel) {
        let expected: Bool
        switch level {
        case .none, .mild: expected = false
        case .moderate, .high: expected = true
        }
        #expect(PainFeedback(level: level).blocksProgression == expected)
    }

    @Test("Feedback de dolor, doble progresión y fuerza dicen lo mismo en cada nivel", arguments: PainLevel.allCases)
    func enginesAgree(level: PainLevel) throws {
        let pain = PainFeedback(level: level, muscleGroup: .chest)
        let prescription = try SetPrescription(targetRepRange: 8...12, loadUnit: .kilograms, restSeconds: 90...120)

        let painEngine = try PainFeedbackEngine(config: PainFeedbackConfig(rule: PainFeedbackPolicyDefaults.makeRule()))
        let suspends = try painEngine.evaluate(PainFeedbackInput(level: level)).suspendsLoadProgression

        let double = try ProgressionEngine(config: DoubleProgressionConfig(rule: DoubleProgressionDefaults.makeRule()))
        let set = try SetRecord(exerciseID: ExerciseID(), weight: 40, unit: .kilograms, reps: 12, painFeedback: pain, lifecycle: .completed)
        let doubleEval = try double.evaluate(ProgressionEvaluationInput(
            prescription: prescription, performedSets: [set], currentWeight: 40, unit: .kilograms,
            availableIncrement: 2.5, loadability: .discreteIncrements, hasRecentSignificantDrop: false
        ))

        let strength = try StrengthProgressionEngine(config: StrengthProgressionConfig(rule: StrengthProgressionDefaults.makeRule()))
        let strengthEval = try strength.evaluate(StrengthProgressionInput(
            strategy: .linearLoad, prescription: prescription,
            performed: [StrengthSetEvidence(isTopSet: false, weight: 40, reps: 12, rir: nil, perceivedDifficulty: nil, painFeedback: pain)],
            currentWeight: 40, unit: .kilograms, availableIncrement: 2.5
        ))

        #expect(suspends == pain.blocksProgression)
        #expect(doubleEval.blockedByPain == pain.blocksProgression)
        #expect((doubleEval.outcome == .hold(weight: 40)) == pain.blocksProgression)
        #expect((strengthEval.decision == .holdLoad(weight: 40)) == pain.blocksProgression)
    }

    @Test("Antes una molestia de 2 dejaba subir la carga; ahora es moderado y no sube")
    func legacyLowDiscomfortNowHolds() throws {
        let pain = try decode(#"{"kind":"discomfort","severity":2,"muscle":"chest"}"#)
        #expect(pain.level == .moderate)
        let prescription = try SetPrescription(targetRepRange: 8...12, loadUnit: .kilograms, restSeconds: 90...120)
        let set = try SetRecord(exerciseID: ExerciseID(), weight: 40, unit: .kilograms, reps: 12, painFeedback: pain, lifecycle: .completed)
        let engine = try ProgressionEngine(config: DoubleProgressionConfig(rule: DoubleProgressionDefaults.makeRule()))
        let eval = try engine.evaluate(ProgressionEvaluationInput(
            prescription: prescription, performedSets: [set], currentWeight: 40, unit: .kilograms,
            availableIncrement: 2.5, loadability: .discreteIncrements, hasRecentSignificantDrop: false
        ))
        #expect(eval.outcome == .hold(weight: 40))
    }
}
