//
//  RecipeDetailView.swift
//  Cozy Crumb
//
//  One recipe, cooked from. Servings scale every quantity live, units convert
//  where it makes sense, and "I made this" writes a CookLog.
//

import Foundation
import SwiftData
import SwiftUI
import os

struct RecipeDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.cozyMotion) private var motion
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @AppStorage(CozyDefaultsKey.measurementSystem)
    private var systemRaw = MeasurementSystem.asWritten.rawValue

    let recipe: Recipe

    @State private var viewModel: RecipeDetailViewModel
    @State private var isEditing = false
    @State private var groceryToast: String?
    @State private var isPresentingAddReview = false
    @State private var isCooking = false
    /// Set when Cook Mode reaches the end, and acted on once it has closed —
    /// a sheet raised from a screen that is mid-dismiss never appears.
    @State private var wantsCookLog = false

    private static let scrollSpace = "recipeScroll"

    init(recipe: Recipe) {
        self.recipe = recipe
        _viewModel = State(initialValue: RecipeDetailViewModel(recipe: recipe))
    }

    private var system: MeasurementSystem {
        MeasurementSystem(rawValue: systemRaw) ?? .asWritten
    }

    /// The hero used to be a share of the screen's height, measured by an
    /// outer `GeometryReader`. It is one number now: a proportional hero left
    /// the title sitting at a different place on every device, and this screen
    /// is read from the title down, not looked at from the top.
    var body: some View {
        // The controls sit in a layer of their own rather than in the scroll
        // view, so they stay put while the recipe moves under them — a back
        // button that scrolls away is a back button you have to scroll back up
        // to find. The ZStack keeps the safe area; only the scroll view opts
        // out of it, which is what lets the hero bleed under the status bar.
        ZStack(alignment: .top) {
            scroller
            floatingControls
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationTitle(recipe.title)
        .navigationBarBackButtonHidden()
    }

    private var scroller: some View {
        ScrollView {
            VStack(spacing: CozySpacing.l) {
                hero(height: CozyMetrics.recipeHeroHeight)
                if !titleOnHero { heading(onHero: false) }
                reviewBanner
                cookModeButton
                ingredientsSection
                addToGroceriesButton
                unitsCard
                stepsSection
                notesCard
                madeThisSection
                if !recipe.cookLogs.isEmpty {
                    historySection
                }
            }
            .padding(.bottom, CozySpacing.xxl)
        }
        .ignoresSafeArea(edges: .top)
        .coordinateSpace(.named(Self.scrollSpace))
        .cozyScreenBackground()
        // Opening a recipe is a weak signal; staying on it is a better one.
        // The sleep is cancelled when the screen goes away, so backing
        // straight out records only the glance.
        .task(id: recipe.id) {
            SignalLog.viewed(recipe, in: modelContext)

            do {
                try await Task.sleep(for: SignalLog.longViewThreshold)
            } catch {
                return
            }

            SignalLog.readProperly(recipe, in: modelContext)
        }
        .sheet(isPresented: $isEditing) {
            viewModel.resync(with: recipe)
        } content: {
            ImportFlowView(editingRecipe: recipe)
        }
        .sheet(isPresented: $viewModel.isLoggingCook) {
            CookLogSheet(recipeTitle: recipe.title) { rating, notes in
                logCook(rating: rating, notes: notes)
            }
        }
        .sheet(isPresented: $isPresentingAddReview) {
            let lines = GroceryService.lineItems(from: recipe, servings: viewModel.servings)
            GroceryAddReviewView(lines: lines, sourceTitle: recipe.title)
        }
        .fullScreenCover(isPresented: $isCooking) {
            guard wantsCookLog else { return }
            wantsCookLog = false
            viewModel.isLoggingCook = true
        } content: {
            CookModeView(
                recipe: recipe,
                servings: viewModel.servings,
                system: system
            ) {
                wantsCookLog = true
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Timers started from a step chip stay visible while reading the
            // rest of the recipe, not only inside Cook Mode.
            CookTimerBar()
                .padding(.horizontal, CozySpacing.l)
        }
        .overlay(alignment: .bottom) { groceryToastBanner }
    }

    // MARK: - Cook mode

    /// The one thing this screen is ultimately for. It sits directly under the
    /// heading rather than at the bottom, because someone about to cook should
    /// not have to scroll past the shopping controls to start.
    private var cookModeButton: some View {
        SquishyButton(title: "Start cooking", systemImage: "flame", minHeight: 58) {
            isCooking = true
        }
        .padding(.horizontal, CozySpacing.l)
        .disabled(recipe.steps.isEmpty)
        .opacity(recipe.steps.isEmpty ? 0.5 : 1)
    }

    // MARK: - Groceries

    /// Sends the ingredient list — at whatever servings the user has dialled
    /// to, not the recipe's original — over to the grocery list.
    private var addToGroceriesButton: some View {
        SquishyButton(
            title: "Add to groceries",
            systemImage: "checklist",
            emphasis: .secondary,
            minHeight: 50
        ) {
            addToGroceries()
        }
        .padding(.horizontal, CozySpacing.l)
    }

    @ViewBuilder
    private var groceryToastBanner: some View {
        if let groceryToast {
            Text(groceryToast)
                .cozyText(CozyFont.caption, color: CozyColor.inkPrimary)
                .padding(.horizontal, CozySpacing.m)
                .padding(.vertical, CozySpacing.s)
                .background(CozyColor.creamDeep, in: .capsule)
                .cozyLiftShadow()
                .padding(.bottom, CozySpacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private func addToGroceries() {
        let lines = GroceryService.lineItems(from: recipe, servings: viewModel.servings)
        
        // Show review view if there are items to add
        if !lines.isEmpty {
            // Present review sheet with the lines
            isPresentingAddReview = true
        } else {
            // Show toast for no items needed
            Haptics.notify(.success)
            withAnimation(motion(Motion.snappy)) {
                groceryToast = "Nothing on this one needs buying."
            }

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.2))
                withAnimation(motion(Motion.gentle)) { groceryToast = nil }
            }
        }
    }

    // MARK: - Hero

    /// The picture and the title, as one thing.
    ///
    /// The title used to sit on the page below the image, under an inline
    /// navigation bar carrying it a second time. Setting it *on* the hero buys
    /// back a whole screen-width of vertical space, and at 44pt in the display
    /// face it is the recipe's name rather than a caption for the photograph.
    private func hero(height: CGFloat) -> some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .named(Self.scrollSpace)).minY
            // Pulling down stretches the image instead of leaving a gap.
            let stretch = max(0, minY)

            RecipeHeroView(recipe: recipe, maxPixelSize: HeroImageLoader.detailPixelSize)
                .frame(width: proxy.size.width, height: height + stretch)
                .offset(y: -stretch)
        }
        .frame(height: height)
        .overlay(alignment: .bottomLeading) {
            if titleOnHero { heading(onHero: true) }
        }
        .clipped()
    }

    /// Whether the title is set on the picture or on the page under it.
    ///
    /// The hero is a fixed 330pt, and a 44pt title at an accessibility size is
    /// not: two lines of AX5 plus a summary and two pills is taller than the
    /// image they are supposed to sit on, and `.clipped()` would take the top
    /// off the recipe's name. So past AX1 the heading comes off the hero and
    /// goes back on the page, where it can be as tall as it needs to be.
    private var titleOnHero: Bool { !typeSize.isAccessibilitySize }

    private func heading(onHero: Bool) -> some View {
        VStack(alignment: .leading, spacing: CozySpacing.s) {
            // Still the source *pill*, and still a link when there is one to
            // follow — it just isn't shaped like a chip any more.
            if let sourceLabel = SourcePill.label(for: recipe) {
                SourcePill(
                    name: sourceLabel,
                    symbol: recipe.sourceKind.symbol,
                    url: recipe.sourceURL
                )
            }

            Text(recipe.title)
                .cozyText(CozyFont.display, color: onHero ? CozyColor.inkOnAccent : CozyColor.inkPrimary)
                .cozyDisplayTracking(CozyTracking.display)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = recipe.summary {
                Text(summary)
                    .cozyText(CozyFont.subheadline,
                              color: onHero ? CozyColor.inkOnAccent : CozyColor.inkSecondary)
                    .lineLimit(onHero ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Translucent white on the picture, creamDeep on the page: an
            // opaque pill on a photograph is a sticker, and a translucent one
            // on cream is barely a pill at all.
            HStack(spacing: CozySpacing.xs) {
                if let time = recipe.totalTimeDisplay {
                    PillTag(text: time, tint: pillFill(onHero), ink: pillInk(onHero))
                }
                PillTag(text: "Serves \(viewModel.servings)",
                        tint: pillFill(onHero), ink: pillInk(onHero))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CozySpacing.l)
        .padding(.bottom, onHero ? CozySpacing.l : 0)
        .background(alignment: .bottom) {
            // The hero can be a photograph, and ink on an unknown photograph is
            // a coin toss. A scrim under the text costs nothing on the
            // procedural placeholders and is the only thing making a 44pt
            // title readable over a bright picture.
            if onHero {
                // `heroScrim`, not `surfaceOnAccent`. A scrim works against
                // the *ink*, so it has to invert rather than follow the
                // surface: light behind dark ink, dark behind light ink. Using
                // the surface token here would have lightened the hero after
                // dark, underneath ink that had just gone light.
                LinearGradient(
                    colors: [CozyColor.heroScrim.opacity(0), CozyColor.heroScrim],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 260)
                .allowsHitTesting(false)
            }
        }
    }

    private func pillFill(_ onHero: Bool) -> Color {
        onHero ? CozyColor.surfaceOnAccent : CozyColor.creamDeep
    }

    private func pillInk(_ onHero: Bool) -> Color {
        onHero ? CozyColor.inkOnAccent : CozyColor.inkSecondary
    }

    /// The "I guessed at this one" warning.
    ///
    /// It came off the hero with the rest of the heading and landed here
    /// instead of on the picture: it is a thing to act on, and the one place it
    /// must not be is set in ink over a photograph.
    @ViewBuilder
    private var reviewBanner: some View {
        if recipe.needsReview {
            Text("I did my best guess here — worth a quick look.")
                .cozyText(CozyFont.caption, color: CozyColor.inkPrimary)
                .padding(CozySpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CozyColor.warning.cozyPaled(0.55),
                            in: .rect(cornerRadius: CozyRadius.field, style: .continuous))
                .padding(.horizontal, CozySpacing.l)
        }
    }

    /// Back, favourite and edit, floating on the hero.
    ///
    /// The navigation bar is hidden, so these are the only way out of the
    /// screen besides the swipe — which is why the back button is drawn first,
    /// full size, and never conditionally.
    private var floatingControls: some View {
        HStack(spacing: CozySpacing.s) {
            heroControl(systemImage: "chevron.left", label: "Back") { dismiss() }

            Spacer()

            heroControl(
                systemImage: recipe.isFavorite ? "heart.fill" : "heart",
                label: recipe.isFavorite ? "Remove from favourites" : "Add to favourites",
                isOn: recipe.isFavorite,
                isSelected: recipe.isFavorite
            ) {
                toggleFavorite()
            }

            heroControl(systemImage: "square.and.pencil", label: "Edit this recipe") {
                isEditing = true
            }
        }
        .padding(.horizontal, CozySpacing.l)
        .padding(.top, CozySpacing.s)
    }

    private func heroControl(
        systemImage: String,
        label: String,
        isOn: Bool = false,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(CozyColor.inkOnAccent)
                .frame(width: 40, height: 40)
                .background(isOn ? CozyColor.butter : CozyColor.surfaceOnAccent,
                            in: .rect(cornerRadius: CozyRadius.control, style: .continuous))
                // Draws at 40, stays tappable at 44.
                .frame(width: CozyMetrics.minimumTouchTarget,
                       height: CozyMetrics.minimumTouchTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Servings & units

    /// Units only. The servings stepper moved out of here and onto the
    /// Ingredients heading, which is the list it actually changes — sitting in
    /// a card of its own, two sections above the quantities, it read as a
    /// setting rather than as a control over the thing right below it.
    private var unitsCard: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("Units")
                    .cozyText(CozyFont.headline)
                Picker("Units", selection: $systemRaw) {
                    ForEach(MeasurementSystem.allCases, id: \.rawValue) { option in
                        Text(option.displayName).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CozySpacing.l)
    }

    /// Minus, value and plus as one pill rather than three floating circles.
    ///
    /// The value keeps `CozyFont.numeral`'s monospaced digits even though the
    /// rest of the app's numbers went to the display face — 8 and 12 have to
    /// be the same width or the two buttons either side of them shuffle every
    /// time the count crosses ten.
    private var stepper: some View {
        HStack(spacing: 0) {
            stepperButton(systemImage: "minus", label: "Fewer servings") {
                viewModel.decreaseServings()
            }

            Text("\(viewModel.servings)")
                .font(CozyFont.numeral)
                .foregroundStyle(CozyColor.inkPrimary)
                .contentTransition(.numericText())
                .frame(minWidth: 30)
                .cozyAnimation(Motion.bouncy, value: viewModel.servings)

            stepperButton(systemImage: "plus", label: "More servings") {
                viewModel.increaseServings()
            }
        }
        .background(CozyColor.card, in: .rect(cornerRadius: CozyRadius.control, style: .continuous))
        .cozyBlockShadow(CozyDepth.small)
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(viewModel.servings) servings")
    }

    private func stepperButton(
        systemImage: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(CozyColor.inkPrimary)
                .frame(width: 42, height: 42)
                .contentShape(.rect)
        }
        .buttonStyle(.squishy)
        .accessibilityLabel(label)
    }

    // MARK: - Ingredients

    /// No card around the list any more. Each row carries its own surface now,
    /// so a card behind them was a tray under a set of tiles — two edges doing
    /// one edge's job, and the ticked rows lost their colour to it.
    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: CozySpacing.m) {
            HStack(alignment: .center, spacing: CozySpacing.s) {
                Text("Ingredients")
                    .cozyText(CozyFont.title2)
                    .cozyDisplayTracking(CozyTracking.title2, relativeTo: .title2)
                Spacer()
                stepper
            }

            if let description = viewModel.scaleDescription {
                scaleNote(description)
            } else if viewModel.isScaled {
                scaleNote("written for \(viewModel.originalServings)")
            }

            VStack(spacing: 6) {
                ForEach(recipe.orderedIngredients) { ingredient in
                    IngredientRow(
                        ingredient: ingredient,
                        originalServings: viewModel.originalServings,
                        targetServings: viewModel.servings,
                        system: system,
                        isChecked: viewModel.isChecked(ingredient)
                    ) {
                        viewModel.toggle(ingredient)
                    }
                }
            }

            Text("Ticks reset when you leave.")
                .cozyText(CozyFont.caption2, color: CozyColor.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CozySpacing.l)
    }

    private func scaleNote(_ text: String) -> some View {
        HStack(spacing: CozySpacing.s) {
            Text(text)
                .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)

            if viewModel.isScaled {
                Button("Reset", action: viewModel.resetServings)
                    .font(CozyFont.caption.weight(.semibold))
                    .foregroundStyle(CozyColor.inkPrimary)
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: CozySpacing.m) {
            Text("Method")
                .cozyText(CozyFont.title2)
                .cozyDisplayTracking(CozyTracking.title2, relativeTo: .title2)
                .padding(.horizontal, CozySpacing.l)

            ForEach(Array(recipe.orderedSteps.enumerated()), id: \.element.id) { index, step in
                StepCard(step: step, number: index + 1, recipeTitle: recipe.title)
                    .padding(.horizontal, CozySpacing.l)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Notes

    private var notesCard: some View {
        CrumbCard {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("Your notes")
                    .cozyText(CozyFont.title2)

                TextField(
                    "Halved the sugar and it was still plenty sweet…",
                    text: notesBinding,
                    axis: .vertical
                )
                .font(CozyFont.body)
                .foregroundStyle(CozyColor.inkPrimary)
                .lineLimit(3...10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CozySpacing.l)
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { recipe.personalNotes ?? "" },
            set: { newValue in
                recipe.personalNotes = newValue.isEmpty ? nil : newValue
                recipe.touch()
            }
        )
    }

    // MARK: - Made this

    private var madeThisSection: some View {
        ZStack {
            SquishyButton(title: "I made this", systemImage: "checkmark.seal") {
                viewModel.isLoggingCook = true
            }
            .padding(.horizontal, CozySpacing.l)

            CrumbConfetti(isActive: viewModel.isCelebrating)
        }
    }

    private var historySection: some View {
        CrumbCard(fill: CozyColor.creamDeep) {
            VStack(alignment: .leading, spacing: CozySpacing.s) {
                Text("You've made this \(recipe.cookLogs.count) time\(recipe.cookLogs.count == 1 ? "" : "s")")
                    .cozyText(CozyFont.headline)

                ForEach(recipe.orderedCookLogs) { log in
                    HStack(spacing: CozySpacing.s) {
                        Text(log.date.formatted(date: .abbreviated, time: .omitted))
                            .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)

                        if let rating = log.rating {
                            HStack(spacing: 1) {
                                ForEach(0..<rating, id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(CozyColor.warning)
                                }
                            }
                        }

                        Spacer()
                    }

                    if let notes = log.notes {
                        Text(notes)
                            .cozyText(CozyFont.caption, color: CozyColor.inkSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CozySpacing.l)
    }

    // MARK: - Actions

    private func toggleFavorite() {
        recipe.isFavorite.toggle()
        recipe.touch()
        save("favourite")
        SignalLog.favorited(recipe, isNowFavorite: recipe.isFavorite, in: modelContext)
    }

    private func logCook(rating: Int?, notes: String?) {
        // Counted before the new log is attached: one prior cook or more is
        // what makes this a repeat, which is the strongest taste signal there
        // is.
        let priorCookCount = recipe.cookLogs.count

        let log = CookLog(rating: rating, notes: notes)
        modelContext.insert(log)
        log.recipe = recipe

        recipe.lastCookedAt = log.date
        // A fresh rating replaces the old one; skipping it leaves it alone.
        if let rating {
            recipe.rating = rating
        }
        recipe.touch()

        save("cook log")

        SignalLog.cooked(
            recipe,
            priorCookCount: priorCookCount,
            rating: rating,
            in: modelContext
        )

        // §3: rebuild immediately after a cook or an explicit rating. Those
        // are the signals worth acting on before the next launch.
        TasteProfileStore.rebuild(in: modelContext)

        viewModel.isCelebrating = true
        Task {
            try? await Task.sleep(for: .milliseconds(1400))
            viewModel.isCelebrating = false
        }
    }

    private func save(_ what: String) {
        do {
            try modelContext.save()
        } catch {
            Log.data.error("Could not save \(what, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - Previews

#Preview("Recipe detail") {
    NavigationStack {
        RecipeDetailView(recipe: SeedData.bananaBread())
    }
    .modelContainer(PreviewData.container)
    .environment(KitchenTimers(usesNotifications: false))
}

#Preview("Recipe detail — dark") {
    NavigationStack {
        RecipeDetailView(recipe: SeedData.chickpeaCurry())
    }
    .modelContainer(PreviewData.container)
    .environment(KitchenTimers(usesNotifications: false))
    .preferredColorScheme(.dark)
}

#Preview("Recipe detail — AX3") {
    NavigationStack {
        RecipeDetailView(recipe: SeedData.misoSalmon())
    }
    .modelContainer(PreviewData.container)
    .environment(KitchenTimers(usesNotifications: false))
    .environment(\.dynamicTypeSize, .accessibility3)
}
