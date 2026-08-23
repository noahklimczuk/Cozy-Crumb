//
//  CuisineClassifier.swift
//  Cozy Crumb
//
//  Works out what kind of food a recipe is, because nothing in the data model
//  says.
//
//  `Recipe` carries free-text tags, and the ones that actually turn up look
//  like ["quick", "fish", "weeknight"] — useful, but not a cuisine. Two of
//  the profile's most important numbers need one: cuisine affinity, and
//  novelty appetite, which is measured as distinct cuisines cooked over a
//  window. Without this the first is empty and the second is meaningless.
//
//  No LLM. Three passes, cheapest first, and it declines to answer rather
//  than guessing:
//
//      1. tags       an explicit "thai" tag is the user's own word for it
//      2. title      "pad thai", "carbonara", "chicken tikka masala"
//      3. pantry     the ingredient signature — fish sauce + lime + lemongrass
//
//  Pass 3 is scored rather than matched, and needs a clear winner. A recipe
//  with garlic, onion and olive oil is not Italian; it is just dinner, and
//  saying "Italian" about it would put a wrong number into the profile and a
//  wrong sentence onto the Taste Profile screen.
//

import Foundation

nonisolated enum CuisineClassifier {

    /// The cuisines the app can name. Keys are canonical and stable — they
    /// become dictionary keys in the taste profile and strings in the digest.
    nonisolated static let known: [String] = [
        "thai", "italian", "mexican", "indian", "chinese", "japanese",
        "korean", "french", "greek", "spanish", "middle eastern",
        "vietnamese", "american", "british", "german", "moroccan",
        "caribbean", "ethiopian", "turkish", "polish"
    ]

    /// Tag spellings that mean a cuisine.
    private nonisolated static let tagAliases: [String: String] = [
        "thai": "thai",
        "italian": "italian", "pasta": "italian",
        "mexican": "mexican", "tex-mex": "mexican", "tex mex": "mexican",
        "indian": "indian", "curry": "indian",
        "chinese": "chinese", "cantonese": "chinese", "sichuan": "chinese",
        "japanese": "japanese", "sushi": "japanese", "ramen": "japanese",
        "korean": "korean",
        "french": "french",
        "greek": "greek",
        "spanish": "spanish", "tapas": "spanish",
        "middle eastern": "middle eastern", "lebanese": "middle eastern",
        "persian": "middle eastern", "israeli": "middle eastern",
        "vietnamese": "vietnamese",
        "american": "american", "southern": "american", "cajun": "american",
        "british": "british", "english": "british",
        "german": "german",
        "moroccan": "moroccan", "north african": "moroccan",
        "caribbean": "caribbean", "jamaican": "caribbean",
        "ethiopian": "ethiopian",
        "turkish": "turkish",
        "polish": "polish"
    ]

    /// Dish names that settle it on their own.
    private nonisolated static let titleMarkers: [String: String] = [
        "pad thai": "thai", "tom yum": "thai", "tom kha": "thai",
        "green curry": "thai", "red curry": "thai", "massaman": "thai",
        "larb": "thai", "som tam": "thai",

        "carbonara": "italian", "bolognese": "italian", "risotto": "italian",
        "lasagne": "italian", "lasagna": "italian", "gnocchi": "italian",
        "cacio e pepe": "italian", "puttanesca": "italian", "amatriciana": "italian",
        "arrabbiata": "italian", "pizza": "italian", "focaccia": "italian",
        "osso buco": "italian", "caprese": "italian", "pesto": "italian",

        "taco": "mexican", "burrito": "mexican", "quesadilla": "mexican",
        "enchilada": "mexican", "fajita": "mexican", "mole": "mexican",
        "carnitas": "mexican", "birria": "mexican", "elote": "mexican",
        "chilaquiles": "mexican", "pozole": "mexican",

        "tikka": "indian", "masala": "indian", "biryani": "indian",
        "dal": "indian", "daal": "indian", "korma": "indian",
        "vindaloo": "indian", "saag": "indian", "rogan josh": "indian",
        "butter chicken": "indian", "chana": "indian", "paneer": "indian",

        "kung pao": "chinese", "mapo": "chinese", "chow mein": "chinese",
        "lo mein": "chinese", "fried rice": "chinese", "dumpling": "chinese",
        "char siu": "chinese", "dan dan": "chinese", "wonton": "chinese",

        "ramen": "japanese", "katsu": "japanese", "teriyaki": "japanese",
        "sushi": "japanese", "donburi": "japanese", "miso soup": "japanese",
        "gyoza": "japanese", "okonomiyaki": "japanese", "yakitori": "japanese",

        "bibimbap": "korean", "bulgogi": "korean", "kimchi": "korean",
        "japchae": "korean", "tteokbokki": "korean",

        "coq au vin": "french", "ratatouille": "french", "cassoulet": "french",
        "bourguignon": "french", "quiche": "french", "gratin": "french",
        "confit": "french", "bouillabaisse": "french", "tarte tatin": "french",

        "moussaka": "greek", "souvlaki": "greek", "spanakopita": "greek",
        "tzatziki": "greek", "gyro": "greek",

        "paella": "spanish", "tortilla espanola": "spanish", "gazpacho": "spanish",
        "patatas bravas": "spanish", "romesco": "spanish",

        "shakshuka": "middle eastern", "falafel": "middle eastern",
        "hummus": "middle eastern", "shawarma": "middle eastern",
        "kofta": "middle eastern", "fattoush": "middle eastern",
        "tabbouleh": "middle eastern", "baba ganoush": "middle eastern",

        "pho": "vietnamese", "banh mi": "vietnamese", "bun cha": "vietnamese",
        "goi cuon": "vietnamese",

        "gumbo": "american", "jambalaya": "american", "mac and cheese": "american",
        "cornbread": "american", "buffalo wing": "american", "clam chowder": "american",
        "sloppy joe": "american", "meatloaf": "american",

        "shepherd's pie": "british", "cottage pie": "british",
        "toad in the hole": "british", "bangers and mash": "british",
        "full english": "british", "sticky toffee": "british",
        "yorkshire pudding": "british", "ploughman": "british",

        "schnitzel": "german", "spaetzle": "german", "sauerbraten": "german",
        "bratwurst": "german",

        "tagine": "moroccan", "harira": "moroccan", "chermoula": "moroccan",

        "jerk chicken": "caribbean", "callaloo": "caribbean", "roti": "caribbean",

        "injera": "ethiopian", "doro wat": "ethiopian", "berbere": "ethiopian",

        "menemen": "turkish", "borek": "turkish", "pide": "turkish",

        "pierogi": "polish", "bigos": "polish", "kielbasa": "polish"
    ]

    /// Ingredients that point at a cuisine, and how strongly.
    ///
    /// Weights are the point. Fish sauce is nearly decisive for Southeast
    /// Asian cooking; garlic is decisive for nothing. Only ingredients that
    /// genuinely narrow the field are listed at all — a signature is built
    /// from what is unusual, not from what is common.
    private nonisolated static let ingredientMarkers: [String: [String: Double]] = [
        "thai": [
            "fish sauce": 2.0, "lemongrass": 2.5, "galangal": 3.0,
            "thai basil": 3.0, "kaffir lime": 3.0, "coconut milk": 1.0,
            "palm sugar": 2.0, "bird's eye chili": 2.0, "curry paste": 1.5
        ],
        "vietnamese": [
            "fish sauce": 1.5, "rice noodle": 1.5, "star anise": 1.0,
            "rice paper": 3.0, "hoisin sauce": 1.0, "cilantro": 0.5
        ],
        "chinese": [
            "soy sauce": 1.0, "shaoxing": 3.0, "oyster sauce": 2.5,
            "hoisin sauce": 2.0, "sichuan peppercorn": 3.0, "five spice": 2.5,
            "sesame oil": 1.0, "rice vinegar": 1.0, "black bean": 1.5
        ],
        "japanese": [
            "miso": 2.5, "mirin": 3.0, "dashi": 3.0, "sake": 2.0,
            "nori": 2.5, "panko": 2.0, "wasabi": 2.5, "soy sauce": 0.5
        ],
        "korean": [
            "gochujang": 3.0, "gochugaru": 3.0, "kimchi": 3.0,
            "sesame oil": 1.0, "soy sauce": 0.5, "doenjang": 3.0
        ],
        "indian": [
            "garam masala": 3.0, "turmeric": 1.5, "cumin": 1.0,
            "cardamom": 1.5, "ghee": 2.0, "paneer": 3.0, "curry leaf": 3.0,
            "asafoetida": 3.0, "fenugreek": 2.5, "coriander seed": 1.0
        ],
        "italian": [
            "parmesan": 2.0, "pancetta": 2.5, "basil": 1.0, "oregano": 1.0,
            "mozzarella": 2.0, "ricotta": 2.0, "balsamic vinegar": 1.5,
            "prosciutto": 2.5, "pasta": 1.5, "polenta": 2.0
        ],
        "mexican": [
            "tortilla": 2.0, "chipotle": 2.5, "jalapeno": 2.0,
            "cilantro": 0.5, "lime": 0.5, "cotija": 3.0, "masa": 3.0,
            "poblano": 2.5, "tomatillo": 3.0, "black bean": 1.0
        ],
        "french": [
            "creme fraiche": 2.5, "gruyere": 2.5, "dijon": 2.0,
            "tarragon": 2.0, "shallot": 1.0, "white wine": 1.0,
            "puff pastry": 1.5, "brie": 2.5
        ],
        "greek": [
            "feta": 2.5, "olive": 1.0, "oregano": 1.0, "phyllo": 2.0,
            "greek yogurt": 1.5, "kalamata": 3.0
        ],
        "spanish": [
            "chorizo": 2.5, "saffron": 2.0, "smoked paprika": 2.5,
            "manchego": 3.0, "sherry vinegar": 2.5
        ],
        "middle eastern": [
            "tahini": 2.5, "sumac": 3.0, "za'atar": 3.0, "pomegranate": 1.5,
            "harissa": 2.0, "chickpea": 1.0, "bulgur": 2.0, "halloumi": 2.5
        ],
        "moroccan": [
            "ras el hanout": 3.0, "preserved lemon": 3.0, "harissa": 1.5,
            "couscous": 2.0, "apricot": 1.0
        ],
        "caribbean": [
            "scotch bonnet": 3.0, "allspice": 2.0, "plantain": 2.5,
            "jerk seasoning": 3.0
        ],
        "ethiopian": [
            "berbere": 3.0, "injera": 3.0, "teff": 3.0
        ],
        "american": [
            "bourbon": 2.0, "maple syrup": 1.0, "buttermilk": 1.5,
            "cheddar": 0.5, "bbq sauce": 2.0
        ],
        "british": [
            "clotted cream": 3.0, "golden syrup": 2.5, "black pudding": 3.0,
            "worcestershire sauce": 1.5, "suet": 2.5
        ],
        "german": [
            "sauerkraut": 3.0, "bratwurst": 3.0, "caraway": 2.0
        ],
        "turkish": [
            "sumac": 1.5, "pomegranate molasses": 3.0, "aleppo pepper": 3.0
        ],
        "polish": [
            "kielbasa": 3.0, "sauerkraut": 1.5, "dill": 1.0
        ]
    ]

    /// How much signature evidence is needed before the guess is worth
    /// keeping. Below this the classifier says nothing.
    nonisolated static let ingredientThreshold: Double = 3.0

    /// How far ahead of the runner-up the winner has to be. A recipe that
    /// scores 3.5 Italian and 3.4 Greek has not been classified; it has been
    /// coin-flipped.
    nonisolated static let ingredientMargin: Double = 1.5

    // MARK: - Classification

    /// The cuisine, or nil when the evidence does not support one.
    nonisolated static func cuisine(
        tags: [String],
        title: String,
        ingredientNames: [String]
    ) -> String? {
        if let fromTags = cuisineFromTags(tags) { return fromTags }
        if let fromTitle = cuisineFromTitle(title) { return fromTitle }
        return cuisineFromIngredients(ingredientNames)
    }

    nonisolated static func cuisine(for recipe: Recipe) -> String? {
        cuisine(
            tags: recipe.tags,
            title: recipe.title,
            ingredientNames: recipe.shoppableIngredients.map(\.name)
        )
    }

    nonisolated static func cuisineFromTags(_ tags: [String]) -> String? {
        for tag in tags {
            let key = tag.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if let cuisine = tagAliases[key] { return cuisine }
        }
        return nil
    }

    nonisolated static func cuisineFromTitle(_ title: String) -> String? {
        // Padded and reduced to words so markers match on word boundaries.
        // A plain `contains` finds "dal" inside "medallions", which would
        // file a beef dish as Indian.
        let words = title
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }

        let text = " " + words.joined(separator: " ") + " "

        // Longest marker first, so "green curry" beats "curry" and
        // "butter chicken" is not read as something else.
        let matches = titleMarkers
            .filter { text.contains(" " + $0.key + " ") }
            .sorted { $0.key.count > $1.key.count }

        return matches.first?.value
    }

    nonisolated static func cuisineFromIngredients(_ names: [String]) -> String? {
        let canonical = Set(names.map(IngredientCanonicalizer.canonical))
        guard !canonical.isEmpty else { return nil }

        let raw = names.map { $0.lowercased() }.joined(separator: " · ")

        var scores: [String: Double] = [:]

        for (cuisine, markers) in ingredientMarkers {
            var score = 0.0
            for (marker, weight) in markers where canonical.contains(marker) || raw.contains(marker) {
                score += weight
            }
            if score > 0 {
                scores[cuisine] = score
            }
        }

        let ranked = scores.sorted { lhs, rhs in
            lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
        }

        guard let best = ranked.first, best.value >= ingredientThreshold else { return nil }

        let runnerUp = ranked.dropFirst().first?.value ?? 0
        guard best.value - runnerUp >= ingredientMargin else { return nil }

        return best.key
    }
}
