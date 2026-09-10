"""Audit bundled lore structure and coverage; this does not establish lore accuracy."""

import argparse
from collections import Counter, defaultdict
from pathlib import Path
import re
from urllib.parse import unquote, urlsplit

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT / "Modes" / "Quiz" / "Packs" / "WarcraftLore"
BUNDLED_PACK_ID = "warcraft-lore"
BUNDLED_PACK_VERSION = 2
DIFFICULTIES = ("easy", "medium", "hard", "very_hard")
LIMITS = {"prompt": 160, "explanation": 160, "era": 64, "category": 64, "source": 512}
MIN_QUESTIONS = 1000
MAX_QUESTIONS = 2000
REQUIRED_ERAS = (
    "Warcraft I", "Warcraft II", "Warcraft II: Beyond the Dark Portal", "Warcraft III",
    "Warcraft III: The Frozen Throne", "Classic", "The Burning Crusade", "Wrath of the Lich King",
    "Cataclysm", "Mists of Pandaria", "Warlords of Draenor", "Legion", "Battle for Azeroth",
    "Shadowlands", "Dragonflight", "The War Within", "Midnight",
)
COMIC_ARCHIVE = PACK / "Archive" / "Comics"
ARCHIVED_COMIC_FILES = (
    "LoreComicSeries.lua", "LoreGraphicNovels.lua", "LoreManga.lua", "LoreDigitalComics.lua",
)
ARCHIVED_COMIC_COUNT = 247
COMIC_ID_PREFIXES = ("comic_", "manga_", "ashbringer_", "bloodsworn_", "pearl_", "riders_", "worgen_")
COMIC_MEDIA_PATTERN = re.compile(r"\b(?:comics?|manga|graphic novels?)\b")
COMIC_DIGITAL_ARTICLES = {
    "20167292", "20167295", "20179680", "21791564", "21797339", "21833317", "23021205",
    "24165124", "24295084",
}
COMIC_DIGITAL_SOURCES = {"blizzard:" + article for article in COMIC_DIGITAL_ARTICLES}


def canonical_source(source):
    parsed = urlsplit(source)
    article = re.search(r"/(?:news|article)/(\d+)", parsed.path)
    if parsed.hostname in ("worldofwarcraft.blizzard.com", "news.blizzard.com") and article:
        return "blizzard:" + article.group(1)
    return (parsed.hostname or "") + unquote(parsed.path).rstrip("/").replace(" ", "_")


def normalized(text):
    return re.sub(r"[^\w]+", " ", text.casefold()).strip()


def references_comic_medium(text):
    return isinstance(text, str) and bool(COMIC_MEDIA_PATTERN.search(normalized(text.replace("_", " "))))


def is_comic_source(source):
    if not isinstance(source, str):
        return False
    canonical = canonical_source(source)
    return references_comic_medium(unquote(source)) or canonical in COMIC_DIGITAL_SOURCES


def words(text):
    return len(re.findall(r"\b[\w'-]+\b", text))


def review_candidates(questions):
    stop = set("a an the of to for in at on by as is was are were which what who whose does did first from with".split())
    by_answer = defaultdict(list)
    for index in range(1, len(questions) + 1):
        question = questions[index]
        key = normalized(question.choices[question.correctIndex])
        tokens = set(normalized(question.prompt).split()) - stop
        for other, other_tokens in by_answer[key]:
            overlap = len(tokens & other_tokens)
            if overlap >= 3 and overlap / max(1, min(len(tokens), len(other_tokens))) >= 0.65:
                print(f"REVIEW {other.id} / {question.id}: {key}\n  {other.prompt}\n  {question.prompt}")
        by_answer[key].append((question, tokens))

    answer_starts = defaultdict(list)
    for answer, rows in by_answer.items():
        trimmed = re.sub(r"^(?:a|an|the) ", "", answer)
        if len(trimmed) >= 4:
            answer_starts[trimmed.split()[0]].append((trimmed, rows))
    mentions = defaultdict(set)
    by_id = {questions[index].id: questions[index] for index in range(1, len(questions) + 1)}
    for question in by_id.values():
        prompt = " " + normalized(question.prompt) + " "
        for start in set(prompt.split()):
            for answer, rows in answer_starts[start]:
                if " " + answer + " " in prompt:
                    mentions[question.id].update(row.id for row, _ in rows)
    for question_id, targets in sorted(mentions.items()):
        for target in sorted(targets):
            if question_id < target and question_id in mentions[target]:
                print(f"REVIEW INVERSE {question_id} / {target}:\n  {by_id[question_id].prompt}\n  {by_id[target].prompt}")


def active_lore_files():
    return sorted(path for path in PACK.glob("*.lua") if path.name not in ("Assemble.lua", "Register.lua"))


def read_lore_files(paths):
    lua = LuaRuntime(unpack_returned_tuples=True)
    games = lua.table()
    games.Quiz = lua.table()
    compile_chunk = lua.eval("function(source, name) return assert(loadstring(source, name)) end")
    origins = {}
    for path in [PACK / "Assemble.lua", *paths]:
        before = len(games.Quiz.Lore.questions) if games.Quiz.Lore else 0
        compile_chunk(path.read_text(encoding="utf-8"), "@" + str(path))("Orbit-Games", games)
        for index in range(before + 1, len(games.Quiz.Lore.questions) + 1):
            origins[games.Quiz.Lore.questions[index].id] = path.name
    return games.Quiz.Lore.questions, origins


def read_drafts():
    return read_lore_files(active_lore_files())


def package_ignore_entries():
    entries = []
    in_ignore = False
    for line in (ROOT / ".pkgmeta").read_text(encoding="utf-8").splitlines():
        if line.strip() == "ignore:":
            in_ignore = True
        elif in_ignore:
            if line and not line[0].isspace():
                break
            text = line.strip()
            if text.startswith("- "):
                entries.append(text[2:].split("#", 1)[0].strip().strip("\"'").replace("\\", "/").rstrip("/"))
    return entries


def audit(questions, draft=False, report=False, origins=None):
    errors = []
    counts = Counter()
    eras = Counter()
    sizes = Counter()
    files = Counter()
    source_words = Counter()
    source_urls = {}
    ids = set()
    prompts = {}
    assertions = 0

    def check(condition, message):
        nonlocal assertions
        assertions += 1
        if not condition:
            errors.append(message)

    count = len(questions)
    check(count <= MAX_QUESTIONS, f"Too many questions: {count}")
    if not draft:
        check(count >= MIN_QUESTIONS, f"Bundled lore needs at least {MIN_QUESTIONS} questions, found {count}")

    for index in range(1, count + 1):
        question = questions[index]
        label = question.id or f"row {index}"
        check(isinstance(question.id, str) and re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,47}", question.id),
              f"Invalid permanent ID: {label}")
        check(question.id not in ids, f"Duplicate ID: {label}")
        ids.add(question.id)
        check(not isinstance(question.id, str) or not question.id.startswith(COMIC_ID_PREFIXES),
              f"Archived comic ID returned to active lore: {label}")
        check(question.era in REQUIRED_ERAS, f"Non-game/comic era returned to active lore: {label}")
        for field in ("prompt", "category"):
            check(not references_comic_medium(question[field]), f"Comic publication {field} returned to active lore: {label}")
        check(not is_comic_source(question.source), f"Comic publication source returned to active lore: {label}")
        check(question.difficulty in DIFFICULTIES, f"Missing/invalid difficulty: {label}")
        counts[question.difficulty] += 1
        for field, limit in LIMITS.items():
            value = question[field]
            if field == "explanation" and value is None:
                continue
            valid = isinstance(value, str) and bool(value.strip())
            check(valid, f"Missing {field}: {label}")
            if valid:
                check(len(value.encode("utf-8")) <= limit, f"{field} exceeds {limit} bytes: {label}")
                check(not re.search(r"[\x00-\x1f\x7f|{}]", value), f"Unsafe text in {field}: {label}")
        if question.source:
            parsed = urlsplit(question.source)
            check(parsed.scheme == "https" and bool(parsed.netloc), f"Invalid HTTPS source: {label}")
        choice_count = len(question.choices)
        sizes[choice_count] += 1
        check(4 <= choice_count <= 6, f"Expected four to six choices: {label}")
        check(isinstance(question.correctIndex, (int, float)) and int(question.correctIndex) == question.correctIndex
              and 1 <= question.correctIndex <= choice_count, f"Invalid correct answer: {label}")
        choice_keys = set()
        for choice_index in range(1, choice_count + 1):
            choice = question.choices[choice_index]
            check(isinstance(choice, str) and bool(choice.strip()) and len(choice.encode("utf-8")) <= 100,
                  f"Invalid choice {choice_index}: {label}")
            check(not re.search(r"[\x00-\x1f\x7f|{}]", choice), f"Unsafe choice {choice_index}: {label}")
            key = normalized(choice)
            check(key not in choice_keys, f"Duplicate normalized choice {choice_index}: {label}")
            choice_keys.add(key)
        key = normalized(question.prompt)
        check(key not in prompts, f"Repeated prompt: {label} / {prompts.get(key)}")
        prompts[key] = label
        eras[question.era] += 1
        if origins:
            files[origins.get(question.id, "unknown")] += 1
        if question.source and 1 <= question.correctIndex <= choice_count:
            source = canonical_source(question.source)
            derived = " ".join((question.prompt, question.choices[question.correctIndex], question.explanation or ""))
            source_words[source] += words(derived)
            source_urls[source] = question.source

    if not draft:
        for difficulty in DIFFICULTIES:
            check(counts[difficulty] > 0, f"Missing difficulty tier: {difficulty}")
        for size in (4, 5, 6):
            check(sizes[size] > 0, f"Bundled content does not exercise {size}-choice questions")
        for era in REQUIRED_ERAS:
            check(eras[era] > 0, f"Missing game-era coverage: {era}")
    for source, count_words in source_words.items():
        check(count_words <= 200, f"Source-derived word budget {count_words}/200: {source_urls[source]}")

    if report:
        print(f"Lore: {count} questions; {len(eras)} game eras; {len(source_words)} source pages")
        print("Difficulty: " + ", ".join(f"{key}={counts[key]}" for key in DIFFICULTIES))
        print("Choices: " + ", ".join(f"{key}={value}" for key, value in sorted(sizes.items())))
        for era, era_count in sorted(eras.items()):
            print(f"  {era}: {era_count}")
        if files:
            print("Files: " + ", ".join(f"{name}={value}" for name, value in sorted(files.items())))
        if errors:
            print("\n".join(errors))
    if errors:
        raise AssertionError(f"{len(errors)} lore audit failure(s): " + "; ".join(errors[:12]))
    return assertions


def run_suite(games):
    quiz = games.Quiz
    assertions = 0

    def check(condition, message):
        nonlocal assertions
        assertions += 1
        if not condition:
            raise AssertionError(message)

    packs = quiz.GetPacks(quiz)
    check(len(packs) == 1 and packs[1].id == BUNDLED_PACK_ID,
          "Exactly one bundled Warcraft Lore pack must replace Warcraft Basics")
    check(packs[1].version == BUNDLED_PACK_VERSION, "Comic-free Warcraft Lore must retain its ID at pack revision two")
    questions = quiz.GetQuestions(quiz, BUNDLED_PACK_ID)
    if isinstance(questions, tuple):
        questions = questions[0]
    check(not (PACK.parent / "WarcraftBasics.lua").exists(),
          "Warcraft Basics must not remain in the shipped pack directory")
    from run import toc_scripts

    authored_files = {path.relative_to(ROOT).as_posix() for path in (PACK / "Assemble.lua", *active_lore_files())}
    for development in (True, False):
        scripts = toc_scripts(development)
        check(authored_files.issubset(set(scripts)), "Every active authored lore file must be loaded by the TOC")
        check(not any("/Archive/" in path or Path(path).name in ARCHIVED_COMIC_FILES for path in scripts),
              "Neither source nor packaged TOCs may load the archived comic files")
    check({path.name for path in COMIC_ARCHIVE.glob("*.lua")} == set(ARCHIVED_COMIC_FILES),
          "All four comic source files must remain recoverable only in the excluded archive")
    check((COMIC_ARCHIVE / "ResearchComics.md").is_file(), "Archived comic research must remain recoverable")
    check(not (PACK / "ResearchComics.md").exists(), "Comic research must not remain in the active pack folder")
    for name in ARCHIVED_COMIC_FILES:
        check(not (PACK / name).exists(), "Comic files cannot remain in the active draft search: " + name)
    ignored = package_ignore_entries()
    for path in COMIC_ARCHIVE.rglob("*"):
        if path.is_file():
            relative = path.relative_to(ROOT).as_posix()
            check(any(relative == entry or relative.startswith(entry + "/") for entry in ignored),
                  "Archive content is not excluded from release packaging: " + relative)
    for path in authored_files:
        check(not any(path == entry or path.startswith(entry + "/") for entry in ignored),
              "Active game lore must not be hidden by a broad packaging exclusion: " + path)

    archived, _ = read_lore_files([COMIC_ARCHIVE / name for name in ARCHIVED_COMIC_FILES])
    archived_ids = {question.id for question in archived.values()}
    active_ids = {question.id for question in questions.values()}
    check(len(archived) == ARCHIVED_COMIC_COUNT, "All 247 removed questions must remain in the excluded source archive")
    check(len(archived_ids) == len(archived), "Archived comic IDs must remain distinct and recoverable")
    check(archived_ids.isdisjoint(active_ids), "Archived comic questions must never register in the active pack")
    for question in archived.values():
        check(question.id.startswith(COMIC_ID_PREFIXES) and question.era not in REQUIRED_ERAS,
              "Only comic/manga question families belong in the archive: " + question.id)
    for question in questions.values():
        check(question.packId == BUNDLED_PACK_ID and question.packVersion == BUNDLED_PACK_VERSION,
              "Every active question must carry the unchanged pack ID and revised content version: " + question.id)

    drafts, origins = read_drafts()
    check({question.id for question in drafts.values()} == active_ids,
          "Draft discovery must include exactly the active game questions, never archive descendants")
    check(not any(name in ARCHIVED_COMIC_FILES for name in origins.values()), "Draft origins must exclude archived comic files")
    for source in (
        "https://warcraft.wiki.gg/wiki/Blackhand_%28comic%29",
        "https://warcraft.wiki.gg/wiki/Death_Knight_%28manga%29",
        "https://example.org/graphic-novel",
        "https://worldofwarcraft.blizzard.com/en-us/news/21791564",
        "https://news.blizzard.com/en-us/article/21791564",
    ):
        check(is_comic_source(source), "Publication-source exclusion must recognize encoded and locale-variant URLs")
    for source in (
        "https://warcraft.wiki.gg/wiki/Defias_Brotherhood",
        "https://warcraft.wiki.gg/wiki/Zul%27jan",
        "https://warcraft.wiki.gg/wiki/Ashbringer",
    ):
        check(not is_comic_source(source), "General game-lore pages must not be banned just because comics also cite them")
    print(f"Comic archive: {len(archived)} questions excluded from runtime, drafts and release packaging")
    return audit(questions, report=True) + assertions


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--draft", action="store_true", help="Audit authored files before final TOC integration")
    parser.add_argument("--review", action="store_true", help="List similar same-answer prompts for editorial review")
    args = parser.parse_args()
    if args.draft:
        data, locations = read_drafts()
        audit(data, draft=True, report=True, origins=locations)
        if args.review:
            review_candidates(data)
    else:
        from run import runtime

        _, games = runtime()
        run_suite(games)
        if args.review:
            review_candidates(games.Quiz.GetQuestions(games.Quiz, "warcraft-lore"))
