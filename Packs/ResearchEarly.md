# Early-era and Dragonflight lore source audit

Researched 2026-08-31. This covers the five content files below; Dragonflight was assigned after completion of the early-era tranche.

| File | Questions | Cited pages | Easy / medium / hard / very hard |
| --- | ---: | ---: | --- |
| LoreRTS.lua | 220 | 76 | 47 / 71 / 69 / 33 |
| LoreClassic.lua | 85 | 33 | 11 / 33 / 27 / 14 |
| LoreBurningCrusade.lua | 80 | 31 | 11 / 33 / 23 / 13 |
| LoreWrath.lua | 90 | 50 | 14 / 29 / 31 / 16 |
| LoreDragonflight.lua | 80 | 23 | 12 / 28 / 30 / 10 |

## Research method

Every question group records its consulted source URL in `Quiz.Lore:Add`; those URLs are the complete per-question source manifest. Sources were read through web search's indexed text, with direct page access where available. Warcraft Wiki commonly rejected direct requests, so this is an indexed-excerpt review, not a claim that every underlying game, novel, manual, or comic was independently reread.

Original prompts and independent distractors were written around the supported facts. Warcraft Wiki campaign transcripts, quest dialogue, Adventure Guide text, and its cited narrative summaries supplied most early-era material. Blizzard's published Nexus description supplied two Wrath questions. A page-level derived-word budget is checked by `.tests/Lore.py`; unrelated aliases and mirrors must not be treated as extra budget.

Dragonflight additionally uses Blizzard's release-era dungeon, raid, faction, and zone narratives. Its initial beta dungeon preview was consulted, but questions use the later release preview after checking the selected facts against that version. Shared descriptions reproduced in the dungeon and Ohn'ahran articles remain under 200 derived words in aggregate.

## Consulted source groups

- Warcraft I: [First War](https://warcraft.wiki.gg/wiki/First_War), [Garona](https://warcraft.wiki.gg/wiki/Garona_Halforcen), [House of Wrynn](https://warcraft.wiki.gg/wiki/House_of_Wrynn), and the cited Medivh, Aegwynn, Karazhan, Durotan, Blackhand, and Doomhammer biographies support the established First War narrative and family relationships.
- Warcraft II: [Alliance of Lordaeron](https://warcraft.wiki.gg/wiki/Alliance_of_Lordaeron), [Silver Hand](https://warcraft.wiki.gg/wiki/Knights_of_the_Silver_Hand), [Demon Soul](https://warcraft.wiki.gg/wiki/Demon_Soul), and the cited Alliance and Old Horde character pages cover the Second War and Alexstrasza's captivity.
- Beyond the Dark Portal: [Invasion of Draenor](https://warcraft.wiki.gg/wiki/Invasion_of_Draenor), [Book of Medivh](https://warcraft.wiki.gg/wiki/Book_of_Medivh), [Spell of Conjuration](https://warcraft.wiki.gg/wiki/Spell_of_Conjuration), and the other named artifact, clan, and expedition pages cover Ner'zhul's plans and the Alliance expedition.
- Warcraft III: individual mission transcripts, including [The Defense of Strahnbrad](https://warcraft.wiki.gg/wiki/The_Defense_of_Strahnbrad_%28WC3_Human%29), [The Culling](https://warcraft.wiki.gg/wiki/The_Culling_%28WC3_Human%29), [By Demons Be Driven](https://warcraft.wiki.gg/wiki/By_Demons_Be_Driven_%28WC3_Orc%29), and [Brothers in Blood](https://warcraft.wiki.gg/wiki/Brothers_in_Blood_%28WC3_NightElf%29), support dialogue, side-quest characters, and campaign events.
- The Frozen Throne: [The Brothers Stormrage](https://warcraft.wiki.gg/wiki/The_Brothers_Stormrage_%28WC3_NightElf%29), [The Dungeons of Dalaran](https://warcraft.wiki.gg/wiki/The_Dungeons_of_Dalaran_%28WC3_BloodElf%29), [A Symphony of Frost and Flame](https://warcraft.wiki.gg/wiki/A_Symphony_of_Frost_and_Flame_%28WC3_Undead%29), and other individual mission pages support Outland, Forsaken, Icecrown, and Rexxar story questions.
- Classic: cited Defias, Windsor, Blackrock, Ahn'Qiraj, Duskwood, Naralex, Maraudon, Uldaman, Hakkar, Scarlet Crusade, Naxxramas, and Scholomance pages support faction motives, named quest characters, and dungeon backstories. See each group URL rather than inferring a question from a boss list.
- The Burning Crusade: cited Aldor/Scryer and Shattrath pages cover factions; dungeon and quest pages cover Coilfang, Auchindoun, Hellfire, Karazhan, and Black Temple. Individual M'uru, Sunwell, Exodar, Geyah, Garrosh, Terokk, Gorefiend, and Mordenaku pages cover the remaining narrative facts.
- Wrath campaign: [The Light of Dawn](https://warcraft.wiki.gg/wiki/The_Light_of_Dawn_%28quest%29), [Battle for the Undercity](https://warcraft.wiki.gg/wiki/Battle_for_the_Undercity), and cited Wrathgate/Lich King pages support the campaign and finale.
- Wrath local stories: [Betrayal](https://warcraft.wiki.gg/wiki/Betrayal), [The Boon of A'dal](https://warcraft.wiki.gg/wiki/The_Boon_of_A%27dal), [A Hero's Burden](https://warcraft.wiki.gg/wiki/A_Hero%27s_Burden), [Back Through the Waygate](https://warcraft.wiki.gg/wiki/Back_Through_the_Waygate), and the separately cited loa, vrykul, trapper, and tournament pages support quest details.
- Wrath dragon/titan stories: [Blizzard's Nexus description](https://worldofwarcraft.blizzard.com/en-us/news/21510319/wrath-of-the-lich-king-timewalking-is-back-february-13-20), [Reply-Code Alpha](https://warcraft.wiki.gg/wiki/Reply-Code_Alpha), and the cited Thorim, Loken, Yogg-Saron, Sindragosa, Keristrasza, and dungeon descriptions support these groups.
- Dragonflight's original regions: Blizzard's [major factions](https://worldofwarcraft.blizzard.com/en-us/news/23823105/dragonflight-major-factions-overview), [Ohn'ahran Plains](https://worldofwarcraft.blizzard.com/en-us/news/23874317/dragonflight-step-foot-into-the-magnificence-of-the-ohnahran-plains), and [release dungeon preview](https://worldofwarcraft.blizzard.com/en-us/news/23874315) support cultures, motives, artifacts, and dungeon backstories.
- Dragonflight raids: Blizzard's [Vault of the Incarnates](https://worldofwarcraft.blizzard.com/en-us/news/23891615/vault-of-the-incarnates-normal-heroic-and-mythic-now-live), [Aberrus](https://worldofwarcraft.blizzard.com/en-us/news/23935246/aberrus-the-shadowed-crucible-raid-finder-wing-4-now-live), and [Amirdrassil](https://worldofwarcraft.blizzard.com/en-us/news/24017500/amirdrassil-the-dreams-hope-raid-finder-wing-4-now-live) descriptions support named characters and their narrative origins. Raid schedules, achievements, and reward mechanics on these pages were not used.
- Dragonflight quest stories: [Sindragosa's simulacrum](https://warcraft.wiki.gg/wiki/Sindragosa_%28simulacrum%29), [Smells Like Loamm](https://warcraft.wiki.gg/wiki/Smells_Like_Loamm), [Elder Honeypelt](https://warcraft.wiki.gg/wiki/Elder_Honeypelt), [Veritistrasz](https://warcraft.wiki.gg/wiki/Veritistrasz), and the cited flight, Tyr, Eternus, and campaign-summary pages support local stories and reunions.
- Dragonflight timeways and conclusion: [Dawn of the Infinite](https://worldofwarcraft.blizzard.com/en-us/news/23987545/dawn-of-the-infinite-heroic-difficulty-coming-in-fury-incarnate), [Dark Heart](https://warcraft.wiki.gg/wiki/Dark_Heart), [Vyranoth](https://warcraft.wiki.gg/wiki/Vyranoth), and [Amirdrassil](https://warcraft.wiki.gg/wiki/Amirdrassil) support the Incarnates' plans and outcomes.

## Canon and ambiguity decisions

- Established history takes precedence over mutually exclusive Warcraft I/II campaign victories. Garona's draenei ancestry is used rather than the original half-human belief. Warcraft film continuity and the non-canon RPG were excluded.
- Independent review removed `beyond_portal_expedition_king`: Terenas directing the invasion of Draenor is an older History of Warcraft account superseded by Beyond the Dark Portal and Chronicle Volume 2. The retained five-file tranche contains 555 questions.
- Warcraft III demon-blood events are distinguished from the original orc corruption. Alternate Draenor facts belong to the separate Warlords material, not this tranche.
- Patch dates, damage values, encounter tactics, achievements, drop rates, and publication trivia were excluded. Named objects matter only as narrative artifacts or quest evidence.
- Mam'toth's destruction is scoped to his Zul'Drak act; no question claims his spirit permanently ceased to exist. Arugal's Grizzly Hills activity is explicitly after his resurrection.
- Bridenbrad's soul is saved from undeath; the questions do not claim his plague is cured. Lana'thel's destroyed blade is Quel'Delar, not Quel'Serrar.
- Azuremyst Isles wording distinguishes the island group from Azuremyst Isle. Very-hard distractors were reviewed for accidental place names masquerading as people and spelling mistakes.
- The same character can recur for distinct events. Shared-answer review flags for the two attacks on Nordrassil, Drakuru's appointment versus execution, and the Nexus stories are not duplicate facts.
- Dragonflight's Sindragosa simulacrum is not her resurrected physical body. Alternate Tyr and the Nighthold visited during Tyr's restoration are explicitly timeline-qualified. Vyranoth's original frost power and later Aspect of Storms title are separate facts.
- The Shadowlands tranche owns creation of Amirdrassil's seed; Dragonflight covers its planting and blooming. The Aspects' renewed power comes from Azeroth, not a repeated bestowal by the titans. No speculation about future Iridikron or Worldsoul Saga events is included.

## Validation boundary

All five files passed StyLua and the Lua 5.1/schema audit, including unique IDs/prompts, four-to-six distinct choices, text limits, metadata, and per-page source budgets. A separate review read every prompt and choice set and rechecked supporting passages, removing the superseded expedition question and clarifying the Hollowstone miners' transformation and the Silver Scale's Tyrhold use. This establishes reviewed content and data integrity, not infallible accuracy. Difficulty labels are editorial judgments; in-game presentation still needs testing.
