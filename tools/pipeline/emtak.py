"""EMTAK (Estonian NACE) sections: a code's first two digits give its section letter; EMTAK 2025
(version 3, NACE Rev. 2.1) renumbers the letters after J compared with EMTAK 2008 (NACE Rev. 2).
The game groups companies by section for colours, signs and interiors."""

# NACE Rev. 2 (EMTAK 2008): (first division, last division) -> letter
SECTIONS_2008 = [(1, 3, "A"), (5, 9, "B"), (10, 33, "C"), (35, 35, "D"), (36, 39, "E"), (41, 43, "F"), (45, 47, "G"), (49, 53, "H"),
                 (55, 56, "I"), (58, 63, "J"), (64, 66, "K"), (68, 68, "L"), (69, 75, "M"), (77, 82, "N"), (84, 84, "O"), (85, 85, "P"),
                 (86, 88, "Q"), (90, 93, "R"), (94, 96, "S"), (97, 98, "T"), (99, 99, "U")]
# NACE Rev. 2.1 (EMTAK 2025): J split into publishing/media (J) and telecom/computing (K), the rest shift one letter
SECTIONS_2025 = [(1, 3, "A"), (5, 9, "B"), (10, 33, "C"), (35, 35, "D"), (36, 39, "E"), (41, 43, "F"), (45, 47, "G"), (49, 53, "H"),
                 (55, 56, "I"), (58, 60, "J"), (61, 63, "K"), (64, 66, "L"), (68, 68, "M"), (69, 75, "N"), (77, 82, "O"), (84, 84, "P"),
                 (85, 85, "Q"), (86, 88, "R"), (90, 93, "S"), (94, 96, "T"), (97, 98, "U"), (99, 99, "V")]

# The game's own groups (stable across versions): key -> (English name, Estonian name)
GROUPS = {
    "farm": ("farming and forestry", "põllumajandus ja metsandus"),
    "industry": ("industry and energy", "tööstus ja energia"),
    "construction": ("construction", "ehitus"),
    "trade": ("trade and repair", "kaubandus"),
    "transport": ("transport and storage", "transport ja ladustamine"),
    "hospitality": ("hotels and restaurants", "majutus ja toitlustus"),
    "media": ("media and IT", "meedia ja IT"),
    "finance": ("finance and insurance", "rahandus"),
    "property": ("real estate", "kinnisvara"),
    "services": ("professional and office services", "teenused"),
    "public": ("public, education and health", "avalik sektor, haridus, tervis"),
    "culture": ("arts, sport and other services", "kultuur, sport, muud teenused"),
}

GROUP_OF_2008 = {"A": "farm", "B": "industry", "C": "industry", "D": "industry", "E": "industry", "F": "construction", "G": "trade",
                 "H": "transport", "I": "hospitality", "J": "media", "K": "finance", "L": "property", "M": "services", "N": "services",
                 "O": "public", "P": "public", "Q": "public", "R": "culture", "S": "culture", "T": "culture", "U": "public"}
GROUP_OF_2025 = {"A": "farm", "B": "industry", "C": "industry", "D": "industry", "E": "industry", "F": "construction", "G": "trade",
                 "H": "transport", "I": "hospitality", "J": "media", "K": "media", "L": "finance", "M": "property", "N": "services",
                 "O": "services", "P": "public", "Q": "public", "R": "public", "S": "culture", "T": "culture", "U": "culture", "V": "public"}

# The Tax Board file names the section in words (upper case Estonian); map the start of the phrase
TAX_SECTION_WORDS = [("PÕLLUMAJANDUS", "farm"), ("MÄETÖÖSTUS", "industry"), ("TÖÖTLEV", "industry"), ("ELEKTRIENERGIA", "industry"),
                     ("VEEVARUSTUS", "industry"), ("EHITUS", "construction"), ("HULGI- JA JAEKAUBANDUS", "trade"), ("VEONDUS", "transport"),
                     ("MAJUTUS", "hospitality"), ("INFO JA SIDE", "media"), ("KIRJASTAMINE", "media"), ("TELEKOMMUNIKATSIOON", "media"),
                     ("FINANTS", "finance"), ("KINNISVARA", "property"), ("KUTSE-", "services"), ("HALDUS-", "services"),
                     ("AVALIK HALDUS", "public"), ("HARIDUS", "public"), ("TERVISHOID", "public"), ("KUNST", "culture"),
                     ("MUUD TEENINDAVAD", "culture"), ("KODUMAJAPIDAMISTE", "culture"), ("EKSTERRITORIAALSETE", "public")]


def section(code, version=2):
    """Section letter of an EMTAK code ('73111' -> 'M' in 2008, 'N' in 2025); '' when unknown."""
    try:
        d = int(str(code)[:2])
    except (TypeError, ValueError):
        return ""
    for lo, hi, letter in (SECTIONS_2025 if int(version or 2) >= 3 else SECTIONS_2008):
        if lo <= d <= hi:
            return letter
    return ""


def group(code, version=2):
    """The game's group key of an EMTAK code ('trade', 'services', ...); '' when unknown."""
    letter = section(code, version)
    table = GROUP_OF_2025 if int(version or 2) >= 3 else GROUP_OF_2008
    return table.get(letter, "")


def group_of_tax_words(text):
    """The group named by the Tax Board's activity phrase; '' when blank or unknown."""
    t = (text or "").strip().upper()
    for start, key in TAX_SECTION_WORDS:
        if t.startswith(start):
            return key
    return ""
