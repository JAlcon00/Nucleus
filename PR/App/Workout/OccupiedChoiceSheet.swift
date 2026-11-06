//
//  OccupiedChoiceSheet.swift
//  PR
//
//  "Máquina ocupada" sin nada que adelantar (SCRUM-234). Se viene a decidir qué hacer ya, entre
//  series y con prisa: un toque por opción, el mejor sustituto primero. Sólo muestra lo que
//  decide el motor. Estados: con sustitutos, sin sustitutos y con dolor; sin conexión no
//  aplica (es local).
//

import SwiftUI
import PRCore
import PRDomain

struct OccupiedChoiceSheet: View {
    let choice: OccupiedChoice
    var onChoose: (ExerciseID) -> Void = { _ in }
    var onWait: () -> Void = {}
    var onSkip: () -> Void = {}
    /// "No hay esta máquina aquí" con su sustituto, o sin ninguno (SCRUM-236).
    var onMissing: (ExerciseID?) -> Void = { _ in }

    /// Eligiendo el sustituto para "No hay esta máquina aquí".
    @State private var markingMissing = false
    private let painPresenter = PainRecommendationPresenter(locale: AppEnvironment.presentationLocale)

    var body: some View {
        NavigationStack {
            List {
                if let recommendation = choice.painRecommendation {
                    Section {
                        Label {
                            Text(painPresenter.message(for: recommendation) ?? "")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color.warning)
                        }
                        .accessibilityIdentifier("occupied.pain")
                    }
                    .listRowBackground(Color.surface)
                } else {
                    substitutes
                }
                Section {
                    if choice.painRecommendation == nil {
                        Button(action: onWait) {
                            Label(choice.isOnlyExercise ? "Esperar" : "Esperar (va al final)", systemImage: "clock")
                        }
                        .frame(minHeight: DSize.dayChip)
                        .accessibilityIdentifier("occupied.wait")
                    }
                    Button(action: onSkip) {
                        Label("Saltar", systemImage: "forward.end")
                    }
                    .frame(minHeight: DSize.dayChip)
                    .accessibilityIdentifier("occupied.skip")
                    if choice.painRecommendation == nil {
                        Button {
                            if choice.options.isEmpty { onMissing(nil) } else { markingMissing = true }
                        } label: {
                            Label("No hay esta máquina aquí", systemImage: "xmark.circle")
                        }
                        .frame(minHeight: DSize.dayChip)
                        .accessibilityIdentifier("occupied.missing")
                    }
                }
                .listRowBackground(Color.surface)
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle("\(choice.exercise) está ocupada")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var substitutes: some View {
        Section(markingMissing ? "¿Qué haces aquí en su lugar?" : "Cambiar por") {
            if choice.options.isEmpty {
                Text("No hay un sustituto equivalente y seguro.")
                    .foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier("occupied.none")
            }
            ForEach(Array(choice.options.enumerated()), id: \.element.id) { index, option in
                Button {
                    if markingMissing { onMissing(option.id) } else { onChoose(option.id) }
                } label: {
                    VStack(alignment: .leading, spacing: DSpace.xs) {
                        Text(option.name).foregroundStyle(Color.textPrimary)
                        Text(option.sameMuscles ? "Mismo movimiento, mismos músculos" : "Mismo movimiento, músculos parecidos")
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: DSize.dayChip, alignment: .leading)
                }
                .accessibilityIdentifier("occupied.option.\(index)")
            }
        }
        .listRowBackground(Color.surface)
    }
}

#Preview("Con sustitutos") {
    OccupiedChoiceSheet(choice: OccupiedChoice(
        exercise: "Press de banca",
        options: [SubstituteOption(id: ExerciseID(), name: "Press con mancuernas", sameMuscles: true)],
        painRecommendation: nil,
        isOnlyExercise: false
    ))
    .ironEnergyTheme()
}

#Preview("Sin sustitutos, accessibility3") {
    OccupiedChoiceSheet(choice: OccupiedChoice(exercise: "Press de banca", options: [], painRecommendation: nil, isOnlyExercise: true))
        .dynamicTypeSize(.accessibility3)
        .ironEnergyTheme()
}

#Preview("Con dolor") {
    OccupiedChoiceSheet(choice: OccupiedChoice(exercise: "Press de banca", options: [], painRecommendation: .stopAndRest, isOnlyExercise: false))
        .ironEnergyTheme()
}
