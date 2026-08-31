# Guides

## Description

Player setup and question-pack authoring guides.

## Purpose

Keep user-facing instructions separate from module maintenance contracts.

## Implementation

[QUICKSTART.md](QUICKSTART.md) covers hosting, joining, appearance, saved progress and verification. [PACKS.md](PACKS.md) gives complete files for an independently distributed addon, its required Orbit-Quiz dependency, the public schema, rule identities and validation errors.

## Gotchas

- Module data flow and implementation traps belong in the owning module's README.
- Commands in these guides are run from the addon root unless stated otherwise. Development tests/templates are source-only, but the pack guide includes everything needed to author a companion addon against an installed release without a core checkout.

## References

- [Project map](../README.md), [development tools](../Dev/README.md), and [bundled content provenance](../Packs/WarcraftLore/SOURCES.md).
