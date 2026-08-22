//
//  TasteProfileBuilder.swift
//  Cozy Crumb
//
//  Turns the signal log into a picture of a cook. Pure, and tested against a
//  fixed fixture whose output is asserted whole — §12 calls for a snapshot of
//  the derivation, because the failure mode here is not a crash, it is a
//  number quietly drifting until the recommendations stop making sense.
//
//  Nothing in this file touches SwiftData. It takes plain values in and
//  returns a plain value out, which is what lets the simulation harness run
//  six months of synthetic behaviour through it in a millisecond.
//
//  The two decisions worth arguing about:
//
//  Staples are excluded from ingredient affinity. Salt is in every recipe
//  anyone has ever cooked, so counting it produces a profile whose strongest
//  finding is that this person likes salt. True, useless, and it crowds out
//  the findings that aren't.
//
//  A signal about a recipe credits every ingredient in that recipe, at full
//  weight rather than a share. A ten-ingredient recipe therefore deposits
//  more total affinity than a four-ingredient one, which is the right way
//  round: cooking something elaborate is more evidence about more foods. The
//  sigmoid at the end stops any of it running away.
//

import Foundation

// MARK: - Inputs

/// Everything the builder needs, flattened out of the store.
nonisolated struct ProfileInput: Sendable {

    nonisolated struct RecipeFacts: Sendable, Equatable {
        var id: UUID
        var title: String
        var cuisine: String?
        /// Canonical, staples included — the builder filters them.
        var ingredients: Set<String>
        var techniques: Set<String>
        var equipmentMentioned: Set<String>
        var totalMinutes: Int?
        var servings: Int
        var rating: Int?
        var cookCount: Int
        var lastCookedAt: Date?
        var createdAt: Date

        nonisolated init(
            id: UUID,
            title: String,
            cuisine: String? = nil,
            ingredients: Set<String> = [],
            techniques: Set<String> = [],
            equipmentMentioned: Set<String> = [],
            totalMinutes: Int? = nil,
            servings: Int = 4,
            rating: Int? = nil,
            cookCount: Int = 0,
            lastCookedAt: Date? = nil,
            createdAt: Date = .now
        ) {
            self.id = id
            self.title = title
            self.cuisine = cuisine
            self.ingredients = ingredients
            self.techniques = techniques
            self.equipmentMentioned = equipmentMentioned
            self.totalMinutes = totalMinutes
            self.servings = servings
            self.rating = rating
            self.cookCount = cookCount
            self.lastCookedAt = lastCookedAt
            self.createdAt = createdAt
        }
    }

    nonisolated struct SignalFacts: Sendable, Equatable {
        var kind: SignalKind
        var recipeID: UUID?
        var ingredientName: String?
        var tag: String?
        var weight: Double
        var timestamp: Date
        var context: SignalContext?

        nonisolated init(
            kind: SignalKind,
            recipeID: UUID? = nil,
            ingredientName: String? = nil,
            tag: String? = nil,
            weight: Double? = nil,
            timestamp: Date = .now,
            context: SignalContext? = nil
        ) {
            self.kind = kind
            self.recipeID = recipeID
            self.ingredientName = ingredientName
            self.tag = tag
            self.weight = weight ?? kind.baseWeight
            self.timestamp = timestamp
            self.context = context
        }

        nonisolated func effectiveWeight(at now: Date) -> Double {
            guard kind.decays else { return weight }
            let days = SignalDecay.days(from: timestamp, to: now)
            return weight * SignalDecay.factor(daysAgo: days)
        }
    }

    var recipes: [RecipeFacts]
    var signals: [SignalFacts]
    /// Values the user has corrected by hand. These win, always (§8).
    var overrides: [String: Double]
    /// Inferences the user has told the app to forget. Dropped entirely —
    /// not just hidden — so they stop affecting recommendations too.
    var dismissed: Set<String>
    var now: Date

    nonisolated init(
        recipes: [RecipeFacts] = [],
        signals: [SignalFacts] = [],
        overrides: [String: Double] = [:],
        dismissed: Set<String> = [],
        now: Date = .now
    ) {
        self.recipes = recipes
        self.signals = signals
        self.overrides = overrides
        self.dismissed = dismissed
        self.now = now
    }
}

// MARK: - The builder

nonisolated enum TasteProfileBuilder {

    /// Steepness of the squash from summed weight to −1…1.
    ///
    /// Chosen so three cooks of a cuisine (6.0 of raw weight) lands near
    /// 0.78, which matches the worked example in the spec's digest. Raising
    /// it makes the profile shout after one dinner; lowering it means nothing
    /// ever reads as a preference.
    nonisolated static let sigmoidSteepness = 0.35

    /// −1…1 from a summed weight.
    nonisolated static func normalize(_ total: Double, steepness: Double = sigmoidSteepness) -> Double {
        2 / (1 + exp(-steepness * total)) - 1
    }

    /// How many cooks on a weekday before that day gets its own effort
    /// number. Below this the global average is used — one Sunday roast is
    /// not a pattern.
    nonisolated static let minimumCooksPerDay = 3

    /// How many recipes with heat before a spice tolerance is claimed.
    nonisolated static let minimumSpiceEvidence = 3

    /// How many times a recipe must call for a piece of equipment before the
    /// app decides they own it.
    nonisolated static let minimumEquipmentCooks = 3

    /// The window novelty appetite is measured over.
    nonisolated static let noveltyWindowDays: Double = 90

    /// Where a stated dislike lands, regardless of what the arithmetic says.
    ///
    /// One typed "I hate coriander" is worth -4.0, which the sigmoid squashes
    /// to about -0.6 — not enough to trip §4's hard filter at 0.8, so the
    /// recipe with coriander in it comes back anyway and the user has to say
    /// it again. The spec calls this signal near-absolute; this is what makes
    /// it so.
    nonisolated static let statedDislikeFloor = -0.95

    // MARK: Entry point

    nonisolated static func build(from input: ProfileInput) -> TasteProfileSnapshot {
        let recipesByID = Dictionary(uniqueKeysWithValues: input.recipes.map { ($0.id, $0) })

        var cuisineTotals: [String: Double] = [:]
        var ingredientTotals: [String: Double] = [:]
        var techniqueTotals: [String: Double] = [:]

        var cuisineSignalCounts: [String: Int] = [:]
        var cuisineRecipeTitles: [String: Set<String>] = [:]
        var cuisineRepeatCounts: [String: Int] = [:]
        var ingredientSignalCounts: [String: Int] = [:]
        var techniqueSignalCounts: [String: Int] = [:]

        var cookMinutesByWeekday: [Int: [Int]] = [:]
        var cookHoursByWeekday: [Int: Set<Int>] = [:]

        var equipmentCookCounts: [String: Int] = [:]
        var cookedServings: [Int] = []

        var spicyCooks = 0
        var spicyDislikes = 0

        var explicitlyDisliked: Set<String> = []
        var recentCuisines: Set<String> = []
        var recentRepeatCooks = 0
        var recentCooks = 0

        for signal in input.signals {
            let weight = signal.effectiveWeight(at: input.now)
            let isCook = signal.kind == .cooked || signal.kind == .cookedRepeat

            // A signal about a loose ingredient — bought it, deleted it,
            // said they hate it. No recipe behind it.
            if let raw = signal.ingredientName {
                let name = IngredientCanonicalizer.canonical(raw)
                if !name.isEmpty, !IngredientCanonicalizer.isStaple(name) {
                    ingredientTotals[name, default: 0] += weight
                    ingredientSignalCounts[name, default: 0] += 1

                    if signal.kind == .explicitlyDisliked {
                        explicitlyDisliked.insert(name)
                    }
                }
            }

            if let tag = signal.tag, let cuisine = CuisineClassifier.cuisineFromTags([tag]) {
                cuisineTotals[cuisine, default: 0] += weight
                cuisineSignalCounts[cuisine, default: 0] += 1
            }

            guard let recipeID = signal.recipeID, let recipe = recipesByID[recipeID] else { continue }

            if let cuisine = recipe.cuisine {
                cuisineTotals[cuisine, default: 0] += weight
                cuisineSignalCounts[cuisine, default: 0] += 1
                cuisineRecipeTitles[cuisine, default: []].insert(recipe.title)
                if signal.kind == .cookedRepeat {
                    cuisineRepeatCounts[cuisine, default: 0] += 1
                }
            }

            for ingredient in recipe.ingredients where !IngredientCanonicalizer.isStaple(ingredient) {
                ingredientTotals[ingredient, default: 0] += weight
                ingredientSignalCounts[ingredient, default: 0] += 1
            }

            for technique in recipe.techniques {
                techniqueTotals[technique, default: 0] += weight
                techniqueSignalCounts[technique, default: 0] += 1
            }

            guard isCook else {
                // Heat that got a bad review counts against spice tolerance,
                // wherever the signal came from.
                if signal.kind == .ratedLow, hasHeat(recipe) {
                    spicyDislikes += 1
                }
                continue
            }

            // Everything below here is "they actually cooked it".

            if let context = signal.context {
                if let minutes = recipe.totalMinutes {
                    cookMinutesByWeekday[context.weekday, default: []].append(minutes)
                }
                cookHoursByWeekday[context.weekday, default: []].insert(context.hour)
            }

            for equipment in recipe.equipmentMentioned {
                equipmentCookCounts[equipment, default: 0] += 1
            }

            cookedServings.append(recipe.servings)

            if hasHeat(recipe) {
                spicyCooks += 1
            }

            let age = SignalDecay.days(from: signal.timestamp, to: input.now)
            if age <= noveltyWindowDays {
                recentCooks += 1
                if signal.kind == .cookedRepeat { recentRepeatCooks += 1 }
                if let cuisine = recipe.cuisine { recentCuisines.insert(cuisine) }
            }
        }

        // MARK: Squash and apply corrections

        var cuisineAffinity = squash(cuisineTotals, keyed: ProfileKey.cuisine, input: input)
        var ingredientAffinity = squash(ingredientTotals, keyed: ProfileKey.ingredient, input: input)
        var techniqueComfort = squash(techniqueTotals, keyed: ProfileKey.technique, input: input)

        // A stated dislike overrules the arithmetic. Someone who typed it
        // should not have to type it again because the sigmoid disagreed.
        for name in explicitlyDisliked {
            guard input.overrides[ProfileKey.ingredient(name)] == nil else { continue }
            ingredientAffinity[name] = min(ingredientAffinity[name] ?? 0, statedDislikeFloor)
        }

        // A dismissed inference is removed rather than zeroed. Zero is a
        // finding ("neutral on Thai"); absence is the truth ("we don't know").
        cuisineAffinity = cuisineAffinity.filter { !input.dismissed.contains(ProfileKey.cuisine($0.key)) }
        ingredientAffinity = ingredientAffinity.filter { !input.dismissed.contains(ProfileKey.ingredient($0.key)) }
        techniqueComfort = techniqueComfort.filter { !input.dismissed.contains(ProfileKey.technique($0.key)) }

        // MARK: Effort and schedule

        let allCookMinutes = cookMinutesByWeekday.values.flatMap { $0 }
        let globalAverage = allCookMinutes.isEmpty
            ? nil
            : allCookMinutes.reduce(0, +) / allCookMinutes.count

        var effortMinutesByWeekday: [Int: Int] = [:]
        for (weekday, minutes) in cookMinutesByWeekday {
            if minutes.count >= minimumCooksPerDay {
                effortMinutesByWeekday[weekday] = minutes.reduce(0, +) / minutes.count
            } else if let globalAverage {
                // Not enough to call it a pattern, so the day inherits the
                // overall average rather than inventing one from a single
                // ambitious Sunday.
                effortMinutesByWeekday[weekday] = globalAverage
            }
        }

        // MARK: Novelty

        let noveltyAppetite: Double
        if recentCooks >= 3 {
            let variety = Double(recentCuisines.count)
            let repeats = Double(recentRepeatCooks)
            noveltyAppetite = min(1, max(0, variety / max(1, variety + repeats)))
        } else {
            noveltyAppetite = 0.5
        }

        // MARK: Equipment, spice, household

        let inferredEquipment = Set(
            equipmentCookCounts
                .filter { $0.value >= minimumEquipmentCooks }
                .map(\.key)
                .filter { !input.dismissed.contains(ProfileKey.equipment($0)) }
        )

        var spiceTolerance: Double?
        if spicyCooks >= minimumSpiceEvidence, !input.dismissed.contains(ProfileKey.spiceTolerance) {
            let total = Double(spicyCooks + spicyDislikes)
            spiceTolerance = total > 0 ? Double(spicyCooks) / total : nil
        }

        var inferredHouseholdSize: Int?
        if cookedServings.count >= 5, !input.dismissed.contains(ProfileKey.householdSize) {
            let sorted = cookedServings.sorted()
            inferredHouseholdSize = sorted[sorted.count / 2]
        }

        // MARK: Assemble

        var snapshot = TasteProfileSnapshot(
            cuisineAffinity: cuisineAffinity,
            ingredientAffinity: ingredientAffinity,
            techniqueComfort: techniqueComfort,
            effortMinutesByWeekday: effortMinutesByWeekday,
            cookHoursByWeekday: cookHoursByWeekday.mapValues { $0.sorted() },
            spiceTolerance: spiceTolerance,
            inferredHouseholdSize: inferredHouseholdSize,
            noveltyAppetite: input.overrides[ProfileKey.noveltyAppetite] ?? noveltyAppetite,
            inferredEquipment: inferredEquipment,
            explicitlyDisliked: explicitlyDisliked.subtracting(
                input.dismissed.map { $0.replacingOccurrences(of: ProfileKey.ingredient(""), with: "") }
            ),
            signalCount: input.signals.count,
            lastRebuiltAt: input.now
        )

        snapshot.evidence = buildEvidence(
            snapshot: snapshot,
            cuisineSignalCounts: cuisineSignalCounts,
            cuisineRecipeTitles: cuisineRecipeTitles,
            cuisineRepeatCounts: cuisineRepeatCounts,
            ingredientSignalCounts: ingredientSignalCounts,
            techniqueSignalCounts: techniqueSignalCounts,
            equipmentCookCounts: equipmentCookCounts,
            cookMinutesByWeekday: cookMinutesByWeekday,
            spicyCooks: spicyCooks,
            recentCuisineCount: recentCuisines.count,
            recentRepeatCooks: recentRepeatCooks
        )

        return snapshot
    }

    // MARK: - Helpers

    private nonisolated static func squash(
        _ totals: [String: Double],
        keyed key: (String) -> String,
        input: ProfileInput
    ) -> [String: Double] {
        var result: [String: Double] = [:]

        for (name, total) in totals {
            // A hand-corrected value is not re-derived. Someone who told the
            // app they like coriander after all is not argued with.
            if let override = input.overrides[key(name)] {
                result[name] = max(-1, min(1, override))
            } else {
                result[name] = normalize(total)
            }
        }

        // An override for something with no signals behind it still counts —
        // that is how a cold-start answer gets into the profile.
        for (overrideKey, value) in input.overrides {
            guard overrideKey.hasPrefix(key("")) else { continue }
            let name = String(overrideKey.dropFirst(key("").count))
            if result[name] == nil, !name.isEmpty {
                result[name] = max(-1, min(1, value))
            }
        }

        return result
    }

    /// Heat-carrying ingredients, for spice tolerance.
    nonisolated static let heatIngredients: Set<String> = [
        "chili", "chili flake", "chili powder", "cayenne", "harissa",
        "gochujang", "gochugaru", "jalapeno", "sriracha", "hot sauce",
        "scotch bonnet", "chipotle", "habanero", "sambal", "chili oil",
        "curry paste", "peri peri", "wasabi", "horseradish"
    ]

    nonisolated static func hasHeat(_ recipe: ProfileInput.RecipeFacts) -> Bool {
        !recipe.ingredients.isDisjoint(with: heatIngredients)
    }

    // MARK: - Provenance

    private nonisolated static func buildEvidence(
        snapshot: TasteProfileSnapshot,
        cuisineSignalCounts: [String: Int],
        cuisineRecipeTitles: [String: Set<String>],
        cuisineRepeatCounts: [String: Int],
        ingredientSignalCounts: [String: Int],
        techniqueSignalCounts: [String: Int],
        equipmentCookCounts: [String: Int],
        cookMinutesByWeekday: [Int: [Int]],
        spicyCooks: Int,
        recentCuisineCount: Int,
        recentRepeatCooks: Int
    ) -> [String: ProfileEvidence] {
        var evidence: [String: ProfileEvidence] = [:]

        for (cuisine, _) in snapshot.cuisineAffinity {
            let titles = (cuisineRecipeTitles[cuisine] ?? []).sorted()
            let repeats = cuisineRepeatCounts[cuisine] ?? 0

            var summary = "You've cooked \(countPhrase(titles.count, "recipe")) I'd call \(cuisine)"
            if repeats > 0 {
                summary += ", \(repeats) of them more than once"
            }
            summary += "."

            evidence[ProfileKey.cuisine(cuisine)] = ProfileEvidence(
                summary: summary,
                signalCount: cuisineSignalCounts[cuisine] ?? 0,
                recipeTitles: Array(titles.prefix(5))
            )
        }

        for (ingredient, score) in snapshot.ingredientAffinity {
            let count = ingredientSignalCounts[ingredient] ?? 0
            let summary = score >= 0
                ? "It's turned up \(countPhrase(count, "time")) in things you've cooked or bought."
                : "You've passed on it \(countPhrase(count, "time")) — deleted off the list, or rated low."

            evidence[ProfileKey.ingredient(ingredient)] = ProfileEvidence(
                summary: summary,
                signalCount: count
            )
        }

        for (technique, _) in snapshot.techniqueComfort {
            evidence[ProfileKey.technique(technique)] = ProfileEvidence(
                summary: "You've made \(countPhrase(techniqueSignalCounts[technique] ?? 0, "thing")) that needed it.",
                signalCount: techniqueSignalCounts[technique] ?? 0
            )
        }

        for equipment in snapshot.inferredEquipment {
            let count = equipmentCookCounts[equipment] ?? 0
            evidence[ProfileKey.equipment(equipment)] = ProfileEvidence(
                summary: "\(countPhrase(count, "recipe")) you've cooked asked for one.",
                signalCount: count
            )
        }

        if let spice = snapshot.spiceDescription {
            evidence[ProfileKey.spiceTolerance] = ProfileEvidence(
                summary: "You've cooked \(countPhrase(spicyCooks, "recipe")) with real heat in them, so I've put you at \(spice).",
                signalCount: spicyCooks
            )
        }

        if let household = snapshot.inferredHouseholdSize {
            evidence[ProfileKey.householdSize] = ProfileEvidence(
                summary: "Most of what you cook serves \(household).",
                signalCount: 0
            )
        }

        let totalCooks = cookMinutesByWeekday.values.reduce(0) { $0 + $1.count }
        if totalCooks > 0 {
            let days = snapshot.effortMinutesByWeekday
                .sorted { $0.key < $1.key }
                .map { "\(SignalContext(weekday: $0.key, hour: 12, season: .spring).weekdayName) about \($0.value) min" }

            evidence[ProfileKey.effort] = ProfileEvidence(
                summary: "Averaged from what you actually cooked: " + days.joined(separator: ", ") + ".",
                signalCount: totalCooks
            )
        }

        evidence[ProfileKey.noveltyAppetite] = ProfileEvidence(
            summary: "In the last three months you've cooked \(countPhrase(recentCuisineCount, "different kind")) of food and repeated \(countPhrase(recentRepeatCooks, "dish")).",
            signalCount: recentCuisineCount + recentRepeatCooks
        )

        return evidence
    }

    /// "1 recipe" / "6 recipes", so no sentence ever reads "1 recipes".
    nonisolated static func countPhrase(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}
