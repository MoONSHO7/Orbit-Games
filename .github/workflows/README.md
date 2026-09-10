# GitHub Actions

## Description

Validation, automatic alpha tagging and CurseForge/GitHub prereleases for Orbit-Games.

## Purpose

Every push to `main` can publish the tested commit without a manual source-version edit. Pull requests run the same checks without release credentials.

## Implementation

`checks.yml` validates an immutable SHA with Python 3.12, Lupa's Lua 5.1 runtime and StyLua 2.3.1.

`auto-tag.yml` validates each `main` push, then creates the next strict `MAJOR.MINOR-alpha` tag with `ORBIT_PAT`. Reruns skip commits already covered by an alpha tag; divergent tag history fails.

`release.yml` revalidates the tagged SHA, ensures it belongs to `main`, stamps `Games.version` in `App/Init.lua` only in the runner checkout, then packages Orbit-Games for CurseForge project `1676376` and a GitHub prerelease.

`.pkgmeta` packages the single `Orbit-Games` addon. Development files, tests and the comic archive remain excluded.

`CURSE_API_KEY` becomes `CF_API_KEY` only for packaging. The job's write-scoped `GITHUB_TOKEN` becomes `GITHUB_OAUTH` for release assets.

## Gotchas

- Checks and packaging use the event SHA, never a later `main` head.
- Tag and package jobs use separate non-cancelling `orbit-games-release-*` queues.
- A failed check creates no tag. A failed package after tagging should be rerun from Release AddOn.
- Only strict `MAJOR.MINOR-alpha` tags publish. Stable and beta channels require an explicit workflow policy change.
- Local validation does not upload or prove repository-secret permissions.

## References

- [Addon README](../../README.md), [offline checks](../../Dev/Tests/README.md), [package metadata](../../.pkgmeta) and [BigWigs packager v2](https://github.com/BigWigsMods/packager/tree/v2).
