# Bricolage Grotesque

The app's display face — screen titles, card titles, section headings, the
Cook Mode step text. Body copy stays SF Rounded.

## Where these came from

Upstream is the variable font shipped by Google Fonts:

    ofl/bricolagegrotesque/BricolageGrotesque[opsz,wdth,wght].ttf

Licensed under the SIL Open Font License 1.1. `OFL.txt` beside this file is
the licence as published, and it must stay in the bundle.

## Why they are static

The upstream file is variable on three axes (`opsz` 12–96, `wght` 200–800,
`wdth` 75–100) and its named instances only exist at `opsz` 14. Shipping it
as-is would leave the optical size at its default of 96 unless Core Text's
automatic optical sizing kicked in, and would make the PostScript name the
code looks up depend on how the instance was resolved.

So each face is pinned to a single static instance instead, with `fvar`
dropped entirely:

| File | wght | wdth | opsz |
| --- | --- | --- | --- |
| `BricolageGrotesque-ExtraBold.ttf` | 800 | 100 | 36 |
| `BricolageGrotesque-SemiBold.ttf` | 600 | 100 | 34 |

The optical sizes are each face's dominant use. ExtraBold carries screen
titles at 44–52pt, recipe titles at 42, section headings at 26 and card
titles at 19, which centres on the mid-thirties. SemiBold exists for one
thing, `CozyFont.cookStep`, which sets at 34pt.

## Why the vertical metrics are edited

The design sets display titles at 0.92–1.05 line height. SwiftUI has no
negative `lineSpacing`, so a line height below the font's own is not
something a call site can ask for — it has to come from the font. Upstream
ships 930 / −270 / 0, which is 1.20em, far looser than any of the targets.

Both faces are re-cut to **890 / −200 / 0 — 1.09em** on `hhea` and on the
OS/2 typo fields, with `USE_TYPO_METRICS` set so Core Text reads them.

That number is the floor, not a preference. It is set from the actual ink:

| Ink | Extent |
| --- | --- |
| accented capitals (`À`, `É`) | 884 |
| lowercase ascenders (`b`, `k`, `l`) | 715 |
| `j` | 745 / −196 |
| descenders (`g`, `y`, `Q`) | −178 |

890 / −200 clears every one of them, so nothing clips on a first or last
line. Going to a true 0.92em would mean an ascent of 713, which cuts the
tops off accented capitals and even plain ascenders — a two-line title in
the mockup's proportions is not worth "Crème" losing its accent.

`usWinAscent` / `usWinDescent` are deliberately left at 1160 / 400 so any
path that reads the win metrics still has generous room.

What this leaves at each call site: card titles land essentially on their
1.05 target, screen and recipe titles sit a little looser than the mockup's
0.92–0.96, and `CozyFont.cookStep` adds its 1.24 back with `lineSpacing`,
which only ever loosens and is always safe.

## The names that matter

`CozyFont.hasDisplayFace` asks Core Text for these PostScript names and
compares what comes back, so they have to be exact:

    BricolageGrotesque-ExtraBold
    BricolageGrotesque-SemiBold

Name IDs 1/2/4/6/16/17 are set for a non-RIBBI style: family is
"Bricolage Grotesque ExtraBold" with subfamily "Regular", and the
typographic pair (16/17) is "Bricolage Grotesque" / "ExtraBold".

## Regenerating

    pip install fonttools brotli
    python3 - <<'PY'
    from fontTools.ttLib import TTFont
    from fontTools.varLib import instancer
    f = TTFont("BricolageGrotesque[opsz,wdth,wght].ttf")
    instancer.instantiateVariableFont(
        f, {"wght": 800, "wdth": 100, "opsz": 36}, inplace=True, updateFontNames=False
    )
    # then set name IDs 1/2/3/4/6/16/17 and OS/2.usWeightClass by hand —
    # updateFontNames=True fails here because STAT has no axis value at opsz 34.
    PY

Both files are also listed under `UIAppFonts` in `Config/CozyCrumb-Info.plist`.
Dropping a font into this folder is not enough on its own: without that key
iOS never registers it and the app falls back to SF Rounded with no error.
