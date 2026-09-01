//
//  HealthAuthorization.swift
//  PRCore
//
//  Created by PR.
//
//  HealthKit authorization abstraction (plan §13 Fase 10, RF-002, PR-1101).
//  PRCore NO importa HealthKit: la capa de aplicación provee un `HealthKitProvider`
//  de producción; aquí definimos el contrato, tipos de permiso granulares, el
//  coordinador de autorización y el origen único de las usage descriptions. Denegar
//  un permiso NUNCA bloquea las funciones core (RF-002).
//

import Foundation

/// Permisos granulares mínimos de HealthKit (§14.1 / §32.3). Cada uno se solicita
/// de forma independiente; se piden sólo los tipos con necesidad demostrada.
public enum HealthPermissionType: String, Codable, Sendable, CaseIterable, Hashable {
    /// Registrar workouts (HKWorkout) cuando PR inicia la sesión.
    case workout
    /// Energy activa (kcal) como contexto de la sesión.
    case activeEnergy
    /// Cardio (heart rate) durante el workout cuando esté disponible.
    case heartRate
}

/// Estado de un permiso de HealthKit.
public enum HealthAuthorizationStatus: String, Codable, Sendable, CaseIterable, Hashable {
    case notDetermined
    case granted
    case denied
}

/// Resultado no-bloqueante de una solicitud de autorización. Se devuelve el estado
/// por tipo para que la UI muestre qué se concedió y qué no, sin bloquear el core.
public enum HealthPermissionOutcome: Equatable, Sendable {
    case success(statusByType: [HealthPermissionType: HealthAuthorizationStatus])
    case failed(message: String)

    public init(_ statusByType: [HealthPermissionType: HealthAuthorizationStatus]) {
        self = .success(statusByType: statusByType)
    }

    /// ¿Todas las solicitudes fueron concedidas?
    public var allGranted: Bool {
        guard case .success(let map) = self else { return false }
        return !map.isEmpty && map.values.allSatisfy { $0 == .granted }
    }

    /// ¿Algún permiso fue denegado explícitamente (RF-002: no bloquea el core)?
    public var anyDeniedButCoreUsable: Bool {
        guard case .success(let map) = self else { return false }
        return map.values.contains { $0 == .denied }
    }
}

/// Provider de HealthKit detrás de un protocolo (plan §13; la app inyecta la
/// implementación de producción `HealthKitWorkoutStore`; los tests usan un fake).
public protocol HealthKitProvider: Sendable {
    /// Estado actual de un permiso sin solicitar.
    func authorizationStatus(for permissionType: HealthPermissionType) async -> HealthAuthorizationStatus
    /// Solicita de forma granular los permisos indicados y devuelve el estado final.
    func requestAuthorization(for permissionTypes: [HealthPermissionType]) async -> HealthPermissionOutcome
}

/// Coordinador de autorización (plan §13): solicita sólo los tipos necesarios y
/// siempre devuelve un resultado no-bloqueante. Si la solicitud falla, las funciones
/// core siguen disponibles (RF-002).
public nonisolated struct HealthAuthorizationCoordinator: Sendable {
    public let provider: HealthKitProvider

    public init(provider: HealthKitProvider) {
        self.provider = provider
    }

    /// Solicita los permisos indicados de forma granular.
    public func requestAuth(for permissionTypes: [HealthPermissionType]) async -> HealthPermissionOutcome {
        await provider.requestAuthorization(for: permissionTypes)
    }

    /// Solicita todos los permisos mínimos del producto (§14.1) salvo los indicados.
    public func requestCorePermissions(excluding excluded: Set<HealthPermissionType> = []) async -> HealthPermissionOutcome {
        let types = HealthPermissionType.allCases.filter { !excluded.contains($0) }
        return await requestAuth(for: types)
    }

    /// Estado actual de cada permiso (sin solicitarlo).
    public func status(of permissionType: HealthPermissionType) async -> HealthAuthorizationStatus {
        await provider.authorizationStatus(for: permissionType)
    }
}

/// Origen único de las `usage descriptions` de HealthKit (Info.plist). Los textos
/// de uso NO pueden computarse en tiempo de ejecución; se exponen aquí para que la
/// configuración del target los mantenga correctos y consistentes (§34/permissions).
public struct HealthUsageDescription {
    /// NSHealthShareUsageDescription — por qué se leen workout / context.
    public static let workoutShare = "Registra tus workouts en la app de Salud para dar contexto a tu entrenamiento."
    /// NSHealthUpdateUsageDescription — por qué se escriben workouts.
    public static let workoutUpdate = "Guarda los workouts que inicias aquí en la app de Salud con tu permiso."
    /// Se lee energía activa y cardio como contexto (no diagnóstico).
    public static let activeEnergy = "Usamos la energía activa y el cardio como contexto de tu sesión; nunca como diagnóstico."

    /// Claves de Info.plist asociadas a cada permiso granular (para configuración).
    public static let plistKeys: [HealthPermissionType: String] = [
        .workout: "NSHealthShareUsageDescription",
        .activeEnergy: "NSHealthShareUsageDescription",
        .heartRate: "NSHealthShareUsageDescription",
    ]

    /// Todos los textos de uso se ven como no vacíos y coherentes.
    public static var allTexts: [String] {
        [workoutShare, workoutUpdate, activeEnergy]
    }
}

/// Fake in-memory de `HealthKitProvider` para tests y previews (§32.3: nunca depender
/// de HealthKit real en unit tests). Permite simular grant/deny por tipo.
public actor InMemoryHealthKitProvider: HealthKitProvider {
    private var statusByType: [HealthPermissionType: HealthAuthorizationStatus]
    private let grantBehavior: HealthGrantBehavior

    /// Comportamiento de solicitud configurable.
    public enum HealthGrantBehavior: Sendable {
        /// Concede todos los tipos solicitados.
        case grantAll
        /// Deniega todos los tipos solicitados.
        case denyAll
        /// Devuelve un fallo del sistema (p.ej. HealthKit no disponible).
        case fail
    }

    /// Crea un provider con estados iniciales y comportamiento de solicitud.
    public init(
        initialStatus: [HealthPermissionType: HealthAuthorizationStatus] = [:],
        grantBehavior: HealthGrantBehavior = .grantAll
    ) {
        self.statusByType = initialStatus
        self.grantBehavior = grantBehavior
    }

    public func authorizationStatus(for permissionType: HealthPermissionType) async -> HealthAuthorizationStatus {
        statusByType[permissionType] ?? .notDetermined
    }

    public func requestAuthorization(for permissionTypes: [HealthPermissionType]) async -> HealthPermissionOutcome {
        switch grantBehavior {
        case .fail:
            return .failed(message: "HealthKit no disponible")
        case .grantAll, .denyAll:
            let granted = grantBehavior == .grantAll
            var next = statusByType
            for type in permissionTypes {
                next[type] = granted ? .granted : .denied
            }
            statusByType = next
            return .success(statusByType: permissionTypes.reduce(into: [:]) { $0[$1] = next[$1] ?? .notDetermined })
        }
    }
}