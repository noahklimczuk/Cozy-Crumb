//
//  Seasonality.swift
//  Cozy Crumb
//
//  What is worth eating this month.
//
//  Ontario, per §4 — a northern-hemisphere calendar with a real winter. The
//  point is not locavore purity; it is that suggesting a tomato salad in
//  February is a slightly worse suggestion than suggesting a braise, and the
//  score should know it.
//
//  Weighted lightly (0.08) because it should nudge rather than decide. Most
//  of a cookbook is seasonless, and a recipe with nothing seasonal in it
//  scores neutral rather than badly — the absence of asparagus is not a mark
//  against a curry.
//

import Foundation

nonisolated enum Seasonality {

    /// Month number → produce at its best.
    nonisolated static let calendar: [Int: Set<String>] = [
        1: ["cabbage", "kale", "leek", "parsnip", "potato", "onion", "carrot",
            "squash", "beet", "turnip", "rutabaga", "citrus", "orange", "lemon"],
        2: ["cabbage", "kale", "leek", "parsnip", "potato", "onion", "carrot",
            "squash", "beet", "citrus", "orange", "lemon", "rhubarb"],
        3: ["leek", "parsnip", "potato", "onion", "carrot", "rhubarb",
            "spinach", "watercress", "citrus"],
        4: ["asparagus", "rhubarb", "spinach", "radish", "watercress",
            "spring onion", "lettuce", "pea"],
        5: ["asparagus", "rhubarb", "spinach", "radish", "strawberry",
            "lettuce", "pea", "spring onion", "arugula", "fennel"],
        6: ["strawberry", "pea", "lettuce", "cucumber", "zucchini", "cherry",
            "raspberry", "arugula", "fennel", "garlic", "beet"],
        7: ["tomato", "zucchini", "cucumber", "corn", "blueberry", "raspberry",
            "peach", "cherry", "bell pepper", "eggplant", "green bean", "basil"],
        8: ["tomato", "corn", "peach", "plum", "blueberry", "bell pepper",
            "eggplant", "zucchini", "green bean", "basil", "melon", "nectarine"],
        9: ["apple", "tomato", "corn", "squash", "pear", "plum", "grape",
            "bell pepper", "eggplant", "green bean", "cabbage", "leek"],
        10: ["apple", "squash", "pumpkin", "pear", "brussels sprout", "kale",
             "cabbage", "leek", "beet", "carrot", "parsnip", "mushroom"],
        11: ["squash", "pumpkin", "brussels sprout", "kale", "cabbage", "leek",
             "parsnip", "potato", "carrot", "beet", "cranberry", "mushroom"],
        12: ["cabbage", "kale", "leek", "parsnip", "potato", "squash",
             "brussels sprout", "cranberry", "citrus", "orange", "chestnut"]
    ]

    /// Everything that is ever seasonal. A recipe touching none of these is
    /// seasonless and scores neutral rather than out-of-season.
    nonisolated static let everSeasonal: Set<String> = {
        calendar.values.reduce(into: Set<String>()) { $0.formUnion($1) }
    }()

    nonisolated static func inSeason(month: Int) -> Set<String> {
        calendar[month] ?? []
    }

    /// 0–1 for how well a recipe suits the month.
    ///
    /// Returns `neutral` when the recipe has no seasonal produce in it at
    /// all, which is most of them.
    nonisolated static let neutral = 0.5

    nonisolated static func score(ingredients: Set<String>, month: Int) -> Double {
        let seasonal = ingredients.intersection(everSeasonal)
        guard !seasonal.isEmpty else { return neutral }

        let nowInSeason = seasonal.intersection(inSeason(month: month))
        return Double(nowInSeason.count) / Double(seasonal.count)
    }

    nonisolated static func month(of date: Date, calendar cal: Calendar = .current) -> Int {
        cal.component(.month, from: date)
    }
}
