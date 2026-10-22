//
//  AppTab.swift
//  PR
//
//  Created by PR.
//
//  Estructura principal del app (SKILL §6): una tab bar de 4 destinos primarios.
//  Meramente descriptivo; no contiene lógica. La sesión activa reemplaza la navegación
//  (SKILL §6) y se presenta a nivel raíz (ver AppRootView.appContent).
//  SCRUM-195: títulos en español e iconos que dicen qué hay detrás (Hoy = entrenar,
//  no "hecho").
//

import SwiftUI

/// Destinos primarios de la tab bar. Orden estable Hoy → Progreso → Plan → Perfil.
enum AppTab: CaseIterable, Identifiable {
    case today
    case progress
    case plan
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .today: return String(localized: "Hoy")
        case .progress: return String(localized: "Progreso")
        case .plan: return String(localized: "Plan")
        case .profile: return String(localized: "Perfil")
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "figure.strengthtraining.traditional"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .plan: return "calendar"
        case .profile: return "person.crop.circle"
        }
    }
}
