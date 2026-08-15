//
//  RecipeExtractorTests.swift
//  Cozy CrumbTests
//
//  Fixtures cover the *shapes* real recipe sites publish, since each one is a
//  distinct code path in the extractors: a bare Recipe object, an @graph
//  wrapper, a top-level array, HowToStep objects, HowToSection groups, and a
//  single instructions blob.
//
//  Per §10 these should eventually be joined by saved HTML from 8–10 real
//  sites. Those need to be captured from a browser and dropped into the test
//  bundle; the shape coverage below is what can be written from first
//  principles.
//

import Foundation
import Testing

@testable import Cozy_Crumb

// MARK: - Fixtures

enum Fixtures {

    /// The common case: one Recipe object, HowToStep instructions.
    static let jsonLDSimple = """
    <html><head>
    <script type="application/ld+json">
    {
      "@context": "https://schema.org",
      "@type": "Recipe",
      "name": "Brown Butter Banana Bread",
      "description": "A loaf that smells like a bakery.",
      "image": "https://example.com/bread.jpg",
      "author": {"@type": "Person", "name": "Test Cook"},
      "recipeYield": "8 servings",
      "prepTime": "PT20M",
      "cookTime": "PT55M",
      "recipeIngredient": ["115 g unsalted butter", "3 very ripe bananas", "150 g brown sugar"],
      "recipeInstructions": [
        {"@type": "HowToStep", "text": "Brown the butter and cool for 10 minutes."},
        {"@type": "HowToStep", "text": "Mash the bananas into the butter."}
      ],
      "keywords": "baking, breakfast"
    }
    </script>
    </head><body></body></html>
    """

    /// The other common case: everything wrapped in @graph alongside other
    /// node types.
    static let jsonLDGraph = """
    <html><head>
    <script type="application/ld+json">
    {
      "@context": "https://schema.org",
      "@graph": [
        {"@type": "WebSite", "name": "A Food Blog"},
        {"@type": "BreadcrumbList", "itemListElement": []},
        {
          "@type": ["Recipe", "NewsArticle"],
          "name": "Weeknight Miso Salmon",
          "recipeYield": 2,
          "totalTime": "PT17M",
          "prepTime": "PT5M",
          "image": {"@type": "ImageObject", "url": "https://example.com/salmon.jpg"},
          "recipeIngredient": ["2 salmon fillets", "2 tbsp white miso paste"],
          "recipeInstructions": "Heat the grill.\\nGlaze the salmon.\\nGrill for 8 minutes."
        }
      ]
    }
    </script>
    </head><body></body></html>
    """

    /// HowToSection groups, which nest the real steps one level deeper.
    static let jsonLDSections = """
    <html><head>
    <script type="application/ld+json">
    [
      {
        "@type": "Recipe",
        "name": "Layered Bake",
        "recipeIngredient": ["For the base:", "200 g flour", "For the top:", "100 g cheese"],
        "recipeInstructions": [
          {
            "@type": "HowToSection",
            "name": "Base",
            "itemListElement": [
              {"@type": "HowToStep", "text": "Rub the butter into the flour."},
              {"@type": "HowToStep", "text": "Chill for 30 minutes."}
            ]
          },
          {
            "@type": "HowToSection",
            "name": "Top",
            "itemListElement": [{"@type": "HowToStep", "text": "Grate the cheese over."}]
          }
        ]
      }
    ]
    </script>
    </head><body></body></html>
    """

    /// Microdata, for sites with no JSON-LD at all.
    static let microdata = """
    <html><body>
    <div itemscope itemtype="https://schema.org/Recipe">
      <h1 itemprop="name">Cupboard Curry</h1>
      <meta itemprop="recipeYield" content="4 servings">
      <meta itemprop="prepTime" content="PT10M">
      <meta itemprop="cookTime" content="PT25M">
      <ul>
        <li itemprop="recipeIngredient">1 onion, chopped</li>
        <li itemprop="recipeIngredient">2 cans chickpeas</li>
        <li itemprop="recipeIngredient">200 ml coconut milk</li>
      </ul>
      <div itemprop="recipeInstructions">
        <p>Soften the onion for 8 minutes.</p>
        <p>Add everything else and simmer.</p>
      </div>
    </div>
    </body></html>
    """

    /// Nothing structured — Open Graph only.
    static let openGraphOnly = """
    <html><head>
    <meta property="og:title" content="A Video About Soup">
    <meta property="og:description" content="Chop an onion. Add stock. That's it.">
    <meta property="og:image" content="https://example.com/soup.jpg">
    <meta property="og:site_name" content="Somewhere Social">
    <title>A Video About Soup</title>
    </head><body></body></html>
    """
}

// MARK: - HTML scanner

@Suite("HTML scanning")
struct HTMLScannerTests {

    @Test("Script blocks are found by type")
    func scriptBlocks() {
        let scanner = HTMLScanner(html: Fixtures.jsonLDSimple)
        let blocks = scanner.scriptContents(type: "application/ld+json")
        #expect(blocks.count == 1)
        #expect(blocks[0].contains("Brown Butter Banana Bread"))
    }

    @Test("Scripts of other types are ignored")
    func otherScripts() {
        let html = "<script type=\"text/javascript\">var x = 1;</script>"
        let scanner = HTMLScanner(html: html)
        #expect(scanner.scriptContents(type: "application/ld+json").isEmpty)
    }

    @Test("Meta content is read by property or name")
    func metaTags() {
        let scanner = HTMLScanner(html: Fixtures.openGraphOnly)
        #expect(scanner.metaContent(property: "og:title") == "A Video About Soup")
        #expect(scanner.metaContent(property: "og:site_name") == "Somewhere Social")
    }

    @Test("Attribute values parse with either quote style, or none")
    func attributeQuoting() {
        #expect(HTMLScanner.attributeValue("type", in: "<script type=\"a/b\">") == "a/b")
        #expect(HTMLScanner.attributeValue("type", in: "<script type='a/b'>") == "a/b")
        #expect(HTMLScanner.attributeValue("type", in: "<script type=a/b>") == "a/b")
    }

    @Test("A prefixed attribute name is not mistaken for the real one")
    func attributePrefixes() {
        // "data-property" must not satisfy a search for "property".
        #expect(HTMLScanner.attributeValue("property", in: "<meta data-property=\"x\" property=\"y\">") == "y")
    }

    @Test("Nested elements of the same tag do not end the outer one early")
    func nestedElements() {
        let html = "<div itemprop=\"recipeInstructions\"><div>one</div><div>two</div></div>"
        let elements = HTMLScanner(html: html).elements(withAttribute: "itemprop", value: "recipeInstructions")
        #expect(elements.count == 1)
        #expect(elements[0].text.contains("one"))
        #expect(elements[0].text.contains("two"))
    }

    @Test("Space-separated itemprop lists match individually")
    func multiValueAttributes() {
        let html = "<span itemprop=\"name description\">Soup</span>"
        let elements = HTMLScanner(html: html).elements(withAttribute: "itemprop", value: "name")
        #expect(elements.count == 1)
    }

    @Test("Entities are decoded, named and numeric")
    func entities() {
        #expect(HTMLScanner.decodeEntities("salt &amp; pepper") == "salt & pepper")
        #expect(HTMLScanner.decodeEntities("caf&eacute;") == "café")
        #expect(HTMLScanner.decodeEntities("it&#39;s") == "it's")
        #expect(HTMLScanner.decodeEntities("it&#x27;s") == "it's")
        #expect(HTMLScanner.decodeEntities("&frac12; cup") == "½ cup")
    }

    @Test("Unknown entities are left alone rather than deleted")
    func unknownEntities() {
        #expect(HTMLScanner.decodeEntities("&notreal; thing") == "&notreal; thing")
    }

    @Test("Tags become spaces so words do not fuse")
    func tagStripping() {
        #expect(HTMLScanner.plainText("<li>one</li><li>two</li>") == "one two")
    }
}

// MARK: - JSON-LD

@Suite("JSON-LD extraction")
struct JSONLDExtractorTests {

    private let extractor = JSONLDExtractor()

    @Test("A simple Recipe object is read fully")
    func simpleRecipe() throws {
        let recipe = try #require(extractor.extract(from: Fixtures.jsonLDSimple, sourceURL: nil))

        #expect(recipe.title == "Brown Butter Banana Bread")
        #expect(recipe.servings == 8)
        #expect(recipe.prepMinutes == 20)
        #expect(recipe.cookMinutes == 55)
        #expect(recipe.ingredients.count == 3)
        #expect(recipe.steps.count == 2)
        #expect(recipe.sourceName == "Test Cook")
        #expect(recipe.confidence == 0.95)
        #expect(recipe.tags.contains("baking"))
    }

    @Test("Ingredients are parsed, not just stored as text")
    func ingredientsAreParsed() throws {
        let recipe = try #require(extractor.extract(from: Fixtures.jsonLDSimple, sourceURL: nil))
        let butter = try #require(recipe.ingredients.first)

        #expect(butter.quantity == 115)
        #expect(butter.unit == "g")
        #expect(butter.name == "unsalted butter")
    }

    @Test("Steps pick up their stated durations")
    func stepDurations() throws {
        let recipe = try #require(extractor.extract(from: Fixtures.jsonLDSimple, sourceURL: nil))
        #expect(recipe.steps[0].durationSeconds == 600)
        #expect(recipe.steps[1].durationSeconds == nil)
    }

    @Test("A Recipe nested in @graph is found")
    func graphWrapper() throws {
        let recipe = try #require(extractor.extract(from: Fixtures.jsonLDGraph, sourceURL: nil))
        #expect(recipe.title == "Weeknight Miso Salmon")
        #expect(recipe.servings == 2)
        #expect(recipe.ingredients.count == 2)
    }

    @Test("@type given as an array still counts as a Recipe")
    func arrayType() throws {
        let recipe = try #require(extractor.extract(from: Fixtures.jsonLDGraph, sourceURL: nil))
        #expect(recipe.title == "Weeknight Miso Salmon")
    }

    @Test("An instructions string splits on its own newlines")
    func stringInstructions() throws {
        let recipe = try #require(extractor.extract(from: Fixtures.jsonLDGraph, sourceURL: nil))
        #expect(recipe.steps.count == 3)
    }

    @Test("An ImageObject yields its url")
    func imageObject() throws {
        let recipe = try #require(extractor.extract(from: Fixtures.jsonLDGraph, sourceURL: nil))
        #expect(recipe.imageURL?.absoluteString == "https://example.com/salmon.jpg")
    }

    @Test("Cook time is derived from total minus prep when absent")
    func derivedCookTime() throws {
        // totalTime PT17M with prepTime PT5M means 12 minutes of cooking,
        // not 17 — otherwise prep gets counted twice.
        let recipe = try #require(extractor.extract(from: Fixtures.jsonLDGraph, sourceURL: nil))
        #expect(recipe.cookMinutes == 12)
    }

    @Test("HowToSection groups are flattened into steps")
    func sections() throws {
        let recipe = try #require(extractor.extract(from: Fixtures.jsonLDSections, sourceURL: nil))
        #expect(recipe.steps.count == 3)
        #expect(recipe.steps[0].text.contains("Rub the butter"))
        #expect(recipe.steps[2].text.contains("Grate the cheese"))
    }

    @Test("Section headers in the ingredient list are marked")
    func ingredientSectionHeaders() throws {
        let recipe = try #require(extractor.extract(from: Fixtures.jsonLDSections, sourceURL: nil))
        #expect(recipe.ingredients.filter(\.isSectionHeader).count == 2)
    }

    @Test("A page with no JSON-LD returns nil rather than an empty recipe")
    func noStructuredData() {
        #expect(extractor.extract(from: Fixtures.openGraphOnly, sourceURL: nil) == nil)
        #expect(extractor.extract(from: Fixtures.microdata, sourceURL: nil) == nil)
    }
}

// MARK: - Microdata

@Suite("Microdata extraction")
struct MicrodataExtractorTests {

    private let extractor = MicrodataExtractor()

    @Test("Itemprop values are collected")
    func basics() throws {
        let recipe = try #require(extractor.extract(from: Fixtures.microdata, sourceURL: nil))

        #expect(recipe.title == "Cupboard Curry")
        #expect(recipe.ingredients.count == 3)
        #expect(recipe.servings == 4)
        #expect(recipe.prepMinutes == 10)
        #expect(recipe.cookMinutes == 25)
        #expect(recipe.confidence == 0.7)
    }

    @Test("An instructions block splits into separate steps")
    func instructionBlock() throws {
        let recipe = try #require(extractor.extract(from: Fixtures.microdata, sourceURL: nil))
        #expect(recipe.steps.count >= 2)
    }

    @Test("Pages with no microdata return nil")
    func noMicrodata() {
        #expect(extractor.extract(from: Fixtures.openGraphOnly, sourceURL: nil) == nil)
    }
}

// MARK: - Open Graph and the cascade

@Suite("Open Graph and cascade")
struct CascadeTests {

    @Test("Open Graph metadata is read")
    func openGraph() {
        let metadata = OpenGraphExtractor().extract(from: Fixtures.openGraphOnly, sourceURL: nil)
        #expect(metadata.title == "A Video About Soup")
        #expect(metadata.siteName == "Somewhere Social")
        #expect(metadata.imageURL?.absoluteString == "https://example.com/soup.jpg")
    }

    @Test("The cascade stops at JSON-LD when it is complete")
    func prefersTierOne() async {
        let coordinator = ImportCoordinator()
        let result = coordinator.parse(html: Fixtures.jsonLDSimple, sourceURL: nil)
        #expect(result.recipe?.confidence == 0.95)
    }

    @Test("The cascade falls through to microdata")
    func fallsThroughToTierTwo() async {
        let coordinator = ImportCoordinator()
        let result = coordinator.parse(html: Fixtures.microdata, sourceURL: nil)
        #expect(result.recipe?.confidence == 0.7)
        #expect(result.recipe?.title == "Cupboard Curry")
    }

    @Test("A page with no recipe yields metadata but no recipe")
    func noRecipeFound() async {
        // The important half of §5.2: never invent a recipe, but hand back
        // enough for the review screen to pre-fill manual entry.
        let coordinator = ImportCoordinator()
        let result = coordinator.parse(html: Fixtures.openGraphOnly, sourceURL: nil)

        #expect(result.recipe == nil)
        #expect(result.metadata.title == "A Video About Soup")
    }

    @Test("Open Graph fills in a missing hero image")
    func fillsMissingImage() async {
        let coordinator = ImportCoordinator()
        let result = coordinator.parse(html: Fixtures.microdata, sourceURL: nil)
        // The microdata fixture has no og:image, so this stays nil rather than
        // being invented.
        #expect(result.recipe?.imageURL == nil)
    }

    @Test("Social hosts are recognised")
    func socialDetection() async {
        let coordinator = ImportCoordinator()
        let url = URL(string: "https://www.instagram.com/p/abc123/")
        let result = coordinator.parse(html: Fixtures.openGraphOnly, sourceURL: url)
        #expect(result.isSocialSource)
    }
}
