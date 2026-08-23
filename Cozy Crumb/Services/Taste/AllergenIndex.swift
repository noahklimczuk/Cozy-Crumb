//
//  AllergenIndex.swift
//  Cozy Crumb
//
//  Which foods count as which allergen, and which foods a diet rules out.
//
//  This is the safety-critical part of the feature and it is written to fail
//  in one direction only. Every list here errs toward catching too much: if
//  the app is unsure whether something contains an allergen, the recipe does
//  not appear. A missed suggestion costs someone a slightly duller week. A
//  missed allergen costs considerably more.
//
//  Two consequences of that stance, both deliberate:
//
//    * Groups expand. Someone allergic to nuts is not asked to enumerate
//      almonds, cashews, pistachios and pecans — "nuts" covers the lot, and
//      the lot includes the compounds (almond milk, peanut butter) that the
//      canonicaliser deliberately keeps whole.
//
//    * Matching is by canonical name *and* by substring on the raw line, so
//      "toasted flaked almonds" is caught even though the canonicaliser
//      reduces it to "almond" and something unusual might not reduce at all.
//
//  There is no "you could substitute" path anywhere in here. §7.1 is explicit
//  that an allergen recipe does not appear at all, not with a caveat attached.
//

import Foundation

nonisolated enum AllergenIndex {

    /// Allergen name → every food that counts as it.
    ///
    /// Canonical names where possible, but raw spellings are included freely:
    /// this list is matched loosely and a duplicate costs nothing.
    nonisolated static let groups: [String: Set<String>] = [
        "peanut": [
            "peanut", "peanut butter", "groundnut", "peanut oil", "satay"
        ],
        "tree nut": [
            "almond", "almond milk", "almond butter", "cashew", "cashew milk",
            "cashew butter", "walnut", "pecan", "pistachio", "hazelnut",
            "macadamia", "brazil nut", "pine nut", "chestnut", "nutella",
            "marzipan", "praline", "frangipane", "amaretto"
        ],
        "milk": [
            "milk", "butter", "cheese", "cream", "cream cheese", "sour cream",
            "yogurt", "greek yogurt", "buttermilk", "ghee", "parmesan",
            "cheddar", "mozzarella", "ricotta", "feta", "halloumi", "brie",
            "gruyere", "manchego", "mascarpone", "creme fraiche", "custard",
            "condensed milk", "evaporated milk", "whey", "casein", "paneer"
        ],
        "egg": [
            "egg", "egg white", "egg yolk", "mayonnaise", "meringue",
            "aioli", "custard", "hollandaise"
        ],
        "shellfish": [
            "shrimp", "prawn", "crab", "lobster", "crayfish", "langoustine",
            "mussel", "clam", "oyster", "scallop", "squid", "calamari",
            "octopus", "cockle", "whelk", "shellfish", "oyster sauce",
            "fish sauce", "shrimp paste", "belacan", "krill"
        ],
        "fish": [
            "fish", "salmon", "tuna", "cod", "haddock", "mackerel", "sardine",
            "anchovy", "trout", "halibut", "sea bass", "snapper", "tilapia",
            "pollock", "fish sauce", "worcestershire sauce", "caviar", "roe",
            "bonito", "dashi"
        ],
        "gluten": [
            "flour", "bread", "breadcrumb", "panko", "pasta", "spaghetti",
            "noodle", "couscous", "bulgur", "semolina", "barley", "rye",
            "wheat", "farro", "spelt", "seitan", "soy sauce", "puff pastry",
            "filo pastry", "shortcrust pastry", "cracker", "tortilla",
            "orzo", "udon", "ramen", "beer", "malt"
        ],
        "soy": [
            "soy", "soy sauce", "soya sauce", "tofu", "edamame", "miso",
            "tempeh", "soy milk", "soya milk", "hoisin sauce", "gochujang",
            "doenjang", "tamari"
        ],
        "sesame": [
            "sesame", "sesame oil", "tahini", "hummus", "za'atar", "halva",
            "sesame seed"
        ],
        "mustard": ["mustard", "dijon", "wholegrain mustard", "mustard seed"],
        "celery": ["celery", "celeriac", "celery salt"],
        "sulphite": ["wine", "dried apricot", "vinegar"]
    ]

    /// Spellings people actually type, mapped onto a group.
    nonisolated static let aliases: [String: String] = [
        "nuts": "tree nut", "nut": "tree nut", "tree nuts": "tree nut",
        "peanuts": "peanut",
        "dairy": "milk", "lactose": "milk", "cheese": "milk",
        "eggs": "egg",
        "wheat": "gluten", "coeliac": "gluten", "celiac": "gluten",
        "shellfish": "shellfish", "crustacean": "shellfish",
        "seafood": "shellfish",
        "soya": "soy",
        "sesame seeds": "sesame"
    ]

    /// Resolves what someone typed to a group name, if it is one.
    nonisolated static func group(named raw: String) -> String? {
        let key = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if groups[key] != nil { return key }
        if let alias = aliases[key], groups[alias] != nil { return alias }

        // Someone allergic to one specific nut still names a group member.
        for (group, members) in groups where members.contains(key) {
            return group
        }
        return nil
    }

    /// Every food to exclude for a set of stated allergies.
    ///
    /// Anything that does not resolve to a known group is kept as itself, so
    /// an unusual allergy still filters rather than being silently dropped.
    nonisolated static func excludedFoods(forAllergies allergies: Set<String>) -> Set<String> {
        var excluded: Set<String> = []

        for allergy in allergies {
            let key = allergy.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }

            if let group = group(named: key), let members = groups[group] {
                excluded.formUnion(members)
            }
            excluded.insert(key)
            excluded.insert(IngredientCanonicalizer.canonical(key))
        }

        return excluded.filter { !$0.isEmpty }
    }
}

// MARK: - Diets

/// A way of eating, and what it rules out.
nonisolated enum DietaryRule: String, CaseIterable, Codable, Sendable, Identifiable {
    case vegetarian
    case vegan
    case pescatarian
    case dairyFree
    case glutenFree
    case nutFree
    case porkFree
    case shellfishFree

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .pescatarian: "Pescatarian"
        case .dairyFree: "Dairy free"
        case .glutenFree: "Gluten free"
        case .nutFree: "Nut free"
        case .porkFree: "No pork"
        case .shellfishFree: "No shellfish"
        }
    }

    /// Foods this rules out.
    nonisolated var excludedFoods: Set<String> {
        switch self {
        case .vegetarian:
            Self.meat.union(Self.poultry).union(AllergenIndex.groups["fish"] ?? [])
                .union(AllergenIndex.groups["shellfish"] ?? [])
                .union(["gelatin", "lard", "suet", "anchovy", "bone broth", "chicken stock", "beef stock"])
        case .vegan:
            DietaryRule.vegetarian.excludedFoods
                .union(AllergenIndex.groups["milk"] ?? [])
                .union(AllergenIndex.groups["egg"] ?? [])
                .union(["honey"])
        case .pescatarian:
            Self.meat.union(Self.poultry).union(["gelatin", "lard", "suet"])
        case .dairyFree:
            AllergenIndex.groups["milk"] ?? []
        case .glutenFree:
            AllergenIndex.groups["gluten"] ?? []
        case .nutFree:
            (AllergenIndex.groups["tree nut"] ?? []).union(AllergenIndex.groups["peanut"] ?? [])
        case .porkFree:
            ["pork", "bacon", "ham", "prosciutto", "pancetta", "chorizo",
             "sausage", "salami", "lard", "gammon", "pepperoni", "guanciale"]
        case .shellfishFree:
            AllergenIndex.groups["shellfish"] ?? []
        }
    }

    nonisolated static let meat: Set<String> = [
        "beef", "pork", "lamb", "veal", "venison", "goat", "rabbit",
        "bacon", "ham", "prosciutto", "pancetta", "chorizo", "sausage",
        "salami", "steak", "mince", "brisket", "short rib", "guanciale",
        "pepperoni", "gammon"
    ]

    nonisolated static let poultry: Set<String> = [
        "chicken", "turkey", "duck", "goose", "quail", "pheasant"
    ]
}
