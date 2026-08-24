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
import os

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
            VStack(spacing: 0) {
                ScreenHeader(title: "Settings", eyebrow: AppBranding.appName)

                ScrollView {
                    VStack(spacing: CozySpacing.l) {
                        sousChefCard
                        cookingCard
                        appearanceCard
                        groceriesCard
                        dataCard
                        aboutCard
                        footerCard
                    }
                    .padding(CozySpacing.l)
                }
            }
            .cozyScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
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
                        : "Asleep — no key yet",
                    showsChevron: true
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
            SettingsHeading(text: "Units")

            SettingsSegmented(
                label: "Units",
                options: MeasurementSystem.allCases.map { SettingsOption(value: $0.rawValue, title: $0.displayName) },
                selection: $measurementRaw
            )

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
                SettingsHeading(text: "Accent")
                accentPicker
            }

            settingsDivider

            VStack(alignment: .leading, spacing: CozySpacing.s) {
                SettingsHeading(text: "Appearance")

                SettingsSegmented(
                    label: "Appearance",
                    options: AppAppearance.allCases.map { SettingsOption(value: $0, title: $0.displayName) },
                    selection: $appearance
                )
            }

            settingsDivider

            Toggle(isOn: $hapticsEnabled) {
                SettingsRowLabel(title: "Haptics", detail: "A soft tap on every press.")
            }
            .tint(accent.deep)
        }
    }

    /// Five swatches, each filled with its own deep step and ringed in it when
    /// chosen.
    ///
    /// Squares rather than circles, and no names: five colour words in a row
    /// were being read instead of the colours, which is the one thing a colour
    /// picker must not make you do. Still writes straight through to
    /// CozyDefaultsKey.accentPalette by way of the binding it was handed.
    private var accentPicker: some View {
        HStack(spacing: CozySpacing.m) {
            ForEach(AccentPalette.allCases) { palette in
                let isSelected = palette == accentSelection

                Button {
                    guard !isSelected else { return }
                    accentSelection = palette
                    Haptics.selection()
                } label: {
                    RoundedRectangle(cornerRadius: CozyRadius.field, style: .continuous)
                        .fill(palette.deep)
                        .frame(width: 46, height: 46)
                        .overlay {
                            // A ring set *outside* the swatch, in the swatch's
                            // own colour. A tick drawn on top would have to be
                            // legible on all five, and butter is not blush.
                            RoundedRectangle(cornerRadius: CozyRadius.field + 4, style: .continuous)
                                .strokeBorder(isSelected ? palette.deep : .clear, lineWidth: 3)
                                .padding(-5)
                        }
                        // Draws at 46, stays tappable at 44 plus its ring.
                        .frame(minWidth: CozyMetrics.minimumTouchTarget,
                               minHeight: CozyMetrics.minimumTouchTarget)
                        .contentShape(.rect)
                }
                .buttonStyle(.squishy)
                .accessibilityLabel(palette.displayName)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Accent colour")
    }

    /// One rule, so the six cards can't each pick their own.
    private var settingsDivider: some View {
        Rectangle()
            .fill(CozyColor.creamDeep)
            .frame(height: 1.5)
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

            settingsDivider

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

            settingsDivider

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
                    detail: "Every colour, type style and component on one screen.",
                    showsChevron: true
                )
            }
            .buttonStyle(.squishy)

            settingsDivider

            NavigationLink {
                TasteProfileView()
            } label: {
                SettingsRowLabel(
                    title: "What I've picked up",
                    detail: "Everything the Sous Chef thinks it knows about your cooking — and how to correct it.",
                    showsChevron: true
                )
            }
            .buttonStyle(.squishy)

            #if DEBUG
            settingsDivider

            NavigationLink {
                SignalInspectorView()
            } label: {
                SettingsRowLabel(
                    title: "Taste signals",
                    detail: "The raw learning log, with the decay arithmetic. Debug builds only.",
                    showsChevron: true
                )
            }
            .buttonStyle(.squishy)
            #endif

        }
    }

    /// The sign-off. Blush, so the screen ends on the same colour it started
    /// on, and the one place on Settings the mascot gets to appear.
    private var footerCard: some View {
        CrumbCard(fill: accent.color, cornerRadius: CozyRadius.sheet, block: accent.block) {
            HStack(spacing: CozySpacing.l) {
                MascotView(pose: .idle, size: 52)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: CozySpacing.s) {
                    Text(AppBranding.tagline)
                        .cozyText(CozyFont.cardTitle, color: CozyColor.inkOnAccent)
                        .cozyDisplayTracking(CozyTracking.cardTitle, relativeTo: .headline)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(AppBranding.versionDisplayString)
                        .cozyEyebrow(color: CozyColor.inkOnAccent)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        CrumbCard(cornerRadius: CozyRadius.sheet) {
            VStack(alignment: .leading, spacing: CozySpacing.m) {
                VStack(alignment: .leading, spacing: CozySpacing.s) {
                    // The group's name is a label on the card, not a heading
                    // inside it. Set as a 26pt title it was bigger than every
                    // setting it introduced, so a screen of six of them read as
                    // six headlines with some controls in between.
                    Text(title)
                        .cozyEyebrow(color: CozyColor.inkSecondary,
                                     tracking: CozyTracking.eyebrowWide)

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

/// A setting's own title, inside a group. The display face at 19pt, which is
/// where it takes over from SF Rounded elsewhere in the app.
private struct SettingsHeading: View {
    let text: String

    var body: some View {
        Text(text)
            .cozyText(CozyFont.cardTitle)
            .cozyDisplayTracking(CozyTracking.cardTitle, relativeTo: .headline)
    }
}

/// Three-up segmented control, drawn in the app's own colours.
///
/// `.pickerStyle(.segmented)` brings iOS's grey capsule with it, which is the
/// one piece of system chrome that survived on this screen and the only grey
/// thing in a warm app.
private struct SettingsOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String

    var id: Value { value }
}

private struct SettingsSegmented<Value: Hashable>: View {
    @Environment(\.accentPalette) private var accent

    let label: String
    let options: [SettingsOption<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options) { option in
                let isSelected = option.value == selection

                Button {
                    guard !isSelected else { return }
                    selection = option.value
                    Haptics.selection()
                } label: {
                    Text(option.title)
                        .font(CozyFont.caption.weight(.bold))
                        .foregroundStyle(isSelected ? CozyColor.inkOnAccent : CozyColor.inkPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: CozyMetrics.minimumTouchTarget)
                        .background(isSelected ? accent.color : CozyColor.creamDeep,
                                    in: .rect(cornerRadius: 11, style: .continuous))
                        .contentShape(.rect)
                }
                .buttonStyle(.squishy)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Title over explanation, used by both toggles and navigation rows so a row
/// reads the same whichever it is.
private struct SettingsRowLabel: View {
    @Environment(\.accentPalette) private var accent

    let title: String
    var detail: String?
    /// Rows that go somewhere say so. Toggles don't, and pass false.
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: CozySpacing.s) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .cozyText(CozyFont.cardTitle)
                    .cozyDisplayTracking(CozyTracking.cardTitle, relativeTo: .headline)
                    .multilineTextAlignment(.leading)

                if let detail {
                    Text(detail)
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(accent.deep)
            }
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
