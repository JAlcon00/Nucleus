//
//  DataExportTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests del export de datos (RF-030, RNEG-006, PR-0204):
//  - JSON completo y determinista del historial de entrenamiento;
//  - CSV mínimo de workout sets (orden determinista, quoting RFC-4180);
//  - no exporta fields con nombres de secrets/identidad;
//  - casos vacíos y opcionales.
//

import Foundation
import Testing
import PRDomain

@Suite("Data export (PR-0204)")
struct DataExportTests {

    private let engine = ExportEngine()

    private func makeExercise(name: String) throws -> Exercise {
        let family = ExerciseFamily(
            name: name + " family",
            movementPatterns: [.horizontalPress]
        )
        return Exercise(
            canonicalName: name,
            movementPattern: .horizontalPress,
            primaryMuscles: [try MuscleContribution(muscleGroupID: .chest, activation: 1.0)],
            equipment: .barbell,
            jointClass: .multiJoint,
            stabilityDemand: .moderate,
            skillDemand: .moderate,
            systemicFatigueCost: try FatigueCost(normalized: 0.5),
            loadability: .discreteIncrements,
            defaultRoles: Set(ExerciseRole.allCases),
            contraindicationTags: [],
            substitutionFamilyID: family.id
        )
    }

    private func makeSet(
        exercise: ExerciseID,
        weight: Double = 60,
        reps: Int = 10,
        at date: Date,
        rir: Int? = nil,
        pain: PainFeedback? = nil
    ) throws -> SetRecord {
        try SetRecord(
            id: SetRecordID(),
            exerciseID: exercise,
            performedAt: date,
            weight: weight,
            unit: .kilograms,
            reps: reps,
            rir: rir,
            perceivedDifficulty: .manageable,
            painFeedback: pain,
            lifecycle: .completed
        )
    }

    private func makeSession(
        exercise: ExerciseID,
        start: Date,
        setCount: Int = 1
    ) throws -> WorkoutSessionRecord {
        var session = WorkoutSessionRecord(
            startedAt: start,
            endedAt: start.addingTimeInterval(1800),
            lifecycle: .completed
        )
        for i in 0..<setCount {
            session = session.performedSet(try makeSet(exercise: exercise, at: start.addingTimeInterval(Double(i))))
        }
        return session
    }

    private func makeProfile() throws -> UserTrainingProfile {
        try UserTrainingProfile(
            experience: .intermediate,
            goal: .strength,
            phase: .maintenance,
            trainingDaysPerWeek: 3,
            usualSessionMinutes: 60,
            varietyPreference: .balanced,
            coachingDetail: .guided
        )
    }

    private func makeBlock() throws -> TrainingBlock {
        try TrainingBlock(
            name: "Test block",
            goal: .strength,
            phase: .maintenance,
            startDate: .init(timeIntervalSince1970: 1000),
            plannedWeeks: 8,
            progressionPolicy: .loadProgression,
            deloadPolicy: .afterEightWeeks,
            varietyPolicy: try VarietyPolicy(percentStable: 0.7)
        )
    }

    private func makeBundle(
        exercise: Exercise,
        session: WorkoutSessionRecord,
        includeProfile: Bool = true
    ) throws -> ExportBundle {
        let restriction = TrainingRestriction(bodyRegion: .shoulder)
        let gym = GymProfile(name: "Test Gym")
        return ExportBundle(
            schemaVersion: ExportBundleVersion.current,
            exportedAt: Date(timeIntervalSince1970: 5000),
            blocks: [try makeBlock()],
            sessions: [session],
            exercises: [exercise],
            gyms: [gym],
            restrictions: [restriction],
            profile: includeProfile ? try makeProfile() : nil
        )
    }

    // MARK: - JSON completo

    @Test("El bundle JSON contiene todo el historial de entrenamiento (determinista)")
    func jsonBundleIsCompleteAndDeterministic() throws {
        let exercise = try makeExercise(name: "Bench Press")
        let session = try makeSession(exercise: exercise.id, start: Date(timeIntervalSince1970: 10), setCount: 2)

        let bundle1 = try makeBundle(exercise: exercise, session: session)
        let data1 = try engine.jsonData(for: bundle1)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExportBundle.self, from: data1)

        #expect(decoded.sessions.count == 1)
        #expect(decoded.sessions.first?.sets.count == 2, "El export preserva todos los sets de la sesión.")
        #expect(decoded.exercises.count == 1)
        #expect(decoded.blocks.count == 1)
        #expect(decoded.gyms.count == 1)
        #expect(decoded.restrictions.count == 1)
        #expect(decoded.profile != nil)

        // Determinismo: mismo input ⇒ mismo JSON.
        let data2 = try engine.jsonData(for: bundle1)
        #expect(data1 == data2, "El export JSON debe ser determinista para el mismo snapshot.")
    }

    @Test("JSON sin secrets: no contiene nombres de campos prohibidos")
    func jsonExcludesSecretFields() throws {
        let exercise = try makeExercise(name: "Squat")
        let session = try makeSession(exercise: exercise.id, start: Date(timeIntervalSince1970: 20))
        let data = try engine.jsonData(for: try makeBundle(exercise: exercise, session: session))

        #expect(ExportEngine.containsForbiddenSecretFields(inJSON: data) == false,
                "El export de training data no debe transportar secrets.")
    }

    @Test("El guardia detecta un field con nombre de secret inyectado")
    func secretGuardRejectsInjectedSecret() throws {
        let poisoned: [String: Any] = [
            "apiKey": "live-1234",
            "sessions": ["startedAt": "2024-01-01T00:00:00Z"],
        ]
        let data = try JSONSerialization.data(withJSONObject: poisoned)
        #expect(ExportEngine.containsForbiddenSecretFields(inJSON: data) == true)
    }

    // MARK: - CSV de workout sets

    @Test("CSV tiene cabecera y una fila por set, en orden determinista")
    func csvHasHeaderAndOneRowPerSet() throws {
        let exercise = try makeExercise(name: "Bench Press")
        let sessionA = try makeSession(exercise: exercise.id, start: Date(timeIntervalSince1970: 100), setCount: 2)
        let sessionB = try makeSession(exercise: exercise.id, start: Date(timeIntervalSince1970: 50), setCount: 1)

        let csv = engine.workoutSetsCSV(sessions: [sessionA, sessionB])
        let lines = csv.split(separator: "\n")

        #expect(lines.count == 1 + 3, "Cabecera + 3 sets (2+1), independiente del orden de entrada.")
        #expect(lines.first == "sessionID,startedAtISO,exerciseID,weight,unit,reps,rir,difficulty,pain,lifecycle")
        // sessionB (start 50) debe preceder a sessionA (start 100).
        let firstDataLine = String(lines[1])
        #expect(firstDataLine.contains("1970-01-01T00:00:50Z"), "Orden determinista por startedAt.")
    }

    @Test("CSV mantiene un número de columnas estable por fila")
    func csvColumnsAreStablePerRow() throws {
        let exercise = try makeExercise(name: "Bench Press")
        let session = try makeSession(exercise: exercise.id, start: Date(timeIntervalSince1970: 100), setCount: 1)
        let csv = engine.workoutSetsCSV(sessions: [session])
        let line = csv.split(separator: "\n")[1]
        let columns = line.split(separator: ",", omittingEmptySubsequences: false)
        #expect(columns.count == 10, "Cada fila de set exporta exactamente 10 columnas (incluye vacíos).")
    }

    @Test("CSV vacío: sólo la línea de cabecera")
    func csvEmptyHasHeaderOnly() {
        #expect(engine.workoutSetsCSV(sessions: []) == "sessionID,startedAtISO,exerciseID,weight,unit,reps,rir,difficulty,pain,lifecycle")
    }

    @Test("CSV registra rir y pain cuando existen")
    func csvIncludesRirAndPain() throws {
        let exercise = try makeExercise(name: "Squat")
        let date = Date(timeIntervalSince1970: 200)
        var session = WorkoutSessionRecord(startedAt: date, endedAt: date.addingTimeInterval(600), lifecycle: .completed)
        session = session.performedSet(try makeSet(exercise: exercise.id, at: date, rir: 2, pain: PainFeedback.none))

        let csv = engine.workoutSetsCSV(sessions: [session])
        let line = csv.split(separator: "\n")[1]
        let columns = line.split(separator: ",", omittingEmptySubsequences: false)

        #expect(columns[6] == "2", "El rir exportado debe aparecer en la columna 7.")
        #expect(columns[8] == "none", "El pain 'none' debe exportarse en la columna 9.")
        #expect(columns[3] == "60.0", "El peso se exporta como Double.")
    }
}