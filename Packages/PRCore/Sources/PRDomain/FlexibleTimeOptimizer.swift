//
//  FlexibleTimeOptimizer.swift
//  PRDomain
//
//  Created by PR.
//
//  Flexible time optimizer (plan §8, RF-006, PR-0803). Ajusta una sesión a una
//  ventana de tiempo `target ± tolerance` cuando es factible: no recorta de más
//  (sólo lo necesario para entrar en la ventana reusando HardTimeOptimizer) y
//  explica cuando no es factible (sobre el límite aun conservando anchors, o ventana
//  demasiado estrecha). No añade volumen por debajo del umbral (plan §388: extra
//  time es otro PR).
//

import Foundation

/// Clasificación del resultado flexible.
public enum FlexibleStatus: String, Equatable, Sendable {
    /// La duración cae dentro de target ± tolerance sin recortes.
    case inWindow
    /// Queda por debajo del umbral inferior (factible y explicable; no se añade
    /// volumen aquí — ver extra-time PR-0804).
    case under
    /// No es factible entrar en la ventana aun conservando anchors/prioridades, o
    /// la ventana es demasiado estrecha para la granularidad de los sets.
    case notFeasible
}

/// Resultado del optimizador flexible por tiempo.
public struct FlexibleTimeResult: Equatable, Sendable {
    public let kept: [SessionItem]
    public let estimatedSeconds: Int
    public let targetSeconds: Int
    public let toleranceSeconds: Int
    public let status: FlexibleStatus
    public let notes: [String]

    public var lowerBound: Int { max(0, targetSeconds - toleranceSeconds) }
    public var upperBound: Int { targetSeconds + toleranceSeconds }
    public var inWindow: Bool { status == .inWindow }

    public init(
        kept: [SessionItem],
        estimatedSeconds: Int,
        targetSeconds: Int,
        toleranceSeconds: Int,
        status: FlexibleStatus,
        notes: [String]
    ) {
        self.kept = kept
        self.estimatedSeconds = estimatedSeconds
        self.targetSeconds = targetSeconds
        self.toleranceSeconds = toleranceSeconds
        self.status = status
        self.notes = notes
    }
}

/// Ajusta una sesión a una ventana `target ± tolerance` (PR-0803).
public struct FlexibleTimeOptimizer: Sendable {
    public var transitionSeconds: Double

    public init(transitionSeconds: Double = 30) {
        self.transitionSeconds = transitionSeconds
    }

    public func optimize(
        items: [SessionItem],
        targetSeconds: Int,
        toleranceSeconds: Int = 0
    ) -> FlexibleTimeResult {
        var notes: [String] = []
        let lower = max(0, targetSeconds - toleranceSeconds)
        let upper = targetSeconds + toleranceSeconds

        // Estimación completa sin recortes.
        let hard = HardTimeOptimizer(transitionSeconds: transitionSeconds)
        let fullSeconds = hard.sessionSeconds(items)

        if fullSeconds >= lower, fullSeconds <= upper {
            return FlexibleTimeResult(
                kept: items,
                estimatedSeconds: fullSeconds,
                targetSeconds: targetSeconds,
                toleranceSeconds: toleranceSeconds,
                status: .inWindow,
                notes: ["La sesión ya cae dentro de target ± tolerance."]
            )
        }

        if fullSeconds < lower {
            notes.append("La sesión está por debajo del umbral inferior; conforme a la invariante no se añade volumen aquí (ver extra-time).")
            return FlexibleTimeResult(
                kept: items,
                estimatedSeconds: fullSeconds,
                targetSeconds: targetSeconds,
                toleranceSeconds: toleranceSeconds,
                status: .under,
                notes: notes
            )
        }

        // Está por encima: recortar lo justo para entrar por el borde superior.
        notes.append("La sesión excede el límite; se recorta lo necesario para entrar en la ventana.")
        let trimmed = hard.optimize(items: items, limitSeconds: upper, toleranceSeconds: 0)
        let trimmedSeconds = trimmed.estimatedSeconds

        if trimmedSeconds <= upper, trimmedSeconds >= lower {
            return FlexibleTimeResult(
                kept: trimmed.kept,
                estimatedSeconds: trimmedSeconds,
                targetSeconds: targetSeconds,
                toleranceSeconds: toleranceSeconds,
                status: .inWindow,
                notes: notes + trimmed.notes
            )
        }

        // No factible entrar en la ventana exacta (o sobrepasó el upper aun
        // conservando anchors, o saltó por debajo del lower).
        if trimmedSeconds > upper {
            notes.append("No es factible entrar en la ventana aun conservando todos los anchors/prioridades.")
        } else {
            notes.append("La ventana es demasiado estrecha para la granularidad de los sets: recortar entró bajo el umbral inferior.")
        }
        return FlexibleTimeResult(
            kept: trimmed.kept,
            estimatedSeconds: trimmedSeconds,
            targetSeconds: targetSeconds,
            toleranceSeconds: toleranceSeconds,
            status: .notFeasible,
            notes: notes + trimmed.notes
        )
    }
}