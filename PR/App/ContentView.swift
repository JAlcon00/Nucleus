//
//  ContentView.swift
//  PR
//
//  Created by Jesús Almanza on 31/08/26.
//
//  Vista raíz transitoria del esqueleto inicial (PR-0001).
//  Renderiza estado y envía intents; no contiene reglas de negocio.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.strengthtraining.traditional")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("PR")
                .font(.largeTitle.bold())
            Text("Tú entrenas. PR administra el resto.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("PR. Tú entrenas, PR administra el resto.")
    }
}

#Preview {
    ContentView()
        .environment(AppEnvironment())
}
