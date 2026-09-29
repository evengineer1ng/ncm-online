#!/usr/bin/env python3
"""Port the backmarker name data (FTB) into ncm/core/paddock/names_data.lua (doc 44 §4.2, L224.7).

The source is the owner's own `ftb_names.py` and `ftb_sponsors.py` (Radio-OS), which L224.7 grants for verbatim reuse.
This tool is the reproducible bridge: the Lua file is GENERATED, never hand-edited, and `--check` fails when the
committed Lua no longer matches what the Python source plus the cleaning rules below produce (the L221 oracle).

Cleaning, all deliberate and all listed here:
  * FTB's flat lists are split into regions by their own comment blocks (the code never used them).
  * Blocks of REAL motorsport people are dropped: every "motorsport" block, the IndyCar/Oceania block that opens the
    American surname section, and both "modern feeder" blocks. A real name must never drive for a Street org.
  * Surnames that leaked into first-name lists are removed (Vandoorne, Daruvala), and "ida" is capitalised.
  * FTB has no Indian, Middle Eastern or African SURNAMES; those three regions are authored below.
  * Duplicates inside a region are removed (FTB used them as accidental weighting).
  * REAL_NAME_DENYLIST catches full names that could still be assembled from ordinary parts (George + Russell).

Usage:  python tools/paddock-names-port.py [--source D:/dev/Radio-OS/plugins] [--check]
"""
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "ncm", "core", "paddock", "names_data.lua")

REGION_OF_FIRST = {
    "British/Irish": "british", "Italian": "italian", "Spanish/Latin American": "latin",
    "German/Austrian": "german", "French": "french", "Scandinavian": "scandinavian", "Dutch/Belgian": "dutch",
    "Eastern European": "eastern_european", "Japanese": "japanese", "Chinese": "chinese", "Brazilian": "brazilian",
    "American/Canadian": "american", "Australian/NZ": "australian", "Indian/South Asian": "indian",
    "Middle Eastern": "middle_eastern", "African": "african", "Korean": "korean", "Southeast Asian": "southeast_asian",
}
REGION_OF_SURNAME = {
    "BRITISH / IRISH": "british", "Additional British/Irish surnames": "british",
    "ITALIAN": "italian", "Additional Italian surnames": "italian",
    "SPANISH / LATIN AMERICAN": "latin", "Additional Spanish/Latin American surnames": "latin",
    "GERMAN / AUSTRIAN / SWISS": "german", "Additional German/Austrian/Swiss surnames": "german",
    "FRENCH / FRANCOPHONE": "french", "Additional French surnames": "french",
    "SCANDINAVIAN": "scandinavian", "Additional Scandinavian surnames": "scandinavian",
    "DUTCH / BELGIAN": "dutch", "Additional Dutch/Belgian surnames": "dutch",
    "EASTERN EUROPEAN / SLAVIC": "eastern_european", "Additional Eastern European/Slavic surnames": "eastern_european",
    "JAPANESE": "japanese", "Additional Japanese surnames": "japanese",
    "CHINESE": "chinese", "Additional Chinese surnames": "chinese",
    "BRAZILIAN / PORTUGUESE": "brazilian", "Additional Brazilian/Portuguese surnames": "brazilian",
    "Additional American/Canadian surnames": "american",
    "Additional Oceania surnames": "australian",
    "KOREAN": "korean", "SOUTHEAST ASIAN": "southeast_asian",
}
# Real people, dropped whole. Matched on the start of the block header.
DROP_BLOCKS = (
    "Additional unique motorsport names", "British motorsport flavor", "German motorsport flavor",
    "Nordic motorsport", "Benelux motorsport", "Brazilian motorsport", "AMERICAN / CANADIAN / AUSTRALIAN / NZ",
    "Oceania", "MODERN FEEDER", "Additional modern feeder surnames",
)
LEAKED_SURNAMES = {"Vandoorne", "Daruvala"}

AUTHORED_SURNAMES = {
    "indian": [
        "Sharma", "Patel", "Singh", "Gupta", "Iyer", "Reddy", "Nair", "Menon", "Rao", "Kapoor", "Malhotra", "Chopra",
        "Bhatt", "Desai", "Joshi", "Kulkarni", "Mehta", "Pillai", "Chatterjee", "Banerjee", "Mukherjee", "Das", "Bose",
        "Sen", "Verma", "Agarwal", "Saxena", "Srinivasan", "Krishnan", "Naidu", "Shetty", "Gill", "Sandhu", "Dhillon",
        "Grewal", "Bhatia", "Thakur", "Chauhan", "Rathore", "Pandey", "Mishra", "Tiwari",
    ],
    "middle_eastern": [
        "Haddad", "Khoury", "Nasser", "Mansour", "Saleh", "Hamdan", "Aziz", "Farouk", "Rahman", "Karimi", "Hosseini",
        "Rostami", "Tehrani", "Najjar", "Sabbagh", "Darwish", "Barakat", "Awad", "Habib", "Jaber", "Kassem", "Maalouf",
        "Nassar", "Obeid", "Rahimi", "Sadeghi", "Shalhoub", "Tahan", "Yousef", "Zayed", "Abboud", "Bishara", "Chahine",
        "Fakhoury", "Ghanem", "Hijazi", "Issa", "Khalil", "Mourad", "Salameh",
    ],
    "african": [
        "Okafor", "Adeyemi", "Okonkwo", "Mensah", "Asante", "Boateng", "Owusu", "Nkosi", "Dlamini", "Ndlovu", "Mokoena",
        "Khumalo", "Kamau", "Mwangi", "Otieno", "Odhiambo", "Njoroge", "Kariuki", "Diallo", "Traore", "Keita", "Sow",
        "Ndiaye", "Diop", "Balogun", "Eze", "Nwosu", "Chukwu", "Obi", "Adebayo", "Oyelaran", "Tshabalala", "Molefe",
        "Banda", "Phiri", "Mutua", "Haile", "Tesfaye", "Bekele", "Girma",
    ],
}

# Night City demographics as weights for the region-first pick. Balance data, not canon: tune freely.
NC_REGION_WEIGHTS = [
    ("american", 22), ("latin", 18), ("japanese", 10), ("chinese", 8), ("southeast_asian", 6), ("african", 6),
    ("korean", 5), ("indian", 5), ("middle_eastern", 4), ("eastern_european", 4), ("british", 3), ("german", 2),
    ("french", 2), ("italian", 2), ("brazilian", 1), ("australian", 1), ("scandinavian", 0.5), ("dutch", 0.5),
]

REAL_NAME_DENYLIST = [
    # Formula 1, past and present
    "Lewis Hamilton", "George Russell", "Lando Norris", "Jenson Button", "James Hunt", "Nigel Mansell", "Damon Hill",
    "Graham Hill", "Jim Clark", "Jackie Stewart", "Stirling Moss", "David Coulthard", "Johnny Herbert",
    "Oliver Bearman", "Max Verstappen", "Jos Verstappen", "Charles Leclerc", "Carlos Sainz", "Fernando Alonso",
    "Sebastian Vettel", "Michael Schumacher", "Ralf Schumacher", "Mick Schumacher", "Nico Rosberg", "Keke Rosberg",
    "Nico Hulkenberg", "Timo Glock", "Nick Heidfeld", "Kimi Raikkonen", "Valtteri Bottas", "Mika Hakkinen",
    "Heikki Kovalainen", "Kevin Magnussen", "Marcus Ericsson", "Ayrton Senna", "Bruno Senna", "Nelson Piquet",
    "Rubens Barrichello", "Felipe Massa", "Felipe Nasr", "Emerson Fittipaldi", "Daniel Ricciardo", "Mark Webber",
    "Oscar Piastri", "Jack Brabham", "Alan Jones", "Sergio Perez", "Esteban Ocon", "Pierre Gasly", "Romain Grosjean",
    "Alain Prost", "Jean Alesi", "Yuki Tsunoda", "Kamui Kobayashi", "Takuma Sato", "Zhou Guanyu", "Guanyu Zhou",
    "Alexander Albon", "Lance Stroll", "Nicholas Latifi", "Jacques Villeneuve", "Gilles Villeneuve", "Logan Sargeant",
    "Daniil Kvyat", "Nikita Mazepin", "Vitaly Petrov", "Robert Kubica", "Jarno Trulli", "Giancarlo Fisichella",
    "Antonio Giovinazzi", "Kimi Antonelli", "Liam Lawson", "Isack Hadjar", "Gabriel Bortoleto", "Jack Doohan",
    "Nyck de Vries", "Stoffel Vandoorne", "Giedo van der Garde", "Jean-Eric Vergne", "Pascal Wehrlein",
    "Jolyon Palmer", "Rio Haryanto", "Adrian Sutil", "Paul di Resta", "Pastor Maldonado", "Juan Pablo Montoya",
    "Niki Lauda", "Gerhard Berger", "Jochen Rindt", "Roland Ratzenberger", "Karl Wendlinger", "Mark Blundell",
    "Martin Brundle", "Eddie Irvine", "Jenson Brooks",
    # IndyCar and sports cars
    "Will Power", "Josef Newgarden", "Scott Dixon", "Alexander Rossi", "Colton Herta", "Pato O'Ward",
    "Scott McLaughlin", "Alex Palou", "Ryan Hunter-Reay", "Graham Rahal", "Bobby Rahal", "Ed Carpenter",
    "James Hinchcliffe", "Robert Wickens", "Mario Andretti", "Michael Andretti", "Marco Andretti", "A.J. Foyt",
    "Al Unser", "Rick Mears", "Dario Franchitti", "Paul Tracy", "Alex Tagliani", "Shane van Gisbergen",
    "Jamie Whincup", "Tom Kristensen", "Jacky Ickx", "Thierry Boutsen", "Christijan Albers", "Tom Coronel",
    "Robert Doornbos",
    # Women in motorsport (the FTB female block)
    "Jamie Chadwick", "Tatiana Calderon", "Simona de Silvestro", "Katherine Legge", "Pippa Mann", "Susie Wolff",
    "Danica Patrick", "Desire Wilson", "Sophia Floersch", "Beitske Visser", "Sarah Fisher", "Milka Duno",
    "Divina Galica", "Giovanna Amati", "Lella Lombardi", "Michela Cerruti", "Bianca Bustamante", "Abbi Pulling",
    "Maria Teresa de Filippis",
]


def blocks(src, listname):
    out, cur, inside = [], None, False
    for line in src:
        if line.startswith(listname + " = ["):
            inside, cur = True, {"h": "(start)", "names": []}
            out.append(cur)
            continue
        if not inside:
            continue
        if line.startswith("]"):
            break
        s = line.strip()
        if s.startswith("#"):
            h = s.lstrip("# ").strip()
            if h and not set(h) <= set("=-"):
                cur = {"h": h, "names": []}
                out.append(cur)
            continue
        cur["names"] += re.findall(r'"([^"]+)"', line)
    return [b for b in out if b["names"]]


def flat(src, listname):
    return [n for b in blocks(src, listname) for n in b["names"]]


def py_list(src_text, name):
    m = re.search(r"^" + name + r"\s*=\s*\[(.*?)^\]", src_text, re.S | re.M)
    if not m:
        raise SystemExit("list not found: " + name)
    return re.findall(r"""['"]([^'"]+)['"]""", re.sub(r"#.*", "", m.group(1)))


def py_dict_lists(src_text, name):
    m = re.search(r"^" + name + r"\s*=\s*\{(.*?)^\}", src_text, re.S | re.M)
    out = {}
    for key, body in re.findall(r"Industry\.(\w+):\s*\[(.*?)\]", m.group(1), re.S):
        out[key.lower()] = re.findall(r"""['"]([^'"]+)['"]""", body)
    return out


def dedupe(seq):
    seen, out = set(), []
    for n in seq:
        if n not in seen:
            seen.add(n)
            out.append(n)
    return out


def dropped(header):
    return any(header.startswith(d) for d in DROP_BLOCKS)


def build(source):
    names_py = open(os.path.join(source, "ftb_names.py"), encoding="utf-8").read()
    sponsors_py = open(os.path.join(source, "ftb_sponsors.py"), encoding="utf-8").read()
    src = names_py.splitlines()

    regions = {r: {"male": [], "female": [], "surnames": []} for r in dict(NC_REGION_WEIGHTS)}
    for listname, key in (("FIRST_NAMES_MALE", "male"), ("FIRST_NAMES_FEMALE", "female")):
        for b in blocks(src, listname):
            if dropped(b["h"]):
                continue
            region = REGION_OF_FIRST.get(b["h"])
            if region is None:
                raise SystemExit("unmapped first-name block: " + b["h"])
            for n in b["names"]:
                if n in LEAKED_SURNAMES:
                    continue
                regions[region][key].append(n[:1].upper() + n[1:])
    for b in blocks(src, "SURNAMES"):
        if dropped(b["h"]):
            continue
        header = re.sub(r"\s*\(\d+ names\)$", "", b["h"])
        region = REGION_OF_SURNAME.get(header)
        if region is None:
            raise SystemExit("unmapped surname block: " + b["h"])
        regions[region]["surnames"] += b["names"]
    for region, names in AUTHORED_SURNAMES.items():
        regions[region]["surnames"] += names
    for r in regions.values():
        for k in r:
            r[k] = dedupe(r[k])
            if not r[k]:
                raise SystemExit("empty region list")

    data = {
        "regions": regions,
        "teamPrefixes": {
            "street": dedupe(flat(src, "TEAM_PREFIXES_GRASSROOTS")),
            "mid": dedupe(flat(src, "TEAM_PREFIXES_MID_TIER")),
            "top": dedupe(flat(src, "TEAM_PREFIXES_TOP_TIER")),
        },
        "teamSuffixes": dedupe(flat(src, "TEAM_SUFFIXES")),
        "sponsorTeamNames": dedupe(flat(src, "SPONSOR_TEAM_NAMES")),
        "leagueRegions": dedupe(flat(src, "LEAGUE_REGIONS")),
        "leagueTypes": {
            "street": dedupe(flat(src, "LEAGUE_TYPES_GRASSROOTS")),
            "mid": dedupe(flat(src, "LEAGUE_TYPES_MID_TIER")),
            "top": dedupe(flat(src, "LEAGUE_TYPES_TOP_TIER")),
        },
        "phoneticConsonants": py_list(sponsors_py, "PHONETIC_CONSONANTS"),
        "phoneticVowels": py_list(sponsors_py, "PHONETIC_VOWELS"),
        "abstractConcepts": py_list(sponsors_py, "ABSTRACT_CONCEPTS"),
        "industrialSuffixes": py_list(sponsors_py, "INDUSTRIAL_SUFFIXES"),
        "techSuffixes": py_list(sponsors_py, "TECH_SUFFIXES"),
        "motorsportCues": py_list(sponsors_py, "MOTORSPORT_CUES"),
        "geographicPrefixes": py_list(sponsors_py, "GEOGRAPHIC_PREFIXES"),
        "industryKeywords": py_dict_lists(sponsors_py, "INDUSTRY_KEYWORDS"),
    }
    return data


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def packed(seq):
    for n in seq:
        if "|" in n:
            raise SystemExit("name contains the separator: " + n)
    return lua_str("|".join(seq))


def render(data):
    L = []
    w = L.append
    w("-- ncm-core module: paddock.names_data")
    w("-- GENERATED by tools/paddock-names-port.py from the owner's FTB name and sponsor generators (L224.7).")
    w("-- DO NOT EDIT BY HAND: change the tool and re-run it; `--check` fails the gate when this file drifts.")
    w("-- Lists are packed as '|'-separated strings and split on first use, which keeps the vendored copy small.")
    w("local Core = NcmCore")
    w("")
    w('Core.define("paddock.names_data", function()')
    w('    local M = { version = "0.1.0" }')
    w("    local function split(s)")
    w("        local out = {}")
    w('        for part in string.gmatch(s, "[^|]+") do out[#out + 1] = part end')
    w("        return out")
    w("    end")
    w("    local packedRegions = {")
    for region, _ in NC_REGION_WEIGHTS:
        r = data["regions"][region]
        w("        %s = {" % region)
        for key in ("male", "female", "surnames"):
            w("            %s = %s," % (key, packed(r[key])))
        w("        },")
    w("    }")
    w("    M.REGION_WEIGHTS = {")
    for region, weight in NC_REGION_WEIGHTS:
        w('        { id = "%s", weight = %s },' % (region, weight))
    w("    }")
    w("    local regionCache = {}")
    w("    --- { male = {...}, female = {...}, surnames = {...} } for a region id, or nil.")
    w("    function M.region(id)")
    w("        local cached = regionCache[id]")
    w("        if cached then return cached end")
    w("        local p = packedRegions[id]")
    w("        if not p then return nil end")
    w("        cached = { male = split(p.male), female = split(p.female), surnames = split(p.surnames) }")
    w("        regionCache[id] = cached")
    w("        return cached")
    w("    end")
    w("    function M.regionIds()")
    w("        local out = {}")
    w("        for i, r in ipairs(M.REGION_WEIGHTS) do out[i] = r.id end")
    w("        return out")
    w("    end")
    lists = {
        "TEAM_SUFFIXES": data["teamSuffixes"], "SPONSOR_TEAM_NAMES": data["sponsorTeamNames"],
        "LEAGUE_REGIONS": data["leagueRegions"], "PHONETIC_CONSONANTS": data["phoneticConsonants"],
        "PHONETIC_VOWELS": data["phoneticVowels"], "ABSTRACT_CONCEPTS": data["abstractConcepts"],
        "INDUSTRIAL_SUFFIXES": data["industrialSuffixes"], "TECH_SUFFIXES": data["techSuffixes"],
        "MOTORSPORT_CUES": data["motorsportCues"], "GEOGRAPHIC_PREFIXES": data["geographicPrefixes"],
    }
    for name, seq in lists.items():
        w("    M.%s = split(%s)" % (name, packed(seq)))
    for name, key in (("TEAM_PREFIXES", "teamPrefixes"), ("LEAGUE_TYPES", "leagueTypes")):
        w("    M.%s = {" % name)
        for tier in ("street", "mid", "top"):
            w("        %s = split(%s)," % (tier, packed(data[key][tier])))
        w("    }")
    w("    M.INDUSTRY_KEYWORDS = {")
    for k in sorted(data["industryKeywords"]):
        w("        [\"%s\"] = split(%s)," % (k, packed(data["industryKeywords"][k])))
    w("    }")
    w("    M.REAL_NAME_DENYLIST = {}")
    w("    for _, n in ipairs(split(%s)) do M.REAL_NAME_DENYLIST[string.lower(n)] = true end" % packed(REAL_NAME_DENYLIST))
    w("    return M")
    w("end)")
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=r"D:/dev/Radio-OS/plugins")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if not os.path.isfile(os.path.join(args.source, "ftb_names.py")):
        print("paddock-names-port: source not found at %s (skipped)" % args.source)
        return 0
    text = render(build(args.source))
    if args.check:
        current = open(OUT, encoding="utf-8").read() if os.path.isfile(OUT) else ""
        if current != text:
            print("paddock-names-port: names_data.lua is STALE against the FTB source; re-run the tool")
            return 1
        print("paddock-names-port: names_data.lua matches the FTB source")
        return 0
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("paddock-names-port: wrote %s (%d bytes)" % (os.path.relpath(OUT), len(text.encode("utf-8"))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
