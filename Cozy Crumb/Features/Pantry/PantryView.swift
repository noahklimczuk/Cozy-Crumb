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
import UIKit

struct PantryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cozyMotion) private var motion
    @Environment(\.accentPalette) private var accent

    // Archived rows are excluded here rather than filtered downstream: a
    // @Query that returns them would put decayed-away food back on the screen
    // in whichever view forgot to filter.
    @Query(
        filter: #Predicate<PantryItem> { $0.archivedAt == nil },
        sort: \PantryItem.displayName
    )
    private var items: [PantryItem]

    @State private var viewModel = PantryViewModel()
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var editingExpiry: PantryItem?

    /// The camera flow. Each step hands to the next through the presentation's
    /// own `onDismiss`, because a sheet and a full-screen cover cannot be
    /// swapped in the same run loop turn without one of them being dropped.
    @AppStorage(CozyDefaultsKey.seenFridgeCameraTips) private var seenCameraTips = false
    @State private var isShowingTips = false
    @State private var isShowingCamera = false
    @State private var isShowingShots = false
    @State private var isShowingPhotoPicker = false
    @State private var nextCameraStep: CameraStep?
    @State private var shots: [UIImage] = []

    /// What to do once the sheet that's on screen has finished getting out of
    /// the way.
    private enum CameraStep {
        case camera
        case shots
        case photoLibrary
    }

    private var groups: [PantryViewModel.Group] {
        viewModel.groups(from: items)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                if viewModel.isReadingPhotos {
                    reading
                } else if items.isEmpty {
                    empty
                } else {
                    list
                }
            }
            .cozyScreenBackground()
            .toolbar(.hidden, for: .navigationBar)
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
            .sheet(isPresented: $isShowingTips, onDismiss: advance) {
                FridgeCameraTipsView(
                    hasCamera: CameraCaptureView.isAvailable,
                    onStart: {
                        seenCameraTips = true
                        take(.camera)
                    },
                    onPickFromPhotos: { take(.photoLibrary) }
                )
            }
            .fullScreenCover(isPresented: $isShowingCamera, onDismiss: advance) {
                CameraCaptureView(
                    onCapture: { image in
                        shots.append(image)
                        take(.shots)
                    },
                    onCancel: {
                        // Back to the tray if anything has been taken already,
                        // otherwise the whole flow is over.
                        take(shots.isEmpty ? nil : .shots)
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isShowingShots, onDismiss: advance) {
                FridgeShotsView(
                    shots: shots,
                    hasCamera: CameraCaptureView.isAvailable,
                    onTakeAnother: { take(.camera) },
                    onRemove: { index in
                        shots.remove(at: index)
                        if shots.isEmpty { take(nil) }
                    },
                    onPickFromPhotos: { take(.photoLibrary) },
                    onRead: { take(nil); Task { await readShots() } }
                )
            }
            .photosPicker(
                isPresented: $isShowingPhotoPicker,
                selection: $photoSelection,
                maxSelectionCount: 4,
                matching: .images
            )
        }
    }

    // MARK: - The camera flow

    /// Closes whatever is on screen and remembers what comes next. Passing nil
    /// simply closes.
    private func take(_ step: CameraStep?) {
        nextCameraStep = step
        isShowingTips = false
        isShowingCamera = false
        isShowingShots = false
    }

    private func advance() {
        guard let step = nextCameraStep else { return }
        nextCameraStep = nil

        switch step {
        case .camera: isShowingCamera = true
        case .shots: isShowingShots = true
        case .photoLibrary: isShowingPhotoPicker = true
        }
    }

    /// The camera button. The tips come up once, on the first go; after that it
    /// goes straight to the viewfinder.
    private func startCamera() {
        shots = []

        guard seenCameraTips else {
            isShowingTips = true
            return
        }

        guard CameraCaptureView.isAvailable else {
            isShowingPhotoPicker = true
            return
        }

        isShowingCamera = true
    }

    private func readShots() async {
        // The encode is the expensive half, and a camera image is big, so it
        // happens off the main actor. `Data` crosses the boundary; `UIImage`
        // stays on this side of it.
        let raw = shots.compactMap { $0.jpegData(compressionQuality: 0.9) }
        shots = []

        let photos = await Task.detached {
            raw.compactMap { ImageProcessor.downscaledJPEG(from: $0) }
        }.value

        await viewModel.read(photos: photos)
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
                    VStack(alignment: .leading, spacing: CozySpacing.m) {
                        header(for: group)

                        // What's about to go off gets cards; everything else
                        // gets a list. A thing with two days left is a decision
                        // to make — it wants room, its own edge and the date
                        // said out loud. A tin of chickpeas is inventory, and
                        // inventory reads fastest as rows.
                        if group.section == .expiring {
                            useSoonGrid(group.items)
                        } else {
                            groupedCard(group.items)
                        }
                    }
                }
            }
            .padding(CozySpacing.l)
            .padding(.bottom, CozySpacing.xxl)
        }
    }

    /// Two-up cards for the things with a clock on them.
    private func useSoonGrid(_ items: [PantryItem]) -> some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: CozySpacing.m),
                      GridItem(.flexible(), spacing: CozySpacing.m)],
            spacing: CozySpacing.m
        ) {
            ForEach(items) { item in
                useSoonCard(for: item)
            }
        }
    }

    private func useSoonCard(for item: PantryItem) -> some View {
        CrumbCard(padding: CozySpacing.m, cornerRadius: CozyRadius.button) {
            VStack(alignment: .leading, spacing: 3) {
                // Lowercase and in the display face. Pantry items are typed in
                // as "spinach", not "Spinach", and title-casing them here made
                // half the shelf look like proper nouns.
                Text(item.displayName)
                    .cozyText(CozyFont.title3)
                    .cozyDisplayTracking(CozyTracking.title3, relativeTo: .title3)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let amount = amountText(for: item) {
                    Text(amount)
                        .cozyText(CozyFont.body, color: CozyColor.inkSecondary)
                        .monospacedDigit()
                }

                if let urgency = urgencyLabel(for: item) {
                    Text(urgency)
                        .cozyEyebrow(color: CozyColor.inkOnBlush,
                                     tracking: CozyTracking.eyebrowTight)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(urgencyFill(for: item),
                                    in: .rect(cornerRadius: CozyRadius.pill, style: .continuous))
                        .padding(.top, CozySpacing.s)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contextMenu { itemMenu(for: item) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: item))
    }

    /// "TOMORROW", "3 DAYS", "WENT OFF". Short enough to be a tag; the row's
    /// full caption still reads properly to VoiceOver.
    private func urgencyLabel(for item: PantryItem) -> String? {
        guard let days = item.daysUntilExpiry() else { return nil }
        return switch days {
        case ..<0: "Went off"
        case 0: "Today"
        case 1: "Tomorrow"
        default: "\(days) days"
        }
    }

    /// The accent for anything you have to deal with today or tomorrow, and a
    /// quiet cream for the rest. A tag that shouts on every card isn't a tag,
    /// it's a background.
    private func urgencyFill(for item: PantryItem) -> Color {
        guard let days = item.daysUntilExpiry() else { return CozyColor.creamDeep }
        return days <= 1 ? accent.deep : CozyColor.creamDeep
    }

    /// Everything that isn't about to go off: one card, rows inside it.
    private func groupedCard(_ items: [PantryItem]) -> some View {
        CrumbCard(padding: 0, cornerRadius: CozyRadius.button) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .fill(CozyColor.creamDeep)
                            .frame(height: 1.5)
                    }

                    row(for: item)
                }
            }
        }
    }

    private func header(for group: PantryViewModel.Group) -> some View {
        AisleTag(
            title: group.section.title,
            systemImage: group.section.symbol,
            count: group.items.count,
            tint: tint(for: group.section)
        )
    }

    /// Full-strength colours, as on the grocery list: at tag size a paled tint
    /// is the same beige as every other paled tint.
    private func tint(for section: PantryViewModel.Section) -> Color {
        switch section {
        case .expiring: accent.deep
        case .category(let category): category.tint
        }
    }

    private func row(for item: PantryItem) -> some View {
        HStack(alignment: .center, spacing: CozySpacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .cozyText(CozyFont.body)

                if let caption = caption(for: item) {
                    Text(caption)
                        .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
                }
            }

            Spacer(minLength: CozySpacing.s)

            // The quantity in a pill of its own. Down a column of rows it is
            // the thing being compared, and set as plain text it ran into the
            // name beside it whenever either got long.
            if let amount = amountText(for: item) {
                Text(amount)
                    .cozyText(CozyFont.caption.weight(.bold), color: CozyColor.inkPrimary)
                    .monospacedDigit()
                    .padding(.horizontal, CozySpacing.s)
                    .padding(.vertical, 5)
                    .background(CozyColor.creamDeep,
                                in: .rect(cornerRadius: CozyRadius.pill, style: .continuous))
            }
        }
        .padding(.horizontal, CozySpacing.l)
        .frame(minHeight: 54)
        .contentShape(.rect)
        .contextMenu { itemMenu(for: item) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: item))
    }

    @ViewBuilder
    private func itemMenu(for item: PantryItem) -> some View {
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

        if item.addedVia == .fridgePhoto {
            parts.append("spotted in a photo")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func accessibilityLabel(for item: PantryItem) -> String {
        [amountText(for: item), item.displayName, caption(for: item)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    // MARK: - Header

    private var header: some View {
        ScreenHeader(
            title: "Pantry",
            eyebrow: AppBranding.appName,
            caption: summary,
            trailing: {
                HeaderActionButton(
                    systemImage: "camera",
                    accessibilityLabel: "Photograph the fridge",
                    accessibilityHint: "Opens the camera to read what's in from a photo",
                    // Butter rather than the accent's deep: this opens a
                    // camera, not another row in the list, and the one control
                    // on the screen that leaves it should not look like the
                    // plus button on every other header.
                    fill: CozyColor.butter
                ) {
                    startCamera()
                }
                .disabled(!viewModel.canReadPhotos)
                .opacity(viewModel.canReadPhotos ? 1 : 0.5)
            },
            below: { addField }
        )
    }

    /// "12 in · 2 going off". The second half is the reason anyone opens this
    /// screen without being sent here, so it goes under the title rather than
    /// waiting to be scrolled to.
    private var summary: String? {
        guard !items.isEmpty else { return nil }

        var parts = ["\(items.count) in"]

        let expiring = groups.first { $0.section == .expiring }?.items.count ?? 0
        if expiring > 0 {
            parts.append("\(expiring) going off")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Adding

    private var addField: some View {
        CozyTextField(
            placeholder: "Half a jar of tahini…",
            text: $viewModel.draft,
            systemImage: "plus.circle",
            submitLabel: .done,
            fill: CozyColor.cardOnBlush
        ) {
            withAnimation(motion(Motion.gentle)) {
                viewModel.addTyped(in: modelContext)
            }
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
            .cozyScreenBackground()
            .navigationTitle(item.displayName)
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
