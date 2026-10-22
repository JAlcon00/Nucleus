//
//  PlanView.swift
//  PR
//
//  Created by PR.
//
//  Pestaña "Plan" (SKILL §6). Estado vacío inicial (SKILL §32: explica qué pasó y qué
//  hacer después). El plan builder (PR-1502) y el detalle (PR-1501) llegarán en su fase.
//  Vista pura; no contiene reglas de negocio.
//

import SwiftUI

struct PlanView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.plus")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(Color.primaryAction)
                Text("Tu plan")
                    .font(.title3.bold())
                Text("Todavía no tienes un plan semanal. Lo generarás y ajustarás aquí.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle("Plan")
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    PlanView()
        .ironEnergyTheme()
}