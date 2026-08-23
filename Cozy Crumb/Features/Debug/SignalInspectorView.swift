//
//  SignalInspectorView.swift
//  Cozy Crumb
//
//  A window onto the taste signal log, for developers only.
//
//  This is how S1 gets verified. A signal system that logs nothing looks
//  exactly like one that works — the profile just comes out empty and every
//  recommendation downstream quietly degrades. The only way to know the hooks
//  are firing is to go and look, so this screen exists to be looked at:
//  cook something, favourite something, tick something off the list, come
//  here and see three new rows.
//
//  DEBUG-only, deliberately. It is not the Taste Profile screen from §8 —
//  that one is written for the user in plain language and lands in S8. This
//  one shows raw rows, raw weights and the decay arithmetic, and no user
//  should ever meet it.
//

#if DEBUG

import SwiftData
import SwiftUI

struct SignalInspectorView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TasteSignal.timestamp, order: .reverse)
    private var signals: [TasteSignal]

    @State private var pruneReport: String?

    private let now = Date.now

    var body: some View {
        List {
            summarySection

            Section("Recent") {
                if signals.isEmpty {
                    Text("Nothing logged yet. Cook something, favourite something, or tick an item off the shopping list.")
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                } else {
                    ForEach(signals.prefix(300)) { signal in
                        row(for: signal)
                    }
                }
            }

            maintenanceSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Taste signals")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var summarySection: some View {
        Section("Totals") {
            LabeledContent("Signals", value: "\(signals.count)")
                .monospacedDigit()

            LabeledContent(
                "Live weight",
                value: totalEffectiveWeight.formatted(.number.precision(.fractionLength(2)))
            )
            .monospacedDigit()

            ForEach(countsByKind) { entry in
                LabeledContent(entry.kind.debugDescription, value: "\(entry.count)")
                    .monospacedDigit()
            }
        }
    }

    private var maintenanceSection: some View {
        Section("Maintenance") {
            Button("Prune spent signals now") {
                let removed = SignalRetention.prune(in: modelContext, now: now)
                pruneReport = removed == 0 ? "Nothing was old enough." : "Removed \(removed)."
            }

            if let pruneReport {
                Text(pruneReport)
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
            }
        }
    }

    private func row(for signal: TasteSignal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(signal.kind.debugDescription)
                    .cozyText(CozyFont.bodyEmphasis)
                Spacer()
                Text(signed(signal.weight) + " → " + signed(signal.effectiveWeight(at: now)))
                    .cozyText(CozyFont.caption, color: weightColor(signal.weight))
                    .monospacedDigit()
            }

            Text(target(of: signal))
                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)

            Text(provenance(of: signal))
                .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Derived

    private var totalEffectiveWeight: Double {
        signals.reduce(0) { $0 + $1.effectiveWeight(at: now) }
    }

    private struct KindTally: Identifiable {
        var kind: SignalKind
        var count: Int
        var id: String { kind.rawValue }
    }

    private var countsByKind: [KindTally] {
        Dictionary(grouping: signals, by: \.kind)
            .map { KindTally(kind: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    /// What the signal points at, resolved back to a title where it can be.
    /// A signal whose recipe has since been deleted says so rather than
    /// showing a bare UUID — that is the soft-link design being visible.
    private func target(of signal: TasteSignal) -> String {
        if let recipeID = signal.recipeID {
            return recipeTitle(for: recipeID) ?? "a recipe since deleted"
        }
        if let ingredient = signal.ingredientName {
            return ingredient
        }
        if let tag = signal.tag {
            return "#\(tag)"
        }
        return "—"
    }

    private func recipeTitle(for id: UUID) -> String? {
        var descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.title
    }

    private func provenance(of signal: TasteSignal) -> String {
        var parts: [String] = []

        let days = signal.age(at: now)
        parts.append(days < 1 ? "today" : "\(Int(days))d ago")

        if let context = signal.context {
            parts.append("\(context.weekdayName) \(context.hour):00")
            parts.append(context.season.displayName)
        }

        if !signal.kind.decays {
            parts.append("does not decay")
        }

        return parts.joined(separator: " · ")
    }

    private func signed(_ value: Double) -> String {
        (value > 0 ? "+" : "") + value.formatted(.number.precision(.fractionLength(2)))
    }

    private func weightColor(_ weight: Double) -> Color {
        weight < 0 ? CozyColor.blushDeep : CozyColor.inkSecondary
    }
}

#Preview("Signal inspector") {
    NavigationStack {
        SignalInspectorView()
    }
    .modelContainer(PreviewData.container)
}

#endif
