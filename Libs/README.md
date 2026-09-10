# Embedded libraries

## Description

Unmodified LibStub, CallbackHandler-1.0, LibSharedMedia-3.0, LibDataBroker-1.1 and LibDBIcon-1.0 copies for standalone fonts and minimap access.

## Purpose

Orbit-Games shares the normal SharedMedia and DataBroker registries with installed addons without requiring Orbit or separate library installations.

## Implementation

The TOC loads LibStub and CallbackHandler before DataBroker, DBIcon and SharedMedia. `../UI/Media.lua` owns font lookup and notifications; `../UI/Minimap.lua` supplies the launcher while DBIcon owns its button, dragging and private tooltip.

`.pkgmeta` pins SharedMedia dependencies. DBIcon minor 56 and DataBroker minor 4 are hard-embedded from official WowAce SVN revision 162. Their SHA-256 values are `85c426947fa50319071b64c7cb845326c44316341713a3847dc8149c1e36716b` and `f3d4758f2060215492c9764b1d7dc2a336826d4cd253cd54ff9ff7c6d78f04e2`.

## Gotchas

- Do not edit or reformat vendored sources. Update each copy and its recorded upstream revision together.
- Preserve upstream headers and licences. LibStub is public domain, LibSharedMedia is LGPL 2.1, and DBIcon retains its published Ace3-style BSD notice.
- LibStub version arbitration reuses compatible existing libraries. Never replace global registries, mutate SharedMedia font tables or freeze a DataBroker proxy as ordinary saved data.

## References

- `../.pkgmeta` — immutable source revisions and package metadata.
- [DBIcon source](https://repos.wowace.com/wow/libdbicon-1-0/!svn/bc/162/trunk/LibDBIcon-1.0/LibDBIcon-1.0.lua), [DataBroker source](https://repos.wowace.com/wow/libdbicon-1-0/!svn/bc/162/trunk/LibDataBroker-1.1/LibDataBroker-1.1.lua) and [DBIcon licence](https://www.wowace.com/project/15552/license).
