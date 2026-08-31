# Your own Orbit-Quiz pack addon

## Description

A complete, independently installable quiz addon template. It supplies three sample questions and author-defined rules, with Orbit-Quiz as its only required dependency.

## Purpose

Create, maintain and distribute your quiz in your own project. No fork, pull request, contribution to Orbit-Quiz, or core-addon file edits are required.

## Implementation

The TOC declares `## Dependencies: Orbit-Quiz`, so WoW loads the framework first. [Questions.lua](Questions.lua) then calls the public `OrbitQuiz:RegisterQuestionPack` API. Orbit-Quiz handles the widget, hosting, answers and saved scores; this addon owns its questions and rules.

1. Copy **this folder only** into a separate project directory or your own repository. Do not author your quiz inside Orbit-Quiz.
2. Rename the folder to your addon's name, for example `MyGuild-Trivia`, and rename `Orbit-Quiz-Pack-Example.toc` to `MyGuild-Trivia.toc`.
3. Edit the TOC's Title, Notes, Author and Version. Keep `## Dependencies: Orbit-Quiz` and the `Questions.lua` entry. Your addon name does not need an `Orbit-Quiz-` prefix.
4. In `Questions.lua`, replace the example's `id`, `title` and `author` with your own. Use a unique ID such as `myguild_trivia`, then replace the sample questions and adjust the `rules` table.
5. With WoW closed, install Orbit-Quiz and copy your pack folder beside it in `World of Warcraft/_retail_/Interface/AddOns/`. Launch WoW and enable both addons.
6. Open `/oq host` and select your quiz. `/oq packs` lists it and reports registration errors. Only the host needs the pack; participants need just Orbit-Quiz.

Your finished pack is its own addon:

```text
Interface/AddOns/
  Orbit-Quiz/
    Orbit-Quiz.toc
    ...
  MyGuild-Trivia/
    MyGuild-Trivia.toc
    Questions.lua
    README.md
```

To distribute it, zip only your pack folder with its TOC and Lua files directly inside. Publish that archive independently and tell hosts to install Orbit-Quiz separately. Do not bundle the framework or its libraries. Replace this README with your quiz's description and installation instructions before publishing.

The sample rules match Warcraft Lore, including the consecutive-correct bonus (+0.1 per step after the first, capped at +0.5). Hosts select the quiz but cannot override the rules you define.

## Gotchas

- The example lives in the core repository only as a template; WoW does not load a pack nested inside another addon's development folder.
- Keep the folder name and TOC basename identical. Keep your chosen pack `id` stable after publishing so content updates retain progress.
- Use the public `OrbitQuiz` global, not the `...` namespace of this addon. A required dependency supplies load order; no registration hook or changes to Orbit-Quiz's TOC are needed.
- Correct answers are one-based indices into the original choices; the quiz engine updates the answer mapping when it shuffles choices.
- Each question needs a stable unique ID and four to six distinct choices. A rejected pack is excluded completely; inspect `/oq packs` for the failing field.
- Unknown rule names reject the pack. Change the rule revision when publishing rule changes; different resolved rules keep separate score totals even if a revision is reused. Editing files takes effect after reload/new game.
- Restart WoW to detect a newly installed addon folder. Existing loaded Lua edits need only `/reload` and a new quiz session.

## References

- [Questions.lua](Questions.lua) — editable metadata, complete rules and sample questions.
- `OrbitQuiz:RegisterQuestionPack` — public framework API; no private core files are imported.
