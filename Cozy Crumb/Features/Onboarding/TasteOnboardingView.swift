//
//  TasteOnboardingView.swift
//  Cozy Crumb
//
//  §9. Forty-five seconds, entirely skippable, and worth offering.
//
//  The first two weeks decide whether anyone keeps using the Sous Chef, and
//  they are exactly the two weeks when it knows nothing. Behaviour will
//  eventually say everything this screen asks — but "eventually" is a
//  fortnight of generic suggestions, which is a fortnight of looking like
//  every other recipe app.
//
//  Two rules keep it from doing harm. Everything here is seeded at *moderate*
//  confidence, so a month of actual cooking overrules it — someone who picks
//  Thai off a list and then cooks Italian every night is an Italian cook, and
//  the profile should say so. And nothing is required: skipping produces an
//  honest empty profile rather than a half-filled one, which is the better of
//  the two.
//
//  Allergies are the exception to the moderate-confidence rule. Typed by
//  hand, on purpose, they are user-stated and enforced immediately — the
//  confirmation dance in §5 exists for things overheard in conversation, not
//  for an answer to a direct question.
//

import SwiftData
import SwiftUI

struct TasteOnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accentPalette) private var accent

    @AppStorage(CozyDefaultsKey.hasSeenTasteOnboarding) private var hasSeenOnboarding = false

    @State private var chosenCuisines: Set<String> = []
    @State private var avoided = ""
    @State private var allergies = ""
    @State private var householdSize = 2
    @State private var weeknightMinutes = 30

    /// What a chip is worth. Deliberately mild: it is a preference someone
    /// tapped in ten seconds, not four cooked dinners.
    private static let seededAffinity = 0.45

    private static let offered = [
        "italian", "thai", "mexican", "indian", "chinese", "japanese",
        "korean", "french", "greek", "middle eastern", "vietnamese", "british"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CozySpacing.l) {
                    intro
                    cuisineCard
                    avoidCard
                    householdCard
                    timeCard
                }
                .padding(CozySpacing.l)
            }
            .cozyScreenBackground()
            .navigationTitle("A quick hello")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { finish() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        // Skipping is a real answer. An honest empty profile
                        // beats a half-filled one.
                        hasSeenOnboarding = true
                        dismiss()
                    }
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: CozySpacing.s) {
            MascotView(pose: .idle, size: 56)

            Text("Tell me roughly where to start?")
                .cozyText(CozyFont.title2)

            Text("None of this is binding — I'll go by what you actually cook soon enough, and this just stops me being useless in the meantime. Skip it if you'd rather.")
                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cuisineCard: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.m) {
                Text("Anything here appeal?")
                    .cozyText(CozyFont.bodyEmphasis)

                FlowChips(items: Self.offered, selected: $chosenCuisines, accent: accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var avoidCard: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.m) {
                Text("Anything you don't eat?")
                    .cozyText(CozyFont.bodyEmphasis)

                CozyTextField(placeholder: "Allergies — I'll filter these out", text: $allergies)
                CozyTextField(placeholder: "Things you just don't like", text: $avoided)

                Text("Allergies are absolute — anything containing them never gets suggested.")
                    .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var householdCard: some View {
        CrumbCard {
            Stepper(value: $householdSize, in: 1...12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You usually cook for")
                        .cozyText(CozyFont.bodyEmphasis)
                    Text(householdSize == 1 ? "just you" : "\(householdSize) people")
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                }
            }
        }
    }

    private var timeCard: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("On a weeknight you've got about \(weeknightMinutes) minutes")
                    .cozyText(CozyFont.bodyEmphasis)

                Slider(
                    value: Binding(
                        get: { Double(weeknightMinutes) },
                        set: { weeknightMinutes = Int(($0 / 5).rounded()) * 5 }
                    ),
                    in: 10...120
                )
                .tint(accent.deep)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Saving

    private func finish() {
        let profile = TasteProfileStore.profile(in: modelContext)

        for cuisine in chosenCuisines {
            profile.userOverrides[ProfileKey.cuisine(cuisine)] = Self.seededAffinity
        }

        for name in Self.split(avoided) {
            let canonical = IngredientCanonicalizer.canonical(name)
            guard !canonical.isEmpty else { continue }
            // A dislike they typed is stronger than a chip they tapped, but
            // still short of the floor a stated "I hate this" gets in chat.
            profile.userOverrides[ProfileKey.ingredient(canonical)] = -0.8
        }

        if householdSize > 0 {
            CookFactStore.add(
                statement: householdSize == 1 ? "Cooks for one" : "Cooks for \(householdSize)",
                category: .household,
                confidence: 0.9,
                source: .userStated,
                excerpt: nil,
                in: modelContext
            )
        }

        CookFactStore.add(
            statement: "Has about \(weeknightMinutes) minutes on a weeknight",
            category: .schedule,
            confidence: 0.8,
            source: .userStated,
            excerpt: nil,
            in: modelContext
        )

        for allergen in Self.split(allergies) {
            // Answered directly, so enforced directly — the confirmation card
            // in §5 is for things overheard, not for this.
            CookFactStore.add(
                statement: "Allergic to \(allergen)",
                category: .allergy,
                confidence: 1,
                source: .userStated,
                excerpt: allergen,
                in: modelContext
            )
        }

        TasteProfileStore.rebuild(in: modelContext)

        hasSeenOnboarding = true
        dismiss()
    }

    nonisolated static func split(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ",;/&"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count > 1 }
    }
}

// MARK: - Chips

private struct FlowChips: View {
    let items: [String]
    @Binding var selected: Set<String>
    let accent: AccentPalette

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: CozySpacing.s)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: CozySpacing.s) {
            ForEach(items, id: \.self) { item in
                Button {
                    if selected.contains(item) {
                        selected.remove(item)
                    } else {
                        selected.insert(item)
                    }
                    Haptics.soft()
                } label: {
                    Text(item.capitalized)
                        .cozyText(CozyFont.caption)
                        .padding(.horizontal, CozySpacing.m)
                        .padding(.vertical, CozySpacing.s)
                        .frame(maxWidth: .infinity)
                        .background(
                            selected.contains(item) ? accent.soft : CozyColor.card,
                            in: .capsule
                        )
                        .overlay {
                            Capsule().strokeBorder(
                                selected.contains(item) ? accent.deep.opacity(0.5) : CozyColor.outline,
                                lineWidth: 1
                            )
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected.contains(item) ? [.isSelected] : [])
            }
        }
    }
}

#Preview("Onboarding") {
    TasteOnboardingView()
        .modelContainer(PreviewData.emptyContainer)
}
