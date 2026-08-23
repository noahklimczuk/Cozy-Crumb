//
//  IngredientSubstitutions.swift
//  Cozy Crumb
//
//  What you can get away with not having.
//
//  §4 asks for missing-ingredient awareness, and the reason is that "8 of 9
//  ingredients" hides the only question that matters: *which* one is missing.
//  A recipe short of mirin is a shopping-free dinner with a bit of improvising.
//  A recipe short of the chicken is not dinner. Those two should not score the
//  same, and without this they do.
//
//  Substitutions are only ever offered for the things that genuinely have
//  one. There is no substitute for the protein a dish is named after, and
//  pretending otherwise produces confident nonsense.
//

import Foundation

nonisolated enum IngredientSubstitutions {

    /// Canonical name → what to use instead, in plain words.
    nonisolated static let table: [String: String] = [
        "mirin": "rice vinegar with a pinch of sugar",
        "shaoxing": "dry sherry",
        "sake": "dry white wine",
        "creme fraiche": "sour cream",
        "sour cream": "greek yogurt",
        "greek yogurt": "sour cream",
        "buttermilk": "milk with a squeeze of lemon",
        "heavy cream": "milk and a knob of butter",
        "shallot": "a little more onion",
        "spring onion": "chives, or the green of a leek",
        "cilantro": "flat-leaf parsley",
        "basil": "flat-leaf parsley at a pinch",
        "tarragon": "chervil, or fennel fronds",
        "lime": "lemon",
        "lemon": "lime",
        "rice vinegar": "white wine vinegar",
        "sherry vinegar": "red wine vinegar",
        "balsamic vinegar": "red wine vinegar with a little honey",
        "tomato puree": "tomato paste, loosened",
        "tomato paste": "reduced passata",
        "gochujang": "sriracha with a spoon of miso",
        "harissa": "chili paste with cumin and caraway",
        "chipotle": "smoked paprika and a fresh chili",
        "smoked paprika": "sweet paprika and a drop of liquid smoke",
        "panko": "coarse dried breadcrumbs",
        "cornstarch": "plain flour, using twice as much",
        "caster sugar": "granulated sugar, blitzed",
        "brown sugar": "white sugar with a spoon of molasses",
        "maple syrup": "honey",
        "honey": "maple syrup",
        "parmesan": "pecorino, or another hard cheese",
        "pancetta": "streaky bacon",
        "prosciutto": "any thin-cut cured ham",
        "ricotta": "cottage cheese, drained",
        "mascarpone": "cream cheese",
        "ghee": "clarified butter, or just butter",
        "fish sauce": "soy sauce with a little lime",
        "oyster sauce": "hoisin with a splash of soy",
        "hoisin sauce": "sweetened soy with five spice",
        "tahini": "smooth peanut butter",
        "star anise": "a pinch of five spice",
        "lemongrass": "lemon zest",
        "galangal": "ginger",
        "kaffir lime": "lime zest",
        "preserved lemon": "lemon zest and a pinch of salt",
        "sumac": "lemon zest",
        "za'atar": "thyme, sesame and a little sumac",
        "dashi": "light chicken or vegetable stock",
        "miso": "a little soy and a spoon of tahini",
        "polenta": "coarse cornmeal",
        "arborio": "any short-grain rice",
        "vegetable stock": "water and a little seasoning",
        "chicken stock": "vegetable stock",
        "double cream": "heavy cream",
        "yogurt": "sour cream"
    ]

    nonisolated static func substitute(for ingredient: String) -> String? {
        table[IngredientCanonicalizer.canonical(ingredient)]
    }

    /// Foods a dish is usually built around. Missing one of these is not a
    /// small problem, whatever the match percentage says.
    nonisolated static let coreProteinsAndBases: Set<String> = [
        "chicken", "beef", "pork", "lamb", "duck", "turkey", "salmon", "tuna",
        "cod", "haddock", "shrimp", "tofu", "paneer", "halloumi", "egg",
        "chickpea", "lentil", "black bean", "pasta", "rice", "noodle",
        "potato", "bread", "flour", "mushroom", "cauliflower", "eggplant"
    ]

    /// How much it hurts to be missing this, 0 (barely) to 1 (that's the dish).
    nonisolated static func severity(ofMissing ingredient: String) -> Double {
        let name = IngredientCanonicalizer.canonical(ingredient)

        if IngredientCanonicalizer.isStaple(name) { return 0.1 }
        if coreProteinsAndBases.contains(name) { return 1.0 }
        if table[name] != nil { return 0.35 }
        return 0.7
    }
}
