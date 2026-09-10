"""Load the author template as an independent addon against the packaged core."""

from pathlib import Path
import re

from run import ROOT, load, runtime


EXAMPLE = ROOT / "Dev" / "Examples" / "Orbit-Games-Quiz-Pack-Example"
PACK_ID = "example_everyday"


def manifest_data(source):
    metadata, scripts = {}, []
    for line in source.splitlines():
        line = line.strip()
        if line.startswith("##"):
            key, separator, value = line[2:].partition(":")
            if separator:
                metadata[key.strip().lower()] = value.strip()
        elif line and not line.startswith("#"):
            scripts.append(line.replace("\\", "/"))
    return metadata, scripts


def registration_api(lua, quiz):
    return lua.eval("""function(core)
        local registrations = {}
        local quizApi = {}
        function quizApi:RegisterPack(pack)
            registrations[#registrations + 1] = pack
            return core:RegisterPack(pack)
        end
        setmetatable(quizApi, { __index = function(_, key)
            error("Companion accessed a private Orbit-Games Quiz member: " .. tostring(key))
        end })
        local gamesApi = { Quiz = quizApi }
        setmetatable(gamesApi, { __index = function(_, key)
            error("Companion accessed a private Orbit-Games member: " .. tostring(key))
        end })
        return gamesApi, registrations
    end""")(quiz)


def run_suite():
    assertions = 0

    def check(condition, message):
        nonlocal assertions
        if not condition:
            raise AssertionError(message)
        assertions += 1

    manifest = EXAMPLE / f"{EXAMPLE.name}.toc"
    check(manifest.is_file(), "The standalone addon needs a TOC matching its folder name")
    metadata, scripts = manifest_data(manifest.read_text(encoding="utf-8"))

    required = []
    for key in ("dependencies", "requireddeps"):
        required.extend(metadata.get(key, "").replace(",", " ").split())
    check(required == ["Orbit-Games"], "The companion's only required addon is Orbit-Games")
    check(not metadata.get("optionaldeps"), "The template needs no extra optional addon dependencies")
    check(metadata.get("loadondemand", "0") == "0", "The companion must load automatically with its dependency")
    check(bool(scripts), "The companion TOC must list its own question script")
    check(len(scripts) == len(set(scripts)), "Companion scripts must load exactly once")
    paths = []
    for script in scripts:
        relative = Path(script)
        path = (EXAMPLE / relative).resolve()
        check(not relative.is_absolute() and path.is_relative_to(EXAMPLE.resolve()),
              "Companion scripts must live inside the standalone addon folder")
        check(path.is_file() and path.suffix == ".lua", "The example TOC must point to an existing Lua file")
        paths.append(path)

    lua, games = runtime(development=False)
    quiz = games.Quiz
    test, globals_ = lua.globals().Test, lua.globals()
    same = lua.eval("rawequal")
    bundled = quiz.GetPacks(quiz)
    bundled_count = len(quiz.GetQuestions(quiz, "all"))
    check(len(bundled) == 1 and bundled[1].id == "warcraft-lore",
          "Packaged Orbit-Games must contain only its bundled quiz before installing the companion")
    check(games.Development is None and globals_.SlashCmdList.ORBITGAMESDEV is None,
          "Standalone pack registration must not need the development module")
    check(globals_.Orbit is None, "Standalone packs must not require the Orbit addon")
    check(len(quiz.GetPackErrors(quiz)) == 0 and len(test.errors) == 0,
          "Packaged initialization must start with clean error state")
    saved_selection = quiz.Store.GetSettings(quiz.Store).packId
    companion_namespace = lua.table()
    check(not same(companion_namespace, quiz), "A companion receives its own addon namespace")

    public_api, registrations = registration_api(lua, quiz)
    globals_.OrbitGames = public_api
    try:
        for path in paths:
            load(lua, path, companion_namespace, EXAMPLE.name)
        check(same(globals_.OrbitGames, public_api), "Pack authors must not replace the framework's public global")
    finally:
        globals_.OrbitGames = games

    check(len(registrations) == 1, "The example must register exactly one pack through the public API")
    authored = registrations[1]
    check(authored.id == PACK_ID, "The installed example retains its stable pack identity")
    check(len(quiz.GetPackErrors(quiz)) == 0 and len(test.errors) == 0,
          "The companion must register without validation or runtime errors")
    packs = {pack.id: pack for pack in quiz.GetPacks(quiz).values()}
    check(set(packs) == {"warcraft-lore", PACK_ID}, "The new pack must be discoverable without editing the core TOC")
    installed = packs[PACK_ID]
    for field in ("title", "version", "author", "locale"):
        check(installed[field] == authored[field], f"Companion registration must retain pack {field}")
    check(installed.count == len(authored.questions) == 3, "All three example questions must be registered")
    check(len(quiz.GetQuestions(quiz, "warcraft-lore")) == bundled_count,
          "Installing a companion must leave bundled questions intact")
    check(len(quiz.GetQuestions(quiz, "all")) == bundled_count + installed.count,
          "The registry must include the standalone pack in its combined catalogue")

    rules, rules_key = quiz.GetRules(quiz, PACK_ID)
    check(installed.rulesKey == rules_key == quiz.Rules.Encode(rules), "The pack keeps its canonical rule identity")
    check(len(list(rules.keys())) == len(list(authored.rules.keys())), "The template must declare its complete ruleset")
    for key, value in authored.rules.items():
        check(rules[key] == value, f"The companion's authored {key} rule must survive registration")
    questions = quiz.GetQuestions(quiz, PACK_ID)
    for index, question in questions.items():
        source = authored.questions[index]
        check(question.packId == PACK_ID and question.rulesKey == rules_key,
              "Each companion question must use its pack identity and rules")
        for field in ("id", "prompt", "correctIndex", "explanation", "category"):
            check(question[field] == source[field], f"Companion registration must retain question {field}")
        check(tuple(question.choices.values()) == tuple(source.choices.values()),
              "Companion registration must retain the original answer choices")
        check(4 <= len(question.choices) <= 6 and 1 <= question.correctIndex <= len(question.choices),
              "Example questions must contain four to six choices with a valid answer")

    test.Advance(30)
    check(quiz.Controller.game is None and not games.Main.IsRunning(games.Main), "Installing a pack must not start a game")
    check(quiz.Session.hostSession is None and quiz.Session.client is None, "Installing a pack must not create a session")
    check(games.UI.frame is None and quiz.Widget.frame is None, "Installing a pack must not open quiz windows")
    check(quiz.Store.GetSettings(quiz.Store).packId == saved_selection, "Installing a pack must not change host selection")
    check(globals_.Orbit is None and games.Development is None, "The companion must not create hidden addon dependencies")
    check(len(test.errors) == 0, "The installed companion must remain error-free during normal runtime ticks")

    settings = quiz.Store.GetSettings(quiz.Store)
    settings.packId = PACK_ID
    check(games.Main.Start(games.Main, settings) is True, "The host can explicitly start the independently installed quiz")
    check(quiz.Controller.game.state == "open" and quiz.Controller.game.round.packId == PACK_ID,
          "The standalone pack must produce a playable question without development code")
    check(quiz.Controller.game.rulesKey == rules_key, "Hosting the companion must use the author's rule identity")
    check(len(quiz.GetPackErrors(quiz)) == 0 and len(test.errors) == 0, "Hosting the companion must remain error-free")

    guide = (ROOT / "Docs" / "PACKS.md").read_text(encoding="utf-8")
    toc_block = re.search(r"^```toc\n(.*?)^```", guide, re.MULTILINE | re.DOTALL)
    lua_block = re.search(r"^```lua\n(.*?)^```", guide, re.MULTILINE | re.DOTALL)
    check(toc_block is not None and lua_block is not None, "The guide must include complete TOC and question files")
    metadata, scripts = manifest_data(toc_block[1])
    check(metadata.get("dependencies") == "Orbit-Games", "The guide's addon must require the installed framework")
    check(not metadata.get("optionaldeps") and not metadata.get("requireddeps")
          and metadata.get("loadondemand", "0") == "0", "The guide must not introduce extra addon-loading requirements")
    check(scripts == ["Questions.lua"], "The guide TOC must load only the provided question file")

    lua, games = runtime(development=False)
    quiz = games.Quiz
    globals_ = lua.globals()
    public_api, registrations = registration_api(lua, quiz)
    globals_.OrbitGames = public_api
    try:
        chunk = lua.eval("function(source, name) return assert(loadstring(source, name)) end")(
            lua_block[1], "@MyGuild-Trivia/Questions.lua"
        )
        chunk("MyGuild-Trivia", lua.table())
    finally:
        globals_.OrbitGames = games
    check(len(registrations) == 1 and registrations[1].id == "myguild_trivia",
          "The guide must register an independently named quiz without the example addon")
    check({pack.id for pack in quiz.GetPacks(quiz).values()} == {"warcraft-lore", "myguild_trivia"},
          "The guide must work with just the released framework and the author's own files")
    question = quiz.GetQuestions(quiz, "myguild_trivia")[1]
    check(question.id == "triangle_sides" and question.choices[question.correctIndex] == "Three",
          "The guide must supply a complete question with the intended correct answer")
    rules, _ = quiz.GetRules(quiz, "myguild_trivia")
    for key, value in registrations[1].rules.items():
        check(rules[key] == value, f"The guide's authored {key} rule must survive registration")
    check(len(quiz.GetPackErrors(quiz)) == 0 and len(globals_.Test.errors) == 0,
          "The guide snippets must execute and register without errors")
    check(quiz.Controller.game is None and quiz.Session.hostSession is None and quiz.Session.client is None,
          "The guide must not automatically host or join a game")
    check(games.Development is None and globals_.Orbit is None, "The guide must not need development code or Orbit")
    return assertions


if __name__ == "__main__":
    print(f"CompanionPack.py: {run_suite()} standalone-addon assertions passed")
