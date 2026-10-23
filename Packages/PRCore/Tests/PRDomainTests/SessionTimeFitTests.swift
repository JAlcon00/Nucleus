//
//  SessionTimeFitTests.swift
//  PRDomainTests
//
//  SCRUM-30 (PR-0108): la duración real de la sesión (series, descansos y transiciones) y
//  su ajuste al tiempo elegido. Para una misma sesión con 30, 45, 60, 90 y 180 minutos:
//  cada versión cabe o dice que no cabe, conserva anclas y prioritarios, nunca agrega
//  series y mantiene el orden. Lo opcional sale primero y los accesorios se reducen desde
//  el final.
//

import Foundation
import Testing
import PRDomain

private func prescription(warmup: Bool = false) throws -> SetPrescription {
    var rx = try SetPrescription(targetRepRange: 8...12, targetRIR: 1...2, loadUnit: .kilograms, restSeconds: 60...90)
    rx.isWarmup = warmup
    return rx
}

/// Sesión con `sets` series de trabajo por ejercicio (y calentamientos opcionales), en orden.
private func session(_ exercises: [(ExerciseID, Int)], warmups: [ExerciseID: Int] = [:]) throws -> SessionTemplate {
    var planned: [PlannedSet] = []
    for (id, sets) in exercises {
        for _ in 0..<(warmups[id] ?? 0) { planned.append(PlannedSet(exerciseID: id, prescription: try prescription(warmup: true))) }
        for _ in 0..<sets { planned.append(PlannedSet(exerciseID: id, prescription: try prescription())) }
    }
    return SessionTemplate(title: "Upper A", plannedSets: planned)
}

private func order(_ template: SessionTemplate) -> [ExerciseID] {
    var seen: Set<ExerciseID> = []
    return template.plannedSets.map(\.exerciseID).filter { seen.insert($0).inserted }
}

private func workSets(_ id: ExerciseID, _ template: SessionTemplate) -> Int {
    template.plannedSets.filter { $0.exerciseID == id && !$0.prescription.isWarmup }.count
}

// Con los valores por defecto: 60 s por serie, 90 s de descanso entre series y 30 s de
// transición entre ejercicios. 4 series = 4×60 + 3×90 = 510 s por ejercicio.
private let anchorA = ExerciseID()
private let anchorB = ExerciseID()
private let accessories = [ExerciseID(), ExerciseID(), ExerciseID(), ExerciseID()]
private let roles = SessionTimeRoles(anchors: [anchorA, anchorB])

/// 2 anclas + 4 accesorios × 4 series: 6 × 510 + 5 × 30 = 3 210 s → 54 min.
private func fullSession() throws -> SessionTemplate {
    try session([(anchorA, 4), (anchorB, 4)] + accessories.map { ($0, 4) })
}

@Suite("Duración real y ajuste a mi tiempo (SCRUM-30)")
struct SessionTimeFitTests {
    private let fitter = SessionTimeFitter()

    @Test("La duración cuenta series, descansos y transiciones")
    func realDuration() throws {
        let template = try fullSession()
        #expect(fitter.seconds(of: template) == 3_210)
        #expect(fitter.minutes(of: template) == 54, "Se redondea hacia arriba")
        #expect(fitter.minutes(of: SessionTemplate(title: "Vacía", plannedSets: [])) == 0)
    }

    @Test("Con 30, 45, 60, 90 y 180 minutos: cabe o lo dice, conserva anclas, nunca agrega series y mantiene el orden")
    func sameSessionAllBudgets() throws {
        let template = try fullSession()
        for budget in [30, 45, 60, 90, 180] {
            let (fitted, adjustment) = fitter.fit(template, budgetMinutes: budget, roles: roles, goal: .hypertrophy, phase: .maintenance)
            #expect(adjustment.budgetMinutes == budget)
            #expect(adjustment.originalMinutes == 54)
            #expect(fitted.id == template.id, "Mismo ID: retomar tras un cierre da la misma sesión")
            for anchor in [anchorA, anchorB] {
                #expect(workSets(anchor, fitted) == workSets(anchor, template), "\(budget) min: las anclas no se tocan")
            }
            for id in order(template) {
                #expect(workSets(id, fitted) <= workSets(id, template), "\(budget) min: nunca se agregan series")
            }
            let kept = Set(order(fitted))
            #expect(order(fitted) == order(template).filter { kept.contains($0) }, "\(budget) min: el orden se conserva")
            switch adjustment.fit {
            case .fits:
                #expect(fitted == template, "\(budget) min: si ya cabe no se toca")
            case .trimmed:
                #expect(fitter.minutes(of: fitted) <= budget, "\(budget) min: recortada cabe")
            case .doesNotFit:
                Issue.record("\(budget) min: esta sesión sí cabe recortada")
            }
        }
    }

    @Test("Con más tiempo no se agregan series; como mucho movilidad, y cardio sólo si encaja con la fase")
    func extraTimeNeverAddsVolume() throws {
        let template = try fullSession()
        let maintenance = fitter.fit(template, budgetMinutes: 180, roles: roles, goal: .hypertrophy, phase: .maintenance)
        #expect(maintenance.template == template)
        #expect(maintenance.adjustment.fit == .fits(spareMinutes: 126, suggestions: [.mobility]))

        let deficit = fitter.fit(template, budgetMinutes: 90, roles: roles, goal: .hypertrophy, phase: .deficit)
        #expect(deficit.template == template)
        #expect(deficit.adjustment.fit == .fits(spareMinutes: 36, suggestions: [.mobility, .cardio]))

        let tight = fitter.fit(template, budgetMinutes: 55, roles: roles, goal: .hypertrophy, phase: .deficit)
        #expect(tight.adjustment.fit == .fits(spareMinutes: 1, suggestions: []), "Si no alcanza para nada, no se sugiere nada")
    }

    @Test("45 minutos: se reducen los accesorios empezando por el último")
    func reducesFromTheEnd() throws {
        let template = try fullSession()
        // 3 210 s → el último 4→2 (2 910), 2→1 (2 760), el penúltimo 4→2 (2 460 ≤ 2 700).
        let (fitted, adjustment) = fitter.fit(template, budgetMinutes: 45, roles: roles, goal: .hypertrophy, phase: .maintenance)
        #expect(adjustment.fit == .trimmed(removed: [], reduced: [
            SetReduction(exerciseID: accessories[2], from: 4, to: 2),
            SetReduction(exerciseID: accessories[3], from: 4, to: 1),
        ]))
        #expect(workSets(accessories[0], fitted) == 4)
        #expect(workSets(accessories[1], fitted) == 4)
        #expect(fitter.minutes(of: fitted) == 41)
    }

    @Test("Si ni recortada cabe lo dice con los minutos que necesita y no quita anclas")
    func doesNotFitKeepsAnchors() throws {
        let anchors = [ExerciseID(), ExerciseID(), ExerciseID(), ExerciseID()]
        let extra = [ExerciseID(), ExerciseID()]
        let template = try session(anchors.map { ($0, 4) } + extra.map { ($0, 4) })
        // Sólo las anclas: 4 × 510 + 3 × 30 = 2 130 s → 36 min.
        let (fitted, adjustment) = fitter.fit(
            template, budgetMinutes: 30, roles: SessionTimeRoles(anchors: Set(anchors)), goal: .hypertrophy, phase: .maintenance
        )
        #expect(adjustment.fit == .doesNotFit(neededMinutes: 36, removed: extra, reduced: []))
        #expect(order(fitted) == anchors)
        #expect(anchors.allSatisfy { workSets($0, fitted) == 4 })
        #expect(adjustment.removed == extra)
    }

    @Test("Lo opcional sale primero; un prioritario no se recorta")
    func optionalFirstPriorityProtected() throws {
        let anchor = ExerciseID(), accessory = ExerciseID(), mobility = ExerciseID(), priority = ExerciseID()
        // 3 × 510 + 2 × 30 = 1 590 s; con 26 min (1 560) basta con quitar lo opcional.
        let withOptional = try session([(anchor, 4), (accessory, 4), (mobility, 4)])
        let first = fitter.fit(
            withOptional, budgetMinutes: 26,
            roles: SessionTimeRoles(anchors: [anchor], optional: [mobility]), goal: .hypertrophy, phase: .maintenance
        )
        #expect(first.adjustment.fit == .trimmed(removed: [mobility], reduced: []))
        #expect(workSets(accessory, first.template) == 4, "El accesorio no se toca si basta con lo opcional")

        let withPriority = try session([(anchor, 4), (priority, 4), (accessory, 4)])
        let second = fitter.fit(
            withPriority, budgetMinutes: 20,
            roles: SessionTimeRoles(anchors: [anchor], priority: [priority]), goal: .hypertrophy, phase: .maintenance
        )
        #expect(workSets(priority, second.template) == 4, "El músculo con énfasis conserva sus series")
        #expect(workSets(accessory, second.template) < 4)
    }

    @Test("Al reducir se conserva el calentamiento y queda al menos una serie de trabajo")
    func keepsWarmupAndOneWorkSet() throws {
        let anchor = ExerciseID(), accessory = ExerciseID()
        // Ancla 510 + accesorio (1 cal. + 3) 510 + 30 = 1 050 s; con 15 min el accesorio baja a 2.
        let template = try session([(anchor, 4), (accessory, 3)], warmups: [accessory: 1])
        let (fitted, adjustment) = fitter.fit(
            template, budgetMinutes: 15, roles: SessionTimeRoles(anchors: [anchor]), goal: .hypertrophy, phase: .maintenance
        )
        let kept = fitted.plannedSets.filter { $0.exerciseID == accessory }
        #expect(kept.map(\.prescription.isWarmup) == [true, false])
        #expect(adjustment.fit == .trimmed(removed: [], reduced: [SetReduction(exerciseID: accessory, from: 3, to: 1)]))
    }

    @Test("El tiempo elegido sólo vale de 30 a 240 minutos y sólo el día en que se eligió")
    func choiceValidityAndDay() throws {
        let zone = try #require(TimeZone(identifier: "America/Mexico_City"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let monday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
        let lateMonday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 23, minute: 50)))
        let tuesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 0, minute: 10)))

        #expect(SessionTimeChoice(minutes: 20, day: monday) == nil)
        #expect(SessionTimeChoice(minutes: 241, day: monday) == nil)
        let choice = try #require(SessionTimeChoice(minutes: 30, day: monday))
        #expect(choice.applies(on: lateMonday, timeZone: zone))
        #expect(!choice.applies(on: tuesday, timeZone: zone), "Al día siguiente ya no aplica")

        // Un valor guardado fuera de rango se lee sin fallar, pero nunca aplica.
        let stored = Data(#"{"minutes":5,"day":0}"#.utf8)
        let decoded = try JSONDecoder().decode(SessionTimeChoice.self, from: stored)
        #expect(!decoded.applies(on: Date(timeIntervalSinceReferenceDate: 0), timeZone: zone))
    }
}
