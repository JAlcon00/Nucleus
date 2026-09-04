//
//  AppTabBarView.swift
//  PR
//
//  Created by PR.
//
//  Pestañas raíz de la app (SKILL §6: Today / Progress / Plan / Profile).
//  La pestaña Today conserva su header, su barra de acciones (restricciones/exportar)
//  y su presentación de WORKOUT MODE. La sesión activa se presenta a nivel raíz
//  (fullScreenCover en AppRootView) para reemplazar la navegación temporalmente.
//  Vista de composición: no contiene reglas de negocio.
//

import SwiftUI
import PRCore
import PRDomain

struct AppTabBarView: View {
    @Environment(AppEnvironment.self) private var environment
    @Binding var selectedTab: AppTab
    @Binding var showWorkout: Bool
    /// Intento: empezar la sesión planeada hoy (envía al composition root).
    var onStart: () -> Void
    /// Intento: continuar la sesión en curso (idem).
    var onResume: () -> Void

    var body: some View {
        TabView(selection: $selectedTab) {
            todayTab
                .tabItem { tabLabel(.today) }
                .tag(AppTab.today)
            ProgressTabView()
                .tabItem { tabLabel(.progress) }
                .tag(AppTab.progress)
            PlanView()
                .tabItem { tabLabel(.plan) }
                .tag(AppTab.plan)
            ProfileView()
                .tabItem { tabLabel(.profile) }
                .tag(AppTab.profile)
        }
        .tint(.accentColor)
    }

    private var todayTab: some View {
        NavigationStack {
            TodayView(
                state: environment.todayPlan.plan?.todayState ?? .restDay,
                onStart: onStart,
                onResume: onResume
            )
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    NavigationLink {
                        RestrictionManagementView(
                            restrictions: [],
                            onCreate: {},
                            onReview: { _ in },
                            onResolve: { _ in }
                        )
                    } label: {
                        Label("Restricciones", systemImage: "list.bullet.clipboard")
                    }

                    NavigationLink {
                        ExportDataView()
                    } label: {
                        Label("Exportar", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tabLabel(_ tab: AppTab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
    }
}