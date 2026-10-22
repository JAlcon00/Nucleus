//
//  ProgressView.swift
//  PR
//
//  Created by PR.
//
//  Pestaña "Progreso" (SKILL §6). Estado vacío inicial (SKILL §32) hasta que haya
//  sesiones registradas que alimentar los charts (PR-1004). Vista pura.
//

import SwiftUI

struct ProgressTabView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(Color.primaryAction)
                Text("Tu progreso")
                    .font(.title3.bold())
                Text("Después de tus primeras sesiones verás aquí tu evolución y tus PRs.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle("Progreso")
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    ProgressTabView()
        .ironEnergyTheme()
}