//
//  MuscleVolumeView.swift
//  PR
//
//  SCRUM-268 (PR-H006): series por músculo de esta semana contra su rango. Se abre desde la
//  KPI "Series esta semana" de Progreso. El conteo, el rango y el nivel los decide
//  `WeeklyMuscleVolumeRule` (PRDomain); aquí sólo se pintan, y cada nivel lleva icono y
//  texto (el color nunca va solo). Es la lista en texto sobre la que irá el mapa del cuerpo
//  (SCRUM-229). Estados:
//  - con series esta semana: cada músculo del plan y lo que se entrenó fuera de él;
//  - semana sin entrenar: los músculos del plan en 0 y "Aún no entrenas esta semana";
//  - sin plan: no aplica, la KPI no abre esta pantalla;
//  - cargando, fallido y sin conexión: no aplican; se abre desde un Progreso ya leído.
//

import SwiftUI
import PRCore
import PRDomain

struct MuscleVolumeView: View {
    let volume: [MuscleWeekVolume]
    /// ¿Hubo algún entrenamiento esta semana?
    let trainedThisWeek: Bool

    private let vocabulary = TrainingVocabularyPresenter(locale: AppEnvironment.presentationLocale)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSpace.s) {
                Text("Cada serie cuenta para el músculo principal de su ejercicio. El rango sale de la prioridad del músculo en tu plan.")
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, DSpace.xs)
                if !trainedThisWeek {
                    Label("Aún no entrenas esta semana.", systemImage: "calendar")
                        .font(.callout)
                        .foregroundStyle(Color.textSecondary)
                        .padding(DSpace.m)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface(cornerRadius: DRadius.medium)
                        .accessibilityIdentifier("progress.muscles.empty")
                }
                ForEach(volume) { item in
                    row(item)
                        .accessibilityIdentifier("progress.muscles.row.\(item.muscle.rawValue)")
                }
            }
            .padding(DSpace.m)
        }
        .screenBackground()
        .navigationTitle("Series por músculo")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("progress.muscles")
    }

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DSpace.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: DSpace.m))
    }

    private func row(_ item: MuscleWeekVolume) -> some View {
        layout {
            VStack(alignment: .leading, spacing: DSpace.xs) {
                Text(vocabulary.muscleName(item.muscle))
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)
                Label(levelText(item), systemImage: levelSymbol(item))
                    .font(.subheadline)
                    .foregroundStyle(levelColor(item))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: DSpace.s)
            }
            VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: DSpace.xs) {
                Text(setsText(item))
                    .font(.title3.bold())
                    .numericStyle()
                    .foregroundStyle(Color.textPrimary)
                if let goal = goalText(item) {
                    Text(goal)
                        .font(.caption)
                        .numericStyle()
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(DSpace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: DRadius.medium)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText(item)))
    }

    // MARK: - Textos (sólo formato)

    private func setsText(_ item: MuscleWeekVolume) -> String {
        item.sets == 1 ? String(localized: "1 serie") : String(localized: "\(item.sets) series")
    }

    private func goalText(_ item: MuscleWeekVolume) -> String? {
        guard case .planned(let target, let range, _) = item.status else { return nil }
        return String(localized: "Objetivo \(target) · rango \(range.lowerBound)–\(range.upperBound)")
    }

    private func levelText(_ item: MuscleWeekVolume) -> String {
        switch item.status {
        case .planned(_, _, .belowRange(let missing)):
            return missing == 1
                ? String(localized: "Falta 1 para el mínimo")
                : String(localized: "Faltan \(missing) para el mínimo")
        case .planned(_, _, .inRange):
            return String(localized: "En rango")
        case .planned(_, _, .aboveRange):
            return String(localized: "Sobre el máximo")
        case .outsidePlan:
            return String(localized: "Fuera de tu plan")
        }
    }

    private func levelSymbol(_ item: MuscleWeekVolume) -> String {
        switch item.status {
        case .planned(_, _, .belowRange): return "circle.dotted"
        case .planned(_, _, .inRange): return "checkmark.circle.fill"
        case .planned(_, _, .aboveRange): return "exclamationmark.circle"
        case .outsidePlan: return "minus.circle"
        }
    }

    private func levelColor(_ item: MuscleWeekVolume) -> Color {
        switch item.status {
        case .planned(_, _, .belowRange): return Color.textSecondary
        case .planned(_, _, .inRange): return Color.success
        case .planned(_, _, .aboveRange): return Color.warning
        case .outsidePlan: return Color.textSecondary
        }
    }

    private func accessibilityText(_ item: MuscleWeekVolume) -> String {
        var parts = [vocabulary.muscleName(item.muscle), setsText(item), levelText(item)]
        if case .planned(let target, let range, _) = item.status {
            parts.append(String(localized: "objetivo \(target), rango de \(range.lowerBound) a \(range.upperBound)"))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Previews

/// Lista calculada por PRDomain con un resolvedor de ejemplo.
private func previewVolume(trained: Bool) -> [MuscleWeekVolume] {
    struct Resolver: ExercisePrimaryResolver {
        let muscles: [ExerciseID: MuscleGroup]
        func primaryMuscle(of exerciseID: ExerciseID) -> MuscleGroup.ID? { muscles[exerciseID] }
    }
    let press = ExerciseID(), row = ExerciseID(), squat = ExerciseID(), curl = ExerciseID()
    guard let config = try? VolumeConfig(rule: VolumeDefaults.makeRule()),
          let targets = try? [
              MuscleVolumeTarget(muscleGroupID: .chest, targetSetsPerWeek: 10),
              MuscleVolumeTarget(muscleGroupID: .back, targetSetsPerWeek: 10),
              MuscleVolumeTarget(muscleGroupID: .quadriceps, targetSetsPerWeek: 14),
              MuscleVolumeTarget(muscleGroupID: .calves, targetSetsPerWeek: 4),
          ] else { return [] }
    let rule = WeeklyMuscleVolumeRule(
        config: config, resolver: Resolver(muscles: [press: .chest, row: .back, squat: .quadriceps, curl: .biceps])
    )
    return rule.volume(
        completedSets: trained ? [press: 6, row: 10, squat: 17, curl: 3] : [:],
        targets: targets,
        priorities: [
            MusclePriority(muscleGroupID: .quadriceps, priority: .emphasize),
            MusclePriority(muscleGroupID: .calves, priority: .maintain),
        ]
    )
}

#Preview("Con series") {
    NavigationStack { MuscleVolumeView(volume: previewVolume(trained: true), trainedThisWeek: true) }
        .ironEnergyTheme()
}

#Preview("Con series · claro") {
    NavigationStack { MuscleVolumeView(volume: previewVolume(trained: true), trainedThisWeek: true) }
        .ironEnergyTheme()
        .preferredColorScheme(.light)
}

#Preview("Con series · accessibility3") {
    NavigationStack { MuscleVolumeView(volume: previewVolume(trained: true), trainedThisWeek: true) }
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}

#Preview("Semana sin entrenar") {
    NavigationStack { MuscleVolumeView(volume: previewVolume(trained: false), trainedThisWeek: false) }
        .ironEnergyTheme()
}
