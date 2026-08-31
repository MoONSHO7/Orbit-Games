# GitHub Actions

## Description

Validation, automatic alpha-version tagging, and CurseForge/GitHub prereleases for Orbit-Quiz.

## Purpose

Every push to `main` can publish the tested commit without a manual version bump. Pull requests run the same checks without release credentials.

## Implementation

`checks.yml` handles pull requests and reusable calls. It checks out the requested immutable SHA, runs StyLua 2.3.1 using the repository's `.stylua.toml`, and runs `Dev/Tests/run.py` with Python 3.12 and Lupa 2.8's Lua 5.1 runtime.

`auto-tag.yml` handles every `main` push, including workflow-only changes. After checks pass, its serialized tag job checks out that same SHA with `ORBIT_PAT`. Alpha tags are strictly `MAJOR.MINOR-alpha`: the first is `1.0-alpha`, then MINOR increases from the highest alpha tag. Reruns and older commits already covered by an alpha tag do not create another version; divergent release history fails instead of guessing.

`release.yml` handles numeric-looking `-alpha` tag pushes and reuses the checks for the tagged SHA. It requires an unchanged strict alpha tag on `main` history and skips tags superseded by a newer alpha version. It stamps `App/Init.lua`'s runtime version only in the runner checkout, then BigWigs packager resolves the TOC's `@project-version@`, builds `Orbit-Quiz`, and uploads to CurseForge project `1676376` as Alpha and GitHub as a prerelease. The tag suffix determines both release channels; no packager override is needed.

`.pkgmeta` owns bundled-library pins and package exclusions. Development previews, tests, example addons, archived comic packs, workflow files, and local build/configuration artifacts stay out of releases. The runtime source and existing license remain intact.

Repository secret `ORBIT_PAT` authenticates only the tag checkout/push. It must be allowed to create tags in this repository; a default `GITHUB_TOKEN` tag push would not start the release workflow. `CURSE_API_KEY` is exported as `CF_API_KEY` only for packaging. The packager receives the job's write-scoped `GITHUB_TOKEN` as `GITHUB_OAUTH` for GitHub release assets.

## Gotchas

- Both checks and packaging use the event's SHA, never whatever `main` points at later. `main` is the remote branch; a local branch called `Main` must be pushed to it explicitly.
- Tag creation and packaging have separate non-cancelling queues. Ancestry and superseded-tag checks prevent delayed runs from tagging old code or publishing an older version after a newer one.
- A failed check creates no automatic tag. If packaging fails after tagging, rerun the failed Release AddOn workflow; rerunning Auto Tag will correctly skip the already-tagged commit.
- Missing/expired `ORBIT_PAT` prevents tagging; a token unable to trigger workflows leaves a tag without a release run. A failed CurseForge upload can require checking `CURSE_API_KEY` or the project's approval/status.
- Only strict `MAJOR.MINOR-alpha` tags publish, including manual tags. Stable, beta, and malformed tags cannot publish through this workflow. Enabling stable releases later requires deliberately updating both workflows' tag policy; there is no manual-dispatch release path.
- Local validation does not upload files or prove that either repository secret has the required remote permissions.

## References

- [Addon README](../../README.md), [offline checks](../../Dev/Tests/README.md), and [package metadata](../../.pkgmeta).
- [BigWigs packager v2](https://github.com/BigWigsMods/packager/tree/v2) and its [Actions workflow guide](https://github.com/BigWigsMods/packager/wiki/GitHub-Actions-workflow).
- [Triggering workflows with a PAT](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow).
- [GitHub concurrency queues](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency).
