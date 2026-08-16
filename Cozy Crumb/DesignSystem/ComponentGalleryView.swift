//
//  ComponentGalleryView.swift
//  Cozy Crumb
//
//  The whole visual language on one screen. This is the Phase 1 deliverable —
//  it exists to be looked at, in light and dark, at normal and accessibility
//  text sizes, with the accent picker live.
//
//  Reachable in-app from Settings so it can be checked on a real device, where
//  haptics and the motion actually work.
//

import SwiftUI

struct ComponentGalleryView: View {
    @Binding var accent: AccentPalette

    @State private var searchText = ""
    @State private var secureText = ""
    @State private var selectedChip = "Weeknight"
    @State private var isFavourite = true
    @State private var motionToggle = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CozySpacing.xxl) {
                accentSection
                colourSection
                typographySection
                buttonSection
                cardSection
                chipSection
                fieldSection
                mascotSection
                motionSection
                stateSection
            }
            .padding(CozySpacing.l)
        }
        .background { BlobBackground() }
        .navigationTitle("Design System")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var accentSection: some View {
        GallerySection("Accent", note: "Re-tints the whole app (§5.9).") {
            ScrollView(.horizontal) {
                HStack(spacing: CozySpacing.s) {
                    ForEach(AccentPalette.allCases) { palette in
                        SelectableChip(
                            text: palette.displayName,
                            tint: palette.color,
                            isSelected: palette == accent
                        ) {
                            accent = palette
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var colourSection: some View {
        GallerySection("Colour", note: "inkSecondary darkened to #826F64 for 4.63:1 on cream.") {
            VStack(alignment: .leading, spacing: CozySpacing.m) {
                swatchRow("Surfaces", [
                    ("cream", CozyColor.cream),
                    ("card", CozyColor.card),
                    ("creamDeep", CozyColor.creamDeep)
                ])
                swatchRow("Hero", [
                    ("blush", CozyColor.blush),
                    ("blushDeep", CozyColor.blushDeep),
                    ("blushSoft", CozyColor.blushSoft)
                ])
                swatchRow("Accents", [
                    ("mint", CozyColor.mint),
                    ("butter", CozyColor.butter),
                    ("sky", CozyColor.sky),
                    ("lavender", CozyColor.lavender),
                    ("peach", CozyColor.peach),
                    ("sage", CozyColor.sage)
                ])
                swatchRow("Ink & line", [
                    ("inkPrimary", CozyColor.inkPrimary),
                    ("inkSecondary", CozyColor.inkSecondary),
                    ("outline", CozyColor.outline),
                    ("outlineStrong", CozyColor.outlineStrong)
                ])
                swatchRow("Semantic", [
                    ("success", CozyColor.success),
                    ("warning", CozyColor.warning),
                    ("danger", CozyColor.danger)
                ])
            }
        }
    }

    private var typographySection: some View {
        GallerySection("Typography", note: "SF Rounded, scaling with Dynamic Type.") {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("Display").cozyText(CozyFont.display)
                Text("Title").cozyText(CozyFont.title)
                Text("Title 2").cozyText(CozyFont.title2)
                Text("Headline").cozyText(CozyFont.headline)
                Text("Body — the quick brown fox jumped over the lazy dog.")
                    .cozyText(CozyFont.body)
                Text("Subheadline supporting text")
                    .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                Text("CAPTION / METADATA")
                    .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                Text("Cook step text")
                    .cozyText(CozyFont.cookStep)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var buttonSection: some View {
        GallerySection("Buttons", note: "Press one — 0.94 squish plus a soft tap.") {
            VStack(spacing: CozySpacing.m) {
                SquishyButton(title: "Save this recipe", systemImage: "heart.fill") {}
                SquishyButton(title: "Send to Notes", systemImage: "note.text", emphasis: .secondary) {}
                SquishyButton(title: "Copy list", emphasis: .quiet) {}

                HStack(spacing: CozySpacing.m) {
                    SquishyIconButton(
                        systemImage: isFavourite ? "heart.fill" : "heart",
                        accessibilityLabel: "Favourite",
                        isOn: isFavourite
                    ) {
                        isFavourite.toggle()
                    }
                    SquishyIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: "Share") {}
                    SquishyIconButton(systemImage: "plus", accessibilityLabel: "Add") {}
                    Spacer()
                }
            }
        }
    }

    private var cardSection: some View {
        GallerySection("Cards") {
            VStack(spacing: CozySpacing.m) {
                CrumbCard {
                    VStack(alignment: .leading, spacing: CozySpacing.s) {
                        Text("Brown Butter Banana Bread")
                            .cozyText(CozyFont.title2)
                        Text("A loaf that makes the whole flat smell like a bakery.")
                            .cozyText(CozyFont.subheadline, color: CozyColor.inkSecondary)
                        HStack(spacing: CozySpacing.s) {
                            PillTag(text: "1 hr 5 min", systemImage: "clock")
                            PillTag(text: "Serves 8", systemImage: "person.2", tint: CozyColor.butter)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                CrumbCardBleed {
                    ZStack {
                        LinearGradient(
                            colors: [CozyColor.peach, CozyColor.blush],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Text("Bleed card — hero images")
                            .cozyText(CozyFont.headline)
                    }
                    .frame(height: 120)
                }
            }
        }
    }

    private var chipSection: some View {
        GallerySection("Pills & chips") {
            VStack(alignment: .leading, spacing: CozySpacing.m) {
                HStack {
                    PillTag(text: "35 min", systemImage: "clock")
                    PillTag(text: "Vegan", tint: CozyColor.sage)
                    PillTag(text: "Produce", systemImage: "carrot", tint: CozyColor.mint)
                }

                ScrollView(.horizontal) {
                    HStack(spacing: CozySpacing.s) {
                        ForEach(["Weeknight", "Baking", "Mom's", "Slow", "Quick"], id: \.self) { name in
                            SelectableChip(
                                text: name,
                                tint: CozyColor.rotatedAccent(for: name),
                                isSelected: selectedChip == name
                            ) {
                                selectedChip = name
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var fieldSection: some View {
        GallerySection("Text fields") {
            VStack(spacing: CozySpacing.m) {
                CozyTextField(
                    placeholder: "Search your cookbook",
                    text: $searchText,
                    systemImage: "magnifyingglass"
                )
                CozyTextField(
                    placeholder: "Paste your API key",
                    text: $secureText,
                    systemImage: "key",
                    isSecure: true
                )
            }
        }
    }

    private var mascotSection: some View {
        GallerySection("Mascot", note: "The cupcake mascot breathes gently, blinks, and winks.") {
            ScrollView(.horizontal) {
                HStack(spacing: CozySpacing.l) {
                    ForEach(MascotView.Pose.allCases) { pose in
                        VStack(spacing: CozySpacing.s) {
                            MascotView(pose: pose, size: 84)
                            Text(pose.rawValue.capitalized)
                                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                        }
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, CozySpacing.s)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var motionSection: some View {
        GallerySection("Motion", note: "Tap to compare. All three flatten under Reduce Motion.") {
            VStack(spacing: CozySpacing.m) {
                HStack(spacing: CozySpacing.l) {
                    motionSwatch("bouncy", Motion.bouncy, CozyColor.blush)
                    motionSwatch("snappy", Motion.snappy, CozyColor.mint)
                    motionSwatch("gentle", Motion.gentle, CozyColor.sky)
                }
                SquishyButton(title: motionToggle ? "Send them back" : "Move them", emphasis: .secondary) {
                    motionToggle.toggle()
                }
            }
        }
    }

    private var stateSection: some View {
        GallerySection("Screen states", note: "Every screen ships all three.") {
            VStack(spacing: CozySpacing.l) {
                CrumbCard(fill: CozyColor.creamDeep) {
                    EmptyStateView(
                        title: "Your cookbook's a blank page.",
                        message: "Paste a link to get started — I'll do the tidying up.",
                        pose: .sleeping,
                        actionTitle: "Paste a link",
                        action: {}
                    )
                }
                CrumbCard(fill: CozyColor.creamDeep) {
                    CozyLoadingView(messages: [
                        "Squinting at the back of the shelf…",
                        "Is that a lime or a lemon…",
                        "Counting the eggs…"
                    ])
                    .frame(maxWidth: .infinity)
                }
                CrumbCard(fill: CozyColor.creamDeep) {
                    CozyErrorView(
                        message: "The kitchen's a bit quiet — check your connection?",
                        onRetry: {}
                    )
                }
            }
        }
    }

    // MARK: - Pieces

    private func motionSwatch(_ label: String, _ animation: Animation, _ colour: Color) -> some View {
        VStack(spacing: CozySpacing.s) {
            RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                .fill(colour)
                .frame(width: 52, height: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                        .strokeBorder(CozyColor.outline, lineWidth: CozyBorder.card)
                }
                .offset(y: motionToggle ? -26 : 0)
                .cozyAnimation(animation, value: motionToggle)
            Text(label)
                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
        }
        .frame(height: 100, alignment: .bottom)
    }

    private func swatchRow(_ title: String, _ colours: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: CozySpacing.s) {
            Text(title)
                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
            ScrollView(.horizontal) {
                HStack(spacing: CozySpacing.s) {
                    ForEach(colours, id: \.0) { name, colour in
                        VStack(spacing: CozySpacing.xs) {
                            RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                                .fill(colour)
                                .frame(width: 60, height: 44)
                                .overlay {
                                    RoundedRectangle(cornerRadius: CozyRadius.chip, style: .continuous)
                                        .strokeBorder(CozyColor.outline, lineWidth: 1)
                                }
                            Text(name)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(CozyColor.inkSecondary)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Section wrapper

private struct GallerySection<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var content: () -> Content

    init(_ title: String, note: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.note = note
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CozySpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .cozyText(CozyFont.title2)
                if let note {
                    Text(note)
                        .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Previews

#Preview("Gallery — light") {
    @Previewable @State var accent: AccentPalette = .blush
    NavigationStack {
        ComponentGalleryView(accent: $accent)
    }
    .environment(\.accentPalette, accent)
}

#Preview("Gallery — dark") {
    @Previewable @State var accent: AccentPalette = .blush
    NavigationStack {
        ComponentGalleryView(accent: $accent)
    }
    .environment(\.accentPalette, accent)
    .preferredColorScheme(.dark)
}

#Preview("Gallery — AX3") {
    @Previewable @State var accent: AccentPalette = .mint
    NavigationStack {
        ComponentGalleryView(accent: $accent)
    }
    .environment(\.accentPalette, accent)
    .environment(\.dynamicTypeSize, .accessibility3)
}
