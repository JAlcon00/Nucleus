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
    /// Permiso de lectura: Salud no revela si se concedió o se negó (§37.1), así que no se
    /// infiere. Si se negó, simplemente no llegan datos.
    case notVisible
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

    /// ¿Se concedió este permiso? Un fallo de la solicitud no concede nada (SCRUM-35).
    public func isGranted(_ type: HealthPermissionType) -> Bool {
        guard case .success(let map) = self else { return false }
        return map[type] == .granted
    }

    /// ¿Se puede usar lo que llegó de este dato? Sí si está concedido o si Salud no dice
    /// (lectura, SCRUM-244). Un fallo de la solicitud no permite nada.
    public func permitsReading(_ type: HealthPermissionType) -> Bool {
        guard case .success(let map) = self else { return false }
        return map[type] == .granted || map[type] == .notVisible
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

/// Lo que la app le pide a Salud: qué escribe y qué lee.
public struct HealthAccessRequest: Sendable, Hashable {
    public let write: Set<HealthPermissionType>
    public let read: Set<HealthPermissionType>

    public init(write: Set<HealthPermissionType>, read: Set<HealthPermissionType>) {
        self.write = write
        self.read = read
    }

    /// Lo mínimo de la Fase F (DF-3): escribir entrenamientos, leer entrenamientos y leer
    /// energía activa. El ritmo cardiaco pasa al Watch.
    public static let workouts = HealthAccessRequest(write: [.workout], read: [.workout, .activeEnergy])

    /// La parte de esta solicitud que cae en `types`.
    func limited(to types: Set<HealthPermissionType>) -> HealthAccessRequest {
        HealthAccessRequest(write: write.intersection(types), read: read.intersection(types))
    }
}

/// Respuesta de Salud sobre un permiso de escritura, el único que revela.
public enum HealthWriteAuthorization: Sendable, Hashable {
    case notDetermined
    case denied
    case authorized
}

/// Lo mínimo que la app necesita de HealthKit para los permisos. La implementación real
/// vive en la app, porque PRCore no importa HealthKit.
public protocol HealthSystemAuthorizing: Sendable {
    var isHealthDataAvailable: Bool { get }
    func writeAuthorization(for type: HealthPermissionType) -> HealthWriteAuthorization
    func requestAuthorization(_ request: HealthAccessRequest) async throws
}

/// `HealthKitProvider` de producción (SCRUM-244). Dice sólo lo que Salud dice: la escritura
/// tiene estado real; la lectura es "no visible"; lo que no se pide queda sin decidir. Lee
/// el estado cada vez, sin guardarlo, porque se puede cambiar desde Ajustes.
public struct HealthSystemPermissionProvider: HealthKitProvider {
    private let system: any HealthSystemAuthorizing
    private let access: HealthAccessRequest

    public init(system: any HealthSystemAuthorizing, access: HealthAccessRequest = .workouts) {
        self.system = system
        self.access = access
    }

    public func authorizationStatus(for permissionType: HealthPermissionType) async -> HealthAuthorizationStatus {
        status(of: permissionType)
    }

    public func requestAuthorization(for permissionTypes: [HealthPermissionType]) async -> HealthPermissionOutcome {
        guard system.isHealthDataAvailable else {
            return .failed(message: "Salud no está disponible en este dispositivo.")
        }
        let request = access.limited(to: Set(permissionTypes))
        do {
            try await system.requestAuthorization(request)
        } catch {
            return .failed(message: "No se pudo pedir el permiso de Salud.")
        }
        let asked = request.write.union(request.read)
        return .success(statusByType: asked.reduce(into: [:]) { $0[$1] = status(of: $1) })
    }

    private func status(of type: HealthPermissionType) -> HealthAuthorizationStatus {
        guard system.isHealthDataAvailable else { return .notDetermined }
        if access.write.contains(type) {
            switch system.writeAuthorization(for: type) {
            case .notDetermined: return .notDetermined
            case .denied: return .denied
            case .authorized: return .granted
            }
        }
        return access.read.contains(type) ? .notVisible : .notDetermined
    }
}

/// Puerta de entrada a los entrenamientos en Salud: con `health.workouts.enabled` apagado
/// no se pide ni se lee nada (SCRUM-244). Denegar o fallar nunca bloquea la app (RF-002).
public struct HealthWorkoutsAccess: Sendable {
    public let isEnabled: Bool
    private let provider: any HealthKitProvider
    private let request: HealthAccessRequest

    public init(
        flags: FeatureFlags,
        provider: any HealthKitProvider,
        request: HealthAccessRequest = .workouts
    ) {
        self.isEnabled = flags.isEnabled(.healthWorkoutsEnabled)
        self.provider = provider
        self.request = request
    }

    /// Pide lo mínimo. Apagado no llama al sistema y devuelve un resultado sin permisos.
    public func requestPermissions() async -> HealthPermissionOutcome {
        guard isEnabled else { return HealthPermissionOutcome([:]) }
        let types = request.write.union(request.read).sorted { $0.rawValue < $1.rawValue }
        return await provider.requestAuthorization(for: types)
    }

    /// Estado de escribir entrenamientos, sin pedirlo.
    public func writeStatus() async -> HealthAuthorizationStatus {
        guard isEnabled else { return .notDetermined }
        return await provider.authorizationStatus(for: .workout)
    }
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
    /// NSHealthShareUsageDescription — qué se lee y para qué (lo que pide Salud en la hoja).
    public static let workoutShare = "Nucleus lee de Salud tus entrenamientos y tu energía activa para no contar dos veces un mismo entrenamiento, y tu fecha de nacimiento, sexo, estatura y peso sólo para llenar \"Sobre ti\" si tú lo pides."
    /// NSHealthUpdateUsageDescription — qué se escribe.
    public static let workoutUpdate = "Nucleus guarda en Salud los entrenamientos que terminas, con su tipo y sus horas de inicio y fin. Nunca series, peso ni notas."
    /// La energía activa es contexto de la sesión, no diagnóstico.
    public static let activeEnergy = "Usamos tu energía activa sólo como contexto de tu sesión, nunca como diagnóstico."

    /// Claves de Info.plist asociadas a cada permiso granular (para configuración).
    /// `workout` lleva el texto de escritura: es lo que la app hace con ese permiso.
    public static let plistKeys: [HealthPermissionType: String] = [
        .workout: "NSHealthUpdateUsageDescription",
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
        /// Concede sólo estos tipos y deniega el resto (permisos parciales, SCRUM-35).
        case grantOnly(Set<HealthPermissionType>)
        /// Devuelve un fallo del sistema (p.ej. HealthKit no disponible).
        case fail

        func grants(_ type: HealthPermissionType) -> Bool {
            switch self {
            case .grantAll: return true
            case .denyAll, .fail: return false
            case .grantOnly(let granted): return granted.contains(type)
            }
        }
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
        case .grantAll, .denyAll, .grantOnly:
            var next = statusByType
            for type in permissionTypes {
                next[type] = grantBehavior.grants(type) ? .granted : .denied
            }
            statusByType = next
            return .success(statusByType: permissionTypes.reduce(into: [:]) { $0[$1] = next[$1] ?? .notDetermined })
        }
    }
}