//
//  AppEnvironment.swift
//  PR
//
//  Created by PR.
//
//  Composition root: construye y expone las dependencias del dominio/core.
//  Mantiene `PRApp.swift` libre de lógica de negocio (PR-0001).
//

import Foundation
import Observation
import PRCore

/// Porta las dependencias compartidas de la aplicación.
/// Es el punto único de composición de la capa de infraestructura.
@MainActor
@Observable
public final class AppEnvironment {
    /// Version del core embebido (para diagnóstico sin datos sensibles).
    public let coreVersion: String

    /// Proveedor LLM con la API key inyectada en runtime (NVIDIAKeyLoader).
    /// NUNCA embebe la key: se lee de entorno/.env en runtime (§22/§42). Es un shim
    /// de prototipado; en producción la app habla con nuestro backend.
    public var llmProvider: any LLMProvider {
        NVIDIAHostedProvider()
    }

    public init(coreVersion: String = PRCore.version) {
        self.coreVersion = coreVersion
    }
}
