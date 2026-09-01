//
//  ExerciseSearch.swift
//  PRDomain
//
//  Created by PR.
//
//  Búsqueda offline del catálogo de ejercicios (PR-0302). Indexa nombres y
//  aliases de forma normalizada (case/diacritic insensitive) y filtra por
//  equipment, patrón de movimiento y grupos musculares. Es un value type puro,
//  determinista y sin IO: misma entrada → mismo orden de resultados.
//

import Foundation

/// Criterios de búsqueda de ejercicios. Todos los filtros presentes se aplican
/// como AND; `text` además requiere coincidencia en nombre o alias.
public struct ExerciseSearchQuery: Sendable, Hashable {
    public var text: String
    /// Si no está vacío, el ejercicio debe usar uno de estos equipos.
    public var equipment: Set<EquipmentType>
    /// Si no está vacío, el patrón del ejercicio debe estar en este conjunto.
    public var movementPatterns: Set<MovementPattern>
    /// Si no está vacío, el ejercicio debe trabajar al menos uno de estos grupos.
    public var muscleGroups: Set<MuscleGroup>

    public init(
        text: String = "",
        equipment: Set<EquipmentType> = [],
        movementPatterns: Set<MovementPattern> = [],
        muscleGroups: Set<MuscleGroup> = []
    ) {
        self.text = text
        self.equipment = equipment
        self.movementPatterns = movementPatterns
        self.muscleGroups = muscleGroups
    }

    /// Devuelve true si no hay texto ni filtros por los que filtrar.
    public var isEmpty: Bool {
        text.isEmpty && equipment.isEmpty && movementPatterns.isEmpty && muscleGroups.isEmpty
    }
}

/// Resultado de búsqueda ordenado: el ejercicio y su score (mayor = mejor).
public struct ExerciseSearchHit: Sendable, Equatable, Identifiable {
    public let exercise: Exercise
    /// Score de relevancia del texto (0 = sin coincidencia de texto).
    public let textScore: Int

    public var id: ExerciseID { exercise.id }

    public init(exercise: Exercise, textScore: Int) {
        self.exercise = exercise
        self.textScore = textScore
    }
}

/// Índice de búsqueda offline sobre una lista de ejercicios (PR-0302).
/// Construye tokens normalizados de nombre y aliases; las búsquedas después son
/// filtros + orden estable, sin IO y por debajo del objetivo <100 ms del
/// catálogo MVP (678 ejercicios).
public struct ExerciseSearchEngine: Sendable {
    public struct Entry: Sendable {
        public let exercise: Exercise
        public let normalizedName: String
        public let nameTokens: Set<String>
        public let aliasTokens: [Set<String>]
    }

    private let entries: [Entry]

    public var allExercises: [Exercise] { entries.map(\.exercise) }
    public var count: Int { entries.count }

    public init(exercises: [Exercise]) {
        self.entries = exercises.map { exercise in
            let name = ExerciseSearchEngine.normalized(exercise.canonicalName)
            return Entry(
                exercise: exercise,
                normalizedName: name,
                nameTokens: ExerciseSearchEngine.tokens(from: name),
                aliasTokens: exercise.aliases
                    .map { ExerciseSearchEngine.tokens(from: ExerciseSearchEngine.normalized($0)) }
            )
        }
    }

    /// Busca y filtra contra el catálogo. Determinista: mismo query → mismo orden.
    public func search(matching query: ExerciseSearchQuery) -> [ExerciseSearchHit] {
        guard !query.isEmpty else {
            // Sin criterios se devuelve todo, ordenado por nombre canónico.
            return entries.sorted { $0.exercise.canonicalName.localizedStandardCompare($1.exercise.canonicalName) == .orderedAscending }
                .map { ExerciseSearchHit(exercise: $0.exercise, textScore: 0) }
        }

        let normalizedQuery = ExerciseSearchEngine.normalized(query.text)
        let queryTokens = ExerciseSearchEngine.tokens(from: normalizedQuery)

        return entries
            .compactMap { entry -> ExerciseSearchHit? in
                guard ExerciseSearchEngine.matchesFilters(entry.exercise, query: query) else { return nil }
                guard !queryTokens.isEmpty else {
                    // Sólo filtros (sin texto): se devuelven todos los que cumplen.
                    return ExerciseSearchHit(exercise: entry.exercise, textScore: 0)
                }
                let score = ExerciseSearchEngine.textScore(
                    normalizedQuery: normalizedQuery,
                    queryTokens: queryTokens,
                    entry: entry
                )
                // Con texto presente se exige coincidencia de relevancia.
                guard score > 0 else { return nil }
                return ExerciseSearchHit(exercise: entry.exercise, textScore: score)
            }
            .sorted { lhs, rhs in
                if lhs.textScore != rhs.textScore { return lhs.textScore > rhs.textScore }
                return lhs.exercise.canonicalName.localizedStandardCompare(rhs.exercise.canonicalName) == .orderedAscending
            }
    }

    // MARK: - Filtros

    private static func matchesFilters(_ exercise: Exercise, query: ExerciseSearchQuery) -> Bool {
        if !query.equipment.isEmpty, !query.equipment.contains(exercise.equipment) {
            return false
        }
        if !query.movementPatterns.isEmpty, !query.movementPatterns.contains(exercise.movementPattern) {
            return false
        }
        if !query.muscleGroups.isEmpty {
            let worked = exercise.primaryMuscles.map(\.muscleGroupID) + exercise.secondaryMuscles.map(\.muscleGroupID)
            guard !worked.isEmpty, worked.contains(where: { query.muscleGroups.contains($0) }) else {
                return false
            }
        }
        return true
    }

    // MARK: - Relevancia de texto

    private static func textScore(
        normalizedQuery: String,
        queryTokens: Set<String>,
        entry: Entry
    ) -> Int {
        // Coincidencia exacta del nombre canónico gana por encima de todo.
        if entry.normalizedName == normalizedQuery { return 100 }
        // Prefijo del nombre canónico.
        if entry.normalizedName.hasPrefix(normalizedQuery) { return 80 }
        // Todos los tokens del query presentes entre los tokens del nombre.
        if !queryTokens.isEmpty, queryTokens.isSubset(of: entry.nameTokens) { return 60 }
        // Subcadena en el nombre canónico.
        if entry.normalizedName.contains(normalizedQuery) { return 50 }

        // Aliases: iguales → prefijo → subconjunto de tokens → subcadena.
        var bestAliasScore = 0
        for aliasTokens in entry.aliasTokens {
            let aliasName = aliasTokens.joined(separator: " ")
            if aliasName == normalizedQuery { return 70 }
            if aliasName.hasPrefix(normalizedQuery) { bestAliasScore = max(bestAliasScore, 65) }
            if !queryTokens.isEmpty, queryTokens.isSubset(of: aliasTokens) { bestAliasScore = max(bestAliasScore, 55) }
            if aliasName.contains(normalizedQuery) { bestAliasScore = max(bestAliasScore, 45) }
        }
        return bestAliasScore
    }

    // MARK: - Normalización

    /// Normaliza texto para búsquedas estables: minúsculas y sin diacríticos,
    /// con locale fijo para que el orden y los matches no dependan del entorno.
    static func normalized(_ string: String) -> String {
        string.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Tokeniza en palabras usando separadores no alfanuméricos.
    static func tokens(from normalizedText: String) -> Set<String> {
        Set(
            normalizedText
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }
}