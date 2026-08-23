//
//  SousChefBriefTests.swift
//  Cozy CrumbTests
//
//  S6 and S7's pure parts: reading the question, reading the reply, and
//  deciding what counts as a durable fact.
//

import Foundation
import Testing

@testable import Cozy_Crumb

@Suite("Reading the reply")
struct RecommendationBlockParserTests {

    private let thai = UUID(uuidString: "11111111-0000-4000-8000-000000000001")!
    private let pork = UUID(uuidString: "11111111-0000-4000-8000-000000000002")!

    @Test("The fenced block never reaches the user")
    func stripsTheBlock() {
        let reply = """
        You've got fish sauce and it's a Tuesday, so the basil chicken is the
        obvious one.

        ```json
        {"recommendations":[{"recipeId":"\(thai.uuidString)","why":"25 minutes and you have everything"}]}
        ```
        """

        let result = RecommendationBlockParser.parse(reply, knownRecipeIDs: [thai])

        #expect(!result.prose.contains("```"))
        #expect(!result.prose.contains("recommendations"))
        #expect(result.prose.hasSuffix("obvious one."))
        #expect(result.recommendations.count == 1)
        #expect(result.recommendations.first?.why == "25 minutes and you have everything")
    }

    @Test("A reply with no block is left exactly as it is")
    func noBlock() {
        let reply = "Reheat it to steaming hot the whole way through — that one's a food-safety matter, not a preference."
        let result = RecommendationBlockParser.parse(reply)

        #expect(result.prose == reply)
        #expect(result.recommendations.isEmpty)
    }

    @Test("An invented recipe id is dropped rather than shown")
    func rejectsUnknownIDs() {
        // §7.1 says only to quote ids from RANKED CANDIDATES. A card built
        // from an id nobody offered would point at the wrong recipe or at
        // nothing.
        let reply = """
        Try these.

        ```json
        {"recommendations":[
          {"recipeId":"\(thai.uuidString)","why":"you have it all"},
          {"recipeId":"99999999-0000-4000-8000-000000000999","why":"invented"}
        ]}
        ```
        """

        let result = RecommendationBlockParser.parse(reply, knownRecipeIDs: [thai, pork])

        #expect(result.recommendations.map(\.recipeID) == [thai])
    }

    @Test("Malformed JSON costs the cards, not the answer")
    func malformedBlock() {
        let reply = """
        Here's what I'd do.

        ```json
        {"recommendations": [ oh dear
        ```
        """

        let result = RecommendationBlockParser.parse(reply, knownRecipeIDs: [thai])

        #expect(result.prose.hasPrefix("Here's what I'd do."))
        #expect(!result.prose.contains("```"))
        #expect(result.recommendations.isEmpty)
    }

    @Test("The same recipe twice is one card")
    func deduplicates() {
        let reply = """
        Both good.

        ```json
        {"recommendations":[
          {"recipeId":"\(thai.uuidString)","why":"first"},
          {"recipeId":"\(thai.uuidString)","why":"again"}
        ]}
        ```
        """

        let result = RecommendationBlockParser.parse(reply, knownRecipeIDs: [thai])
        #expect(result.recommendations.count == 1)
    }

    @Test("A missing 'why' is not a missing recommendation")
    func toleratesMissingWhy() {
        let reply = """
        This one.

        ```json
        {"recommendations":[{"recipeId":"\(thai.uuidString)"}]}
        ```
        """

        let result = RecommendationBlockParser.parse(reply, knownRecipeIDs: [thai])

        #expect(result.recommendations.count == 1)
        #expect(result.recommendations.first?.why == "")
    }
}

@Suite("Reading the question")
struct ConversationConstraintTests {

    @Test("A stated time limit is picked up")
    func minutes() {
        #expect(ConversationConstraints.minutes(in: "something in 20 minutes") == 20)
        #expect(ConversationConstraints.minutes(in: "I've got half an hour") == 30)
        #expect(ConversationConstraints.minutes(in: "something quick") == 25)
        #expect(ConversationConstraints.minutes(in: "what should I cook tonight") == nil)
    }

    @Test("A diet stated in the moment is a hard filter, not a hint")
    func diets() {
        #expect(ConversationConstraints.diets(in: "something vegetarian") == [.vegetarian])
        #expect(ConversationConstraints.diets(in: "vegan please") == [.vegan])
        #expect(ConversationConstraints.diets(in: "what's for dinner").isEmpty)
    }

    @Test("Things ruled out in the message are excluded")
    func exclusions() {
        #expect(ConversationConstraints.excludedIngredients(in: "pasta without mushrooms").contains("mushroom"))
        #expect(ConversationConstraints.excludedIngredients(in: "no coriander please").contains("cilantro"))
        #expect(ConversationConstraints.excludedIngredients(in: "what can I make").isEmpty)
    }
}

@Suite("Deciding what to extract")
struct FactExtractorGateTests {

    @Test("A durable statement is worth a request")
    func worthExtracting() {
        #expect(FactExtractor.isWorthExtracting(from: "I'm allergic to shellfish"))
        #expect(FactExtractor.isWorthExtracting(from: "my partner doesn't eat mushrooms"))
        #expect(FactExtractor.isWorthExtracting(from: "I've got an air fryer if that helps"))
        #expect(FactExtractor.isWorthExtracting(from: "we're vegetarian during the week"))
    }

    @Test("Ordinary chat is not")
    func notWorthExtracting() {
        // The gate exists because the key is the user's. Every one of these
        // would return an empty array and still be billed.
        #expect(!FactExtractor.isWorthExtracting(from: "what should I cook tonight"))
        #expect(!FactExtractor.isWorthExtracting(from: "that sounds good"))
        #expect(!FactExtractor.isWorthExtracting(from: "thanks"))
        #expect(!FactExtractor.isWorthExtracting(from: "how long does it take"))
    }

    @Test("The prompt tells the model what it already knows")
    func promptCarriesKnownFacts() {
        let prompt = FactExtractor.prompt(
            exchange: ["I can't stand blue cheese"],
            existingFacts: ["Partner doesn't eat mushrooms"]
        )

        #expect(prompt.contains("I can't stand blue cheese"))
        #expect(prompt.contains("do not return any of these again"))
        #expect(prompt.contains("Partner doesn't eat mushrooms"))
    }
}

@Suite("Fact similarity")
struct FactSimilarityTests {

    @Test("The same thing said differently is the same thing")
    func duplicates() {
        #expect(FactSimilarity.areSame(
            "Partner doesn't eat mushrooms",
            "partner does not eat mushrooms"
        ))
        #expect(FactSimilarity.areSame("Lactose intolerant", "lactose intolerant"))
    }

    @Test("Different things are different")
    func distinct() {
        #expect(!FactSimilarity.areSame(
            "Partner doesn't eat mushrooms",
            "Allergic to shellfish"
        ))
        #expect(!FactSimilarity.areSame("No dishwasher", "Has an air fryer"))
    }

    @Test("An about-turn is spotted")
    func contradictions() {
        // The behaviour that makes the app feel like it is paying attention:
        // notice, then ask, rather than silently keeping both.
        #expect(FactSimilarity.contradict(
            "Partner doesn't eat mushrooms",
            "Partner loves mushrooms"
        ))
        #expect(FactSimilarity.contradict(
            "Never cooks on weeknights",
            "Cooks on weeknights"
        ))
    }

    @Test("Two unrelated facts do not contradict just because one is negative")
    func unrelatedIsNotContradiction() {
        #expect(!FactSimilarity.contradict(
            "Partner doesn't eat mushrooms",
            "Loves anchovies"
        ))
    }
}

@Suite("Allergen names in a sentence")
struct AllergenNameTests {

    @Test("The food is pulled out of the statement")
    func namesAreFound() {
        #expect(CookFactStore.allergenNames(in: "Allergic to shellfish").contains("shellfish"))
        #expect(CookFactStore.allergenNames(in: "Has a peanut allergy").contains("peanut"))
        #expect(CookFactStore.allergenNames(in: "Lactose intolerant").contains("milk"))
    }

    @Test("An unrecognised allergy still filters something")
    func unknownAllergiesStillFilter() {
        // Better to over-filter on a food nobody has heard of than to
        // silently enforce nothing at all.
        let names = CookFactStore.allergenNames(in: "Allergic to buckwheat")
        #expect(names.contains("buckwheat"))
    }
}
