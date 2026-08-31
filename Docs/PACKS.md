# Create your own quiz addon

Quiz packs are **independent WoW addons with a required dependency on Orbit-Quiz**. Keep your quiz in its own folder or repository and distribute it separately. You do not need to fork this repository, submit a pull request, or edit any Orbit-Quiz files.

Use **Lua data tables inside a small companion addon**. WoW loads Lua files named in an addon's TOC; it does not let an addon scan a directory or read arbitrary YAML, JSON, Markdown, or text files. Orbit-Quiz has no question editor or text-to-code importer.

Only the quiz host needs the pack. A pack can cover Warcraft, general trivia, or your guild's own topics.

The quiz author owns its rules. The host selects the quiz and starts it; there are no host timing, scoring or rule overrides. Orbit-Quiz validates and copies the pack's rules, then sends them to participants with the questions.

## Create the addon in your own project

1. Create a separate project folder with your addon's name, for example `MyGuild-Trivia`. An `Orbit-Quiz-` name prefix is not required.
2. Create `MyGuild-Trivia.toc` and `Questions.lua` using the complete examples below. The folder and TOC basename must match.
3. Set your addon metadata, a unique pack `id`, your questions, and the quiz's `rules`. Save Lua files as UTF-8 without a BOM. You maintain these files in your own project, not inside Orbit-Quiz.
4. With WoW closed, install the released Orbit-Quiz addon and copy your finished `MyGuild-Trivia` folder beside it in `World of Warcraft/_retail_/Interface/AddOns/`.
5. Launch WoW, enable both addons, open `/oq host`, and select your quiz. `/oq packs` lists registered packs and validation errors.

Prefer a starter to copy? The repository's [example addon](../Dev/Examples/Orbit-Quiz-Pack-Example/README.md) includes three questions and a complete rules table. Copy only that folder into your own project, then rename its folder and TOC. The example is source-only; the two file examples below also work with an installed release, without downloading or contributing to the core repository.

Once installed, editing an already listed Lua file takes effect after `/reload` and a new game. Restart WoW when adding a new addon folder or when a new TOC entry is not detected. Keeping the pack separate lets Orbit-Quiz and your quiz update independently.

The resulting folder layout is:

```text
Interface/AddOns/
  Orbit-Quiz/
    Orbit-Quiz.toc
    ...
  MyGuild-Trivia/
    MyGuild-Trivia.toc
    Questions.lua
```

The companion TOC:

```toc
## Interface: 120100
## Title: My Guild Trivia
## Notes: Our guild's question pack.
## Author: Your name
## Version: 1.0
## Dependencies: Orbit-Quiz

Questions.lua
```

`## Dependencies: Orbit-Quiz` is the connection to the framework: WoW loads Orbit-Quiz before your question file. Keep it a required dependency, not an optional one. Do not bundle Orbit-Quiz, copy its libraries, or add your files to its TOC.

Do not set `LoadOnDemand`: packs register during normal addon loading. To split a large pack into multiple files, list each file in **your addon's** TOC. Either register a separate pack ID from each file, or collect questions in your addon's namespace and register one combined pack from a final file.

## Question format

`Questions.lua` is a normal Lua file calling the public API:

```lua
OrbitQuiz:RegisterQuestionPack({
    id = "myguild_trivia",
    title = "My Guild Trivia",
    version = 1,
    author = "Your name",
    locale = "enUS",
    rules = {
        version = 1,
        answerSeconds = 15,
        revealSeconds = 3,
        streakBonusPerCorrect = 0.1,
        streakBonusMax = 0.5,
    },
    questions = {
        {
            id = "triangle_sides",
            prompt = "How many sides does a triangle have?",
            choices = { "Two", "Three", "Four", "Five" },
            correctIndex = 2,
            explanation = "A triangle has three sides.",
            category = "General Knowledge",
        },
    },
})
```

Call the public `OrbitQuiz:RegisterQuestionPack` API directly. The `...` namespace passed to your Lua file belongs to **your addon**, not Orbit-Quiz; do not copy the core addon's private namespace imports. No extra registration event, slash command, or change to the core addon is needed.

`correctIndex` is the position of the correct answer **in the file**, starting at 1. The game can shuffle the choices and adjusts the answer mapping itself. Explanations must name the answer, not say "B is correct". Put `\"` inside a double-quoted Lua string when the text itself needs a quotation mark; do not insert literal line breaks.

## Share and update your quiz

Maintain the pack in your own repository if you use version control. To share it, zip only the `MyGuild-Trivia` folder, with its TOC and Lua files directly inside that folder, and publish that archive as your own addon. Do not include an extra repository wrapper folder or a copy of Orbit-Quiz. Your release instructions should tell hosts to install Orbit-Quiz separately and enable both addons.

Only the host needs your pack installed; other players need Orbit-Quiz and receive the questions and rules from the host. Your addon supplies content and rules, while the framework owns the widget, sessions and saved scores. No pack-specific SavedVariables or UI are needed.

Keep the pack `id` stable across updates, bump its content `version` when questions change, and bump `rules.version` when rules change. The TOC `Version` identifies your addon release separately. Before publishing, test with the installed release of Orbit-Quiz and check `/oq packs`; your quiz never needs approval or registration in this repository.

## Schema and limits

| Field | Contract |
| --- | --- |
| Pack `id` | Required, unique across all installed packs. 1-48 lowercase ASCII letters, digits, `_` or `-`; first character must be a letter or digit. `all` is reserved. |
| Pack `title` | Required plain text, up to 64 bytes. |
| Pack `version` | Positive integer up to 2147483647; defaults to 1. Bump it when publishing revised content. It does not replace another registered pack with the same ID. |
| Pack `author` | Optional plain text, up to 64 bytes. |
| Pack `locale` | Defaults to `enUS`. Accepted: `enUS`, `enGB`, `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`. Metadata describing the questions, not automatic translation. |
| Pack `questions` | Required consecutive array of 1-2,000 questions, with no gaps or named entries. |
| Pack `rules` | Optional plain table containing the supported rules below. Omitted fields use engine defaults; existing packs without rules remain playable without streak bonuses. |
| Question `id` | Required, unique within its pack. Same character/length rules as pack IDs. |
| Question `prompt` | Required plain text, up to 160 bytes. |
| Question `choices` | Four to six consecutive non-empty plain-text strings, each up to 100 bytes. Choices must differ after trimming and ignoring ASCII letter case. |
| Question `correctIndex` | Required integer from 1 to the number of choices in that question. |
| Question `explanation` | Optional plain text, up to 160 bytes. |
| Question `category` | Optional plain text, up to 64 bytes. Descriptive metadata; it does not create a separate pack. |
| Question `difficulty` | Optional `easy`, `medium`, `hard`, or `very_hard`. Retained as metadata, not displayed on the Q/A widget; it does not change scoring. |
| Question `era` | Optional plain text, up to 64 bytes, naming the expansion, game, or work. Retained as metadata, not displayed on the Q/A widget. |
| Question `source` | Optional HTTPS URL, up to 512 bytes, without spaces, controls, or markup. Retained for content review on the host; never sent with a live question. |

All pack, question, array and rules tables must be ordinary tables without metatables. Extra, unrecognized pack/question record fields are ignored; unknown **rule** fields reject the pack so a misspelled rule cannot silently change gameplay. Empty strings are not valid optional values; omit the field instead.

Text limits are **UTF-8 bytes**, not visible character counts, to bound addon-message payloads. Leading and trailing ASCII spaces are removed. Control characters, `|` characters, and `{`/`}` braces are rejected, preventing links, colors, textures, and raid-icon escape markup in question text. Keep each question self-contained and short enough to read within the answer window.

Give each new question a stable ID. Rearranging a pack must not change IDs. Correcting a typo can keep the same ID; replacing a question with a different one needs a new ID. The registry's normalized key is `packId:questionId`. Personal progress belongs to the stable pack ID, with separate score totals for different rules. Content-version updates retain the same ruleset's progress; a genuinely different quiz needs its own ID.

Packs retain the language of their files. Installing a French pack does not translate an English pack. `GetQuestions("all")` still returns the full content pool regardless of locale; hosting All installed packs is offered only when every installed pack has exactly the same normalized rules, including rule revision. Mixed games credit each question's originating pack and share the session's consecutive-answer streak. Choose an individual pack for a single-language quiz or whenever rules differ.

Existing four-choice packs need no changes. A pack can mix four-, five-, and six-choice questions. The widget shows one clickable text line per answer (wrapping when needed); every question uses its quiz's rules regardless of difficulty metadata. Explanations remain in pack/result data but are not displayed on this text-only widget. `difficulty`, `era`, and `source` are mandatory editorial fields for bundled Warcraft Lore, but optional in the public API.

The bundled pack is split by era/work for maintenance, then registered as one `warcraft-lore` pack. See [Warcraft Lore's source guide](../Packs/WarcraftLore/SOURCES.md) for its scope, continuity rules, and source-review process. Keep additions of your own in a companion addon so an update cannot overwrite them.

## Quiz rules

Rules are pack-wide, not per-question. They are snapshotted at game start, so changing a pack file requires `/reload` and a new game. The Host pane displays a read-only summary; font, scale and widget position remain personal preferences.

| Rule | Default | Allowed values / effect |
| --- | --- | --- |
| `version` | `1` | Author's rules revision, integer 1-2147483647. Separate from the pack's content version. |
| `answerSeconds` | `15` | Integer 5-120. Full answer window after synchronization. |
| `revealSeconds` | `3` | Integer 1-30. Result display before the next question or automatic game completion. |
| `allowAnswerChanges` | `true` | `false` locks the first accepted answer; retries of that answer remain safe. |
| `shuffleQuestions` | `true` | `false` uses the authored order. |
| `shuffleChoices` | `true` | `false` keeps choices in file order. Correct-answer mapping is maintained automatically. |
| `repeatQuestions` | `true` | Cycle through the deck again after exhaustion. `false` ends after one pass. |
| `questionLimit` | `0` | Integer 0-2000. Positive values cap completed questions; `0` adds no cap. Without repetition, a shorter deck ends first. |
| `correctPoints` | `1` | 0-1000 points, in tenths. Base reward for a correct answer. |
| `speedBonusPerSecond` | `0.1` | 0-10 points, in tenths, per **whole second remaining**. `0` disables the speed bonus. |
| `wrongPenaltyStart` | `1` | 0-1000, in tenths; positive magnitude deducted for an immediate wrong answer. |
| `wrongPenaltyEnd` | `0.5` | 0-1000, in tenths; magnitude near timeout. Must not exceed the starting penalty. |
| `wrongPenaltyCurve` | `2.5` | 0.1-10 in tenths; exponential half-lives across the answer window. Larger values reduce the penalty sooner. |
| `streakBonusPerCorrect` | `0` | 0-10 points in tenths added per consecutive correct answer **after the first**. |
| `streakBonusMax` | `0` | 0-100 points in tenths; maximum extra streak points on one answer. Set both streak fields to `0` to disable. |

Correct points are `correctPoints + floor(secondsRemaining) * speedBonusPerSecond + streakBonus`. The wrong penalty follows a normalized exponential between its two endpoints, rounded to tenths. Equal endpoints give a flat penalty; set both to `0` for no wrong-answer penalty. Unanswered questions always score zero, totals may be negative, and score precision stays at one decimal place.

Warcraft Lore explicitly uses the defaults above except `streakBonusPerCorrect = 0.1` and `streakBonusMax = 0.5`. Its streak bonuses are `0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.5, ...` on successive correct answers. A wrong or unanswered **closed** round resets the streak. A voided question neither awards points nor breaks the streak. A new game starts at zero streak; leaving cannot erase an already accepted answer. Only the final selection at closure counts, never intermediate guesses or retries.

Automatic advancement, one correct choice from four to six, host-observed timing, communication safety pauses, the supported player limit and fastest-correct recognition remain engine behaviour. No untimed, manual-next, per-question rules, teams, hints or new answer types are included yet. A void consumes its deck position; ending a one-pass deck through voids finishes without scoring those questions. Validate the balance of custom rewards and penalties: arbitrary settings are not guaranteed to discourage blind guessing.

Scores are separated by stable pack ID and a canonical key containing **every resolved rule**, including `rules.version`. Increase the rule revision when publishing changed rules; even if an author forgets, different resolved values create separate score rows. Changing only content with unchanged rules retains the same score row. Earlier scores remain under Original rules without rescoring. These keys provide identity and consistency, not encryption, authentication or anti-cheat protection.

## Validation and troubleshooting

Registration is atomic: a malformed question rejects the entire pack, and a duplicate pack never replaces the first one. A rejected pack is not offered to the host. The registry returns `false, errorMessage` on failure and retains contextual errors for the host; valid registration returns `true`.

The public API is:

```lua
local ok, errorMessage = OrbitQuiz:RegisterQuestionPack(pack)
local metadata = OrbitQuiz:GetQuestionPacks()
local rules, rulesKey = OrbitQuiz:GetPackRules("myguild_trivia")
local questions, errorMessage = OrbitQuiz:GetQuestions("myguild_trivia")
local everyQuestion = OrbitQuiz:GetQuestions("all")
local errors = OrbitQuiz:GetPackErrors()
```

Metadata is sorted by title, then ID, and includes `id`, `title`, `version`, `author`, `locale`, `count`, detached normalized `rules` and `rulesKey`. Question reads return fresh copies, including `choices`, `packId`, `packTitle`, `packVersion` and `rulesKey`. `GetPackRules` returns a detached rules table and canonical key; incompatible `all` rules return `nil, "incompatible_pack_rules"`. Mutating originals or returned data cannot change the registry. Unknown packs return `nil, errorMessage`.

For a missing pack, check that the folder is directly under `Interface/AddOns`, its TOC basename matches the folder, it is enabled, and its listed Lua filename matches the actual file. Type `/oq packs` to list registered packs and validation errors. Lua syntax/runtime errors happen before registration and appear in WoW's normal error reporting or BugSack; the registry cannot recover a file that never executed.

Question content is **not** stored in SavedVariables. Result records retain the canonical rule identity needed to validate their historical points. Updating or removing a pack affects future games, not previously earned scores. There is no online pack synchronization or download system.

## Trust boundary

A companion pack is executable Lua addon code. Install only packs from authors you trust, and inspect unfamiliar files. Schema validation protects the quiz's data shape; it does **not** sandbox a malicious addon or make arbitrary downloaded Lua safe.
