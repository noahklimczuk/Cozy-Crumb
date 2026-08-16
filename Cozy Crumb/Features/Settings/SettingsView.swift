//
//  SettingsView.swift
//  Cozy Crumb
//
//  Phase 7. The placeholder this replaces had grown four toggles and two
//  links; this is the same screen taken seriously.
//
//  Three things were missing rather than merely unstyled, and they're the
//  point of the phase:
//
//    - The accent picker only existed inside the design-system gallery, which
//      is a developer screen. Choosing the app's colour is not a debug tool.
//    - Units could only be changed from inside a recipe, so a metric cook had
//      to convert every recipe individually and could never say "I think in
//      grams" once.
//    - "Dark mode" was a boolean, so its off position forced the app light for
//      someone whose phone was dark. Matching the phone is now an option, and
//      the default.
//
//  Everything reads and writes the same `CozyDefaultsKey` values the rest of
//  the app already observes, so nothing here needs to notify anything.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent

    @Query private var recipes: [Recipe]
    @Query private var collections: [RecipeCollection]
    @Query private var plannedMeals: [PlannedMeal]

    @Binding var accentSelection: AccentPalette
    @Binding var appearance: AppAppearance

    @AppStorage(CozyDefaultsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(CozyDefaultsKey.measurementSystem)
    private var measurementRaw = MeasurementSystem.asWritten.rawValue
    @AppStorage(CozyDefaultsKey.checkOffAddsToPantry) private var checkOffAddsToPantry = false
    @AppStorage(CozyDefaultsKey.roundUpShoppingAmounts) private var roundUpShoppingAmounts = true

    @State private var isConfirmingRecipeDeletion = false

    private var measurementSystem: MeasurementSystem {
        MeasurementSystem(rawValue: measurementRaw) ?? .asWritten
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CozySpacing.l) {
                    sousChefCard
                    cookingCard
                    appearanceCard
                    groceriesCard
                    dataCard
                    aboutCard
                }
                .padding(CozySpacing.l)
            }
            .background { BlobBackground() }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Delete every recipe?",
                isPresented: $isConfirmingRecipeDeletion,
                titleVisibility: .visible
            ) {
                Button("Delete \(recipes.count) recipes", role: .destructive, action: deleteAllRecipes)
                Button("Keep them", role: .cancel) {}
            } message: {
                Text("Your collections, plan and grocery list stay. This can't be undone.")
            }
        }
    }

    // MARK: - Sous Chef

    private var sousChefCard: some View {
        SettingsCard(title: "Sous Chef", note: "Reads recipes out of links, captions and video.") {
            NavigationLink {
                AIKeySettingsView()
            } label: {
                SettingsRowLabel(
                    title: "Key and model",
                    detail: KeychainStore.shared.hasValue(for: .geminiAPIKey)
                        ? "Awake, using \(GeminiModel.preferred.displayName)"
                        : "Asleep — no key yet"
                )
            }
            .buttonStyle(.squishy)
        }
    }

    // MARK: - Cooking

    private var cookingCard: some View {
        SettingsCard(
            title: "Cooking",
            note: "How measurements are written everywhere — recipes, the plan and the shopping list."
        ) {
            Picker("Units", selection: $measurementRaw) {
                ForEach(MeasurementSystem.allCases, id: \.rawValue) { option in
                    Text(option.displayName).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Text(unitsExplanation)
                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var unitsExplanation: String {
        switch measurementSystem {
        case .asWritten:
            "Quantities stay exactly as the recipe wrote them."
        case .metric:
            "Cups and ounces are converted to grams and millilitres where the conversion is honest."
        case .imperial:
            "Grams and millilitres are converted to cups and ounces where the conversion is honest."
        }
    }

    // MARK: - Appearance

    private var appearanceCard: some View {
        SettingsCard(title: "Look and feel") {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("Accent")
                    .cozyText(CozyFont.bodyEmphasis)

                ScrollView(.horizontal) {
                    HStack(spacing: CozySpacing.s) {
                        ForEach(AccentPalette.allCases) { palette in
                            SelectableChip(
                                text: palette.displayName,
                                tint: palette.color,
                                isSelected: palette == accentSelection
                            ) {
                                accentSelection = palette
                                Haptics.selection()
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }

            Divider().overlay(CozyColor.outline)

            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("Appearance")
                    .cozyText(CozyFont.bodyEmphasis)

                Picker("Appearance", selection: $appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Label(option.displayName, systemImage: option.symbol).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider().overlay(CozyColor.outline)

            Toggle(isOn: $hapticsEnabled) {
                SettingsRowLabel(title: "Haptics", detail: "A soft tap on every press.")
            }
            .tint(accent.deep)
        }
    }

    // MARK: - Groceries

    private var groceriesCard: some View {
        SettingsCard(title: "Groceries") {
            Toggle(isOn: $roundUpShoppingAmounts) {
                SettingsRowLabel(
                    title: "Round up to shop sizes",
                    detail: "375 g of flour becomes the 400 g you'd actually buy."
                )
            }
            .tint(accent.deep)

            Divider().overlay(CozyColor.outline)

            Toggle(isOn: $checkOffAddsToPantry) {
                SettingsRowLabel(
                    title: "Ticking stocks the Pantry",
                    detail: "Anything you tick off the grocery list counts as bought."
                )
            }
            .tint(accent.deep)
        }
    }

    // MARK: - Data

    private var dataCard: some View {
        SettingsCard(
            title: "Your data",
            note: "Everything lives on this phone. Nothing is uploaded, and there's no account."
        ) {
            VStack(spacing: CozySpacing.xs) {
                dataRow(label: "Recipes", value: recipes.count)
                dataRow(label: "Collections", value: collections.count)
                dataRow(label: "Planned meals", value: plannedMeals.count)
            }

            Divider().overlay(CozyColor.outline)

            Button(role: .destructive) {
                isConfirmingRecipeDeletion = true
            } label: {
                Text("Delete every recipe")
                    .font(CozyFont.bodyEmphasis)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: CozyMetrics.minimumTouchTarget)
                    .contentShape(.rect)
            }
            .disabled(recipes.isEmpty)
            .opacity(recipes.isEmpty ? 0.5 : 1)
        }
    }

    private func dataRow(label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .cozyText(CozyFont.body)
            Spacer()
            Text("\(value)")
                .cozyText(CozyFont.bodyEmphasis, color: CozyColor.inkSecondary)
                .monospacedDigit()
        }
    }

    // MARK: - About

    private var aboutCard: some View {
        SettingsCard(title: "About") {
            NavigationLink {
                ComponentGalleryView(accent: $accentSelection)
            } label: {
                SettingsRowLabel(
                    title: "Design system",
                    detail: "Every colour, type style and component on one screen."
                )
            }
            .buttonStyle(.squishy)

            Divider().overlay(CozyColor.outline)

            VStack(spacing: CozySpacing.xs) {
                Text(AppBranding.tagline)
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                Text(AppBranding.versionDisplayString)
                    .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, CozySpacing.xs)
        }
    }

    // MARK: - Actions

    /// Deletes the recipes themselves. Collections, the plan and the grocery
    /// list are left alone — they're separate work the user hasn't asked to
    /// throw away, and SwiftData clears the relationships for us.
    private func deleteAllRecipes() {
        for recipe in recipes {
            modelContext.delete(recipe)
        }

        do {
            try modelContext.save()
            Haptics.notify(.success)
        } catch {
            Log.data.error("Could not delete recipes: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Pieces

/// A titled card with a stack of settings inside it. Every section on this
/// screen is one of these, so they can't drift apart.
private struct SettingsCard<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .cozyText(CozyFont.title2)

                    if let note {
                        Text(note)
                            .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Title over explanation, used by both toggles and navigation rows so a row
/// reads the same whichever it is.
private struct SettingsRowLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(spacing: CozySpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .cozyText(CozyFont.bodyEmphasis)
                    .multilineTextAlignment(.leading)

                if let detail {
                    Text(detail)
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
    }
}

// MARK: - Previews

#Preview("Settings") {
    @Previewable @State var accent = AccentPalette.blush
    @Previewable @State var appearance = AppAppearance.system

    SettingsView(accentSelection: $accent, appearance: $appearance)
        .modelContainer(PreviewData.container)
}

#Preview("Settings — dark") {
    @Previewable @State var accent = AccentPalette.mint
    @Previewable @State var appearance = AppAppearance.dark

    SettingsView(accentSelection: $accent, appearance: $appearance)
        .modelContainer(PreviewData.container)
        .preferredColorScheme(.dark)
}
