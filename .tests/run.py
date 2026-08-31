"""Execute the real addon modules and regression suites in a Lua 5.1 runtime."""

from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / ".tests"
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
    scripts = toc_scripts()
    packaged_scripts = toc_scripts(development=False)
    if scripts.count("Development.lua") != 1 or scripts[-1] != "Development.lua":
        raise AssertionError("The source-only preview must load exactly once after the runtime")
    if "Development.lua" in packaged_scripts or set(scripts) - set(packaged_scripts) != {"Development.lua"}:
        raise AssertionError("Only the development fixture must be omitted from the packaged TOC")
    package_metadata = (ROOT / ".pkgmeta").read_text(encoding="utf-8")
    if "ignore:" not in package_metadata or "- Development.lua" not in package_metadata.split("ignore:", 1)[1]:
        raise AssertionError("Release archives must exclude Development.lua")
    if (ROOT / "Chat.lua").exists() or "Chat.lua" in scripts:
        raise AssertionError("The retired visible-chat transport must not ship or load")
    if "Identity.lua" not in scripts or any(scripts.index("Identity.lua") >= scripts.index(consumer)
                                           for consumer in ("Comms.lua", "Session.lua", "Main.lua")):
        raise AssertionError("Native identity must load before addon communication and session consumers")
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
    for suite in ("Scoring.lua", "Model.lua", "PersonalScores.lua", "Packs.lua", "Comms.lua", "Runtime.lua", "Session.lua", "Discovery.lua", "Interface.lua", "Appearance.lua", "VisualStability.lua", "HUDPolish.lua", "Lore.lua"):
        lua, namespace = runtime()
        assertions = load(lua, TESTS / suite)(namespace)
        total += assertions
        if len(lua.globals().Test.errors):
            raise AssertionError(f"{suite}: unexpected WoW error handler calls")
        print(f"{suite}: {assertions} assertions passed")

    for development in (True, False):
        lua, namespace = runtime(development=development)
        assertions = load(lua, TESTS / "Development.lua")(namespace, development)
        total += assertions
        if len(lua.globals().Test.errors):
            raise AssertionError("Development.lua: unexpected WoW error handler calls")
        flavor = "source-only preview" if development else "packaged addon without development code"
        print(f"Development.lua ({flavor}): {assertions} assertions passed")

    lua, namespace = runtime()
    namespace.Development.ShowGames(namespace.Development)
    assert namespace.Development.enabled is True
    reloaded_lua, reloaded_namespace = runtime()
    assert reloaded_namespace.Development.enabled is False
    assert reloaded_namespace.Development.games is None
    assert reloaded_namespace.UI.gamePreview is None
    assert reloaded_namespace.UI.frame is None
    total += 5
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

    bundled_count = len(namespace.GetQuestions(namespace, "all"))
    bundled_packs = len(namespace.GetQuestionPacks(namespace))
    example = ROOT / "Examples" / "Orbit-Quiz-Pack-Example" / "Questions.lua"
    load(lua, example, lua.table(), "Orbit-Quiz-Pack-Example")
    assert len(namespace.GetQuestionPacks(namespace)) == bundled_packs + 1
    assert len(namespace.GetQuestions(namespace, "all")) == bundled_count + 3
    print(f"Companion pack: dependency-ordered registration passed ({bundled_count} + 3 questions)")
    from Network import run_suite

    network_assertions = run_suite()
    total += network_assertions
    print(f"Network.py: {network_assertions} paired-runtime assertions passed")
    print(f"PASS: {total} assertions; in-game validation is still required.")


if __name__ == "__main__":
    main()
