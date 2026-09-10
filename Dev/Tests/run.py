"""Execute the real addon modules and regression suites in a Lua 5.1 runtime."""

from fnmatch import fnmatchcase
import math
from pathlib import Path
import re
from runpy import run_path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2]
TESTS = ROOT / "Dev" / "Tests"
ADDON_NAME = "Orbit-Games"
ADDON_TOC = ROOT / "Orbit-Games.toc"
COMPATIBILITY_LOADER = ROOT / "Compatibility" / "Orbit-Quiz" / "Loader.lua"
COMPATIBILITY_TOC = ROOT / "Compatibility" / "Orbit-Quiz" / "Orbit-Quiz.toc"
PREVIEW = "Dev/Preview.lua"
ADDON_ICON = "Assets/Orbit.png"
CARD_ASSETS = (
    "Assets/Cards/PlayingCards.png",
    "Assets/Cards/PlayingCards.json",
    "Assets/Cards/LICENSE.playing-cards-assets",
)
MINIMAP_SCRIPTS = (
    "Libs/LibDataBroker-1.1/LibDataBroker-1.1.lua",
    "Libs/LibDBIcon-1.0/LibDBIcon-1.0.lua",
    "UI/Minimap.lua",
)
STREAK_SOUNDS = ("dominating.mp3", "ownage.mp3", "rampage.mp3", "wicked-sick.mp3", "holyshit.mp3", "godlike.mp3")
LOCALES = ("enUS", "enGB", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW")
VISIBLE_CHAT_PATTERNS = {
    "Games:Print": re.compile(r"\bGames\s*:\s*Print\s*\("),
    "chat frame": re.compile(r"\b(?:DEFAULT_CHAT_FRAME|SELECTED_CHAT_FRAME|ChatFrame\d*)\b"),
    "global print": re.compile(r"(?<![\w.:])print\s*\("),
    "SendChatMessage": re.compile(r"\bSendChatMessage\b"),
    "CHAT_MSG_CHANNEL": re.compile(r"\bCHAT_MSG_CHANNEL\b"),
}


def load(lua, path, namespace=None, addon_name=ADDON_NAME):
    code = path.read_text(encoding="utf-8")
    chunk = lua.eval("function(source, name) return assert(loadstring(source, name)) end")(
        code, "@" + str(path)
    )
    return chunk(addon_name, namespace) if namespace is not None else chunk()


def toc_scripts(development=True):
    scripts = []
    development_block = False
    for line in ADDON_TOC.read_text(encoding="utf-8").splitlines():
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


def plain(value):
    if not hasattr(value, "items"):
        return value
    items = list(value.items())
    keys = [key for key, _ in items]
    if keys and all(isinstance(key, int) for key in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
        by_key = dict(items)
        return [plain(by_key[index]) for index in range(1, len(keys) + 1)]
    return {key: plain(child) for key, child in items}


def runtime(
        locale="enUS", host_name="Quizhost", realm="TestRealm", development=True, saved=None,
        legacy_saved=None):
    lua = LuaRuntime(unpack_returned_tuples=True)
    load(lua, TESTS / "Stubs.lua")
    lua.globals().Test.locale = locale
    lua.globals().Test.hostName = host_name
    lua.globals().Test.realm = realm
    if saved is not None:
        lua.globals().OrbitGamesDB = lua.table_from(saved, recursive=True)
    if legacy_saved is not None:
        lua.globals().OrbitQuizDB = lua.table_from(legacy_saved, recursive=True)
    games = lua.table()
    for script in toc_scripts(development):
        path = ROOT / script
        if not path.is_file():
            raise AssertionError(f"Missing TOC file: {path}")
        load(lua, path, games)
    lua.globals().Test.Initialize()
    if legacy_saved is not None:
        minimap = games.Store.GetMinimapSettings(games.Store)
        load(lua, COMPATIBILITY_LOADER, addon_name="Orbit-Quiz")
        same = lua.eval("rawequal")
        if not same(minimap, games.Store.GetMinimapSettings(games.Store)):
            raise AssertionError("Compatibility import must retain the root minimap table used by LibDBIcon")
    return lua, games


def main():
    toc = ADDON_TOC.read_text(encoding="utf-8")
    metadata = {}
    for line in toc.splitlines():
        if line.startswith("## "):
            key, _, value = line[3:].partition(":")
            metadata[key.strip()] = value.strip()
    if metadata.get("Title") != ADDON_NAME:
        raise AssertionError("The primary addon identity must be Orbit-Games")
    if metadata.get("SavedVariables") != "OrbitGamesDB":
        raise AssertionError("The primary addon must persist only the generic OrbitGamesDB root")
    if metadata.get("Category") != "Orbit UI":
        raise AssertionError("The addon-list category must remain Orbit UI")
    icon_texture = "Interface\\AddOns\\Orbit-Games\\" + ADDON_ICON.replace("/", "\\")
    if metadata.get("IconTexture") != icon_texture:
        raise AssertionError("The addon-list icon must use Orbit-Games' bundled logo")
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
    minimap_order = ["Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua", *MINIMAP_SCRIPTS, "App/Runtime.lua"]
    if any(script not in packaged_scripts for script in minimap_order):
        raise AssertionError("Release TOCs must load the embedded minimap libraries and launcher")
    if [packaged_scripts.index(script) for script in minimap_order] != sorted(
            packaged_scripts.index(script) for script in minimap_order):
        raise AssertionError("Broker, minimap library and launcher must load before application initialization")
    for script in MINIMAP_SCRIPTS:
        relative = Path(script)
        if any(fnmatchcase(parent.as_posix(), pattern)
               for parent in (relative, *relative.parents) for pattern in ignored):
            raise AssertionError(f"Release archives must include minimap dependency: {relative}")
    required_assets = ("Assets", ADDON_ICON, "Assets/Cards", *CARD_ASSETS)
    if any(fnmatchcase(path, pattern) for path in required_assets for pattern in ignored):
        raise AssertionError("Release archives must include bundled logo and playing-card assets")
    print("Addon-list branding: Orbit UI category and bundled logo passed")
    for sound in STREAK_SOUNDS:
        relative = Path("Assets/Sounds") / sound
        path = ROOT / relative
        if not path.is_file() or path.stat().st_size == 0:
            raise AssertionError(f"Missing bundled streak sound: {relative}")
        if any(fnmatchcase(parent.as_posix(), pattern)
               for parent in (relative, *relative.parents) for pattern in ignored):
            raise AssertionError(f"Release archives must include streak sound: {relative}")
    print("Streak audio: six original MP3s survive packaging exclusions")
    card_builder = run_path(str(ROOT / "Dev" / "Assets" / "BuildCardAtlas.py"))
    card_builder["check"]()
    if "Dev" not in ignored:
        raise AssertionError("Release archives must exclude all development tools, tests and examples")
    for path in (ROOT / "Dev").rglob("*"):
        if path.is_file():
            relative = path.relative_to(ROOT)
            if not any(fnmatchcase(parent.as_posix(), pattern)
                       for parent in (relative, *relative.parents) for pattern in ignored):
                raise AssertionError(f"Development file can enter the release archive: {relative}")
    pkgmeta = (ROOT / ".pkgmeta").read_text(encoding="utf-8")
    if "Orbit-Games/Compatibility/Orbit-Quiz: Orbit-Quiz" not in pkgmeta:
        raise AssertionError("The release must move the legacy compatibility loader into a sibling addon")
    compatibility_metadata = {}
    for line in COMPATIBILITY_TOC.read_text(encoding="utf-8").splitlines():
        if line.startswith("## "):
            key, _, value = line[3:].partition(":")
            compatibility_metadata[key.strip()] = value.strip()
    if compatibility_metadata.get("Dependencies") != ADDON_NAME:
        raise AssertionError("The compatibility addon must load after Orbit-Games")
    if compatibility_metadata.get("SavedVariables") != "OrbitQuizDB":
        raise AssertionError("The compatibility addon must load only the legacy SavedVariable")
    if any(ROOT.rglob("Chat.lua")):
        raise AssertionError("The retired visible-chat transport must not ship or load")
    identity = "Network/Identity.lua"
    if identity not in scripts or any(scripts.index(identity) >= scripts.index(consumer)
                                      for consumer in (
                                          "Network/Transport.lua", "Modes/Quiz/Network/Session.lua", "App/Runtime.lua")):
        raise AssertionError("Native identity must load before addon communication and session consumers")
    if list(ROOT.glob("*.lua")):
        raise AssertionError("Runtime Lua belongs in its owning module, not the addon root")
    if len(scripts) != len(set(scripts)):
        raise AssertionError("TOC scripts must load exactly once")
    runtime_folders = ("App", "Core", "Data", "Modes", "Network", "UI")
    runtime_files = {
        path.relative_to(ROOT).as_posix()
        for folder in runtime_folders
        for path in (ROOT / folder).rglob("*.lua")
        if "/Archive/" not in path.relative_to(ROOT).as_posix()
    }
    loaded_runtime = {path for path in scripts if path.split("/", 1)[0] in runtime_folders}
    if runtime_files != loaded_runtime:
        raise AssertionError("Every runtime module must appear in the TOC with its exact case-sensitive path")
    if any(path.startswith("Dev/") for path in packaged_scripts):
        raise AssertionError("Development files must never load in packaged releases")
    for script in packaged_scripts:
        relative = Path(script)
        if any(fnmatchcase(parent.as_posix(), pattern)
               for parent in (relative, *relative.parents) for pattern in ignored):
            raise AssertionError(f"Packaged TOC script is excluded by .pkgmeta: {relative}")
    first_party_scripts = [script for script in scripts if not script.startswith("Libs/")]
    first_party_scripts.append(COMPATIBILITY_LOADER.relative_to(ROOT).as_posix())
    for script in first_party_scripts:
        source = (ROOT / script).read_text(encoding="utf-8")
        for label, pattern in VISIBLE_CHAT_PATTERNS.items():
            if pattern.search(source):
                raise AssertionError(f"Visible-chat output {label} must not return in {script}")
    print("Release boundary: Dev is excluded and every packaged TOC script survives .pkgmeta")
    print("Visible chat: production, compatibility and source-preview scripts contain no output sink")
    for line in toc.splitlines():
        key, separator, value = line.partition(":")
        if separator and key.strip().lower() in ("## dependencies", "## requireddeps", "## optionaldeps"):
            dependencies = value.replace(",", " ").split()
            if "orbit" in (dependency.lower() for dependency in dependencies):
                raise AssertionError("Orbit-Games must not depend on Orbit for its standalone styling")
    compiler = LuaRuntime(unpack_returned_tuples=True)
    compile_chunk = compiler.eval("function(source, name) return assert(loadstring(source, name)) end")
    paths = sorted(ROOT.rglob("*.lua"))
    for path in paths:
        content = path.read_bytes()
        if content.startswith(b"\xef\xbb\xbf"):
            raise AssertionError(f"UTF-8 BOM: {path}")
        compile_chunk(content.decode("utf-8"), "@" + str(path))
    print(f"Lua 5.1 syntax: {len(paths)} files passed")

    lua, games = runtime(development=False)
    if games.Print is not None:
        raise AssertionError("The packaged runtime must expose no visible-chat output helper")
    globals_ = lua.globals()
    if globals_.SLASH_ORBITGAMES1 != "/orbitgames" or globals_.SLASH_ORBITGAMES2 != "/og":
        raise AssertionError("Orbit-Games must own the generic slash-command aliases")
    if globals_.SlashCmdList.ORBITGAMES is None or globals_.SlashCmdList.ORBITQUIZ is not None:
        raise AssertionError("Only the Orbit-Games runtime command handler may be registered")

    current = plain(games.Store.db)
    legacy = plain(games.Quiz.Store.db)
    legacy["schemaVersion"] = 6
    legacy["minimap"] = {"minimapPos": 37.5, "hide": True, "lock": False, "showInCompartment": True}
    migrated_lua, migrated = runtime(development=False, legacy_saved=legacy)
    migrated_db = migrated_lua.globals().OrbitGamesDB
    if migrated_lua.globals().OrbitQuizDB is not None:
        raise AssertionError("Successful Orbit-Quiz migration must retire the legacy SavedVariable")
    if not migrated.Store.importedModeData or migrated_db.schemaVersion != 1:
        raise AssertionError("The compatibility addon must import legacy Quiz data into the generic root store")
    if migrated_db.modes.quiz.schemaVersion != 7 or migrated_db.minimap.minimapPos != 37.5:
        raise AssertionError("Legacy Quiz state must land in modes.quiz while minimap state remains root-owned")
    compatibility = migrated_lua.globals().OrbitQuiz
    legacy_api = (
        "RegisterQuestionPack", "RegisterPack", "GetQuestionPacks", "GetPackRules", "GetQuestions", "GetPackErrors",
    )
    if any(compatibility[name] is None for name in legacy_api):
        raise AssertionError("The compatibility addon must retain the complete documented legacy pack API")

    invalid_legacy = dict(legacy)
    invalid_legacy["schemaVersion"] = 999
    failed_lua, failed = runtime(development=False, legacy_saved=invalid_legacy)
    if failed_lua.globals().OrbitGamesDB is not None or failed_lua.globals().OrbitQuizDB is None:
        raise AssertionError("A failed legacy import must remain retryable without replacing the old SavedVariable")
    if failed.Main.initialized or failed.Comms.initialized or failed.Discovery.initialized:
        raise AssertionError("A failed legacy import must disable the partially initialized new runtime")

    existing_lua, existing = runtime(development=False, saved=current, legacy_saved=legacy)
    if existing_lua.globals().OrbitQuizDB is not None or existing.Store.importedModeData:
        raise AssertionError("An existing Orbit-Games database must win and retire redundant legacy input")
    if plain(existing_lua.globals().OrbitGamesDB) != current:
        raise AssertionError("Redundant legacy input must not mutate an existing Orbit-Games database")
    print("Compatibility: legacy API, atomic migration, retry safety and new-database precedence passed")

    total = 0
    for suite in ("Rules.lua", "Scoring.lua", "Model.lua", "CardsEngine.lua", "CardsIntegration.lua", "CardsUI.lua", "PersonalScores.lua", "Packs.lua", "Comms.lua", "Runtime.lua", "Session.lua", "HostAudiences.lua", "Discovery.lua", "Scores.lua", "Interface.lua", "Appearance.lua", "WidgetPosition.lua", "SoundSettings.lua", "VisualStability.lua", "HUDPolish.lua", "ScrollingLabels.lua", "StreakToasts.lua", "HUDStreaks.lua", "Lore.lua"):
        lua, games = runtime()
        assertions = load(lua, TESTS / suite)(games)
        total += assertions
        if len(lua.globals().Test.errors):
            raise AssertionError(f"{suite}: unexpected WoW error handler calls")
        if len(lua.globals().Test.messages):
            raise AssertionError(f"{suite}: unexpected visible-chat output")
        print(f"{suite}: {assertions} assertions passed")

    for suite in ("Development.lua", "CardsPreview.lua", "ToastPreview.lua", "Minimap.lua"):
        for development in (True, False):
            lua, games = runtime(development=development)
            assertions = load(lua, TESTS / suite)(games, development)
            total += assertions
            if len(lua.globals().Test.errors):
                raise AssertionError(f"{suite}: unexpected WoW error handler calls")
            if games.Print is not None or len(lua.globals().Test.messages):
                raise AssertionError(f"{suite}: source and release runtimes must expose no visible-chat output")
            flavor = "source-only preview" if development else "packaged addon without development code"
            print(f"{suite} ({flavor}): {assertions} assertions passed")
            if suite == "Minimap.lua":
                saved = plain(games.Store.db)
                reloaded_lua, reloaded = runtime(development=development, saved=saved)
                icons, _ = reloaded_lua.globals().LibStub.GetLibrary(reloaded_lua.globals().LibStub, "LibDBIcon-1.0")
                button = icons.GetMinimapButton(icons, reloaded.addonName)
                same_table = reloaded_lua.eval("function(first, second) return rawequal(first, second) end")
                assert dict(button.db) == saved["minimap"]
                assert same_table(button.db, reloaded_lua.globals().OrbitGamesDB.minimap)
                assert icons.loggedIn and button.IsShown(button)
                assert reloaded.UI.frame is None and reloaded.Quiz.Widget.frame is None
                minimap = reloaded_lua.globals().Minimap
                angle = math.radians(saved["minimap"]["minimapPos"])
                assert math.isclose(button.point[4], math.cos(angle) * (minimap.GetWidth(minimap) / 2 + icons.radius), abs_tol=1e-6)
                assert math.isclose(button.point[5], math.sin(angle) * (minimap.GetHeight(minimap) / 2 + icons.radius), abs_tol=1e-6)
                total += 6
                print(f"Minimap reload ({flavor}): saved drag preferences bind to a fresh native button")

    lua, games = runtime()
    games.Development.ShowGames(games.Development)
    assert games.Development.enabled is True
    assert games.Development.ShowToasts(games.Development) is True
    assert games.Quiz.Widget.streakPreview is not None
    assert games.Development.enabled is False
    assert games.UI.gamePreview is None
    assert games.Development.ShowCards(games.Development) is True
    assert games.Quiz.Widget.streakPreview is None
    assert games.Development.cardsPreview.active is True
    assert games.Cards.Table.frame.IsShown(games.Cards.Table.frame)
    assert games.Development.ShowGames(games.Development) is True
    assert games.Development.cardsPreview.active is False
    assert games.Development.enabled is True
    assert games.UI.gamePreview is not None
    assert games.Development.ShowCards(games.Development) is True
    assert games.Development.cardsPreview.active is True
    assert games.UI.gamePreview is None
    assert games.Development.HideGames(games.Development) is True
    assert games.Development.cardsPreview.active is False
    reloaded_lua, reloaded_namespace = runtime()
    assert reloaded_namespace.Development.enabled is False
    assert reloaded_namespace.Development.games is None
    assert reloaded_namespace.UI.gamePreview is None
    assert reloaded_namespace.UI.frame is None
    assert reloaded_namespace.Quiz.Widget.streakPreview is None
    assert reloaded_namespace.Quiz.StreakToasts.frame is None
    total += 24
    print("Development preview: fresh runtimes reset all nonpersistent preview state")

    for locale in LOCALES:
        lua, games = runtime(locale)
        assertions = load(lua, TESTS / "Packs.lua")(games)
        total += assertions
    print(f"Pack validation: all {len(LOCALES)} locale codes passed")

    lua, games = runtime()
    from Lore import run_suite as run_lore_suite

    lore_assertions = run_lore_suite(games)
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
    from CardsNetwork import run_suite as run_cards_network_suite

    cards_network_assertions = run_cards_network_suite()
    total += cards_network_assertions
    print(f"CardsNetwork.py: {cards_network_assertions} paired-runtime assertions passed")
    print(f"PASS: {total} assertions; in-game validation is still required.")


if __name__ == "__main__":
    main()
