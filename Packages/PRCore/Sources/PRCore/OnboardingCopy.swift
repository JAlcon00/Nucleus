//
//  OnboardingCopy.swift
//  PRCore
//
//  SCRUM-210 (FB-3): título, subtítulo y pista de cada paso del formulario según a quién
//  le habla (`OnboardingAudience`): lenguaje simple con ejemplos para quien empieza,
//  el de siempre para el intermedio y terminología técnica, sin explicaciones obvias,
//  para el avanzado. La vista sólo pinta estos textos.
//

import Foundation
import PRDomain

public struct OnboardingCopy: Sendable {
    private let locale: Locale
    private let audience: OnboardingAudience

    public init(locale: Locale = .current, audience: OnboardingAudience) {
        self.locale = locale
        self.audience = audience
    }

    public func title(for step: OnboardingStep) -> String {
        switch (step, audience) {
        case (.experience, _): return resource("Experiencia", "Título del paso: experiencia")
        case (.goal, .guided): return resource("¿Qué quieres lograr?", "Título del paso objetivo (principiante)")
        case (.goal, .standard), (.goal, .expert): return resource("Objetivo", "Título del paso objetivo")
        case (.phase, .guided): return resource("¿Cómo estás comiendo?", "Título del paso fase (principiante)")
        case (.phase, .standard), (.phase, .expert): return resource("Fase", "Título del paso fase")
        case (.daysPerWeek, .expert): return resource("Días de entrenamiento", "Título del paso días (avanzado)")
        case (.daysPerWeek, .guided), (.daysPerWeek, .standard): return resource("¿Qué días puedes entrenar?", "Título del paso días")
        case (.sessionMinutes, .guided): return resource("¿Cuánto tiempo tienes?", "Título del paso minutos (principiante)")
        case (.sessionMinutes, .standard): return resource("Minutos por sesión", "Título del paso minutos")
        case (.sessionMinutes, .expert): return resource("Duración de la sesión", "Título del paso minutos (avanzado)")
        case (.variety, _): return resource("Variedad", "Título del paso variedad")
        case (.priorityMuscles, .guided): return resource("¿Quieres enfocarte en algo?", "Título del paso músculos prioritarios (principiante)")
        case (.priorityMuscles, .standard), (.priorityMuscles, .expert): return resource("Músculos prioritarios", "Título del paso músculos prioritarios")
        case (.restrictions, .guided): return resource("¿Algo te molesta?", "Título del paso restricciones (principiante)")
        case (.restrictions, .standard), (.restrictions, .expert): return resource("Restricciones", "Título del paso restricciones")
        }
    }

    public func subtitle(for step: OnboardingStep) -> String {
        switch (step, audience) {
        case (.experience, _):
            return resource("Cuánto tiempo llevas entrenando con constancia. Con esto adaptamos las preguntas.", "Subtítulo del paso experiencia")
        case (.goal, .guided):
            return resource("Elige lo que más te importa ahora. Puedes cambiarlo después.", "Subtítulo del paso objetivo (principiante)")
        case (.goal, .standard):
            return resource("¿Qué quieres lograr primero? Puedes cambiarlo después.", "Subtítulo del paso objetivo")
        case (.goal, .expert):
            return resource("Prioridad del bloque.", "Subtítulo del paso objetivo (avanzado)")
        case (.phase, .guided):
            return resource("Si no estás seguro, elige \"Como normal\".", "Subtítulo del paso fase (principiante)")
        case (.phase, .standard):
            return resource("Cómo estás comiendo ahora. Ajusta el volumen de tu semana.", "Subtítulo del paso fase")
        case (.phase, .expert):
            return resource("Balance energético actual: ajusta el volumen semanal.", "Subtítulo del paso fase (avanzado)")
        case (.daysPerWeek, .guided):
            return resource("Dejamos días de descanso para que tu cuerpo se recupere. Elige al menos 2.", "Subtítulo del paso días (principiante)")
        case (.daysPerWeek, .standard):
            return resource("Dejamos descanso entre sesiones para que recuperes. Elige al menos 2 días.", "Subtítulo del paso días")
        case (.daysPerWeek, .expert):
            return resource("Frecuencia semanal; el descanso se reparte entre sesiones. Mínimo 2.", "Subtítulo del paso días (avanzado)")
        case (.sessionMinutes, .guided):
            return resource("Los minutos que puedes dedicar a cada entrenamiento.", "Subtítulo del paso minutos (principiante)")
        case (.sessionMinutes, .standard):
            return resource("El tiempo que sueles tener para cada entrenamiento.", "Subtítulo del paso minutos")
        case (.sessionMinutes, .expert):
            return resource("Minutos por sesión; si no alcanza se recortan accesorios.", "Subtítulo del paso minutos (avanzado)")
        case (.variety, .expert):
            return resource("Rotación de ejercicios entre semanas.", "Subtítulo del paso variedad (avanzado)")
        case (.variety, .guided), (.variety, .standard):
            return resource("Cuánto cambian tus ejercicios de una semana a otra.", "Subtítulo del paso variedad")
        case (.priorityMuscles, .guided):
            return resource("Puedes saltarlo. Si eliges hasta 2 músculos, les damos más trabajo en tu semana.", "Subtítulo del paso músculos prioritarios (principiante)")
        case (.priorityMuscles, .standard), (.priorityMuscles, .expert):
            return resource("Opcional. Hasta 2: reciben más volumen semanal (énfasis).", "Subtítulo del paso músculos prioritarios")
        case (.restrictions, .guided):
            return resource("Opcional. Si algo te duele, lo cuidamos en tu plan.", "Subtítulo del paso restricciones (principiante)")
        case (.restrictions, .standard), (.restrictions, .expert):
            return resource("Opcional. Si algo te molesta, lo cuidamos en tu plan.", "Subtítulo del paso restricciones")
        }
    }

    /// Pista del pie cuando aún no se puede avanzar (`nil`: el paso ya se explica solo).
    public func hint(for step: OnboardingStep) -> String? {
        switch step {
        case .goal, .phase, .experience, .variety: return resource("Elige una opción para seguir.", "Pista: falta elegir una opción")
        case .priorityMuscles: return resource("Elige como mucho 2.", "Pista: demasiados músculos prioritarios")
        case .restrictions: return resource("La nota es demasiado larga.", "Pista: nota de restricciones demasiado larga")
        case .daysPerWeek, .sessionMinutes: return nil
        }
    }

    private static let bundle = LocalizedStringResource.BundleDescription.atURL(Bundle.module.bundleURL)

    private func resource(_ key: String.LocalizationValue, _ comment: StaticString) -> String {
        String(localized: LocalizedStringResource(key, locale: locale, bundle: Self.bundle, comment: comment))
    }
}
