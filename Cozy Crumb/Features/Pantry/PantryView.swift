//
//  PantryView.swift
//  Cozy Crumb
//
//  Phase 9. What's in.
//
//  Two things earn this screen its tab: the Sous Chef reads it to answer "what
//  can I make tonight?", and it's what stops a third jar of tahini. Both only
//  work if it's accurate, and it's only accurate if keeping it up to date is
//  nearly free — hence a one-line add, a photo of the fridge, and "used it up"
//  on every row.
//
//  Expiry outranks aisle. Something going off tomorrow sits at the top under
//  its own heading, whatever shelf it lives on.
//

import PhotosUI
import SwiftData
import SwiftUI

struct PantryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accentPalette) private var accent
    @Environment(\.cozyMotion) private var motion

    @Query(sort: \PantryItem.name) private var items: [PantryItem]

    @State private var viewModel = PantryViewModel()
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var editingExpiry: PantryItem?

    private var groups: [PantryViewModel.Group] {
        viewModel.groups(from: items)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isReadingPhotos {
                    reading
                } else if items.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .background { BlobBackground() }
            .navigationTitle("Pantry")
            .safeAreaInset(edge: .top) { addBar }
            .toolbar { photoButton }
            .sheet(item: $editingExpiry) { item in
                PantryExpirySheet(item: item) { date in
                    viewModel.setExpiry(date, on: item, in: modelContext)
                }
            }
            .sheet(isPresented: showingSpotted) {
                FridgePhotoReviewView(items: viewModel.spotted) { kept in
                    viewModel.accept(kept, in: modelContext)
                } onCancel: {
                    viewModel.discardSpotted()
                }
            }
            .alert(
                "That didn't work",
                isPresented: .init(
                    get: { viewModel.failure != nil },
                    set: { if !$0 { viewModel.failure = nil } }
                )
            ) {
                Button("Fair enough", role: .cancel) { viewModel.failure = nil }
            } message: {
                Text(viewModel.failure?.friendlyMessage ?? "")
            }
            .onChange(of: photoSelection) { _, picked in
                guard !picked.isEmpty else { return }
                Task { await handlePicked(picked) }
            }
        }
    }

    private var showingSpotted: Binding<Bool> {
        .init(
            get: { !viewModel.spotted.isEmpty },
            set: { if !$0 { viewModel.discardSpotted() } }
        )
    }

    // MARK: - States

    private var empty: some View {
        EmptyStateView(
            title: "The pantry's bare.",
            message: "Type what you've got in above — or snap a photo of the fridge and I'll take a look.",
            pose: .peeking
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reading: some View {
        CozyLoadingView(
            messages: [
                "Peering into the fridge…",
                "Squinting at the back of the shelf…",
                "Working out what's what…"
            ],
            pose: .peeking
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CozySpacing.l) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: CozySpacing.s) {
                        header(for: group)

                        CrumbCard(padding: CozySpacing.s) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 {
                                        Divider()
                                            .overlay(CozyColor.outline)
                                            .padding(.leading, CozySpacing.s)
                                    }

                                    row(for: item)
                                }
                            }
                        }
                    }
                }
            }
            .padding(CozySpacing.l)
            .padding(.bottom, CozySpacing.xxl)
        }
    }

    private func header(for group: PantryViewModel.Group) -> some View {
        HStack(spacing: CozySpacing.xs) {
            Image(systemName: group.section.symbol)
                .font(.caption.weight(.semibold))
            Text(group.section.title)
                .font(CozyFont.caption.weight(.semibold))
            Spacer()
            Text("\(group.items.count)")
                .font(CozyFont.caption2)
        }
        .foregroundStyle(CozyColor.inkPrimary)
        .padding(.horizontal, CozySpacing.m)
        .padding(.vertical, CozySpacing.s)
        .background(tint(for: group.section), in: .rect(cornerRadius: CozyRadius.chip, style: .continuous))
    }

    private func tint(for section: PantryViewModel.Section) -> Color {
        switch section {
        case .expiring: CozyColor.warning.opacity(0.6)
        case .category(let category): category.tint.opacity(0.55)
        }
    }

    private func row(for item: PantryItem) -> some View {
        HStack(spacing: CozySpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: CozySpacing.xs) {
                    Text(item.name)
                        .cozyText(CozyFont.body)

                    Spacer(minLength: CozySpacing.s)

                    if let amount = amountText(for: item) {
                        Text(amount)
                            .cozyText(CozyFont.bodyEmphasis, color: CozyColor.inkSecondary)
                            .monospacedDigit()
                    }
                }

                if let caption = caption(for: item) {
                    Text(caption)
                        .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                }
            }
        }
        .padding(.vertical, CozySpacing.s)
        .padding(.horizontal, CozySpacing.s)
        .frame(minHeight: CozyMetrics.minimumTouchTarget)
        .contentShape(.rect)
        .contextMenu {
            Button {
                editingExpiry = item
            } label: {
                Label(item.expiresAt == nil ? "Add a use-by date" : "Change the use-by date",
                      systemImage: "calendar")
            }

            Button(role: .destructive) {
                withAnimation(motion(Motion.gentle)) {
                    viewModel.useUp(item, in: modelContext)
                }
            } label: {
                Label("Used it up", systemImage: "checkmark.circle")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: item))
    }

    private func amountText(for item: PantryItem) -> String? {
        let text = FractionFormatter.quantityString(quantity: item.quantity, unit: item.unit)
        return text.isEmpty ? nil : text
    }

    private func caption(for item: PantryItem) -> String? {
        var parts: [String] = []

        if let days = item.daysUntilExpiry() {
            let expiry: String = switch days {
            case ..<0: "went off \(-days)d ago"
            case 0: "use today"
            case 1: "use tomorrow"
            default: "\(days) days left"
            }
            parts.append(expiry)
        }

        if item.source == .fridgePhoto {
            parts.append("spotted in a photo")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func accessibilityLabel(for item: PantryItem) -> String {
        [amountText(for: item), item.name, caption(for: item)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    // MARK: - Adding

    private var addBar: some View {
        HStack(spacing: CozySpacing.s) {
            CozyTextField(
                placeholder: "Half a jar of tahini…",
                text: $viewModel.draft,
                systemImage: "plus.circle",
                submitLabel: .done
            ) {
                withAnimation(motion(Motion.gentle)) {
                    viewModel.addTyped(in: modelContext)
                }
            }
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.vertical, CozySpacing.m)
        .background(.ultraThinMaterial)
    }

    @ToolbarContentBuilder
    private var photoButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            PhotosPicker(
                selection: $photoSelection,
                maxSelectionCount: 4,
                matching: .images
            ) {
                Image(systemName: "camera")
                    .foregroundStyle(CozyColor.inkSecondary)
            }
            .disabled(!viewModel.canReadPhotos)
            .accessibilityLabel("Read the fridge from a photo")
        }
    }

    private func handlePicked(_ picked: [PhotosPickerItem]) async {
        photoSelection = []

        var photos: [Data] = []

        for item in picked {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let jpeg = ImageProcessor.downscaledJPEG(from: data) else { continue }
            photos.append(jpeg)
        }

        await viewModel.read(photos: photos)
    }
}

// MARK: - Use-by sheet

private struct PantryExpirySheet: View {
    @Environment(\.dismiss) private var dismiss

    let item: PantryItem
    let onSave: (Date?) -> Void

    @State private var date: Date

    init(item: PantryItem, onSave: @escaping (Date?) -> Void) {
        self.item = item
        self.onSave = onSave
        _date = State(initialValue: item.expiresAt ?? Date.now.addingTimeInterval(3 * 86_400))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: CozySpacing.l) {
                DatePicker("Use by", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(CozyColor.blushDeep)

                SquishyButton(title: "Save", systemImage: "checkmark") {
                    onSave(date)
                    dismiss()
                }

                if item.expiresAt != nil {
                    Button("Remove the date") {
                        onSave(nil)
                        dismiss()
                    }
                    .font(CozyFont.subheadline)
                    .foregroundStyle(CozyColor.inkSecondary)
                    .frame(minHeight: CozyMetrics.minimumTouchTarget)
                }

                Spacer(minLength: 0)
            }
            .padding(CozySpacing.l)
            .background { BlobBackground() }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Previews

#Preview("Pantry") {
    PantryView()
        .modelContainer(PreviewData.container)
}
