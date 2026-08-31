"""Execute the real addon modules and regression suites in a Lua 5.1 runtime."""

from fnmatch import fnmatchcase
from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "Dev" / "Tests"
PREVIEW = "Dev/Preview.lua"
ADDON_ICON = "Assets/Orbit.png"
STREAK_SOUNDS = ("dominating.mp3", "ownage.mp3", "rampage.mp3", "wicked-sick.mp3", "holyshit.mp3", "godlike.mp3")
LOCALES = ("enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW")


def load(lua, path, namespace=None, addon_name="Orbit-Quiz"):
    code = path.read_text(encoding="utf-8")
    chunk = lua.eval("function(source, name) return assert(loadstring(source, name)) end")(
        code, "@" + str(path)
    )
    return chunk(addon_name, namespace) if namespace is not None else chunk()


def toc_scripts(development=True):
    scripts = []
    development_block = False
    for line in (ROOT / "Orbit-Quiz.toc").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line == "#@do-not-package@":
            if development_block:
                raise AssertionError("Nested development-only TOC block")
            development_block = True
        elif line == "#@end-do-not-package@":
            if not development_block:
                raise AssertionError("Unmatched development-only TOC block terminator")
            development_block = False
        elif line and not line.startswith("#") and (development or not development_block):
            scripts.append(line.replace("\\", "/"))
    if development_block:
        raise AssertionError("Unclosed development-only TOC block")
    return scripts


def runtime(locale="enUS", host_name="Quizhost", realm="TestRealm", development=True):
    lua = LuaRuntime(unpack_returned_tuples=True)
    load(lua, TESTS / "Stubs.lua")
    lua.globals().Test.locale = locale
    lua.globals().Test.hostName = host_name
    lua.globals().Test.realm = realm
    namespace = lua.table()
    for script in toc_scripts(development):
        path = ROOT / script
        if not path.is_file():
            raise AssertionError(f"Missing TOC file: {path}")
        load(lua, path, namespace)
    lua.globals().Test.Initialize()
    return lua, namespace


def main():
    toc = (ROOT / "Orbit-Quiz.toc").read_text(encoding="utf-8")
    metadata = {}
    for line in toc.splitlines():
        if line.startswith("## "):
            key, _, value = line[3:].partition(":")
            metadata[key.strip()] = value.strip()
    if metadata.get("Category") != "Orbit UI":
        raise AssertionError("The addon-list category must remain Orbit UI")
    icon_texture = "Interface\\AddOns\\Orbit-Quiz\\" + ADDON_ICON.replace("/", "\\")
    if metadata.get("IconTexture") != icon_texture:
        raise AssertionError("The addon-list icon must use Orbit-Quiz's bundled logo")
    if not (ROOT / ADDON_ICON).read_bytes().startswith(b"\x89PNG\r\n\x1a\n"):
        raise AssertionError("The bundled addon-list logo must be a PNG asset")
    scripts = toc_scripts()
    packaged_scripts = toc_scripts(development=False)
    if scripts.count(PREVIEW) != 1 or scripts[-1] != PREVIEW:
        raise AssertionError("The source-only preview must load exactly once after the runtime")
    if PREVIEW in packaged_scripts or set(scripts) - set(packaged_scripts) != {PREVIEW}:
        raise AssertionError("Only the development fixture must be omitted from the packaged TOC")
    from Lore import package_ignore_entries

    ignored = package_ignore_entries()
    if any(fnmatchcase(path, pattern) for path in ("Assets", ADDON_ICON) for pattern in ignored):
        raise AssertionError("Release archives must include the bundled addon-list logo")
    print("Addon-list branding: Orbit UI category and bundled logo passed")
    for sound in STREAK_SOUNDS:
        original = Path("Assets/Sounds") / sound
        variants = [original] + [
            original.parent / "Volume" / f"{original.stem}-{volume}.ogg"
            for volume in range(10, 100, 10)
        ]
        for relative in variants:
            path = ROOT / relative
            if not path.is_file() or path.stat().st_size == 0:
                raise AssertionError(f"Missing bundled streak sound: {relative}")
            if relative.suffix == ".ogg" and not path.read_bytes().startswith(b"OggS"):
                raise AssertionError(f"Invalid volume-variant audio: {relative}")
            if any(fnmatchcase(parent.as_posix(), pattern)
                   for parent in (relative, *relative.parents) for pattern in ignored):
                raise AssertionError(f"Release archives must include streak sound: {relative}")
    print("Streak audio: six original clips and all 54 volume variants survive packaging exclusions")
    if "Dev" not in ignored:
        raise AssertionError("Release archives must exclude all development tools, tests and examples")
    if any(ROOT.rglob("Chat.lua")):
        raise AssertionError("The retired visible-chat transport must not ship or load")
    identity = "Network/Identity.lua"
    if identity not in scripts or any(scripts.index(identity) >= scripts.index(consumer)
                                      for consumer in ("Network/Transport.lua", "Network/Session.lua", "App/Runtime.lua")):
        raise AssertionError("Native identity must load before addon communication and session consumers")
    if list(ROOT.glob("*.lua")):
        raise AssertionError("Runtime Lua belongs in its owning module, not the addon root")
    if len(scripts) != len(set(scripts)):
        raise AssertionError("TOC scripts must load exactly once")
    runtime_files = {path.relative_to(ROOT).as_posix()
                     for folder in ("App", "Game", "Data", "Network", "UI")
                     for path in (ROOT / folder).rglob("*.lua")}
    loaded_runtime = {path for path in scripts if path.split("/", 1)[0] in ("App", "Game", "Data", "Network", "UI")}
    if runtime_files != loaded_runtime:
        raise AssertionError("Every runtime module must appear in the TOC with its exact case-sensitive path")
    if any(path.startswith("Dev/") for path in packaged_scripts):
        raise AssertionError("Development files must never load in packaged releases")
    for script in scripts:
        source = (ROOT / script).read_text(encoding="utf-8")
        for retired_api in ("SendChatMessage", "CHAT_MSG_CHANNEL"):
            if retired_api in source:
                raise AssertionError(f"Visible-chat API {retired_api} must not return in {script}")
    for line in toc.splitlines():
        key, separator, value = line.partition(":")
        if separator and key.strip().lower() in ("## dependencies", "## requireddeps", "## optionaldeps"):
            dependencies = value.replace(",", " ").split()
            if "orbit" in (dependency.lower() for dependency in dependencies):
                raise AssertionError("Orbit-Quiz must not depend on Orbit for its standalone styling")
    compiler = LuaRuntime(unpack_returned_tuples=True)
    compile_chunk = compiler.eval("function(source, name) return assert(loadstring(source, name)) end")
    paths = sorted(ROOT.rglob("*.lua"))
    for path in paths:
        content = path.read_bytes()
        if content.startswith(b"\xef\xbb\xbf"):
            raise AssertionError(f"UTF-8 BOM: {path}")
        compile_chunk(content.decode("utf-8"), "@" + str(path))
    print(f"Lua 5.1 syntax: {len(paths)} files passed")

    total = 0
    for suite in ("Rules.lua", "Scoring.lua", "Model.lua", "PersonalScores.lua", "Packs.lua", "Comms.lua", "Runtime.lua", "Session.lua", "Discovery.lua", "Interface.lua", "Appearance.lua", "SoundSettings.lua", "VisualStability.lua", "HUDPolish.lua", "ScrollingLabels.lua", "StreakToasts.lua", "HUDStreaks.lua", "Lore.lua"):
        lua, namespace = runtime()
        assertions = load(lua, TESTS / suite)(namespace)
        total += assertions
        if len(lua.globals().Test.errors):
            raise AssertionError(f"{suite}: unexpected WoW error handler calls")
        print(f"{suite}: {assertions} assertions passed")

    for suite in ("Development.lua", "ToastPreview.lua"):
        for development in (True, False):
            lua, namespace = runtime(development=development)
            assertions = load(lua, TESTS / suite)(namespace, development)
            total += assertions
            if len(lua.globals().Test.errors):
                raise AssertionError(f"{suite}: unexpected WoW error handler calls")
            flavor = "source-only preview" if development else "packaged addon without development code"
            print(f"{suite} ({flavor}): {assertions} assertions passed")

    lua, namespace = runtime()
    namespace.Development.ShowGames(namespace.Development)
    assert namespace.Development.enabled is True
    assert namespace.Development.ShowToasts(namespace.Development) is True
    assert namespace.Widget.streakPreview is not None
    reloaded_lua, reloaded_namespace = runtime()
    assert reloaded_namespace.Development.enabled is False
    assert reloaded_namespace.Development.games is None
    assert reloaded_namespace.UI.gamePreview is None
    assert reloaded_namespace.UI.frame is None
    assert reloaded_namespace.Widget.streakPreview is None
    assert reloaded_namespace.StreakToasts.frame is None
    total += 9
    print("Development preview: fresh runtimes reset all nonpersistent preview state")

    for locale in LOCALES:
        lua, namespace = runtime(locale)
        assertions = load(lua, TESTS / "Packs.lua")(namespace)
        total += assertions
    print(f"Pack validation: all {len(LOCALES)} locale codes passed")

    lua, namespace = runtime()
    from Lore import run_suite as run_lore_suite

    lore_assertions = run_lore_suite(namespace)
    total += lore_assertions
    print(f"Lore.py: {lore_assertions} catalogue assertions passed")

    from CompanionPack import run_suite as run_companion_suite

    companion_assertions = run_companion_suite()
    total += companion_assertions
    print(f"CompanionPack.py: {companion_assertions} standalone-addon assertions passed")
    from Network import run_suite

    network_assertions = run_suite()
    total += network_assertions
    print(f"Network.py: {network_assertions} paired-runtime assertions passed")
    print(f"PASS: {total} assertions; in-game validation is still required.")


if __name__ == "__main__":
    main()
