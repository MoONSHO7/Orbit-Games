# File-based Question Packs

Use **Lua data tables inside a small companion addon**. WoW loads Lua files named in an addon's TOC; it does not let an addon scan a directory or read arbitrary YAML, JSON, Markdown, or text files. Orbit-Quiz has no question editor or text-to-code importer.

Only the quiz host needs the pack. A pack can cover Warcraft, general trivia, or your guild's own topics.

## Install or create a pack

1. Copy `Examples/Orbit-Quiz-Pack-Example` to `World of Warcraft/_retail_/Interface/AddOns/`, beside the `Orbit-Quiz` folder, not inside it.
2. For your own pack, rename the folder and its TOC to the same unique name, such as `Orbit-Quiz-Pack-GuildNight` and `Orbit-Quiz-Pack-GuildNight.toc`.
3. Edit `Questions.lua` in a text editor. Change the pack `id` and `title`, then replace the sample questions. Save it as UTF-8 without a BOM.
4. Enable both addons on the AddOns screen and reload. If the new pack does not appear on that screen, restart WoW so it can discover the new folder.
5. Open `/oq host` and select the registered pack.

Once installed, editing the contents of an already listed Lua file takes effect after `/reload`. If a new addon directory or TOC entry is not discovered, restart the game. Keep custom packs outside the core addon so a core update does not replace them.

The resulting folder layout is:

```text
Interface/AddOns/
  Orbit-Quiz/
    Orbit-Quiz.toc
    ...
  Orbit-Quiz-Pack-GuildNight/
    Orbit-Quiz-Pack-GuildNight.toc
    Questions.lua
```

The companion TOC:

```toc
## Interface: 120100
## Title: Orbit-Quiz: Guild Night
## Notes: Our guild's question pack.
## Author: Your name
## Version: 1.0
## Dependencies: Orbit-Quiz

Questions.lua
```

Do not set `LoadOnDemand`: packs should register during normal addon loading. To split a large companion addon into multiple files, list each file in its TOC. Either register a separate pack ID from each file, or collect questions in your addon's namespace and register one combined pack from a final file. There is no need to modify Orbit-Quiz's TOC.

## Question format

`Questions.lua` is a normal Lua file calling the public API:

```lua
OrbitQuiz:RegisterQuestionPack({
    id = "guild_night",
    title = "Guild Night",
    version = 1,
    author = "Your name",
    locale = "enUS",
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

`correctIndex` is the position of the correct answer **in the file**, starting at 1. The game can shuffle the choices and adjusts the answer mapping itself. Explanations must name the answer, not say "B is correct". Put `\"` inside a double-quoted Lua string when the text itself needs a quotation mark; do not insert literal line breaks.

## Schema and limits

| Field | Contract |
| --- | --- |
| Pack `id` | Required, unique across all installed packs. 1-48 lowercase ASCII letters, digits, `_` or `-`; first character must be a letter or digit. `all` is reserved. |
| Pack `title` | Required plain text, up to 64 bytes. |
| Pack `version` | Positive integer up to 2147483647; defaults to 1. Bump it when publishing revised content. It does not replace another registered pack with the same ID. |
| Pack `author` | Optional plain text, up to 64 bytes. |
| Pack `locale` | Defaults to `enUS`. Accepted: `enUS`, `enGB`, `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`. Metadata describing the questions, not automatic translation. |
| Pack `questions` | Required consecutive array of 1-2,000 questions, with no gaps or named entries. |
| Question `id` | Required, unique within its pack. Same character/length rules as pack IDs. |
| Question `prompt` | Required plain text, up to 160 bytes. |
| Question `choices` | Four to six consecutive non-empty plain-text strings, each up to 100 bytes. Choices must differ after trimming and ignoring ASCII letter case. |
| Question `correctIndex` | Required integer from 1 to the number of choices in that question. |
| Question `explanation` | Optional plain text, up to 160 bytes. |
| Question `category` | Optional plain text, up to 64 bytes. Descriptive metadata; it does not create a separate pack. |
| Question `difficulty` | Optional `easy`, `medium`, `hard`, or `very_hard`. Retained as metadata, not displayed on the Q/A widget; it does not change scoring. |
| Question `era` | Optional plain text, up to 64 bytes, naming the expansion, game, or work. Retained as metadata, not displayed on the Q/A widget. |
| Question `source` | Optional HTTPS URL, up to 512 bytes, without spaces, controls, or markup. Retained for content review on the host; never sent with a live question. |

All pack, question, and array tables must be ordinary tables without metatables. Extra, unrecognized record fields are ignored and never copied into the registry. Empty strings are not valid optional values; omit the field instead.

Text limits are **UTF-8 bytes**, not visible character counts, to bound addon-message payloads. Leading and trailing ASCII spaces are removed. Control characters, `|` characters, and `{`/`}` braces are rejected, preventing links, colors, textures, and raid-icon escape markup in question text. Keep each question self-contained and short enough to read within the answer window.

Give each new question a stable ID. Rearranging a pack must not change IDs. Correcting a typo can keep the same ID; replacing a question with a different one needs a new ID. The registry's normalized key is `packId:questionId`. Personal scores belong to the stable pack ID, not its title: bumping the content version retains progress, while a genuinely different quiz needs its own ID. All packs games credit each question's originating pack.

Packs retain the language of their files. Installing a French pack does not translate an English pack, and the combined `all` pool includes every installed pack regardless of locale. Choose an individual pack when running a single-language quiz.

Existing four-choice packs need no changes. A pack can mix four-, five-, and six-choice questions. The widget shows one clickable text line per answer (wrapping when needed), with the same fifteen-second clock, three-second reveal and scoring at every difficulty. Explanations remain in the pack/result data but are not displayed on this text-only widget. Add `difficulty`, `era`, and `source` when authoring reviewed content; they are mandatory editorial fields for the bundled Warcraft Lore pack, but optional in the public API.

The bundled pack is split by era/work for maintenance, then registered as one `warcraft-lore` pack. See [Packs/SOURCES.md](Packs/SOURCES.md) for its scope, continuity rules, and source-review process. Keep additions of your own in a companion addon so an update cannot overwrite them.

## Validation and troubleshooting

Registration is atomic: a malformed question rejects the entire pack, and a duplicate pack never replaces the first one. A rejected pack is not offered to the host. The registry returns `false, errorMessage` on failure and retains contextual errors for the host; valid registration returns `true`.

The public API is:

```lua
local ok, errorMessage = OrbitQuiz:RegisterQuestionPack(pack)
local metadata = OrbitQuiz:GetQuestionPacks()
local questions, errorMessage = OrbitQuiz:GetQuestions("guild_night")
local everyQuestion = OrbitQuiz:GetQuestions("all")
local errors = OrbitQuiz:GetPackErrors()
```

Metadata is sorted by title, then ID, and includes `id`, `title`, `version`, `author`, `locale`, and `count`. Question reads return fresh copies, including their `choices` arrays and normalized `packId`, `packTitle` and `packVersion`. Mutating an original pack table or a returned question cannot change the stored registry. Unknown packs return `nil, errorMessage`.

For a missing pack, check that the folder is directly under `Interface/AddOns`, its TOC basename matches the folder, it is enabled, and its listed Lua filename matches the actual file. Type `/oq packs` to list registered packs and validation errors. Lua syntax/runtime errors happen before registration and appear in WoW's normal error reporting or BugSack; the registry cannot recover a file that never executed.

Question content is **not** stored in SavedVariables. Updating or removing a pack changes future question pools, not the already-awarded league points. There is no online pack synchronization or download system.

## Trust boundary

A companion pack is executable Lua addon code. Install only packs from authors you trust, and inspect unfamiliar files. Schema validation protects the quiz's data shape; it does **not** sandbox a malicious addon or make arbitrary downloaded Lua safe.
