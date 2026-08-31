# Warcraft Lore: scope and review

## Content contract

The bundled `warcraft-lore` pack replaces Warcraft Basics with **1,183 game-based questions** in content version 2. It is one mixed, automatically shuffled catalogue assembled from separate Lua files for maintainability, not a collection of individually selectable expansion packs. It contains full story spoilers. Comic, graphic-novel, manga and digital-comic questions are excluded.

Every entry has a permanent ID, one correct answer among four to six distinct choices, a difficulty, an era/work label, and an HTTPS source reference. Difficulty is descriptive: all questions retain the same fifteen-second answer window and scoring. The addon never downloads source pages, and it does not send a question's source or answer key to participants before results.

The review cutoff is **31 August 2026**. Coverage includes released Midnight material, including the Coiled Isle; it excludes unreleased Last Titan story claims.

## Coverage

The complete game catalogue contains **1,183 questions**:

| Game or era | Questions |
| --- | ---: |
| Warcraft I | 40 |
| Warcraft II | 44 |
| Warcraft II: Beyond the Dark Portal | 23 |
| Warcraft III | 77 |
| Warcraft III: The Frozen Throne | 36 |
| Original World of Warcraft / Classic | 85 |
| The Burning Crusade | 80 |
| Wrath of the Lich King | 90 |
| Cataclysm | 70 |
| Mists of Pandaria | 80 |
| Warlords of Draenor | 69 |
| Legion | 80 |
| Battle for Azeroth | 80 |
| Shadowlands | 72 |
| Dragonflight | 80 |
| The War Within | 97 |
| Midnight | 80 |

[ResearchEarly.md](ResearchEarly.md) covers the RTS, Classic, Burning Crusade, Wrath and Dragonflight sources; [ResearchMiddle.md](ResearchMiddle.md) covers Cataclysm through Shadowlands. Every remaining source is attached to its question in the game-era file. The 247 retired comic/manga questions and their research are preserved only in the source checkout's `Archive/Comics` directory, outside the TOC and release package.

Difficulty mix: **183 easy, 391 medium, 440 hard, 169 very hard**. Choice counts: **932 four-choice, 228 five-choice, 23 six-choice**. These labels are editorial estimates, not measured player-success rates.

These are lore questions about characters, places, motivations, relationships, artifacts, campaigns, raids and quests. Publication dates, patch numbers, balance changes, loot tables, encounter rotations, achievement requirements and historical class mechanics are not quiz topics.

Existing geography/history topics include the Horde's Black Morass landfall, Lothar's First War refugees, the War of the Three Hammers, Vashj'ir's Highborne ruins, the Shado-Pan Monastery's location, the naming of the Ohn'ahran Plains and Darkflame Cleft's former purpose. They are mixed into the relevant game eras, not separate selectable topic packs.

## Continuity decisions

- Use the game universe, not the separate Warcraft film continuity. Bonds of Brotherhood, Hearthstone-only stories and non-canon RPG material are excluded.
- Prefer current established lore over superseded manuals, early previews, unused dialogue or speculation. An old source remains useful for an unchanged fact, not as authority for a retconned claim.
- Warcraft RTS questions do not treat mutually exclusive campaign endings as simultaneously canonical. A question about a specific campaign scene is explicitly contextualized where needed.
- The older History of Warcraft attribution of the Draenor invasion decision to Terenas is excluded; Beyond the Dark Portal and Chronicle Volume 2 supersede that account. [Invasion chronology](https://warcraft.wiki.gg/wiki/Invasion_of_Draenor).
- Warlords of Draenor describes alternate Draenor. Qualify incarnation-dependent details instead of assigning them to the main-universe character.
- Exclude questions requiring comic, graphic-novel or manga knowledge, even where that story is canonical. A shared character/faction wiki page does not make a game-supported fact comic-only; retain the game-context question, not comic plot details.
- Use Retail continuity rather than mixing divergent Season of Discovery events into it. Ula'tek questions use the released game account, not the RPG's Old God speculation.
- Conflicting descriptions are grounds to omit a question or narrow its wording. For example, an official Cataclysm retrospective's swapped dungeon-location blurbs were not used as factual authority.

## Evidence and editorial process

Sources were consulted through publicly accessible text and indexed excerpts: official Blizzard story/zone/raid material, transcribed game dialogue and Adventure Guide lore, and Warcraft Wiki reference summaries. A source on a character's page is used only for the relevant game passage, not as proof that every detail on that page applies to every era.

The original editorial pass corrected factual and wording issues and removed a superseded expedition question. The retained game catalogue links to 350 source pages. Removing comic-based content is a scope change, not a fresh fact-check of all remaining claims. Access errors often required indexed excerpts; neither the editorial review nor automated checks constitute an infallibility guarantee.

`Quiz.Lore:Add` groups short original questions under the consulted reference. The helper copies that URL onto each question; maintainers can identify and review a disputed fact by its stable ID. The questions are not copied quiz-bank material, and explanatory text is omitted where the source and answer suffice.

The offline audit checks size, unique IDs and normalized prompts, distinct choices, byte bounds, all four difficulty tiers, game-era coverage and source metadata. It rejects retired comic IDs/publication metadata and checks that the archive cannot load or ship. It also limits derived prompt/correct-answer/explanation wording per source page, merging Blizzard article IDs across locale/domain aliases. It does **not** prove a factual claim or disambiguate canon automatically. Its optional `--review` report flags similar and reciprocal questions for manual judgment; related questions can legitimately refer to different events.

Difficulty guidance:

- `easy`: widely recognizable protagonists, settings and central story events.
- `medium`: campaign relationships, major factions and familiar zone/raid identities.
- `hard`: specific quests, motivations, named supporting characters and detailed story events.
- `very_hard`: missable dialogue, obscure quests, supporting characters and regional-history deep cuts.

## Maintaining the catalogue

From the addon folder, run `python .tests/Lore.py` for the shipped pack, or `python .tests/Lore.py --draft --review` while editing era files. Run `python .tests/run.py` for registration, shuffle, scoring, protocol and widget regressions. These checks do not replace reading the cited evidence or testing in WoW.

Correct wording in place under the same ID when the underlying fact is unchanged. Give a genuinely different question a new ID; do not recycle archived IDs. If later canon makes an answer ambiguous, remove or replace it instead of retaining a knowingly disputable answer. Increment the content version when changing the catalogue, retaining the stable pack ID. Content changes never rewrite already-earned scores.
