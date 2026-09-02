//
//  WatchContentView.swift
//  PRWatch
//
//  Created on 31/08/26.
//
//  Vista raíz transitoria del companion watchOS (PR-0001).
//

import SwiftUI
import PRDomain

struct WatchContentView: View {
    var body: some View {
        // Shell PR-1201: sin sesión activa aún, la vista de workout opera en
        // estado idle. El cableado con la sesión viva llega en historias posteriores.
        WatchWorkoutView(
            template: nil,
            performedSets: [],
            lastCompletedPrescription: nil,
            now: Date(),
            onCompleteSet: {},
            onSkipRest: {}
        )
    }
}

#Preview {
    WatchContentView()
}
