//
//  RestrictionManagerTests.swift
//  PRDomainTests
//
//  Created by PR.
//
//  Tests para la gestión determinista de restricciones (PR-1401): create/edit/review/
//  resolve, userReported vs professionalGuidance, y reviewDate sin auto-resolución.
//  SCRUM-36 (decisión 1 de Jesús, 2026-10-29) cambió a propósito dos pruebas: una activa ya
//  se puede resolver, y resolver siempre pide confirmación explícita y guarda la fecha.
//

import XCTest
@testable import PRDomain

final class RestrictionManagerTests: XCTestCase {
    private let manager = RestrictionManager()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func userDraft() -> RestrictionDraft {
        RestrictionDraft(
            bodyRegion: .shoulder,
            side: .right,
            source: .userReported,
            reviewDate: now.addingTimeInterval(86400 * 7),
            forbiddenPatterns: [.verticalPress],
            notes: "Hombro derecho"
        )
    }

    private func profDraft() -> RestrictionDraft {
        RestrictionDraft(
            bodyRegion: .lumbar,
            source: .professionalGuidance,
            forbiddenPatterns: [.hinge]
        )
    }

    // MARK: - Create

    func testCreateUserReportedActive() throws {
        let r = try manager.create(from: userDraft(), explicitlyConfirmed: false, now: now)
        XCTAssertEqual(r.status, .active)
        XCTAssertEqual(r.source, .userReported)
        XCTAssertEqual(r.bodyRegion, .shoulder)
        XCTAssertEqual(r.side, .right)
        XCTAssertTrue(r.forbids(.verticalPress))
    }

    func testCreateEmptyRestrictionThrows() {
        XCTAssertThrowsError(try manager.create(from: RestrictionDraft(bodyRegion: .knee), explicitlyConfirmed: false)) { error in
            XCTAssertEqual(error as? RestrictionManagerError, .emptyRestriction)
        }
    }

    func testCreateProfessionalRequiresExplicitConfirmation() {
        XCTAssertThrowsError(try manager.create(from: profDraft(), explicitlyConfirmed: false)) { error in
            XCTAssertEqual(error as? RestrictionManagerError, .needsExplicitConfirmation)
        }
    }

    func testCreateProfessionalConfirmedSuccceeds() throws {
        let r = try manager.create(from: profDraft(), explicitlyConfirmed: true, now: now)
        XCTAssertEqual(r.source, .professionalGuidance)
        XCTAssertEqual(r.status, .active)
    }

    // MARK: - Update

    func testUpdateAppliesEdits() throws {
        let original = try XCTUnwrap(try manager.create(from: userDraft(), explicitlyConfirmed: false, now: now))
        var draft = userDraft()
        draft.notes = "Actualizado"
        draft.forbiddenPatterns = [.verticalPress, .horizontalPress]
        let updated = try manager.update(original, with: draft, explicitlyConfirmed: false)
        XCTAssertEqual(updated.notes, "Actualizado")
        XCTAssertTrue(updated.forbids(.horizontalPress))
        XCTAssertEqual(updated.id, original.id)
    }

    // MARK: - Review: no auto-resolve

    func testReviewBeforeDateStaysActive() throws {
        let r = try XCTUnwrap(try manager.create(from: userDraft(), explicitlyConfirmed: false, now: now))
        let before = manager.review(r, asOf: now.addingTimeInterval(86400))
        XCTAssertEqual(before.status, .active)
    }

    func testReviewAfterDateBecomesReviewNeeded() throws {
        let r = try XCTUnwrap(try manager.create(from: userDraft(), explicitlyConfirmed: false, now: now))
        let after = manager.review(r, asOf: now.addingTimeInterval(86400 * 10))
        XCTAssertEqual(after.status, .reviewNeeded)
    }

    func testReviewNeverAutoResolves() throws {
        let r = try XCTUnwrap(try manager.create(from: userDraft(), explicitlyConfirmed: false, now: now))
        let farFuture = manager.review(r, asOf: now.addingTimeInterval(86400 * 3650))
        XCTAssertEqual(farFuture.status, .reviewNeeded)
        XCTAssertNotEqual(farFuture.status, .resolved)
    }

    // MARK: - Resolve

    /// Antes: "resolver exige revisión primero". Desde SCRUM-36 una activa se resuelve por
    /// acción explícita ("Ya no me molesta"), nunca sin confirmar.
    func testResolveActiveRequiresExplicitConfirmation() throws {
        let r = try XCTUnwrap(try manager.create(from: userDraft(), explicitlyConfirmed: false, now: now))
        XCTAssertThrowsError(try manager.resolve(r, explicitlyConfirmed: false)) { error in
            XCTAssertEqual(error as? RestrictionManagerError, .needsExplicitConfirmation)
        }
        let resolved = try manager.resolve(r, explicitlyConfirmed: true, now: now.addingTimeInterval(86400))
        XCTAssertEqual(resolved.status, .resolved)
        XCTAssertEqual(resolved.resolvedDate, now.addingTimeInterval(86400))
        XCTAssertFalse(resolved.isInForce)
    }

    func testResolveAfterReviewWorks() throws {
        let r = try XCTUnwrap(try manager.create(from: userDraft(), explicitlyConfirmed: false, now: now))
        let reviewed = manager.review(r, asOf: now.addingTimeInterval(86400 * 10))
        let resolved = try manager.resolve(reviewed, explicitlyConfirmed: true)
        XCTAssertEqual(resolved.status, .resolved)
    }

    func testResolveProfessionalRequiresConfirmation() throws {
        let r = try XCTUnwrap(try manager.create(from: profDraft(), explicitlyConfirmed: true, now: now))
        let reviewed = manager.review(r, asOf: now.addingTimeInterval(86400 * 10))
        XCTAssertThrowsError(try manager.resolve(reviewed, explicitlyConfirmed: false)) { error in
            XCTAssertEqual(error as? RestrictionManagerError, .needsExplicitConfirmation)
        }
    }

    func testResolvedIsTerminal() throws {
        let r = try XCTUnwrap(try manager.create(from: userDraft(), explicitlyConfirmed: false, now: now))
        let resolved = try manager.resolve(manager.review(r, asOf: now.addingTimeInterval(86400 * 10)), explicitlyConfirmed: true)
        XCTAssertThrowsError(try manager.resolve(resolved, explicitlyConfirmed: true))
    }

    // MARK: - Fifths & persistence helpers

    func testStatusTransitionsAreValidated() {
        XCTAssertTrue(RestrictionStatus.active.canTransition(to: .reviewNeeded))
        XCTAssertTrue(RestrictionStatus.active.canTransition(to: .resolved), "SCRUM-36: por acción explícita")
        XCTAssertFalse(RestrictionStatus.resolved.canTransition(to: .active), "Una resuelta es historial")
        XCTAssertTrue(RestrictionStatus.reviewNeeded.canTransition(to: .resolved))
        XCTAssertTrue(RestrictionStatus.reviewNeeded.canTransition(to: .active))
    }
}