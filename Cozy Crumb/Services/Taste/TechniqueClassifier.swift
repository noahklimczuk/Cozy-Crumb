//
//  TechniqueClassifier.swift
//  Cozy Crumb
//
//  What a recipe asks you to *do*, read off its steps.
//
//  §3 wants technique comfort — braising, stir-frying, roasting — and §4's
//  stretch picks are defined as "a new technique one step above their
//  comfort", so the app needs both what someone has done and what they
//  haven't. Neither exists in the data model, and both fall out of the step
//  text with a keyword pass.
//
//  Ordered by difficulty on purpose. "One step above their comfort" is only
//  meaningful if the techniques sit on a scale, so each carries a rough
//  demand rating: boiling something is not the same ask as laminating dough,
//  and a stretch pick that jumps from stir-frying to fermenting is not a
//  stretch, it is a different hobby.
//

import Foundation

nonisolated enum TechniqueClassifier {

    nonisolated struct Technique: Sendable, Hashable {
        var name: String
        /// 1 (anyone) to 5 (a project). Drives the size of a stretch.
        var demand: Int
    }

    nonisolated static let all: [Technique] = [
        Technique(name: "boiling", demand: 1),
        Technique(name: "assembling", demand: 1),
        Technique(name: "grilling", demand: 2),
        Technique(name: "roasting", demand: 2),
        Technique(name: "sautéing", demand: 2),
        Technique(name: "stir-frying", demand: 2),
        Technique(name: "baking", demand: 3),
        Technique(name: "simmering", demand: 2),
        Technique(name: "steaming", demand: 2),
        Technique(name: "frying", demand: 3),
        Technique(name: "braising", demand: 3),
        Technique(name: "slow-cooking", demand: 2),
        Technique(name: "pressure-cooking", demand: 2),
        Technique(name: "air-frying", demand: 1),
        Technique(name: "emulsifying", demand: 4),
        Technique(name: "caramelising", demand: 3),
        Technique(name: "proving", demand: 4),
        Technique(name: "laminating", demand: 5),
        Technique(name: "tempering", demand: 4),
        Technique(name: "fermenting", demand: 5),
        Technique(name: "curing", demand: 5),
        Technique(name: "smoking", demand: 4),
        Technique(name: "sous vide", demand: 4),
        Technique(name: "deep-frying", demand: 4),
        Technique(name: "poaching", demand: 3),
        Technique(name: "pickling", demand: 3)
    ]

    nonisolated static func demand(of technique: String) -> Int {
        all.first { $0.name == technique }?.demand ?? 3
    }

    /// Words in the method that mean a technique. Deliberately verb-shaped:
    /// "roast" catches "roast", "roasted" and "roasting" by prefix.
    private nonisolated static let markers: [String: String] = [
        "boil": "boiling", "blanch": "boiling",
        "grill": "grilling", "barbecue": "grilling", "char": "grilling",
        "roast": "roasting",
        "sauté": "sautéing", "saute": "sautéing", "sweat": "sautéing",
        "stir-fry": "stir-frying", "stir fry": "stir-frying", "wok": "stir-frying",
        "bake": "baking",
        "simmer": "simmering", "reduce": "simmering",
        "steam": "steaming",
        "shallow-fry": "frying", "pan-fry": "frying", "sear": "frying",
        "braise": "braising", "pot-roast": "braising",
        "slow cook": "slow-cooking", "slow-cook": "slow-cooking",
        "pressure cook": "pressure-cooking", "instant pot": "pressure-cooking",
        "air fry": "air-frying", "air-fry": "air-frying", "air fryer": "air-frying",
        "emulsif": "emulsifying", "whisk in": "emulsifying",
        "caramelis": "caramelising", "carameliz": "caramelising",
        "prove": "proving", "proof": "proving", "rise until": "proving",
        "laminat": "laminating", "fold the butter": "laminating",
        "temper": "tempering",
        "ferment": "fermenting",
        "cure": "curing", "brine": "curing",
        "smoke": "smoking",
        "sous vide": "sous vide",
        "deep-fry": "deep-frying", "deep fry": "deep-frying",
        "poach": "poaching",
        "pickle": "pickling"
    ]

    /// Techniques a recipe uses, from its steps and tags.
    nonisolated static func techniques(
        stepTexts: [String],
        tags: [String] = []
    ) -> Set<String> {
        let haystack = (stepTexts + tags)
            .joined(separator: " ")
            .lowercased()

        guard !haystack.isEmpty else { return [] }

        var found: Set<String> = []

        for (marker, technique) in markers where haystack.contains(marker) {
            found.insert(technique)
        }

        return found
    }

    nonisolated static func techniques(for recipe: Recipe) -> Set<String> {
        techniques(
            stepTexts: recipe.orderedSteps.map(\.text),
            tags: recipe.tags
        )
    }
}
