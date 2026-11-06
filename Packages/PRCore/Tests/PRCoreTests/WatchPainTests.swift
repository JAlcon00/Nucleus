//
//  WatchPainTests.swift
//  PRCoreTests
//
//  SCRUM-260 (PR-G009): reportar dolor desde el reloj bloquea la progresión igual que en el
//  iPhone. El reloj no decide ni diagnostica. Con `LocalPersistence` real en un directorio
//  temporal del lado del iPhone.
//

import Foundation
import Testing
import PRCore
import PRDomain

private let now = Date(timeIntervalSince1970: 1_792_670_400)

@MainActor
private final class Rig {
    let link = FakeWorkoutLink()
    let exercise: Exercise
    let persistence: LocalPersistence
    let bridge: PhoneWatchBridge
    let phone: WorkoutSessionCoordinator
    let watch: WatchSessionController
    let session: WorkoutID

    init() async throws {
        exercise = Exercise(
            canonicalName: "Press",
            movementPattern: .horizontalPress,
            primaryMuscles: [try MuscleContribution(muscleGroupID: .chest, activation: 1.0)],
            equipment: .barbell,
            jointClass: .multiJoint,
            stabilityDemand: .moderate,
            skillDemand: .moderate,
            systemicFatigueCost: try FatigueCost(normalized: 0.5),
            loadability: .discreteIncrements,
            defaultRoles: [.primaryCompound],
            substitutionFamilyID: ExerciseFamily(name: "Press", movementPatterns: [.horizontalPress]).id
        )
        let work = try SetPrescription(targetRepRange: 8...10, targetLoad: 60, loadUnit: .kilograms, restSeconds: 60...60)
        let id = exercise.id
        let template = SessionTemplate(title: "Pecho", plannedSets: (0..<3).map { _ in PlannedSet(exerciseID: id, prescription: work) })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pr-watch-pain-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let persistence = try LocalPersistence(rootURL: root, log: PersistenceLog { _ in })
        self.persistence = persistence
        let link = self.link
        bridge = PhoneWatchBridge(link: link, clock: { now }) {
            WatchBridgeStorage(queue: try persistence.pendingOperationQueue(), workouts: try persistence.workoutRepository())
        }
        phone = try await persistence.makeWorkoutCoordinator(
            template: template, exerciseNames: [exercise.id: "Press"], catalog: [exercise], clock: { now }
        )
        bridge.attach(phone)
        _ = phone.start()
        session = try phone.snapshot().session.id
        watch = WatchSessionController(store: WatchLocalStore(store: MemoryRepositoryStore()), link: link, clock: { now })
        await sync()
    }

    /// Entrega al reloj lo último que publicó el iPhone.
    func sync() async {
        await bridge.flush()
        if let latest = link.publishedSnapshots.last { await watch.receive(latest) }
    }

    /// Entrega al iPhone lo que el reloj tenga en el buzón.
    func deliver() async throws {
        for message in watch.state.outbox { try await bridge.handle(message) }
        await sync()
    }
}

@MainActor
@Suite("SCRUM-260 · Reportar dolor desde el reloj")
struct WatchPainTests {

    @Test("Antes de hacer una serie no hay sobre qué reportar")
    func nothingToReport() async throws {
        let rig = try await Rig()
        #expect(!rig.watch.canReportPain)
        await rig.watch.reportPain(.high)
        #expect(rig.watch.saveFailed)
        #expect(rig.watch.reportedPain == nil)
    }

    @Test("Moderado o alto queda en la serie del iPhone y bloquea la progresión", arguments: [PainLevel.moderate, .high])
    func blocksProgression(level: PainLevel) async throws {
        let rig = try await Rig()
        await rig.watch.completeCurrentSet()
        try await rig.deliver()
        await rig.watch.reportPain(level)
        try await rig.deliver()

        let set = try #require(try rig.phone.snapshot().session.sets.last)
        #expect(set.painFeedback?.level == level)
        #expect(set.painFeedback?.blocksProgression == true)
        #expect(rig.phone.painReport?.level == level, "El iPhone ve lo mismo.")
        #expect(try await rig.persistence.workoutRepository().session(id: rig.session)?.sets.last?.painFeedback?.level == level)
    }

    @Test("Sin dolor o leve no bloquea", arguments: [PainLevel.none, .mild])
    func doesNotBlock(level: PainLevel) async throws {
        let rig = try await Rig()
        await rig.watch.completeCurrentSet()
        await rig.watch.reportPain(level)
        try await rig.deliver()
        #expect(try rig.phone.snapshot().session.sets.last?.painFeedback?.blocksProgression == false)
    }

    @Test("La recomendación es la misma que en el iPhone", arguments: PainLevel.allCases)
    func sameRecommendation(level: PainLevel) async throws {
        let rig = try await Rig()
        await rig.watch.completeCurrentSet()
        try await rig.deliver()
        await rig.watch.reportPain(level)
        let phone = try rig.phone.reportPain(level)
        #expect(rig.watch.painRecommendation == phone)
    }

    @Test("Sin conexión el dolor se guarda con su serie y llega después")
    func offline() async throws {
        let rig = try await Rig()
        await rig.watch.completeCurrentSet()
        await rig.watch.reportPain(.high)
        #expect(rig.watch.state.pendingCount == 2, "Las dos cosas siguen en el buzón.")

        try await rig.deliver()

        #expect(try rig.phone.snapshot().session.sets.count == 1)
        #expect(try rig.phone.snapshot().session.sets.last?.painFeedback?.level == .high)
        #expect(rig.watch.state.pendingCount == 0)
    }

    @Test("Una serie confirmada no suelta su reporte de dolor hasta que el iPhone lo guarde")
    func confirmationKeepsPainReport() async throws {
        let rig = try await Rig()
        await rig.watch.completeCurrentSet()
        try await rig.bridge.handle(try #require(rig.watch.state.outbox.first))
        await rig.watch.reportPain(.high)

        await rig.sync()

        #expect(rig.watch.state.pendingCount == 1, "El reporte sigue pendiente.")
        try await rig.deliver()
        #expect(rig.watch.state.pendingCount == 0)
    }

    @Test("Reportar dos veces la misma serie: gana el último")
    func lastLevelWins() async throws {
        let rig = try await Rig()
        await rig.watch.completeCurrentSet()
        try await rig.deliver()
        await rig.watch.reportPain(.mild)
        await rig.watch.reportPain(.high)
        try await rig.deliver()
        #expect(rig.watch.reportedPain == .high)
        #expect(try rig.phone.snapshot().session.sets.last?.painFeedback?.level == .high)
        #expect(try rig.phone.snapshot().session.sets.count == 1, "No crea otra serie.")
    }

    @Test("Dolor sobre una serie en conflicto no se ignora")
    func painOnConflict() async throws {
        let rig = try await Rig()
        _ = try rig.phone.recordEditedSet(weight: 60, reps: 8, now: now.addingTimeInterval(100))
        await rig.watch.completeCurrentSet()
        await rig.watch.reportPain(.high)
        try await rig.deliver()
        let session = try rig.phone.snapshot().session
        #expect(session.setConflicts?.first?.set.painFeedback?.level == .high)
    }

    @Test("Reportar no agrega pasos: completar sigue siendo una sola acción")
    func optional() async throws {
        let rig = try await Rig()
        await rig.watch.completeCurrentSet()
        #expect(rig.watch.canReportPain)
        #expect(rig.watch.confirmedTaps == 1)
        #expect(rig.watch.reportedPain == nil)
    }
}
