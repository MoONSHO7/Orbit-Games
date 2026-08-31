# SharedMedia libraries

## Description

Unmodified LibStub, CallbackHandler-1.0 and LibSharedMedia-3.0 copies for standalone font discovery.

## Purpose

Orbit-Quiz shares the normal global SharedMedia registry with installed media addons without requiring Orbit or a separate library installation.

## Implementation

The addon TOC loads LibStub, CallbackHandler and LibSharedMedia in that order before first-party modules. `../Media.lua` owns font lookup and registration notifications; `../Widget.lua` owns rendering. `.pkgmeta` pins the upstream sources used for packaged releases.

## Gotchas

- These are vendored sources, copied from the workspace's pinned library snapshots. Do not edit or reformat them; update the upstream pin and copy together.
- Preserve the upstream headers and licenses: LibStub is public domain; LibSharedMedia is LGPL 2.1. No font files are bundled here; the registry contains native fonts and fonts registered by installed addons.
- LibStub version arbitration reuses compatible existing libraries. Never replace the global registry or mutate its font tables.

## References

- `../.pkgmeta` — immutable source revisions and upstream locations.
- `../README.md` — addon startup and Q/A appearance data flow.
