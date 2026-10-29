//
//  RestrictionEditorTests.swift
//  PRDomainTests
//
//  SCRUM-36: lo que se hace desde Perfil › Restricciones (agregar, editar, evitar o permitir
//  un ejercicio, resolver) y lo que hace el cuestionario con las resueltas. Decisiones de
//  Jesús (2026-10-29): resolver desde activa con confirmación; desmarcar resuelve y no borra;
//  permitir sólo con origen profesional; el lado se guarda pero el plan cuida la zona.
//

import Foundation
import Testing
@testable import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)
private let later = now.addingTimeInterval(7 * 86_400)
private let editor = RestrictionEditor()

/// IDs fijos para que las pruebas sean deterministas.
private func ids(_ values: Int...) -> () -> RestrictionID {
    var queue = values.map { RestrictionID(rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0)) ?? UUID()) }
    return { queue.isEmpty ? RestrictionID() : queue.removeFirst() }
}

private let curl = ExerciseID()
private let pushdown = ExerciseID()

private func exercise(_ id: ExerciseID, _ pattern: MovementPattern) throws -> Exercise {
    Exercise(
        id: id, canonicalName: "Ejercicio", movementPattern: pattern,
        primaryMuscles: [try MuscleContribution(muscleGroupID: .biceps, activation: 1)],
        equipment: .dumbbell, jointClass: .singleJoint, stabilityDemand: .low, skillDemand: .low,
        systemicFatigueCost: try FatigueCost(normalized: 0.25), loadability: .discreteIncrements,
        defaultRoles: [.accessoryIsolation], substitutionFamilyID: ExerciseFamilyID()
    )
}

@Suite("SCRUM-36 · Editar restricciones desde Perfil")
struct RestrictionEditorTests {

    @Test("Agregar una zona: queda activa con los patrones y la etiqueta de la tabla, el lado y la nota limpia")
    func addZone() throws {
        let result = try editor.adding(
            .elbow, details: RestrictionDetails(side: .left, notes: "  Me molesta al bajar  "),
            to: [], explicitlyConfirmed: false, now: now, newID: ids(1)
        )
        let elbow = try #require(result.first)
        #expect(result.count == 1)
        #expect(elbow.status == .active)
        #expect(elbow.source == .userReported)
        #expect(elbow.side == .left)
        #expect(elbow.forbiddenPatterns == BodyRegionRestrictionRule.forbiddenPatterns(for: .elbow))
        #expect(elbow.restrictionTags == [.elbow])
        #expect(elbow.notes == "Me molesta al bajar")
        #expect(elbow.startDate == now)
    }

    @Test("Una zona en vigor no se duplica: se pide abrir la existente; una resuelta sí deja agregar otra")
    func noDuplicates() throws {
        let first = try editor.adding(.knee, details: RestrictionDetails(), to: [], explicitlyConfirmed: false, now: now, newID: ids(1))
        let existing = try #require(first.first?.id)
        #expect(throws: RestrictionEditError.alreadyInForce(existing)) {
            try editor.adding(.knee, details: RestrictionDetails(side: .right), to: first, explicitlyConfirmed: false, now: now)
        }
        let resolved = try editor.resolving(existing, in: first, explicitlyConfirmed: true, now: later)
        let again = try editor.adding(.knee, details: RestrictionDetails(), to: resolved, explicitlyConfirmed: false, now: later, newID: ids(2))
        #expect(again.count == 2, "La resuelta queda en el historial")
        #expect(again.filter(\.isInForce).count == 1)
    }

    @Test("Origen profesional: sin confirmación no se guarda nada (RN-020); con ella, con su fecha de revisión")
    func professionalNeedsConfirmation() throws {
        let details = RestrictionDetails(source: .professionalGuidance, reviewDate: later)
        #expect(throws: RestrictionEditError.needsExplicitConfirmation) {
            try editor.adding(.lumbar, details: details, to: [], explicitlyConfirmed: false, now: now)
        }
        let saved = try editor.adding(.lumbar, details: details, to: [], explicitlyConfirmed: true, now: now)
        #expect(saved.first?.source == .professionalGuidance)
        #expect(saved.first?.reviewDate == later)
    }

    @Test("Editar: la propia sin confirmar; una profesional (también pasarla a propia) sólo confirmando; una resuelta no")
    func editing() throws {
        let own = try editor.adding(.shoulder, details: RestrictionDetails(), to: [], explicitlyConfirmed: false, now: now, newID: ids(1))
        let id = try #require(own.first?.id)
        let edited = try editor.updating(id, details: RestrictionDetails(side: .right, notes: "Al subir el brazo"), in: own, explicitlyConfirmed: false)
        #expect(edited.first?.side == .right)
        #expect(edited.first?.forbiddenPatterns == own.first?.forbiddenPatterns, "Los patrones de la zona no cambian")

        let professional = try editor.updating(id, details: RestrictionDetails(source: .professionalGuidance), in: edited, explicitlyConfirmed: true)
        #expect(throws: RestrictionEditError.needsExplicitConfirmation) {
            try editor.updating(id, details: RestrictionDetails(source: .userReported), in: professional, explicitlyConfirmed: false)
        }
        let resolved = try editor.resolving(id, in: professional, explicitlyConfirmed: true, now: later)
        #expect(throws: RestrictionEditError.alreadyResolved) {
            try editor.updating(id, details: RestrictionDetails(), in: resolved, explicitlyConfirmed: true)
        }
        #expect(throws: RestrictionEditError.notFound) {
            try editor.updating(RestrictionID(), details: RestrictionDetails(), in: resolved, explicitlyConfirmed: true)
        }
    }

    @Test("Una nota de más de 280 caracteres no se guarda")
    func noteTooLong() {
        let long = String(repeating: "a", count: RestrictionDetails.maxNoteLength + 1)
        #expect(throws: RestrictionEditError.noteTooLong(RestrictionDetails.maxNoteLength)) {
            try editor.adding(.neck, details: RestrictionDetails(notes: long), to: [], explicitlyConfirmed: false, now: now)
        }
    }

    @Test("Evitar un ejercicio vale con cualquier origen; permitir, sólo con origen profesional y confirmación")
    func avoidAndAllow() throws {
        let own = try editor.adding(.elbow, details: RestrictionDetails(), to: [], explicitlyConfirmed: false, now: now, newID: ids(1))
        let id = try #require(own.first?.id)
        let avoided = try editor.avoiding(pushdown, in: id, restrictions: own, explicitlyConfirmed: false)
        #expect(avoided.first?.forbiddenExerciseIDs == [pushdown])
        #expect(throws: RestrictionEditError.allowRequiresProfessional) {
            try editor.allowing(curl, in: id, restrictions: avoided, explicitlyConfirmed: true)
        }

        let professional = try editor.updating(id, details: RestrictionDetails(source: .professionalGuidance), in: avoided, explicitlyConfirmed: true)
        #expect(throws: RestrictionEditError.needsExplicitConfirmation) {
            try editor.allowing(curl, in: id, restrictions: professional, explicitlyConfirmed: false)
        }
        let allowed = try editor.allowing(pushdown, in: id, restrictions: professional, explicitlyConfirmed: true)
        #expect(allowed.first?.allowedExerciseIDs == [pushdown])
        #expect(allowed.first?.forbiddenExerciseIDs.isEmpty == true, "Permitir quita el mismo ejercicio de los evitados")
        let removed = try editor.removing(pushdown, from: id, restrictions: allowed, explicitlyConfirmed: true)
        #expect(removed.first?.allowedExerciseIDs.isEmpty == true)
    }

    @Test("Un permiso sólo refina su restricción: si otra lo prohíbe, sigue fuera (SCRUM-31)")
    func allowOnlyRefinesItsOwnRestriction() throws {
        let curlExercise = try exercise(curl, .elbowFlexion)
        var restrictions = try editor.adding(
            .elbow, details: RestrictionDetails(source: .professionalGuidance), to: [], explicitlyConfirmed: true, now: now, newID: ids(1)
        )
        let elbow = try #require(restrictions.first?.id)
        #expect(RestrictionPolicyEngine.verdict(for: curlExercise, under: restrictions) != .allowed)
        restrictions = try editor.allowing(curl, in: elbow, restrictions: restrictions, explicitlyConfirmed: true)
        #expect(RestrictionPolicyEngine.verdict(for: curlExercise, under: restrictions) == .allowed)

        restrictions = try editor.adding(.wrist, details: RestrictionDetails(), to: restrictions, explicitlyConfirmed: false, now: now, newID: ids(2))
        let wrist = try #require(restrictions.last?.id)
        restrictions = try editor.avoiding(curl, in: wrist, restrictions: restrictions, explicitlyConfirmed: false)
        #expect(RestrictionPolicyEngine.verdict(for: curlExercise, under: restrictions) != .allowed)
    }

    @Test("Resolver: siempre con confirmación; guarda la fecha, deja de limitar y queda en la lista")
    func resolving() throws {
        let own = try editor.adding(.ankle, details: RestrictionDetails(), to: [], explicitlyConfirmed: false, now: now, newID: ids(1))
        let id = try #require(own.first?.id)
        #expect(throws: RestrictionEditError.needsExplicitConfirmation) {
            try editor.resolving(id, in: own, explicitlyConfirmed: false, now: later)
        }
        let resolved = try editor.resolving(id, in: own, explicitlyConfirmed: true, now: later)
        let ankle = try #require(resolved.first)
        #expect(resolved.count == 1, "Nunca se borra")
        #expect(ankle.status == .resolved)
        #expect(ankle.resolvedDate == later)
        #expect(!ankle.isInForce)
        #expect(throws: RestrictionEditError.alreadyResolved) {
            try editor.resolving(id, in: resolved, explicitlyConfirmed: true, now: later)
        }
    }

    @Test("Una fecha de revisión vencida nunca la resuelve: sigue en vigor (RN-004)")
    func reviewDateIsNotRecovery() throws {
        let saved = try editor.adding(
            .hip, details: RestrictionDetails(reviewDate: now.addingTimeInterval(86_400)), to: [], explicitlyConfirmed: false, now: now
        )
        let refreshed = try #require(saved.first?.refreshed(asOf: now.addingTimeInterval(365 * 86_400)))
        #expect(refreshed.status == .reviewNeeded)
        #expect(refreshed.isInForce)
    }
}

@Suite("SCRUM-36 · El cuestionario y las restricciones resueltas")
struct QuestionnaireRestrictionHistoryTests {

    @Test("Volver a marcar una zona resuelta crea una activa nueva; la resuelta queda en el historial")
    func remarkingAResolvedZoneProtectsAgain() throws {
        let resolved = TrainingRestriction(
            bodyRegion: .elbow, startDate: now, status: .resolved,
            forbiddenPatterns: [.elbowFlexion, .elbowExtension], resolvedDate: now
        )
        let result = BodyRegionRestrictionRule.restrictions(
            for: RestrictionsAnswer(zones: [.elbow], previous: [resolved]), now: later, newID: ids(9)
        )
        #expect(result.contains(resolved), "La resuelta se conserva tal cual")
        let active = try #require(result.first { $0.bodyRegion == .elbow && $0.isInForce })
        #expect(active.id != resolved.id)
        #expect(active.startDate == later)
    }

    @Test("Desmarcar una zona propia la resuelve con su fecha (no la borra); las profesionales y las resueltas no se tocan")
    func unmarkingResolvesInsteadOfDeleting() throws {
        let own = TrainingRestriction(bodyRegion: .knee, startDate: now, forbiddenPatterns: [.lunge])
        let professional = TrainingRestriction(bodyRegion: .shoulder, startDate: now, source: .professionalGuidance, forbiddenPatterns: [.verticalPress])
        let old = TrainingRestriction(bodyRegion: .wrist, startDate: now, status: .resolved, forbiddenPatterns: [.carry], resolvedDate: now)
        let result = BodyRegionRestrictionRule.restrictions(
            for: RestrictionsAnswer(zones: [], previous: [own, professional, old]), now: later
        )
        #expect(result.count == 3)
        let knee = try #require(result.first { $0.id == own.id })
        #expect(knee.status == .resolved)
        #expect(knee.resolvedDate == later)
        #expect(result.contains(professional), "Desmarcar nunca debilita una profesional")
        #expect(result.contains(old))
    }
}
