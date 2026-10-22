//
//  ReadinessEngineTests.swift
//  PRDomainTests
//
//  SCRUM-203 (IA-2): el check-in de sueño sólo puede aligerar el día, con reglas fijas.
//

import Foundation
import Testing
import PRDomain

private let squat = ExerciseID()
private let curl = ExerciseID()
private let raise = ExerciseID()

private func template() throws -> SessionTemplate {
    let warmup = try SetPrescription(targetRepRange: 10...12, restSeconds: 60...60, isWarmup: true)
    let heavy = try SetPrescription(targetRepRange: 5...8, targetRIR: 2...2, targetLoad: 100, restSeconds: 120...180)
    let iso = try SetPrescription(targetRepRange: 10...15, targetRIR: 0...1, targetLoad: 20, restSeconds: 60...90)
    return SessionTemplate(title: "Pierna", plannedSets: [
        PlannedSet(exerciseID: squat, prescription: warmup),
        PlannedSet(exerciseID: squat, prescription: heavy),
        PlannedSet(exerciseID: squat, prescription: heavy),
        PlannedSet(exerciseID: squat, prescription: heavy),
        PlannedSet(exerciseID: curl, prescription: iso),
        PlannedSet(exerciseID: curl, prescription: iso),
        PlannedSet(exerciseID: raise, prescription: iso),
    ])
}

private func jointClass(_ id: ExerciseID) -> JointClass? {
    id == squat ? .multiJoint : .singleJoint
}

@Suite("Disposición del día por sueño (SCRUM-203)")
struct ReadinessEngineTests {
    private let engine = ReadinessEngine()

    @Test("Tabla: horas y calidad → ajuste")
    func adjustmentTable() throws {
        #expect(engine.adjustment(for: nil) == .none, "Sin check-in no hay ajuste")
        #expect(engine.adjustment(for: try SleepCheckIn(day: "d", hours: 7.5, quality: .good)) == .none)
        #expect(engine.adjustment(for: try SleepCheckIn(day: "d", hours: 6, quality: .good)) == .none, "6 h justas no es corto")
        #expect(engine.adjustment(for: try SleepCheckIn(day: "d", hours: 5.5, quality: .good))
                == .lighter(reason: .shortSleep, rirIncrease: 1, isolationSetReduction: 1))
        #expect(engine.adjustment(for: try SleepCheckIn(day: "d", hours: 8, quality: .poor))
                == .lighter(reason: .poorSleep, rirIncrease: 1, isolationSetReduction: 1))
        #expect(engine.adjustment(for: try SleepCheckIn(day: "d", hours: 4, quality: .poor))
                == .lighter(reason: .shortAndPoorSleep, rirIncrease: 1, isolationSetReduction: 1))
    }

    @Test("Horas fuera de rango no se aceptan")
    func invalidHours() {
        #expect(throws: SleepCheckInError.invalidHours(-1)) { try SleepCheckIn(day: "d", hours: -1, quality: .good) }
        #expect(throws: SleepCheckInError.invalidHours(20)) { try SleepCheckIn(day: "d", hours: 20, quality: .good) }
    }

    @Test("Día ligero: RIR +1 en trabajo, una serie menos en aislados con más de una; compuestos intactos")
    func lighterDay() throws {
        let original = try template()
        let adjusted = engine.apply(
            .lighter(reason: .poorSleep, rirIncrease: 1, isolationSetReduction: 1),
            to: original, jointClass: jointClass
        )
        #expect(adjusted.id == original.id, "Misma sesión: se puede retomar")
        let count = { (id: ExerciseID) in adjusted.plannedSets.filter { $0.exerciseID == id && !$0.prescription.isWarmup }.count }
        #expect(count(squat) == 3, "El compuesto conserva sus series")
        #expect(count(curl) == 1, "Aislado con 2 series pierde una")
        #expect(count(raise) == 1, "Aislado con 1 serie se queda con 1")
        let warmups = adjusted.plannedSets.filter(\.prescription.isWarmup)
        #expect(warmups.count == 1 && warmups[0].prescription.targetRIR == nil, "El calentamiento no cambia")
        for planned in adjusted.plannedSets where !planned.prescription.isWarmup {
            let before = try #require(original.plannedSets.first { $0.exerciseID == planned.exerciseID && !$0.prescription.isWarmup })
            let rir = try #require(planned.prescription.targetRIR)
            let oldRIR = try #require(before.prescription.targetRIR)
            #expect(rir == (oldRIR.lowerBound + 1)...(oldRIR.upperBound + 1))
            #expect(planned.prescription.targetLoad == before.prescription.targetLoad, "Nunca cambia la carga")
            #expect(planned.prescription.targetRepRange == before.prescription.targetRepRange, "Ni las repeticiones")
        }
    }

    @Test("Sin ajuste la sesión queda idéntica")
    func noneLeavesSession() throws {
        let original = try template()
        #expect(engine.apply(.none, to: original, jointClass: jointClass) == original)
    }

    @Test("Día local estable para el check-in")
    func dayKey() throws {
        let utc = try #require(TimeZone(identifier: "UTC"))
        let mexico = try #require(TimeZone(identifier: "America/Mexico_City"))
        let lateNight = Date(timeIntervalSince1970: 1_792_717_200) // 2026-10-23 03:00 UTC
        #expect(SleepCheckIn.day(of: lateNight, timeZone: utc) == "2026-10-23")
        #expect(SleepCheckIn.day(of: lateNight, timeZone: mexico) == "2026-10-22", "Cuenta el día local")
    }
}
