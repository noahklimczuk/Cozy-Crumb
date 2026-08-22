//
//  IngredientCanonicalizerTests.swift
//  Cozy CrumbTests
//
//  S2. The spec calls this the foundation — if it is wrong, everything
//  downstream is — so it gets the most tests of anything in the feature.
//
//  Two groups matter more than the rest. The compound tests protect against a
//  real harm: reducing "coconut milk" to milk or "peanut butter" to butter
//  would write dairy and nut affinities into the profile of someone who
//  avoids both. And the non-collapse tests pin the things that must stay
//  apart, which is the failure mode a keen canonicaliser produces.
//

import Foundation
import Testing

@testable import Cozy_Crumb

@Suite("Canonical food names")
struct IngredientCanonicalizerTests {

    private func canonical(_ raw: String) -> String {
        IngredientCanonicalizer.canonical(raw)
    }

    @Test("The spec's own example: every tomato is a tomato")
    func tomatoes() {
        #expect(canonical("Roma tomatoes") == "tomato")
        #expect(canonical("cherry tomatoes") == "tomato")
        #expect(canonical("1 can diced tomatoes") == "tomato")
        #expect(canonical("tomatoes") == "tomato")
        #expect(canonical("2 large ripe tomatoes, roughly chopped") == "tomato")
        #expect(canonical("400g tin of chopped tomatoes") == "tomato")
    }

    @Test("Amounts, units and notes are not part of the name")
    func stripsAmountsAndUnits() {
        #expect(canonical("2 tbsp olive oil") == "olive oil")
        #expect(canonical("500 g chicken thighs") == "chicken")
        #expect(canonical("1/2 cup flour") == "flour")
        #expect(canonical("3 cloves garlic, minced") == "garlic")
        #expect(canonical("a handful of fresh basil") == "basil")
        #expect(canonical("Parmesan (freshly grated)") == "parmesan")
    }

    @Test("A cut of meat is still the animal")
    func cutsReduceToTheProtein() {
        #expect(canonical("chicken thighs") == "chicken")
        #expect(canonical("boneless skinless chicken breast") == "chicken")
        #expect(canonical("pork shoulder") == "pork")
        #expect(canonical("beef ribs") == "beef")
        #expect(canonical("salmon fillets") == "salmon")
    }

    @Test("Ground beef is beef — that is the whole point of this layer")
    func stateWordsDoNotSplitAFood() {
        #expect(canonical("ground beef") == "beef")
        #expect(canonical("beef mince") == "beef")
        #expect(canonical("dried basil") == "basil")
        #expect(canonical("fresh basil") == "basil")
        #expect(canonical("frozen peas") == "pea")
        #expect(canonical("canned chickpeas") == "chickpea")
    }

    @Test("Compounds are not their head noun")
    func compoundsAreProtected() {
        // The safety-adjacent ones. Reducing any of these writes dairy or nut
        // affinities into a profile that should not have them.
        #expect(canonical("coconut milk") == "coconut milk")
        #expect(canonical("full-fat coconut milk") == "coconut milk")
        #expect(canonical("400ml can of coconut milk") == "coconut milk")
        #expect(canonical("almond milk") == "almond milk")
        #expect(canonical("oat milk") == "oat milk")
        #expect(canonical("peanut butter") == "peanut butter")
        #expect(canonical("smooth almond butter") == "almond butter")

        // The merely-wrong ones.
        #expect(canonical("sweet potatoes") == "sweet potato")
        #expect(canonical("soy sauce") == "soy sauce")
        #expect(canonical("fish sauce") == "fish sauce")
        #expect(canonical("sesame oil") == "sesame oil")
        #expect(canonical("cream cheese") == "cream cheese")
        #expect(canonical("sour cream") == "sour cream")
        #expect(canonical("tomato paste") == "tomato paste")
        #expect(canonical("bay leaves") == "bay leaf")
    }

    @Test("Foods that must stay apart, stay apart")
    func doesNotOverCollapse() {
        #expect(canonical("coconut milk") != canonical("whole milk"))
        #expect(canonical("peanut butter") != canonical("unsalted butter"))
        #expect(canonical("sweet potato") != canonical("potato"))
        #expect(canonical("spring onion") != canonical("onion"))
        #expect(canonical("bell pepper") != canonical("chili"))
        #expect(canonical("tomato paste") != canonical("tomatoes"))
        #expect(canonical("cherry") != canonical("cherry tomatoes"))
    }

    @Test("Two names for one food land on the same key")
    func synonyms() {
        #expect(canonical("coriander") == canonical("cilantro"))
        #expect(canonical("fresh coriander") == "cilantro")
        #expect(canonical("courgettes") == canonical("zucchini"))
        #expect(canonical("aubergine") == canonical("eggplant"))
        #expect(canonical("king prawns") == canonical("shrimp"))
        #expect(canonical("garbanzo beans") == canonical("chickpeas"))
        #expect(canonical("scallions") == canonical("green onions"))
        #expect(canonical("chillies") == canonical("chili"))
    }

    @Test("Plurals become singular, including the awkward ones")
    func plurals() {
        #expect(canonical("potatoes") == "potato")
        #expect(canonical("anchovies") == "anchovy")
        #expect(canonical("bay leaves") == "bay leaf")
        #expect(canonical("chives") == "chive")
        #expect(canonical("asparagus") == "asparagus")
        #expect(canonical("hummus") == "hummus")
        #expect(canonical("couscous") == "couscous")
        #expect(canonical("molasses") == "molasses")
    }

    @Test("It is idempotent — running it twice changes nothing")
    func idempotent() {
        let samples = [
            "Roma tomatoes", "2 tbsp olive oil", "boneless chicken thighs",
            "full-fat coconut milk", "fresh coriander", "canned chickpeas",
            "bay leaves", "ground beef", "sweet potatoes"
        ]

        for sample in samples {
            let once = canonical(sample)
            #expect(canonical(once) == once, "\(sample) → \(once) was not stable")
        }
    }

    @Test("An unrecognised food comes back tidied, never empty")
    func neverReturnsNothing() {
        #expect(!canonical("2 tbsp yuzu kosho").isEmpty)
        #expect(canonical("yuzu kosho") == "kosho")
        #expect(canonical("boneless skinless").isEmpty == false)
        #expect(canonical("").isEmpty)
        #expect(canonical("   ").isEmpty)
    }

    @Test("Staples are the things whose absence should not count")
    func staples() {
        #expect(IngredientCanonicalizer.isStaple("salt"))
        #expect(IngredientCanonicalizer.isStaple("2 tsp fine sea salt"))
        #expect(IngredientCanonicalizer.isStaple("olive oil"))
        #expect(IngredientCanonicalizer.isStaple("plain flour"))
        #expect(IngredientCanonicalizer.isStaple("water"))

        #expect(!IngredientCanonicalizer.isStaple("chicken thighs"))
        #expect(!IngredientCanonicalizer.isStaple("harissa"))
        #expect(!IngredientCanonicalizer.isStaple("coconut milk"))
    }

    @Test("It does not disturb the shopping list's own key")
    func doesNotReplaceGroceryMerge() {
        // The two layers answer different questions, and this pins the
        // difference so a later tidy-up cannot quietly merge them: the
        // shopping key keeps ground beef apart from beef, this one does not.
        #expect(GroceryMerge.normalizedName("ground beef") == "ground beef")
        #expect(canonical("ground beef") == "beef")

        #expect(GroceryMerge.normalizedName("cherry tomatoes") == "cherry tomato")
        #expect(canonical("cherry tomatoes") == "tomato")
    }
}

@Suite("Cuisine classification")
struct CuisineClassifierTests {

    @Test("An explicit tag is taken at their word")
    func fromTags() {
        #expect(CuisineClassifier.cuisine(tags: ["thai", "quick"], title: "Dinner", ingredientNames: []) == "thai")
        #expect(CuisineClassifier.cuisine(tags: ["Pasta"], title: "Dinner", ingredientNames: []) == "italian")
        #expect(CuisineClassifier.cuisine(tags: ["weeknight"], title: "Dinner", ingredientNames: []) == nil)
    }

    @Test("A dish name settles it")
    func fromTitle() {
        #expect(CuisineClassifier.cuisineFromTitle("Spaghetti carbonara") == "italian")
        #expect(CuisineClassifier.cuisineFromTitle("Weeknight pad thai") == "thai")
        #expect(CuisineClassifier.cuisineFromTitle("Chicken tikka masala") == "indian")
        #expect(CuisineClassifier.cuisineFromTitle("Sheet pan salmon") == nil)
    }

    @Test("The longest title marker wins")
    func longestTitleMarkerWins() {
        // "green curry" is Thai; "curry" alone would have said Indian.
        #expect(CuisineClassifier.cuisineFromTitle("Thai green curry") == "thai")
    }

    @Test("A signature of unusual ingredients is enough")
    func fromIngredients() {
        let thai = CuisineClassifier.cuisineFromIngredients(
            ["fish sauce", "lemongrass", "coconut milk", "lime", "chicken"]
        )
        #expect(thai == "thai")

        let japanese = CuisineClassifier.cuisineFromIngredients(
            ["miso paste", "mirin", "dashi", "spring onions"]
        )
        #expect(japanese == "japanese")
    }

    @Test("Ordinary ingredients classify as nothing")
    func decliningToGuess() {
        // Garlic, onion and olive oil is not Italian. It is dinner.
        #expect(CuisineClassifier.cuisineFromIngredients(["garlic", "onion", "olive oil", "salt"]) == nil)
        #expect(CuisineClassifier.cuisineFromIngredients([]) == nil)
        #expect(CuisineClassifier.cuisineFromIngredients(["chicken", "rice", "butter"]) == nil)
    }

    @Test("A close call is not a classification")
    func needsAClearWinner() {
        // Oregano and olives point at both Italy and Greece and settle
        // neither, so nothing is written rather than a coin flip.
        let ambiguous = CuisineClassifier.cuisineFromIngredients(["oregano", "olive", "olive oil"])
        #expect(ambiguous == nil)
    }

    @Test("Tags beat the title, and the title beats the ingredients")
    func passOrder() {
        let cuisine = CuisineClassifier.cuisine(
            tags: ["korean"],
            title: "Spaghetti carbonara",
            ingredientNames: ["fish sauce", "lemongrass", "galangal"]
        )
        #expect(cuisine == "korean")
    }
}

@Suite("Technique detection")
struct TechniqueClassifierTests {

    @Test("Techniques are read off the method")
    func fromSteps() {
        let techniques = TechniqueClassifier.techniques(stepTexts: [
            "Sear the beef on all sides.",
            "Braise in the oven for three hours until the meat falls apart."
        ])

        #expect(techniques.contains("braising"))
        #expect(techniques.contains("frying"))
    }

    @Test("A recipe with no method has no techniques")
    func emptyIsEmpty() {
        #expect(TechniqueClassifier.techniques(stepTexts: []).isEmpty)
        #expect(TechniqueClassifier.techniques(stepTexts: ["", "  "]).isEmpty)
    }

    @Test("Techniques sit on a difficulty scale")
    func demandOrdering() {
        // §4's stretch picks are "one step above their comfort", which only
        // means anything if the scale is ordered.
        #expect(TechniqueClassifier.demand(of: "boiling") < TechniqueClassifier.demand(of: "braising"))
        #expect(TechniqueClassifier.demand(of: "braising") < TechniqueClassifier.demand(of: "laminating"))
        #expect(TechniqueClassifier.demand(of: "something invented") == 3)
    }
}
