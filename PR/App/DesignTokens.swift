//
//  DesignTokens.swift
//  PR
//
//  Created by PR.
//
//  Tokens de diseño semánticos (SKILL apple-product-designer §74). Centraliza
//  spacing, radios y colore de acción para no hardcodear estilos por pantalla.
//

import SwiftUI

/// Tokens de espaciado semántico (SKILL §74).
enum DSpace {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
}

/// Tokens de radio de esquina (SKILL §74).
enum DRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 14
    static let large: CGFloat = 22
}

/// Colores de acción semánticos (SKILL §74). Deciden el tono; no el color por pantalla.
extension Color {
    /// Acción primaria (empezar / completar serie).
    static let primaryAction = Color.accentColor
    /// Acción secundaria / neutra.
    static let secondaryAction = Color.gray
    /// Estado de éxito (set completado, PR).
    static let success = Color.green
    /// Aviso (ocupado / reemplazo).
    static let warning = Color.orange
}