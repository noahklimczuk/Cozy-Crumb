# Super Prompt — Make Cozy Crumb's recipe import bulletproof

> Paste this whole file as the task. It is written against `Cozy-Crumb` at the
> commit that introduced it; line numbers are signposts, not contracts — if a
> line has moved, find the code by its description.

---

## 0. Mission

Take Cozy Crumb's recipe import from "works on tidy recipe sites and sometimes
on a Reel" to **an import that never dead-ends, never silently drops half a
recipe, and never invents one**.

Three outcomes, in priority order:

1. **No dead ends.** Every import attempt ends at a reviewable draft or at a
   screen offering a route that always works. No screen may be terminal.
2. **Nothing missed.** When a recipe is on the page, in the video, on the
   linked blog, or on the slide-two recipe card, it comes back complete —
   ingredients, method, yield, times, image, source.
3. **Nothing else breaks.** The rest of the app — Cookbook, Pantry, Groceries,
   Meal Plan, Sous Chef, Taste Profile, the share extension, launch — behaves
   exactly as it does today.

**Be honest about "no errors."** Zero *errors* is not achievable: sites go
down, phones go offline, Instagram serves a login wall, and Gemini rate-limits.
Zero **dead ends** is achievable and is the real target. Never paper over a
genuine failure by inventing content or by saving a hollow recipe — an empty
recipe in the library is a worse bug than an honest error screen.

---

## 1. Invariants you may not break

These are load-bearing. Breaking one is a failed task even if everything else
works.

| # | Invariant | Where it lives |
|---|---|---|
| I1 | **Nothing reaches the library without passing the review screen.** No auto-save, no "trust high confidence and skip review". | `ImportReviewView`, `ImportViewModel.save` |
| I2 | **Never invent a recipe.** No fabricated quantities, times, temperatures or steps. `found: false` must stay a real outcome. Absent data stays `nil`. | `Prompts.extractionSystem`, `AIRecipeParser.run` |
| I3 | **`rawText` is preserved verbatim** on every ingredient, always. Decoration stripping, reparsing and AI normalisation all operate on copies. | `IngredientLineParser.parse`, `ImportedIngredient` |
| I4 | **The API key never leaves the `x-goog-api-key` header**, and **request/response bodies are never logged** in any build. Status codes and finish reasons only. | `GeminiClient` |
| I5 | **Extractors stay pure.** `RecipeExtracting.extract` takes HTML in and values out, does no networking, and is testable from a fixture with no network. | `RecipeImporting.swift` protocol |
| I6 | **Parsing stays off the main actor.** The target defaults to `@MainActor`; the import path is explicitly `nonisolated` / actor-isolated. Do not let string work drift onto the main thread. | `ImportCoordinator`, every `nonisolated` marker |
| I7 | **The share extension links no app-target code** beyond `Shared/CozyDeepLink.swift`, references no `UIApplication` symbol, and always draws its own page before attempting anything. | `Cozy CrumbShare/ShareViewController.swift` |
| I8 | **The review screen is also the manual-entry form and the editor.** One document, one editor. Do not fork it. | `ImportReviewView`, `ImportedRecipe(editing:)` |
| I9 | **Launch stays fast and non-blocking.** Add no synchronous work to the launch passes in `RootTabView.task`. | `RootTabView` |
| I10 | **Zero new Swift warnings.** CI reports them and the gate is one uncommented line away from blocking. | `.github/workflows/ios.yml` |

---

## 2. The pipeline as it stands

Read these before changing anything.

```
Entry points
  LibraryView (+ button)      → ImportFlowView(pasteLinkText:)
  RootTabView .onOpenURL      → ImportFlowView(initialURL:)      ← share extension
  RecipeDetailView (edit)     → ImportFlowView(editingRecipe:)

ImportViewModel.runImport(from:existingRecipes:)
  ├─ SocialPlatform.detect(from:) hits → runSocialImport(...)
  │    SocialImporter.fetch           oEmbed (YouTube, TikTok) + Open Graph
  │    ├─ YouTube  → AIRecipeParser.parseVideo (Gemini watches the URL)
  │    ├─ caption ≥40 chars → AIRecipeParser.parse(caption:)
  │    ├─ importFromPostMedia:
  │    │    SocialMediaResolver.resolve → embed page / rehydration blob
  │    │    1. fuller caption  2. downloaded video (≤12 MB)  3. post images
  │    └─ else → stage = .needsCaption  (paste caption / hand over video / screenshots)
  │
  └─ web → ImportCoordinator.importRecipe
       fetchHTML → parse():
         Tier 1 JSONLDExtractor   (confidence 0.95)
         Tier 2 MicrodataExtractor (confidence 0.70)
         OpenGraphExtractor fills image / summary / source name
       no recipe → AIRecipeParser.parse(text: rawHTML)   (Tier 3, ceiling 0.85)
       still nothing → prefill draft from OG, didFallBackToManual = true

Always → stage = .review → ImportReviewView → save(into:updatingExisting:)
```

Supporting cast: `HTMLScanner` (tiny, deliberately not a DOM), `QuantityParser`,
`IngredientLineParser`, `DurationParser`, `GroceryCategoryGuesser`,
`VideoFrameSampler`, `ImageFetcher`/`ImageProcessor`, `GeminiClient`,
`RecipeSchemas.extraction`, `CozyError`.

---

## 3. Confirmed defects — fix all of these

Each one was verified by reading the code. Fix the cause, not the symptom.

### D1 — The AI web fallback is fed raw HTML and almost always fails
`ImportViewModel.runImport` passes `result.rawHTML` straight to
`AIRecipeParser.parse(text:)` (~`ImportViewModel.swift:166`), which caps at
15 000 characters **from the start of the string**
(`AIRecipeParser.swift:39`). The first 15 000 characters of a modern recipe
blog are `<head>`, inline analytics, and CSS. **Tier 3 is being handed the
wrong 1% of the page**, so the fallback that exists to rescue unstructured
sites reliably returns `found: false`.

Fix: extract readable text before the cap. Strip `<script>`, `<style>`,
`<noscript>`, `<nav>`, `<header>`, `<footer>`, `<aside>` and comment blocks;
run the remainder through block-aware text extraction (`HTMLScanner
.blockSeparatedText` is the existing primitive); then cap. Prefer the region
around ingredient/method signals over a blind prefix — if the text exceeds the
budget, centre the window on the densest cluster of quantity-and-unit lines
rather than truncating the tail. Keep the cap configurable and covered by a
test that proves a 400 KB page yields recipe text, not `<head>`.

### D2 — Duplicate detection never fires on the paste path
`importFromPastedText` calls `runImport(from: url)` with the default
`existingRecipes: []` (`ImportViewModel.swift:135` / `:138`). Only the
share-extension/deep-link path passes the `@Query` results in. So the "You've
already saved this one" screen is unreachable for the single most common entry
point.

Fix: thread the existing library through every entry point, or move duplicate
lookup behind an injected dependency the view model owns. Then broaden the
match itself — see **D3**.

### D3 — Duplicate matching is raw URL equality
`existing = existingRecipes.first { $0.sourceURL == url }` compares
un-normalised URLs for web imports. `example.com/recipe`,
`example.com/recipe/`, `http://…`, `…?utm_source=pinterest` and
`www.example.com/recipe` are five different recipes today. The social path
canonicalises first, which is better, but only for social.

Fix: one canonicalisation function used by *both* paths and by the save path —
lowercase host, strip `www.`, drop the tracking-parameter set already listed
in `SocialImporter.canonical`, normalise the trailing slash, force `https`
for comparison purposes. Match on the canonical form. Add a secondary
title-similarity check so the same recipe imported from an AMP URL and its
canonical URL is still recognised. Store the canonical URL on the recipe.

### D4 — Short links are never resolved
`vm.tiktok.com/…`, `vt.tiktok.com/…`, `pin.it/…`, `fb.watch/…` and `youtu.be`
share links are redirect stubs. `SocialImporter.canonical`
(`SocialImporter.swift:230`) rewrites `youtu.be` and `/shorts/` by hand but
never follows a redirect. Consequence: Instagram shortcode extraction fails,
the oEmbed lookup is made against the stub, and duplicate matching compares
stubs to canonical URLs.

Fix: resolve the redirect chain (HEAD, falling back to a ranged GET) before
canonicalising, with a hop limit, a short timeout and a same-scheme guard.
Feed the *resolved* URL into platform detection, shortcode extraction and
duplicate matching. Never follow a redirect to a non-http(s) scheme.

### D5 — Two divergent lists decide what "social" means
`ImportCoordinator.socialHosts` (`:44–54`) and `SocialPlatform.detect`
(`SocialImporter.swift:79–95`) are independent host lists that already
disagree in shape (`detect` strips `www.`, `socialHosts` enumerates it). A
host in one and not the other produces incoherent behaviour: a page treated as
social by the coordinator but with no platform, or the reverse.

Fix: one source of truth. Derive `isSocialSource` from
`SocialPlatform.detect(from:) != nil`. While you are there, cover
`web.facebook.com`, `l.instagram.com`, `ddinstagram.com`-style mirrors,
`youtube-nocookie.com`, `m.` and country subdomains via suffix matching rather
than exact-string matching.

### D6 — JSON-LD recipe selection is non-deterministic and takes the first, not the best
`findRecipeNode` recurses `for value in dictionary.values`
(`JSONLDExtractor.swift:49`). **Swift dictionary iteration order is not
stable**, so on a page carrying several `Recipe` nodes — a roundup post, a
"related recipes" carousel, a print variant — *which recipe you import can
change between runs on identical input*.

Fix: collect **all** candidate `Recipe` nodes deterministically (stable key
order, breadth-first), score them, and take the best: most ingredients + steps,
title closest to `og:title`/`<title>`, node reachable from the page's main
entity. Add a test with two Recipe nodes that asserts the same one comes back
every time.

### D7 — Microdata duplicates every ingredient and step on hybrid sites
`MicrodataExtractor.extract` concatenates `itemprop` matches **and**
`class="ingredient"` matches (`:24–31`). A site publishing both — which the
legacy-hRecipe-plus-schema.org generation of food blogs does — gets every
line twice, and every step twice.

Fix: prefer `itemprop` when present, fall back to class names only when the
itemprop pass came back empty. Then dedupe defensively on normalised text
regardless.

### D8 — A thin structured parse silently beats a good AI parse
The cascade accepts any candidate where `isUsable` — title plus **one**
ingredient *or* **one** step (`RecipeImporting.swift:108`). A "related recipe"
widget or a stub JSON-LD block clears that bar, `best` is set, and the AI tier
is never consulted because `result.recipe != nil`.

Fix: add a plausibility gate before accepting a structured result — e.g.
require ≥2 ingredients *and* ≥1 step, or ≥3 of either, plus a title that isn't
obviously the site name. Below the gate, keep the structured result as a floor
but still run Tier 3 and take whichever is richer. Record which tier won so
the review banner can be honest.

### D9 — Tiers never merge
`ImportCoordinator.parse` (`:93–108`) breaks on the first *complete* candidate
and otherwise keeps only the first usable one. A page where JSON-LD carries
ingredients and microdata carries the method yields half a recipe.

Fix: run every tier, then merge field-by-field, highest-confidence source
winning per field, with a longer list beating a shorter one for `ingredients`
and `steps`. Confidence for a merged result is the minimum of the contributing
tiers.

### D10 — HTTP 403 / bot walls are a terminal failure
`fetchHTML` returns `.failure(.httpStatus(403))` (`ImportCoordinator.swift:146`)
and `ImportFlowView.failure(_:)` offers only "Try again" and "Type it in
instead". Cloudflare and friends 403 a great many recipe sites on first
contact. The user is told the site "won't let me in" and given a blank form.

Fix: a fetch ladder, then the never-fail contract in §5. On a 403/429/503, or
a 200 whose body is an interstitial: retry once with a different plausible
`Accept-Language`/`Accept` and with the site's own origin as `Referer`; try
the AMP variant (`<link rel="amphtml">`) if the first response gave one; try
the canonical URL if it differs. Cap the whole ladder inside the budget from
§6. **Do not** impersonate a logged-in user, do not bypass a paywall, and do
not add credential-bearing requests.

### D11 — Video parsing ignores whether the chosen model can do video
`GeminiModel.supportsVideo` exists and is checked **only in Settings**
(`AIKeySettingsView.swift:248`). A user on "Speedy" (`flash-lite`) who imports
a YouTube link or hands over a Reel gets a video/image part sent to a
text-first model and a confusing failure with no explanation.

Fix: check `model.supportsVideo` in `AIRecipeParser` before building any
video, frame or image part. Either transparently use the video-capable model
for that one call, or fail with a specific, actionable `CozyError` that names
the setting. Cover with a test.

### D12 — Truncated AI responses are a hard failure
`MAX_TOKENS` maps to `.responseTruncated` (`GeminiClient.swift:496`), which
`AIRecipeParser` returns as a failure. A long recipe — twenty steps, four
sub-recipes — therefore fails outright, and `.responseTruncated` is marked
retryable but nothing retries it with a larger budget.

Fix: on `.responseTruncated`, retry once with a raised `maxOutputTokens` and
thinking disabled. If it truncates again, degrade deliberately: ask for
ingredients and steps in two calls and stitch. Never return partial JSON as a
recipe.

### D13 — Platform is guessed as Instagram when unknown
`currentPost` falls back to `.instagram` (`ImportViewModel.swift:478`) and
`parsePastedCaption` constructs `SocialPost(platform: .instagram, url:)`
(`:513`) regardless of the real source. The wrong platform name is then
written into the prompt and into `sourceName`.

Fix: make the platform genuinely optional through this path, and have the
prompt say "a social post" when it isn't known. Never assert a platform the
app did not detect.

### D14 — "Try again" and the disabled-state check read different text sources
`ImportFlowView` carries both `viewModel.urlText` and an optional external
`pasteLinkText` binding. The `.disabled` expression at `:130` consults
`pasteLinkText` when present and `urlText` otherwise, while the retry button
in `failure(_:)` always calls `importFromPastedText()` with no override. The
two can disagree.

Fix: one source of truth for the entry text. Let the view model own it and
have `LibraryView` write through to it, or drop the external binding. Retry
must re-run *the URL that failed*, held explicitly, not re-read a text field.

### D15 — Nothing can be cancelled, and the worst case is minutes long
`stage = .working` has no cancel affordance. The sheet's Cancel button
dismisses the sheet but the in-flight `Task` keeps running. Summing the
existing timeouts, a single social import can legitimately occupy: oEmbed 20 s
+ Open Graph 20 s + video parse 90 s + caption parse 30 s + resolve 2×20 s +
video download 60 s + video parse 90 s + image fetches + image parse 90 s.

Fix: see §6. A visible Cancel, a hard overall budget, and structured
cancellation that actually stops the work.

### D16 — Non-UTF-8 pages mojibake silently
`ImportCoordinator.decode` falls back to `isoLatin1`, which never fails
(`:169–182`). A UTF-8 page that declares no charset and trips the UTF-8
decoder comes back as garbage ingredients rather than as an error, and there
is no `<meta charset>` sniff.

Fix: sniff `<meta charset>` / `<meta http-equiv="content-type">` from the
first few KB, try that, then UTF-8, then Latin-1 — and when the result
contains replacement characters or a high density of mojibake bigrams, say so
rather than presenting it as a clean parse.

### D17 — Unbounded page download
`session.data(for:)` reads the whole body into memory with no size cap. A
misbehaving URL can pull tens of megabytes onto a phone before anything checks.

Fix: cap the response body (a few MB is generous for HTML), stream-and-abort
past the cap, and treat "too large" as `.notAWebPage` rather than crashing or
hanging.

### D18 — Dead code in the category guesser
`GroceryCategoryGuesser.category` runs the keyword table reversed and then
forward (`IngredientLineParser.swift:225–236`). The second loop can only match
if the first already did, so it is unreachable. Harmless, but it signals the
function needs a proper look — while you are in there, confirm the specific-
before-general ordering actually holds for the pairs it claims (`coconut milk`
vs `milk`).

### D19 — Confidence banners are incoherent between tiers
Microdata (0.70) always trips the "worth a quick look" banner
(`showsConfidenceBanner`: `>0 && <0.8`); an AI parse at the 0.85 ceiling often
does not — so the *less* trustworthy source can warn *less*.

Fix: derive the banner from provenance, not only from a number. An AI-derived
recipe always says so. A structured parse from a site's own JSON-LD does not
need a warning. Keep the copy in the app's voice.

### D20 — Reparse-on-save can overwrite user intent
`reparseIngredient(at:)` takes `reparsed.note ?? existing.note` (so a
hand-typed note loses to a parsed one) and `reparsed.isSectionHeader ||
existing.isSectionHeader` (so a section header can never be un-marked). The
merge is otherwise good and its comment explains why it exists — preserve that
behaviour, fix only these two asymmetries.

---

## 4. New capability — follow the link to where the recipe actually lives

**This is the "navigate to the profile / blog site" requirement, and it is a
first-class deliverable, not a nice-to-have.**

An enormous share of Reels and TikToks say "full recipe on my blog 👇" or "link
in bio". Today the app reads the caption, finds no recipe, and asks the user to
do the work. It should follow the trail first.

Build a resolver — suggested home `Services/RecipeImport/RecipeLinkResolver.swift`
— that runs **after the caption parse fails and before the media parse**,
because a blog post is cheaper, better structured and more complete than a
video parse:

1. **Harvest candidate links** from everything already in hand: the caption
   text (`NSDataDetector`), the oEmbed payload, the post page's outbound
   links, the YouTube description, and — for Instagram and TikTok — the
   **profile page's bio link**, reached from the post's author handle.
2. **Score them.** Prefer a link on the poster's own domain; prefer paths that
   look like a post (`/recipes/`, `/blog/`, a slug with hyphens) over a home
   page; prefer a link-in-bio aggregator's *entries* over the aggregator
   itself. Deprioritise affiliate, storefront, newsletter and social links.
3. **Expand one hop through link-in-bio aggregators.** Linktree, Beacons,
   Stan, Later/Linkin.bio, Milkshake and similar are index pages: fetch,
   enumerate the entries, and score those entries against the post's title and
   caption keywords. Take the best match, not the first.
4. **When the candidate is a site's home page or archive**, use its on-site
   search or its sitemap to find the post whose title best matches the
   caption's dish name. Match on normalised title tokens; require a real
   overlap before accepting.
5. **Run the ordinary web cascade** against the winning URL. If it produces a
   recipe, accept it with the *blog* as `sourceURL`/`sourceName`, note in the
   review banner where it came from ("The caption pointed at their blog, so I
   read the recipe from there"), and keep the post's thumbnail as the hero if
   the blog has none.
6. **Give up cheaply.** At most 2 hops and 3 candidate fetches, inside the
   §6 budget, each best-effort. An empty result is an ordinary outcome that
   falls through to the media path exactly as today.

Rules for this resolver:

- **Only public, unauthenticated pages.** No login walls, no credentialed
  requests, no scraping of anything that requires an account. If a page
  requires auth, stop.
- **Respect the ladder.** This never replaces the video path; it precedes it,
  and failure is silent.
- Everything parseable must be **pure and static** so it is testable from
  fixtures with no network — the same discipline `SocialMediaResolver` already
  follows. The actor does the fetching; the scoring, harvesting and matching
  are `nonisolated static` functions with unit tests.

---

## 5. The never-fail contract

Codify this as an explicit ladder in `ImportViewModel`, documented in the file
header, and prove it with tests. **Every rung falls through to the next; the
last rung always works.**

```
1  structured markup (JSON-LD, microdata, merged)
2  AI over extracted page text
3  followed link — blog post / link-in-bio target      ← §4
4  post media the app can fetch (fuller caption → video → carousel images)
5  media the user hands over (saved video → screenshots)
6  caption or recipe text the user pastes
7  pre-filled manual entry — title, photo, source, servings already in place
```

Requirements:

- **No terminal error screen.** `stage = .failed` must always offer both a
  retry (when the error is retryable) *and* the next rung down — including the
  hand-over-media and paste-the-text routes that today are reachable only from
  the social path. A 403 on a recipe blog should offer "paste the recipe text"
  just as a Reel offers "paste the caption".
- **Never save a hollow recipe.** `canSave` stays as it is: a title plus at
  least one ingredient or step.
- **Every rung explains itself** in the app's voice, in one sentence, in
  `socialNote` / `captionPromptReason`. The user should always know what was
  tried and what to do next. Add new copy to `CozyError.friendlyMessage`
  rather than rendering raw errors — views never show a raw error string.
- **Partial success is success.** A recipe with ingredients but no method,
  recovered from a caption, goes to review with a banner saying the method is
  missing — not to an error.

---

## 6. Budgets, cancellation and progress

- **One overall budget for an import**, enforced in `ImportViewModel`: a hard
  ceiling (target ~75 s for a social import with media, ~30 s for a plain web
  import) after which the pipeline stops and lands on the best rung reached so
  far, with an honest message. Per-stage timeouts stay as sub-budgets.
- **Structured cancellation.** The work runs in a task the view model owns and
  stores; dismissing the sheet or tapping Cancel cancels it, and every `await`
  in the chain honours `Task.isCancelled`. Map cancellation to `.cancelled`,
  which already exists and is non-retryable.
- **A Cancel affordance on the `.working` screen.** A 90-second wait with no
  way out is the single worst moment in the current flow.
- **Honest progress.** Replace the canned rotating messages in `ImportFlowView
  .working` with the stage actually running ("Reading the page", "Watching the
  video", "Checking their blog"), driven by an enum on the view model.
  Keep the mascot and the voice.
- **A per-session result cache** keyed by canonical URL, so a retry after a
  cancelled or failed run is instant and does not re-charge a Gemini call.
  In-memory only; no persistence, no new store.
- **Bounded concurrency** on image downloads (they are currently sequential in
  `downloadImages`) — fetch the carousel in parallel with a small cap, and
  keep the existing 6-image and 4-download ceilings.

---

## 7. Nothing missed — completeness rules

For every rung, these fields must be populated when the source contains them:

| Field | Rule |
|---|---|
| `title` | Never the site name, never "Recipe", never truncated mid-word. Prefer JSON-LD `name`, then `og:title` with the site suffix trimmed. |
| `ingredients` | Every line, in source order, including section headers. Sub-recipes ("For the sauce:") preserved as headers, not dropped or flattened. No duplicates. |
| `steps` | Every step, in order. A single instruction blob is split on real boundaries; a run of `<p>`/`<li>` is one step each. Never merge the whole method into one step when the source separated it. |
| `servings` | From `recipeYield` in any of its shapes (number, `"4 servings"`, `["4", "4 servings"]`, `"Serves 4-6"` → 4). |
| `prepMinutes` / `cookMinutes` | ISO 8601 where given; `totalTime − prepTime` for cook time only when `cookTime` is absent (already correct — keep the test). |
| `imageURL` / hero | Structured image first, then `og:image`, then the post thumbnail, then a video frame. Protocol-relative and root-relative URLs resolved. |
| `sourceName` / `sourceURL` | Author, then site name, then host. Canonical URL. A camera-roll import keeps *no* invented URL (already handled by the placeholder — preserve it). |
| `tags` | Deduped, lowercased, capped — keep the existing behaviour. |
| `durationSeconds` | Only when the step states a time. Never invented. |
| `confidence` | Honest, provenance-aware — see D19. AI stays capped at 0.85. |

Add a **completeness check** before review: if ingredients are present but the
method is empty (or vice versa), attempt the next rung *for the missing half*
before landing, and if it stays missing, say so in the banner rather than
letting the user discover it in Cook Mode.

---

## 8. Test plan — this is not optional

The project uses **swift-testing** (`@Suite` / `@Test` / `#expect` /
`#require`), not XCTest. `ImportViewModel` — the highest-risk file in the
import stack — currently has **zero tests**. Fix that.

**New fixtures** (`Cozy CrumbTests/`, saved markup, no network):

- 8–10 real recipe sites' saved HTML, as `RecipeExtractorTests.swift`'s own
  header has asked for since it was written: a WordPress recipe-card site, a
  `@graph` site, a microdata-only site, a hybrid itemprop+class site (D7), a
  page with two `Recipe` nodes (D6), a JS-rendered page with no recipe in the
  HTML, a non-UTF-8 page (D16), and a 403 interstitial body.
- Instagram embed markup, a TikTok rehydration blob, a link-in-bio aggregator
  page, and a caption containing a blog URL (§4).

**New suites, at minimum:**

1. `ImportCoordinator` fetch behaviour via a stubbed `URLProtocol` — status
   codes, redirects, MIME types, oversize bodies, encodings, the 403 ladder.
2. The tier-merge and plausibility gate (D8, D9) — including "thin JSON-LD
   plus good AI text" and "ingredients here, steps there".
3. Deterministic Recipe-node selection (D6) — same input, same output, run
   repeatedly.
4. Page-text extraction for the AI tier (D1) — a large page yields recipe
   prose, and the cap is applied to *text*, not markup.
5. URL canonicalisation and duplicate matching (D3, D4) across the whole
   equivalence set.
6. `RecipeLinkResolver` (§4) — harvesting, scoring, aggregator expansion,
   title matching, and giving up cleanly.
7. `ImportViewModel` state machine, with injected fakes for coordinator,
   importer, resolver, media resolver and parser (the initialiser already
   takes all five — use it): every rung of §5, cancellation, budget expiry,
   duplicate detection on the paste path, and "never lands on a terminal
   screen" as an explicit assertion over every failure mode of `CozyError`.
8. The save path — `apply(to:in:)` writes ordering, drops blank lines,
   replaces children on update, and does not log a signal for an edit.

**Keep every existing test green.** Where behaviour intentionally changes
(banner rules, merged confidence), update the test *and* say why in the commit
message. Do not delete a test to make a change pass.

---

## 9. Blast radius — what else touches this

Check each before you finish; a change to the import stack reaches further
than it looks:

- **`IngredientRepair`** re-parses every saved ingredient line at launch. If
  you change `IngredientLineParser` or `QuantityParser` semantics, you change
  every recipe already in the library, retroactively, on next launch.
- **`ServingsScaler`, `UnitConverter`, `ShoppingRounder`, `GroceryMerge`,
  `GroceryConsolidation`, `IngredientCanonicalizer`** all consume
  `quantity`/`unit`/`name`. A parser change that leaves more `nil` quantities
  silently breaks scaling and the shopping list — this exact regression is
  documented in `reparseIngredient(at:)`'s comment. Do not repeat it.
- **`CuisineBackfill`, `SignalLog`, `TasteProfileBuilder`, `CookFactStore`**
  read imported recipes. `save()` logs an import signal only for genuinely new
  recipes — keep that.
- **`RecipeDetailView` / `CookMode` / `KitchenTimers`** render `steps` and
  `durationSeconds`.
- **The share extension** and `CozyDeepLink` — both targets compile
  `Shared/CozyDeepLink.swift`; a format change breaks the hand-off silently.
- **`Config/CozyCrumb-Info.plist`** carries the URL scheme and usage strings,
  and CI asserts them in the built product. Do not disturb the plist merge.

---

## 10. Working agreement

- **Branch:** `claude/recipe-import-robustness-rufxm8`. Commit in coherent
  steps with real messages — one per defect or per coherent group, not one
  giant commit. Push to that branch. **Do not open a pull request unless
  asked.**
- **Swift 6, MainActor-by-default target.** Match the existing isolation
  discipline exactly: `nonisolated` on value types, their memberwise inits,
  their `Codable`/protocol conformances, and every pure parsing function.
  Actors do the networking. Do not introduce `@unchecked Sendable` and do not
  silence a concurrency error with an isolation annotation you cannot justify
  in a comment.
- **Match the house style.** Read three neighbouring files before writing one.
  This codebase comments *why*, not *what*, in full sentences, with the
  failure that motivated the code written down. Keep that. Keep the app's
  voice in every user-facing string — warm, brief, never blaming the user.
- **No new third-party dependencies.** No HTML-parsing library, no networking
  library. `HTMLScanner` is deliberately small; extend it if you must, and
  keep it testable.
- **No new persisted schema** unless a defect genuinely requires it. If it
  does, migration must be additive and safe for an existing library.
- **Verify before pushing.** Build for the simulator, run the full test suite,
  and check the Swift-warning count has not risen. CI also installs the app,
  launches it in **both light and dark appearance**, and fails on a blank
  screen or a crash — a change that compiles and tests clean can still fail
  there.
- **Report honestly.** If a defect turns out to be wrong, or a fix is not
  worth its risk, say so plainly and explain — do not quietly skip it. If you
  cannot complete something, finish everything else and list what you left and
  why.

---

## 11. Definition of done

- [ ] D1–D20 each fixed, or explicitly declined with a reason.
- [ ] §4 link-following implemented, bounded, public-pages-only, and tested
      from fixtures.
- [ ] §5 ladder implemented and asserted by test: **no reachable terminal
      screen**, for every case of `CozyError`.
- [ ] §6 budget, cancellation, real progress and session cache in place.
- [ ] §7 completeness rules hold across all fixtures.
- [ ] New test suites from §8 exist and pass; every pre-existing test still
      passes.
- [ ] Zero new Swift warnings.
- [ ] CI green: build, Info.plist checks, launch smoke test in light **and**
      dark, full test run.
- [ ] Invariants I1–I10 all still hold, verified deliberately rather than
      assumed.
- [ ] A short written summary: what changed, what each fix was for, what you
      chose not to do, and what remains fragile about importing from platforms
      that actively resist being read.
