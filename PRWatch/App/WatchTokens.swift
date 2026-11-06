//
//  WatchTokens.swift
//  PRWatch
//
//  Created by PR.
//
//  Tokens del reloj (SCRUM-194, M4). Las cifras de peso y reps usan un tamaño fijo a
//  propósito: en la muñeca deben leerse de un vistazo y caber en una fila; aceptado en la
//  auditoría siempre que salga de aquí y no de un número suelto en la vista.
//

import SwiftUI

enum WatchType {
    /// Peso y repeticiones de la serie actual.
    static let setValueSize: CGFloat = 30
}

/// Medidas del reloj. El área de toque nunca baja de 44 pt.
enum WatchMetric {
    static let touchTarget: CGFloat = 44
    static let completeHeight: CGFloat = 52
    static let spacing: CGFloat = 8
}

/// Colores del reloj. Texto negro sobre la acción: el blanco no llega al contraste mínimo.
enum WatchColor {
    static let action = Color("IronFire")
    static let onAction = Color.black
}
