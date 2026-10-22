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
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                Text("Tu perfil")
                    .font(.title3.bold())
                Text("Datos, preferencias y accesibilidad se gestionarán aquí.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Profile")
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    ProfileView()
        .environment(\.colorScheme, .light)
}