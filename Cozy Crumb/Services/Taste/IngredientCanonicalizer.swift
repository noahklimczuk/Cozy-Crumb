//
//  IngredientCanonicalizer.swift
//  Cozy Crumb
//
//  "Roma tomatoes", "cherry tomatoes" and "1 can diced tomatoes" are all
//  *tomato*. Working that out is the foundation of the taste profile: without
//  it every affinity is computed over a hundred near-duplicate keys and the
//  whole thing turns to mush.
//
//  This is deliberately NOT `GroceryMerge.normalizedName`, and the two must
//  not be merged. They answer different questions:
//
//      GroceryMerge  — "is this the same thing to buy?"
//                      ground beef ≠ beef, dried basil ≠ basil,
//                      cherry tomato ≠ tomato. Collapsing those puts the
//                      wrong product in someone's basket.
//
//      this file     — "is this the same food?"
//                      ground beef = beef, dried basil = basil,
//                      cherry tomato = tomato. Keeping those apart means
//                      never noticing that someone likes beef.
//
//  So this layer is aggressive where that one is careful, and the shopping
//  list is unaffected by anything here.
//
//  The order of operations matters more than any single rule:
//
//      1. surface tidy-up      strip amounts, units, notes, punctuation
//      2. compounds            "coconut milk" is not milk. Checked FIRST,
//                              because everything after this reduces.
//      3. synonyms             cilantro/coriander, prawn/shrimp, courgette/…
//      4. descriptor stripping variety, prep, size, colour, cut
//      5. head noun            the last word standing, singularised
//
//  Step 2 exists because of the failure it prevents. Someone lactose
//  intolerant who cooks with coconut milk must not have "milk" written into
//  their ingredient affinities — and someone with a peanut allergy must never
//  have "peanut butter" reduced to "butter". Compound protection is a
//  correctness rule, not a nicety.
//

import Foundation

nonisolated enum IngredientCanonicalizer {

    // MARK: - Entry point

    /// The canonical food name for a line, a pantry item or a grocery row.
    ///
    /// Always returns something: a name it cannot reduce comes back tidied
    /// rather than empty, because an unrecognised food is still a food and
    /// dropping it would silently narrow the profile.
    nonisolated static func canonical(_ raw: String) -> String {
        let tidied = surfaceForm(raw)
        guard !tidied.isEmpty else { return "" }

        if let compound = compound(in: tidied) {
            return compound
        }

        if let synonym = synonyms[tidied] {
            return synonym
        }

        let stripped = stripDescriptors(from: tidied)

        if let compound = compound(in: stripped) {
            return compound
        }
        if let synonym = synonyms[stripped] {
            return synonym
        }
        if canonicalFoods.contains(stripped) {
            return stripped
        }

        let head = singularised(stripped.components(separatedBy: " ").last ?? stripped)

        if let synonym = synonyms[head] {
            return synonym
        }

        return head.isEmpty ? stripped : head
    }

    /// Canonical names for a whole recipe, deduplicated, section headers and
    /// blanks dropped.
    nonisolated static func canonical(ingredients: [Ingredient]) -> Set<String> {
        var names: Set<String> = []

        for ingredient in ingredients where !ingredient.isSectionHeader {
            let name = canonical(ingredient.name.isEmpty ? ingredient.rawText : ingredient.name)
            if !name.isEmpty {
                names.insert(name)
            }
        }

        return names
    }

    // MARK: - Staples

    /// Things almost every kitchen has, and whose absence should not count
    /// against a recipe.
    ///
    /// §4 weights pantry match at 0.30, and without this a recipe is marked
    /// "missing 3 ingredients" because the user never thought to add salt,
    /// pepper and oil to their pantry. Missing the chicken matters; missing
    /// the salt does not.
    nonisolated static let staples: Set<String> = [
        "salt", "pepper", "black pepper", "water", "oil", "olive oil",
        "vegetable oil", "sunflower oil", "canola oil", "cooking spray",
        "butter", "flour", "sugar", "brown sugar", "icing sugar",
        "baking powder", "baking soda", "cornstarch", "vinegar",
        "white vinegar", "ice"
    ]

    nonisolated static func isStaple(_ raw: String) -> Bool {
        let name = canonical(raw)
        return staples.contains(name) || staples.contains(surfaceForm(raw))
    }

    // MARK: - Step 1: surface form

    private nonisolated static let units: Set<String> = [
        "g", "gram", "grams", "kg", "ml", "l", "litre", "litres", "liter",
        "liters", "tsp", "teaspoon", "teaspoons", "tbsp", "tablespoon",
        "tablespoons", "cup", "cups", "oz", "ounce", "ounces", "lb", "lbs",
        "pound", "pounds", "clove", "cloves", "piece", "pieces", "pinch",
        "pinches", "can", "cans", "tin", "tins", "jar", "jars", "packet",
        "packets", "pack", "packs", "bunch", "bunches", "handful", "handfuls",
        "sprig", "sprigs", "stick", "sticks", "slice", "slices", "head",
        "heads", "knob", "dash", "splash", "box", "bag"
    ]

    private nonisolated static let articles: Set<String> = ["a", "an", "the", "of", "some"]

    /// Lowercase, drop bracketed asides and anything after a comma, drop
    /// amounts and units, drop articles.
    ///
    /// Cutting at the comma is what turns "tomatoes, roughly chopped" into
    /// "tomatoes". Recipe writers put the food first and the instruction
    /// after the comma with remarkable consistency.
    nonisolated static func surfaceForm(_ raw: String) -> String {
        var text = raw.lowercased()

        // Bracketed asides: "tomatoes (san marzano, if you can get them)".
        while let open = text.firstIndex(of: "("), let close = text[open...].firstIndex(of: ")") {
            text.removeSubrange(open...close)
        }

        if let comma = text.firstIndex(of: ",") {
            text = String(text[..<comma])
        }

        // "chicken thighs - bone in" and "chicken thighs — bone in".
        for separator in [" - ", " – ", " — ", ": "] {
            if let range = text.range(of: separator) {
                text = String(text[..<range.lowerBound])
            }
        }

        text = text.replacingOccurrences(of: "/", with: " ")

        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-'"))
        text = String(text.unicodeScalars.filter { allowed.contains($0) })

        let words = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .filter { word in
                // Amounts, fractions and ranges are not part of the name.
                if word.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." || $0 == "'" }) { return false }
                if units.contains(word) { return false }
                if articles.contains(word) { return false }
                return true
            }

        guard var last = words.last else { return "" }
        last = singularised(last)

        // Singularised here rather than at the end: every later step matches
        // against singular keys, so "coconut milks" has to become "coconut
        // milk" before the compound check, not after it.
        return (words.dropLast() + [last])
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Step 2: compounds

    /// Phrases whose meaning is not their head noun. Checked before anything
    /// reduces, and matched on the tail so "full-fat coconut milk" still
    /// lands on "coconut milk".
    ///
    /// Every entry here is either a safety matter (the milks and the nut
    /// butters) or a food that is genuinely unrelated to its head noun
    /// (a sweet potato is not a potato).
    nonisolated static let compounds: Set<String> = [
        // Dairy-shaped things that are not dairy.
        "coconut milk", "coconut cream", "almond milk", "oat milk",
        "soy milk", "soya milk", "rice milk", "cashew milk",
        // Nut and seed butters.
        "peanut butter", "almond butter", "cashew butter", "tahini",
        // Sauces and condiments whose head noun means something else.
        "soy sauce", "fish sauce", "oyster sauce", "hoisin sauce",
        "worcestershire sauce", "hot sauce", "tomato sauce", "tomato paste",
        "tomato puree", "apple cider vinegar", "balsamic vinegar",
        "rice vinegar", "red wine vinegar", "white wine vinegar",
        "sesame oil", "olive oil", "coconut oil", "chilli oil", "chili oil",
        "truffle oil",
        // Different foods that share a head noun with another.
        "sweet potato", "bell pepper", "chilli pepper", "chili pepper",
        "cream cheese", "sour cream", "double cream", "single cream",
        "heavy cream", "whipping cream", "greek yogurt", "greek yoghurt",
        "coconut water", "spring onion",
        "bay leaf", "star anise", "black bean", "green bean", "broad bean",
        "brown sugar", "icing sugar", "caster sugar", "powdered sugar",
        "baking powder", "baking soda", "black pepper", "white pepper",
        "cayenne pepper", "maple syrup", "golden syrup", "corn syrup",
        "olive tapenade", "puff pastry", "filo pastry", "shortcrust pastry",
        "brussels sprout", "spring roll wrapper", "wonton wrapper",
        "short rib", "spare rib",
        "chicken stock", "beef stock", "vegetable stock", "chicken broth",
        "beef broth", "vegetable broth", "fish stock",
        "condensed milk", "evaporated milk", "buttermilk"
    ]

    /// The longest compound that the text ends with, if any. Longest wins so
    /// "chilli oil" is not swallowed by a shorter match.
    private nonisolated static func compound(in text: String) -> String? {
        compounds
            .filter { text == $0 || text.hasSuffix(" " + $0) }
            .max { $0.count < $1.count }
    }

    // MARK: - Step 3: synonyms

    /// Two names, one food. The right-hand side is arbitrary but must be
    /// stable — it becomes the key everything downstream aggregates on.
    nonisolated static let synonyms: [String: String] = [
        "coriander": "cilantro",
        "coriander leaf": "cilantro",
        "aubergine": "eggplant",
        "courgette": "zucchini",
        "rocket": "arugula",
        "prawn": "shrimp",
        "king prawn": "shrimp",
        "garbanzo": "chickpea",
        "garbanzo bean": "chickpea",
        "chick pea": "chickpea",
        "scallion": "spring onion",
        "green onion": "spring onion",
        "salad onion": "spring onion",
        "capsicum": "bell pepper",
        "sweet pepper": "bell pepper",
        "mince": "beef",
        "beef mince": "beef",
        "minced beef": "beef",
        "hamburger": "beef",
        "swede": "rutabaga",
        "beetroot": "beet",
        "spring greens": "collard greens",
        "cornflour": "cornstarch",
        "corn flour": "cornstarch",
        "plain flour": "flour",
        "all purpose flour": "flour",
        "all-purpose flour": "flour",
        "self raising flour": "flour",
        "double cream": "cream",
        "single cream": "cream",
        "heavy cream": "cream",
        "whipping cream": "cream",
        "greek yoghurt": "greek yogurt",
        "yoghurt": "yogurt",
        "chilli": "chili",
        "chile": "chili",
        "chilli flake": "chili flake",
        "red pepper flake": "chili flake",
        "chilli powder": "chili powder",
        "soya sauce": "soy sauce",
        "gochujang paste": "gochujang",
        "creme fraiche": "sour cream",
        "crème fraîche": "sour cream",
        "passata": "tomato puree",
        "aioli": "mayonnaise",
        "mayo": "mayonnaise",
        "bicarbonate soda": "baking soda",
        "bicarb": "baking soda",
        "stock cube": "stock",
        "bouillon": "stock",
        "sea salt": "salt",
        "kosher salt": "salt",
        "table salt": "salt",
        "flaky salt": "salt",
        "peppercorn": "black pepper",
        "red pepper": "bell pepper",
        "green pepper": "bell pepper"
    ]

    // MARK: - Step 4: descriptors

    /// Words that describe a food without changing which food it is.
    ///
    /// Broader than `GroceryMerge.preparationWords` on purpose — this list
    /// includes variety names ("roma", "cherry"), states ("dried", "frozen",
    /// "canned"), and cuts ("thigh", "breast"), all of which that list must
    /// keep because they change what you buy.
    nonisolated static let descriptors: Set<String> = [
        // Preparation.
        "chopped", "diced", "minced", "sliced", "grated", "crushed",
        "shredded", "cubed", "julienned", "halved", "quartered", "peeled",
        "trimmed", "finely", "roughly", "thinly", "coarsely", "freshly",
        "beaten", "melted", "softened", "divided", "packed", "rinsed",
        "drained", "cooked", "uncooked", "raw", "toasted", "roasted",
        "boneless", "skinless", "bone-in", "skin-on", "deveined", "shelled",
        "pitted", "seeded", "stemmed", "washed", "trimmed", "torn",
        // Size and quality.
        "large", "small", "medium", "extra", "jumbo", "baby", "mini",
        "ripe", "fresh", "good", "quality", "free-range", "organic",
        "unsalted", "salted", "low-fat", "full-fat", "fat-free", "reduced",
        "lean", "whole", "half", "thick", "thin", "firm", "soft",
        // State.
        "dried", "dry", "frozen", "canned", "tinned", "jarred", "smoked",
        "cured", "pickled", "fermented", "ground", "granulated", "flaked",
        "powdered", "instant", "plain", "natural", "unsweetened", "sweetened",
        // Colour and variety.
        "roma", "cherry", "plum", "vine", "heirloom", "beefsteak",
        "yukon", "russet", "maris", "piper", "waxy", "floury",
        "white", "yellow", "purple", "golden", "dark", "light",
        "red", "green",
        "wild", "farmed", "atlantic", "pacific", "king", "tiger",
        "italian", "french", "spanish", "greek", "thai", "chinese",
        "japanese", "mexican", "indian", "korean", "vietnamese",
        // Cuts. The animal is the food; the cut is a detail.
        "thigh", "thighs", "breast", "breasts", "shoulder", "loin",
        "tenderloin", "fillet", "fillets", "filet", "steak", "steaks",
        "chop", "chops", "wing", "wings", "drumstick", "drumsticks",
        "shank", "brisket", "rib", "ribs", "rump", "sirloin", "belly",
        "leg", "legs", "thigh", "mince", "cutlet", "cutlets", "escalope"
    ]

    /// Removes descriptors, but never the last word standing — "fresh" on its
    /// own is nothing, and an empty key would collapse unrelated foods
    /// together.
    nonisolated static func stripDescriptors(from text: String) -> String {
        var words = text.components(separatedBy: " ").filter { !$0.isEmpty }
        guard words.count > 1 else { return text }

        var kept = words.filter { !descriptors.contains($0) }

        if kept.isEmpty {
            // Everything was a descriptor: "boneless skinless" with no noun.
            // Keep the last word rather than returning nothing.
            kept = [words.removeLast()]
        }

        return kept.joined(separator: " ")
    }

    // MARK: - Step 5: head noun

    /// Foods that are two words and stay two words, but are not "compounds"
    /// in the protective sense — reducing them to a head noun would merely be
    /// wrong rather than dangerous.
    nonisolated static let canonicalFoods: Set<String> = [
        "spring onion", "bell pepper", "sweet potato", "greek yogurt",
        "chili flake", "kaffir lime", "curry paste", "palm sugar",
        "soy sauce", "fish sauce", "olive oil", "sesame oil", "coconut milk",
        "peanut butter", "cream cheese", "sour cream", "black pepper",
        "brown sugar", "chili powder", "bay leaf",
        "star anise", "tomato paste", "tomato puree",
        "maple syrup", "puff pastry", "green bean", "black bean"
    ]

    private nonisolated static let irregularPlurals: [String: String] = [
        "leaves": "leaf",
        "loaves": "loaf",
        "knives": "knife",
        "halves": "half",
        "potatoes": "potato",
        "tomatoes": "tomato",
        "mangoes": "mango",
        "avocadoes": "avocado",
        "anchovies": "anchovy",
        "berries": "berry",
        "cherries": "cherry",
        "chives": "chive",
        "chillies": "chilli",
        "chilies": "chili",
        "ribs": "rib",
        "greens": "greens",
        "molasses": "molasses",
        "couscous": "couscous",
        "hummus": "hummus",
        "asparagus": "asparagus",
        "watercress": "watercress"
    ]

    private nonisolated static let neverSingularised: Set<String> = [
        "greens", "molasses", "couscous", "hummus", "asparagus",
        "watercress", "swiss chard", "grits", "oats"
    ]

    nonisolated static func singularised(_ word: String) -> String {
        if let irregular = irregularPlurals[word] { return irregular }
        if neverSingularised.contains(word) { return word }
        guard word.count > 3 else { return word }

        for ending in ["us", "ss", "is", "os"] where word.hasSuffix(ending) {
            return word
        }

        if word.hasSuffix("ies") {
            return String(word.dropLast(3)) + "y"
        }
        if word.hasSuffix("oes") {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("es"), word.count > 4 {
            let stem = String(word.dropLast(2))
            // "cheeses" → "cheese", not "chees".
            if stem.hasSuffix("s") || stem.hasSuffix("x") || stem.hasSuffix("ch") || stem.hasSuffix("sh") {
                return stem
            }
            return String(word.dropLast())
        }
        if word.hasSuffix("s") {
            return String(word.dropLast())
        }
        return word
    }
}
