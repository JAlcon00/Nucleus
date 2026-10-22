//
//  AppTab.swift
//  PR
//
//  Created by PR.
//
//  Estructura principal del app (SKILL §6): una tab bar de 4 destinos primarios.
//  Meramente descriptivo; no contiene lógica. La sesión activa reemplaza la navegación
//  (SKILL §6) y se presenta a nivel raíz (ver AppRootView.appContent).
//

import SwiftUI

/// Destinos primarios de la tab bar. Orden estable Today → Progress → Plan → Profile.
enum AppTab: CaseIterable, Identifiable {
    case today
    case progress
    case plan
    case profile

    var id: Self { self }

    var title: String {
        switch self {
        case .today: return "Today"
        case .progress: return "Progress"
        case .plan: return "Plan"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "checkmark.circle.fill"
        case .progress: return "chart.line.uptrend.xyaxis"
        case .plan: return "calendar"
        case .profile: return "person.crop.circle"
        }
    }

    var selectedSystemImage: String {
        switch self {
        case .today: return "checkmark.circle.fill"
        case .progress: return "chart.line.uptrend.xyaxis.fill"
        case .plan: return "calendar.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}