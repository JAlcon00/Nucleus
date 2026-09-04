//
//  ProgressView.swift
//  PR
//
//  Created by PR.
//
//  Pestaña "Progress" (SKILL §6). Estado vacío inicial (SKILL §32) hasta que haya
//  sesiones registradas que alimentar los charts (PR-1004). Vista pura.
//

import SwiftUI

struct ProgressTabView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Tu progreso")
                    .font(.title3.bold())
                Text("Después de tus primeras sesiones verás aquí tu evolución y tus PRs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Progress")
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    ProgressTabView()
        .environment(\.colorScheme, .light)
}