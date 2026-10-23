//
//  TrainingAudience.swift
//  PR
//
//  SCRUM-210 (FB-3): a quién le habla la app según su experiencia. La raíz lo fija a
//  partir del perfil; las etiquetas técnicas (RIR) lo leen para explicarse en palabras a
//  quien empieza. Sin perfil todavía: el lenguaje estándar.
//

import SwiftUI
import PRDomain

extension EnvironmentValues {
    @Entry var trainingAudience: OnboardingAudience = .standard
}
