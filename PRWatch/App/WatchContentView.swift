//
//  WatchContentView.swift
//  PRWatch
//
//  Created on 31/08/26.
//
//  Vista raíz del reloj: crea el controlador y lo conecta con el iPhone.
//

import PRCore
import SwiftUI

struct WatchContentView: View {
    var body: some View {
        if let controller = WatchSessionModel.shared {
            WatchWorkoutView(controller: controller)
                .task { controller.start() }
        } else {
            WatchMessageView(
                symbol: "exclamationmark.triangle",
                title: "No se puede guardar",
                detail: "Registra esta sesión en el iPhone."
            )
        }
    }
}

#Preview {
    WatchContentView()
}
