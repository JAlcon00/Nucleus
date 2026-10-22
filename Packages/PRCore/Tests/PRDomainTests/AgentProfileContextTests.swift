//
//  AgentProfileContextTests.swift
//  PRDomainTests
//
//  SCRUM-202 (IA-1): el contexto para la IA sólo existe con consentimiento y nunca
//  lleva el nombre, IDs ni notas libres.
//

import Foundation
import Testing
import PRDomain

private let utc = TimeZone(identifier: "UTC") ?? .current
private let now = Date(timeIntervalSince1970: 1_792_670_400) // 2026-10-22

private func profile(aboutYou: AboutYou?, restrictions: [TrainingRestriction] = []) throws -> OnboardingProfile {
    var profile = try OnboardingProfile(
        goal: .hypertrophy, phase: .deficit, experience: .intermediate,
        trainingDays: [.friday, .monday, .wednesday], usualSessionMinutes: 60, varietyPreference: .balanced
    )
    profile.aboutYou = aboutYou
    profile.restrictions = restrictions
    return profile
}

private func ana() throws -> AboutYou {
    try AboutYou(name: "Ana", birthYear: 1992, sex: .female, heightCentimeters: 165, weight: 61.5, weightUnit: .kilograms)
}

@Suite("Contexto de perfil para la IA (SCRUM-202)")
struct AgentProfileContextTests {
    private let builder = AgentProfileContextBuilder()

    @Test("Sin consentimiento (sin preguntar o rechazado) no hay contexto")
    func noConsentNoContext() throws {
        let profile = try profile(aboutYou: try ana())
        #expect(builder.context(profile: profile, consent: .notAsked, now: now, timeZone: utc) == nil)
        #expect(builder.context(profile: profile, consent: .declined(at: now), now: now, timeZone: utc) == nil)
    }

    @Test("Con consentimiento lleva el perfil completo, con edad y días en orden")
    func grantedContext() throws {
        let context = try #require(builder.context(profile: try profile(aboutYou: try ana()), consent: .granted(at: now), now: now, timeZone: utc))
        #expect(context.ageYears == 34)
        #expect(context.sex == .female)
        #expect(context.heightCentimeters == 165)
        #expect(context.weight == 61.5 && context.weightUnit == .kilograms)
        #expect(context.goal == .hypertrophy && context.phase == .deficit && context.experience == .intermediate)
        #expect(context.trainingDays == [.monday, .wednesday, .friday])
        #expect(context.sessionMinutes == 60 && context.variety == .balanced)
    }

    @Test("Sin \"Sobre ti\" no se manda un perfil a medias")
    func missingAboutYou() throws {
        #expect(builder.context(profile: try profile(aboutYou: nil), consent: .granted(at: now), now: now, timeZone: utc) == nil)
    }

    @Test("Nunca lleva el nombre, IDs ni notas; sólo restricciones activas")
    func minimization() throws {
        let active = TrainingRestriction(
            bodyRegion: .knee, side: .left, forbiddenPatterns: [.squat, .lunge],
            forbiddenExerciseIDs: [ExerciseID()], notes: "me operaron en 2024"
        )
        let resolved = TrainingRestriction(bodyRegion: .shoulder, status: .resolved, forbiddenPatterns: [.verticalPress])
        let context = try #require(builder.context(
            profile: try profile(aboutYou: try ana(), restrictions: [active, resolved]),
            consent: .granted(at: now), now: now, timeZone: utc
        ))
        #expect(context.restrictions == [AgentRestrictionSummary(bodyRegion: .knee, side: .left, forbiddenPatterns: [.squat, .lunge])])
        let json = try #require(String(data: JSONEncoder().encode(context), encoding: .utf8))
        #expect(!json.contains("Ana"), "El nombre nunca sale")
        #expect(!json.contains("me operaron"), "Las notas libres nunca salen")
    }

    @Test("Decisión: sólo aceptado permite compartir; sólo \"sin preguntar\" pide decidir")
    func consentSemantics() {
        #expect(AIDataConsent.granted(at: now).allowsSharing)
        #expect(!AIDataConsent.declined(at: now).allowsSharing)
        #expect(!AIDataConsent.notAsked.allowsSharing)
        #expect(AIDataConsent.notAsked.needsDecision)
        #expect(!AIDataConsent.granted(at: now).needsDecision)
        #expect(!AIDataConsent.declined(at: now).needsDecision)
    }
}
