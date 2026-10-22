//
//  ProfileView.swift
//  PR
//
//  Created by PR.
//
//  Pestaña "Profile" (SKILL §6). Estado vacío inicial: perfil, preferencias y
//  accesibilidad llegarán en su fase (PR-0906). Vista pura.
//

import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(Color.primaryAction)
                Text("Tu perfil")
                    .font(.title3.bold())
                Text("Datos, preferencias y accesibilidad se gestionarán aquí.")
                    .font(.callout)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle("Profile")
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    ProfileView()
        .ironEnergyTheme()
}