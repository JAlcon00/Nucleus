//
//  IntensityAdvisorTests.swift
//  PRDomainTests
//
//  SCRUM-200: RIR por tipo de ejercicio y recomendación de dropset.
//

import Foundation
import Testing
import PRDomain

/// Ejercicio mínimo con lo que la regla usa: articulaciones, equipo y tipo de carga.
private func exercise(
    _ jointClass: JointClass,
    equipment: EquipmentType,
    loadability: Loadability,
    pattern: MovementPattern = .squat,
    tags: Set<RestrictionTag> = []
) throws -> Exercise {
    try Exercise(
        canonicalName: "Ejercicio",
        movementPattern: pattern,
        primaryMuscles: [MuscleContribution(muscleGroupID: .quadriceps, activation: 1.0)],
        equipment: equipment,
        jointClass: jointClass,
        stabilityDemand: .moderate,
        skillDemand: .moderate,
        systemicFatigueCost: FatigueCost(normalized: 0.5),
        loadability: loadability,
        defaultRoles: [],
        contraindicationTags: tags,
        substitutionFamilyID: ExerciseFamilyID()
    )
}

@Suite("Intensidad: RIR por tipo y dropset (SCRUM-200)")
struct IntensityAdvisorTests {
    private let advisor = IntensityAdvisor()

    @Test("RIR objetivo: barra libre compuesta 2, otro compuesto 1–2, aislado 0–1")
    func targetRIRByClass() throws {
        let squat = try exercise(.multiJoint, equipment: .barbell, loadability: .discreteIncrements)
        let legPress = try exercise(.multiJoint, equipment: .machine, loadability: .fixedStack)
        let curl = try exercise(.singleJoint, equipment: .dumbbell, loadability: .discreteIncrements)
        #expect(advisor.intensityClass(of: squat) == .heavyBarbellCompound)
        #expect(advisor.targetRIR(for: squat) == 2...2)
        #expect(advisor.intensityClass(of: legPress) == .compound)
        #expect(advisor.targetRIR(for: legPress) == 1...2)
        #expect(advisor.intensityClass(of: curl) == .isolation)
        #expect(advisor.targetRIR(for: curl) == 0...1)
    }

    @Test("Dropset: sí en aislados y en compuestos de carga fija (sólo última serie)")
    func dropsetRecommended() throws {
        let legCurl = try exercise(.singleJoint, equipment: .machine, loadability: .fixedStack)
        let dumbbellCurl = try exercise(.singleJoint, equipment: .dumbbell, loadability: .discreteIncrements)
        let legPress = try exercise(.multiJoint, equipment: .machine, loadability: .fixedStack)
        for item in [legCurl, dumbbellCurl, legPress] {
            #expect(advisor.advice(for: item, experience: .intermediate).dropset == .recommendedOnLastSet)
        }
    }

    @Test("Dropset: nunca con barra libre pesada, peso libre compuesto ni peso corporal")
    func dropsetBlockedByExercise() throws {
        let squat = try exercise(.multiJoint, equipment: .barbell, loadability: .discreteIncrements)
        let dumbbellPress = try exercise(.multiJoint, equipment: .dumbbell, loadability: .discreteIncrements)
        let pullUp = try exercise(.multiJoint, equipment: .bodyweight, loadability: .bodyweight)
        let plank = try exercise(.singleJoint, equipment: .bodyweight, loadability: .bodyweight)
        #expect(advisor.advice(for: squat, experience: .advanced).dropset == .notRecommended(.heavyFreeBarbell))
        #expect(advisor.advice(for: dumbbellPress, experience: .advanced).dropset == .notRecommended(.freeWeightCompound))
        #expect(advisor.advice(for: pullUp, experience: .advanced).dropset == .notRecommended(.bodyweight))
        #expect(advisor.advice(for: plank, experience: .advanced).dropset == .notRecommended(.bodyweight))
    }

    @Test("Dropset: no para novato ni principiante; sí desde intermedio")
    func dropsetNeedsExperience() throws {
        let legCurl = try exercise(.singleJoint, equipment: .machine, loadability: .fixedStack)
        #expect(advisor.advice(for: legCurl, experience: .novice).dropset == .notRecommended(.experience))
        #expect(advisor.advice(for: legCurl, experience: .beginner).dropset == .notRecommended(.experience))
        for level in [ExperienceLevel.intermediate, .advanced, .competitive] {
            #expect(advisor.advice(for: legCurl, experience: level).dropset == .recommendedOnLastSet)
        }
    }

    @Test("Prioridad: restricción > descarga > experiencia > tipo de ejercicio")
    func blockerPriority() throws {
        let squat = try exercise(.multiJoint, equipment: .barbell, loadability: .discreteIncrements)
        #expect(advisor.advice(for: squat, experience: .novice, isDeload: true, isRestricted: true).dropset == .notRecommended(.restriction))
        #expect(advisor.advice(for: squat, experience: .novice, isDeload: true).dropset == .notRecommended(.deload))
        #expect(advisor.advice(for: squat, experience: .novice).dropset == .notRecommended(.experience))
        // El RIR no cambia por el contexto: lo ajusta la descarga en su propio motor.
        #expect(advisor.advice(for: squat, experience: .novice, isDeload: true).targetRIR == 2...2)
    }

    @Test("Restricción activa: por patrón, por ID o por etiqueta; resuelta o permitida no cuenta")
    func restrictionMatching() throws {
        let squat = try exercise(.multiJoint, equipment: .barbell, loadability: .discreteIncrements, pattern: .squat, tags: [.knee])
        let byPattern = TrainingRestriction(bodyRegion: .knee, forbiddenPatterns: [.squat])
        let byTag = TrainingRestriction(bodyRegion: .knee, restrictionTags: [.knee])
        let byID = TrainingRestriction(bodyRegion: .knee, forbiddenExerciseIDs: [squat.id])
        let resolved = TrainingRestriction(bodyRegion: .knee, status: .resolved, forbiddenPatterns: [.squat])
        let allowed = TrainingRestriction(bodyRegion: .knee, forbiddenPatterns: [.squat], allowedExerciseIDs: [squat.id])
        let unrelated = TrainingRestriction(bodyRegion: .shoulder, forbiddenPatterns: [.verticalPress], restrictionTags: [.shoulder])
        for restriction in [byPattern, byTag, byID] {
            #expect(IntensityAdvisor.isRestricted(squat, by: [restriction]))
        }
        for restriction in [resolved, allowed, unrelated] {
            #expect(!IntensityAdvisor.isRestricted(squat, by: [restriction]))
        }
    }

    @Test("Los rangos salen de la configuración, no del código que decide")
    func configurable() throws {
        let custom = IntensityAdvisor(config: IntensityPolicyConfig(isolationRIR: 1...2, dropsetMinimumExperience: .advanced))
        let legCurl = try exercise(.singleJoint, equipment: .machine, loadability: .fixedStack)
        #expect(custom.targetRIR(for: legCurl) == 1...2)
        #expect(custom.advice(for: legCurl, experience: .intermediate).dropset == .notRecommended(.experience))
    }
}
