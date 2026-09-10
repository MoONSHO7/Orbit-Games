# Your own Orbit-Games Quiz pack

## Description

A complete independently installable Quiz companion addon. It supplies three sample questions and authored rules, with Orbit-Games as its only dependency.

## Purpose

Create, maintain and distribute Quiz content without modifying or forking the framework.

## Implementation

The TOC declares `## Dependencies: Orbit-Games`, so WoW loads the framework before [Questions.lua](Questions.lua) calls `OrbitGames.Quiz:RegisterPack`. Orbit-Games owns hosting, transport, the Quiz HUD and saved scores; this addon owns its pack.

1. Copy this folder into a separate project.
2. Rename the folder and `Orbit-Games-Quiz-Pack-Example.toc` to the same addon name, such as `MyGuild-Trivia`.
3. Edit the TOC metadata while keeping `## Dependencies: Orbit-Games` and `Questions.lua`.
4. Replace the pack `id`, `title`, `author`, rules and questions. Keep the ID stable after release.
5. With WoW closed, install Orbit-Games and place the finished folder beside it under `Interface/AddOns/`.
6. Launch WoW, enable both addons, then open `/og` and select Host or use `/og packs` to go there directly. Select the pack there and read any validation failure from its notice lane.

A finished installation looks like:

```text
Interface/AddOns/
  Orbit-Games/
    Orbit-Games.toc
    ...
  MyGuild-Trivia/
    MyGuild-Trivia.toc
    Questions.lua
    README.md
```

Zip only the companion folder for distribution. Tell hosts to install Orbit-Games separately; participants need Orbit-Games but not the host's pack.

The sample rules match Warcraft Lore, including its capped consecutive-correct bonus.

## Gotchas

- WoW does not load this template while it remains nested under `Dev/Examples/`.
- Folder and TOC basenames must match.
- Use `OrbitGames.Quiz:RegisterPack`, not this addon's private `...` namespace.
- Correct answers are one-based original-choice indices; Quiz remaps them when choices shuffle.
- Questions require stable IDs and four to six distinct choices.
- Change `rules.version` when authored rules change. Distinct normalized rules keep separate history even if the revision is reused.
- Restart WoW to discover a new addon folder. Existing listed Lua edits need only `/reload` and a new Quiz game.

## References

- [Questions.lua](Questions.lua) — complete editable pack.
- [Quiz pack contract](../../../Docs/PACKS.md).
