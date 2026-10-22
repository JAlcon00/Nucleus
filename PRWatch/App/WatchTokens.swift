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
