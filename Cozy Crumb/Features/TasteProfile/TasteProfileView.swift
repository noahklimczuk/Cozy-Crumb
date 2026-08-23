//
//  TasteProfileView.swift
//  Cozy Crumb
//
//  "What I've picked up" — everything the app thinks it knows, in the user's
//  own language, and correctable.
//
//  §8 calls this non-negotiable, and it is right to. An app that silently
//  profiles you and cannot be corrected degrades on its own: a wrong
//  inference feeds the recommendations, the recommendations get worse, and
//  nobody can see why. Every claim here is tappable, every claim shows what
//  it was built from, and every claim can be edited or forgotten.
//
//  The writing matters as much as the mechanism. This is not a data dump with
//  a heading; it reads like someone telling you what they've noticed. A
//  screen of decimals would be accurate and awful.
//
//  The confidence line is deliberately the first thing on it. "Still getting
//  to know you" is honest and rather charming; a confidently wrong profile is
//  off-putting, and the fortnight where it is wrong is the fortnight that
//  decides whether anyone keeps using the feature.
//

import SwiftData
import SwiftUI

struct TasteProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent

    @Query private var profiles: [TasteProfile]
    @Query private var facts: [CookFact]

    @State private var editingKey: String?
    @State private var editingLabel = ""
    @State private var editingValue = 0.0
    @State private var editingFact: CookFact?
    @State private var editingFactText = ""
    @State private var isConfirmingStartFresh = false

    private var snapshot: TasteProfileSnapshot {
        profiles.first?.snapshot ?? TasteProfileSnapshot()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: CozySpacing.l) {
                confidenceCard

                if snapshot.isEmpty {
                    EmptyStateView(
                        title: "Nothing picked up yet.",
                        message: "Cook something, favourite something, tick something off the shopping list — I'll start noticing on my own. Nothing you have to fill in.",
                        pose: .idle
                    )
                } else {
                    scheduleCard
                    tasteCard
                    ingredientsCard
                    techniqueCard
                    kitchenCard
                }

                factsCard
                privacyCard
                startFreshCard
            }
            .padding(CozySpacing.l)
        }
        .background { BlobBackground() }
        .navigationTitle("What I've picked up")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { editingKey.map(EditingInference.init(key:)) },
            set: { if $0 == nil { editingKey = nil } }
        )) { editing in
            editSheet(for: editing.key)
        }
        .sheet(item: $editingFact) { fact in
            factEditSheet(for: fact)
        }
        .confirmationDialog(
            "Forget everything you've picked up?",
            isPresented: $isConfirmingStartFresh,
            titleVisibility: .visible
        ) {
            Button("Start fresh", role: .destructive) {
                TasteProfileStore.startFresh(in: modelContext)
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Every signal and every correction goes. Your recipes, plan and shopping list are untouched.")
        }
    }

    // MARK: - Confidence

    private var confidenceCard: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text(snapshot.confidenceDescription)
                    .cozyText(CozyFont.title2)

                ProgressView(value: snapshot.confidence)
                    .tint(accent.deep)

                Text(confidenceNote)
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var confidenceNote: String {
        guard !snapshot.isEmpty else {
            return "I haven't seen you cook anything yet, so I'm not guessing at your taste."
        }

        let base = "Built from \(snapshot.signalCount) things you've done in the app."

        return snapshot.isUsable
            ? base
            : base + " Not enough yet for me to lean on it, so I'll ask rather than assume."
    }

    // MARK: - Sections

    private var scheduleCard: some View {
        SettingsCardShim(title: "Your week") {
            if !snapshot.busiestCookingDays.isEmpty {
                inferenceRow(
                    key: ProfileKey.schedule,
                    label: "You cook most on " + snapshot.busiestCookingDays
                        .prefix(3)
                        .map { SignalContext(weekday: $0, hour: 12, season: .spring).weekdayName }
                        .joined(separator: ", "),
                    isEditable: false
                )
            }

            let weeknight = [2, 3, 4, 5, 6].compactMap { snapshot.effortMinutesByWeekday[$0] }
            if !weeknight.isEmpty {
                inferenceRow(
                    key: ProfileKey.effort,
                    label: "Weeknights, you tend to spend about \(weeknight.reduce(0, +) / weeknight.count) minutes",
                    isEditable: false
                )
            }

            if let household = snapshot.inferredHouseholdSize {
                inferenceRow(
                    key: ProfileKey.householdSize,
                    label: "You usually cook for \(household)",
                    isEditable: false
                )
            }
        }
    }

    private var tasteCard: some View {
        SettingsCardShim(title: "What you reach for") {
            ForEach(snapshot.topCuisines(5)) { entry in
                inferenceRow(
                    key: ProfileKey.cuisine(entry.name),
                    label: "You seem to enjoy \(entry.name) food",
                    value: entry.score
                )
            }

            ForEach(snapshot.coolerCuisines(3)) { entry in
                inferenceRow(
                    key: ProfileKey.cuisine(entry.name),
                    label: "You're cooler on \(entry.name) food",
                    value: entry.score
                )
            }

            if snapshot.topCuisines(5).isEmpty && snapshot.coolerCuisines(3).isEmpty {
                emptyNote("Nothing settled yet — cook a few more things and this will fill in.")
            }
        }
    }

    private var ingredientsCard: some View {
        SettingsCardShim(title: "Likes and dislikes") {
            ForEach(snapshot.lovedIngredients(8)) { entry in
                inferenceRow(
                    key: ProfileKey.ingredient(entry.name),
                    label: "You seem to love \(entry.name)",
                    value: entry.score
                )
            }

            ForEach(snapshot.avoidedIngredients(8)) { entry in
                inferenceRow(
                    key: ProfileKey.ingredient(entry.name),
                    label: snapshot.explicitlyDisliked.contains(entry.name)
                        ? "You told me you don't like \(entry.name)"
                        : "You steer clear of \(entry.name)",
                    value: entry.score
                )
            }

            if snapshot.lovedIngredients(8).isEmpty && snapshot.avoidedIngredients(8).isEmpty {
                emptyNote("Nothing strong enough to mention yet.")
            }
        }
    }

    private var techniqueCard: some View {
        SettingsCardShim(title: "What you're up for") {
            ForEach(snapshot.comfortableTechniques(6)) { entry in
                inferenceRow(
                    key: ProfileKey.technique(entry.name),
                    label: "You're comfortable with \(entry.name)",
                    value: entry.score
                )
            }

            if let spice = snapshot.spiceDescription {
                inferenceRow(
                    key: ProfileKey.spiceTolerance,
                    label: "You like your food \(spice)",
                    isEditable: false
                )
            }

            inferenceRow(
                key: ProfileKey.noveltyAppetite,
                label: noveltyLabel,
                value: snapshot.noveltyAppetite,
                range: 0...1
            )
        }
    }

    private var noveltyLabel: String {
        switch snapshot.noveltyAppetite {
        case ..<0.3: "You've got a rotation and you like it"
        case ..<0.6: "You'll try new things, but you have your regulars"
        default: "You like trying something different"
        }
    }

    private var kitchenCard: some View {
        SettingsCardShim(title: "Your kitchen") {
            if snapshot.inferredEquipment.isEmpty {
                emptyNote("I haven't spotted any particular kit yet. I only notice things you've actually cooked with — I never assume you don't own something.")
            } else {
                ForEach(snapshot.inferredEquipment.sorted(), id: \.self) { equipment in
                    inferenceRow(
                        key: ProfileKey.equipment(equipment),
                        label: "You've got \(anArticle(for: equipment)) \(equipment)",
                        isEditable: false
                    )
                }
            }
        }
    }

    private func anArticle(for word: String) -> String {
        "aeiou".contains(word.lowercased().first ?? "x") ? "an" : "a"
    }

    private var factsCard: some View {
        SettingsCardShim(title: "Things you've told me") {
            let active = facts.filter(\.isActive)

            if active.isEmpty {
                emptyNote("Nothing yet. Mention an allergy or who you're cooking for in the chat and I'll remember it.")
            } else {
                ForEach(active.sorted { $0.createdAt < $1.createdAt }) { fact in
                    factRow(fact)
                }
            }
        }
    }

    private var privacyCard: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.xs) {
                Label("All of this stays on your phone", systemImage: "lock.fill")
                    .cozyText(CozyFont.bodyEmphasis)

                Text("Your signals, this profile and everything you've told me live only on this device. When you ask the Sous Chef something, a short summary goes with the question — nothing else, and only then.")
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var startFreshCard: some View {
        Button(role: .destructive) {
            isConfirmingStartFresh = true
        } label: {
            Label("Start fresh", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.squishy)
    }

    // MARK: - Rows

    @ViewBuilder
    private func inferenceRow(
        key: String,
        label: String,
        value: Double? = nil,
        range: ClosedRange<Double> = -1...1,
        isEditable: Bool = true
    ) -> some View {
        VStack(alignment: .leading, spacing: CozySpacing.xs) {
            HStack(alignment: .top) {
                Text(label)
                    .cozyText(CozyFont.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    if isEditable, value != nil {
                        Button("Change this", systemImage: "slider.horizontal.3") {
                            editingKey = key
                            editingLabel = label
                            editingValue = value ?? 0
                        }
                    }
                    Button("Forget this", systemImage: "eye.slash", role: .destructive) {
                        TasteProfileStore.dismiss(key, in: modelContext)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(CozyColor.inkSecondary)
                }
                .accessibilityLabel("Change or forget: \(label)")
            }

            // Every inference is tappable and shows the evidence. Without
            // this the screen is just a nicer-looking data dump.
            if let evidence = snapshot.evidence[key] {
                Text(evidence.summary)
                    .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func factRow(_ fact: CookFact) -> some View {
        VStack(alignment: .leading, spacing: CozySpacing.xs) {
            HStack(alignment: .top) {
                Label {
                    Text(fact.statement)
                        .cozyText(CozyFont.body)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: fact.category.symbol)
                        .foregroundStyle(fact.category.isSafetyRelevant ? CozyColor.blushDeep : CozyColor.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button("Edit", systemImage: "pencil") {
                        editingFactText = fact.statement
                        editingFact = fact
                    }
                    Button("Forget this", systemImage: "trash", role: .destructive) {
                        CookFactStore.forget(fact, in: modelContext)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(CozyColor.inkSecondary)
                }
                .accessibilityLabel("Edit or forget: \(fact.statement)")
            }

            if fact.needsConfirmation {
                Text("Waiting on you — I'm not filtering anything out until you say so.")
                    .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
            } else if let excerpt = fact.sourceExcerpt, !excerpt.isEmpty {
                Text("Because you said: \"\(excerpt)\"")
                    .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(fact.provenanceLabel)
                    .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(text)
            .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Editing

    private func editSheet(for key: String) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: CozySpacing.l) {
                Text(editingLabel)
                    .cozyText(CozyFont.title2)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Drag to tell me how far off I am. Once you set this by hand I'll stop guessing at it.")
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Slider(value: $editingValue, in: -1...1)
                    .tint(accent.deep)

                HStack {
                    Text("Not for me").cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                    Spacer()
                    Text("Love it").cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                }

                Spacer()
            }
            .padding(CozySpacing.l)
            .navigationTitle("Set it straight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        TasteProfileStore.override(key, value: editingValue, in: modelContext)
                        editingKey = nil
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingKey = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func factEditSheet(for fact: CookFact) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: CozySpacing.m) {
                CozyTextField(placeholder: "What should I know?", text: $editingFactText)

                Text("I'll take this as your own words from now on and stop trying to work it out.")
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding(CozySpacing.l)
            .navigationTitle("Put it in your words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        CookFactStore.update(fact, statement: editingFactText, in: modelContext)
                        editingFact = nil
                    }
                    .disabled(editingFactText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingFact = nil }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// `sheet(item:)` needs something Identifiable, and a bare String key isn't.
private struct EditingInference: Identifiable {
    let key: String
    var id: String { key }
}

/// The same card chrome Settings uses. Duplicated rather than shared because
/// the Settings version is private to that file and this screen has no
/// business reaching into it.
private struct SettingsCardShim<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.m) {
                Text(title)
                    .cozyText(CozyFont.title2)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Taste profile") {
    NavigationStack {
        TasteProfileView()
    }
    .modelContainer(PreviewData.container)
}
