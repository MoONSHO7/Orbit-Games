# Orbit-Quiz Example Pack

## Description

A three-question companion addon that can be copied and customized.

## Purpose

Demonstrate file-based question packs that survive updates to the core addon.

## Implementation

The matching TOC's `Dependencies: Orbit-Quiz` ensures the public registry is available before `Questions.lua` calls `OrbitQuiz:RegisterQuestionPack`. The example pack becomes a separate choice in the host panel after normal addon loading.

## Gotchas

- Install this folder beside `Orbit-Quiz`, not inside it.
- Keep the folder name and TOC basename identical. Change the Lua pack `id` when copying this example into a different pack.
- Correct answers are one-based indices into the original choices; the quiz engine updates the answer mapping when it shuffles choices.
- A rejected pack is excluded completely; inspect the core addon's pack errors for the failing field.

## References

- Orbit-Quiz's `PACKS.md` — full authoring guide.
