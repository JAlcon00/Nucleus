//
//  WatchContentView.swift
//  PRWatch
//
//  Created on 31/08/26.
//
//  Vista raíz transitoria del companion watchOS (PR-0001).
//

import SwiftUI

struct WatchContentView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.strengthtraining.traditional")
                .imageScale(.large)
            Text("PR")
                .font(.headline.bold())
            Text("Entrena.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    WatchContentView()
}
