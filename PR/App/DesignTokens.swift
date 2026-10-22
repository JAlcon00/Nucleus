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

/// Tamaños de piezas gráficas que no son texto (escalan con `@ScaledMetric` donde se usan).
enum DSize {
    /// Anillo de progreso de un loader de paso completo.
    static let progressRing: CGFloat = 96
    /// Grosor del trazo de anillos de progreso.
    static let ringStroke: CGFloat = 6
    /// Hueco del icono de estado de una fila (✓, en curso, pendiente).
    static let statusIcon: CGFloat = 28
}

/// Tokens de movimiento. Con Reduce Motion se sustituye el desplazamiento/escala por un
/// fundido breve (mismo significado, sin movimiento).
enum DMotion {
    /// Aparición de un logro (PR-1004): spring corto, sin rebote exagerado.
    static let celebration: Animation = .spring(duration: 0.4)
    /// Variante con Reduce Motion: sólo opacidad.
    static let celebrationReduced: Animation = .easeOut(duration: 0.2)

    static func celebration(reduceMotion: Bool) -> Animation {
        reduceMotion ? celebrationReduced : celebration
    }

    /// Tiempo mínimo en pantalla de un loader de paso completo ("Armando tu semana"):
    /// evita el parpadeo. Nunca se espera más de esto si la operación ya terminó.
    static let minimumLoaderDuration: Duration = .milliseconds(800)
    /// Espera tras la que el inicio de sesión ofrece "Reintentar".
    static let slowSignInThreshold: Duration = .seconds(10)
    /// Barrido del skeleton de carga (sin él con Reduce Motion).
    static let shimmer: Animation = .linear(duration: 1.4).repeatForever(autoreverses: false)
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