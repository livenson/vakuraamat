# Vakuraamat — language across the three eras

> **Revision note (2026-09-05):** this document describes the historical three-era game, kept at the
> git tag `v0.9-historical`. The game is now a present-day economy on the same real ground with a shared
> town ledger; the current rules are in `AGENTS.md`, `README.md` and `docs/custom-sites.md`.


**Purpose of this document:** a reference for writing dialogue, examine-text, and in-world documents so that each era *sounds* right, plus the localization consequences. Complements `first-iteration-design.md`. Everything here is scoped to the slice's three eras (1798, 1938, 2026) and the Palupera area, which sits in the **Tartu dialect** zone of South Estonian.

The short version: the three eras are three different linguistic worlds, and the differences are themselves material for the game — including one that improves the family's story.

---

## 1. The big picture

| | 1798 | 1938 | 2026 |
|---|---|---|---|
| What the family speaks at home | Tartu dialect (South Estonian) | Tartu dialect, shifting toward standard | Standard Estonian; Leida keeps dialect features |
| What is written locally | Old Tartu literary language (church, school), old orthography | Standard Estonian, modern orthography | Standard Estonian |
| Language of power / administration | German (the register, the manor, the courts) | Estonian (the republic, the school, the surveyor) | Estonian (and English on the phone) |
| What the family calls themselves | *maarahvas*, speaking *maakeel* | *eestlased*, speaking *eesti keel* | *eestlased* |
| Family name | None — farm name + first name | A surname, possibly newly Estonianized | The same surname |
| Literacy | Reading (catechism, hymnbook); writing rare | Universal; newspapers, radio, schoolbooks | Universal; screens |

## 2. 1798 — the manor era

### 2.1 Two Estonians, and German on top
There were two written Estonian languages in 1798, not one. The Palupera area used the **South Estonian / Tartu literary language** ("Tartu keel"), based on the Tartu dialect and used in church, school, and court in Tartumaa and Võrumaa from the 17th century until it faded in the second half of the 19th. The New Testament had been available in it since 1686 — thirty years before the North Estonian one. Sample features from the standard reference description: *enge* 'but', *rügga* 'rye', *pään* 'in the head', *latsile* 'to the children', *ma laula* 'I sing', *es olle* 'was not', *om tettu* 'is done'.

What Mart actually *spoke* was the Tartu dialect — closer to that literary form than modern standard Estonian is, but not identical. The gap between the written church language and peasant speech was, by the linguists' own account, especially wide until the mid-19th century.

Above both sat **German**. The register (the *Wackenbuch*, which is where the word *vakuraamat* comes from) was kept in German, as were the manor's accounts, the court records, and the baron's world. The steward is the bilingual hinge: German to the manor, Estonian to the farms.

### 2.2 Old orthography
Anything written in Estonian in 1798 uses the **old orthography** (*vana kirjaviis*), devised in Tartu in the 1680s on German principles. Its tells: a long vowel in an open syllable written single (*hä* for *hea*, *Loja* for *looja*), long vowels in closed syllables doubled (*pääl*), and short vowels marked by doubling the *following consonant* (*Karro* for *karu*, *Sabba* for *saba*). Nouns capitalized, German-style. This is what a 1798 hymnbook, catechism, or school primer in the game should look like on the page.

A real local example, from the 1863 school inspection record for Palupera (later than 1798, but the same local variety in the same orthography): *"Lastele saap kolin õppetedus: werima, luggema, üte hälega laulma ja ka paar wisi nelja häle pääl, ütskord üts, weidike pääst arvama..."* ("The children are taught at school: writing, reading, singing in one voice and a few tunes in four, the times table, a little mental arithmetic…"). This single sentence is a better style guide than any grammar.

### 2.3 Identity words that did not exist yet
Mart would **not** say *eestlane* or *eesti keel*. Until the national awakening of the mid-19th century Estonians called themselves *maarahvas* ("the country people") and their language *maakeel*; the South Estonian variant was named *Tarto-Ma Keel*. The word *eestlane* came into wide use only in the 1850s–60s. In 1798 the operative contrast is *maarahvas* vs. *saksad* (Germans, i.e. the manor). The most authentic single detail the 1798 dialogue can carry is that nobody in it says "Estonian."

### 2.4 Names and address
- **No surnames.** Livonian peasants received surnames only in 1823–26. Mart is *Kaseoja Mart* — farm name first, then given name. The steward's register lists him under the farm (the German *Gesinde*), not under a family name.
- **Given names** are the Lutheran stock in their spoken forms: Mart, Jaan, Hans, Peep, Jüri, Ann, Mari, Liis, Kai.
- **Address upward:** the baron is *herra* or simply *saks*; the steward is *kubjas* (from the office) or by name. Address downward is by farm name or bare given name. The formal/informal *teie/sina* distinction as it works today is not the frame; social distance was carried by titles and by who was allowed to speak at all.

### 2.5 The vocabulary of obligation (use it — it's the theme)
| Estonian (1798 sense) | German (register) | English gloss |
|---|---|---|
| vakuraamat | Wackenbuch | the manor's register of farms and obligations — the game's title object |
| adramaa | Haken | "plough-land": the unit of land assessment, a full farm needing one plough and a pair of oxen, including its share of meadow and forest |
| talu, talumaja | Gesinde | farm, farmstead (as a taxable unit) |
| peremees | Wirth | the farm's head |
| teoorjus, teopäev | Frohne, Frohntag | corvée labour; a labour-day owed to the manor |
| kubjas | Kubjas / Aufseher | overseer |
| kilter | Kilter | under-overseer, field foreman |
| aidamees | Kleetenkerl | granary keeper |
| magasiait | Magazin | the communal grain store |
| vald | Gebiet / Gemeinde | at this date: the manor's peasant community, not a territory |

Two things follow. First, the register the player carries is in German — the design should decide whether its 1798 pages appear untranslated (with the game language alongside) or rendered; the former is more authentic and costs little. Second, the word *vald* meant "the people belonging to this manor" in 1798 and "a municipality" by 1938: the same word, a different world, which the surveyor can be confused by.

### 2.6 How to write it (Estonian source text)
Do **not** write Mart's lines in full Tartu dialect or old orthography — a modern player can't read it fluently, and it can't be localized. Write standard Estonian with a *controlled* set of South Estonian markers, applied consistently to all 1798 speakers:
- Negation with *es* / *ei ole* → *es olõ / es tulõ* only if you commit to the vowel; otherwise keep *ei* and mark elsewhere.
- A few high-frequency dialect words: *latse* (children), *tsiga* (pig), *rüga* (rye), *pääl*, *säält*, *om* (is), *ütle* (say).
- No modern abstractions, no words coined after 1900 (see 3.2).
- Rhythm: short clauses, proverbs, understatement. Mart's dry humour lives in what he leaves out.

Written documents (a hymnbook, a school slate, the register margin) *can* use old orthography in full, because they are read as objects, not as speech.

---

## 3. 1938 — the republic

### 3.1 Standard Estonian arrives in the village
By 1938 there is one written Estonian, based on the North Estonian tradition; the Tartu literary language is gone as a written medium. The **new orthography** (essentially today's) has been in place since the 1870s–80s. The Estonian Literary Society's 1872 programme "to cultivate the Estonian written language, make it fuller and more uniform" has been fulfilled; there are dictionaries, a language academy, a state that legislates in Estonian.

Two waves have reshaped the vocabulary within living memory:
- **The awakening (1860s–80s)** gave the language its national words: *eestlane, Eesti, eesti keel, rahvus, isamaa.* By 1938 these are not new — they are the water the characters swim in.
- **Johannes Aavik's language reform (1910s–20s)** consciously modernized the language: coined and revived words (*relv* 'weapon', *veenma* 'to convince', *laip* 'corpse', *mõrv* 'murder', *ese* 'object' and hundreds more), new grammatical shortcuts, a taste for compactness. A schoolteacher or a newspaper-reading farmer in 1938 uses these without noticing; Mart in 1798 could not have.

Aino and Juhan therefore **code-switch**: Tartu dialect at home and with neighbours, standard Estonian with the surveyor, the teacher, the bank, the radio. This is real, it is period-accurate, and it gives the writer a cheap, honest way to show who they are with — and it lets the player hear the dialect thread that connects them back to Mart.

### 3.2 New words for a new world (and words that don't exist yet)
Period vocabulary the 1938 scenes should use naturally: *asundustalu* (settler farm from the land reform), *maaseadus* (the 1919 Land Act), *maamõõtja* (surveyor), *vallavalitsus* (municipal government), *riigivanem* (head of state), *raadio*, *piimaühing* (dairy cooperative), *seltsimaja* (community hall), *kaitseliit*, *koolimaja*, *laen* (loan — many settler farms were bought on long-term credit).

Words that must **not** appear in 1938: *kolhoos, sovhoos, nõukogude, küüditamine* — and also nothing the characters could only know from after 1940. The lightness of the era is honest only if the characters' vocabulary is honest.

### 3.3 The name campaign — and what it does for the Kaseoja family
This is the linguistic fact that improves the story.

- Livonian peasants got surnames in **1823–26**, chosen more or less freely but under manor influence, often German-flavoured, sometimes simply the farm name.
- From the 1920s, and as **state policy from 1 January 1935** (free of charge, decided by the local registrar), Estonia ran a national campaign to Estonianize "foreign-sounding" (mostly German) surnames. It became a boom: some 78,000 changes are recorded for 1919–1940, the great majority after 1935, until the Soviet occupation cut it off. Common methods: translation (*Johannisbeer → Sõstar*), partial translation (*Alberg → Altmäe*), sound-alike (*Sauer → Saue*), and, less often than linguists later wished, reverting to the **farm name**.

**Proposal:** in 1826 the family was registered as **Birkenbach** — the steward's German for the farm, *Kaseoja*, birch brook. In **1937**, in the middle of the campaign, Aino and Juhan Estonianize it back to **Kaseoja**. They are not inventing a name; they are taking back the one the land already had. The ledger in the player's hands shows all three states: *Kaseoja Mart* (1798), *Birkenbach* (the 1826 entry and the 1920s land-reform paperwork), *Kaseoja* (1937 onward).

This does three things at once:
1. It makes **CP1** mechanically and emotionally exact. The surveyor cannot match "Birkenbach" in the land-reform files to the "Kaseoja" family in front of him; the 1798 register page, with *Kaseoja Mart* on it, is the missing link that proves the farm and the family have been the same thing for 140 years.
2. It gives Aino a line worth having: the name on the door is older than the name on the papers.
3. It plants the theme — the land's name outlasting every administration's name for it — inside the family's own surname, without a word of exposition.

Verify *Kaseoja* against the National Archives' name-change database (the Onomastika register of 1919–1940 changes) to make sure the specific German→Estonian pair is not a real family's documented change.

### 3.4 How to write it
Warm, plain, slightly formal in public and loose at home. Aino's sentences run on; Juhan's don't. Standard Estonian with the *same* dialect markers as 1798 when they speak to each other — that continuity is the point. The surveyor speaks pure 1930s officialese, a little pompous, full of Aavik-era words he's proud of. The schoolteacher, if voiced, is the standard-language enforcer, kindly.

---

## 4. 2026 — the present

Standard Estonian, informal register, with English loans and phone-era clipping in the player's examine-text (*okei, tšekkima, laikima* used sparingly — the player voice is dry, not slangy). The player is likely urban; their Estonian has no dialect.

**Leida is the bridge.** Born in the mid-1930s, she speaks standard Estonian shaped by Soviet-era schooling, but her *home* Estonian is the Tartu dialect she learned from Aino and Juhan, and her vocabulary keeps 1930s words the player has just heard in 1938 (*asundustalu, seltsimaja, piimaühing*). When she uses one, the player should recognize it. This is the cheapest possible way to make the eras feel connected: the same words in an old woman's mouth.

The one era-change that should be *audible* in 2026 and absent before: English. A phone notification, a road sign, an app. Small, and enough.

---

## 5. Writing guidelines by era (summary)

| | 1798 | 1938 | 2026 |
|---|---|---|---|
| Base | Standard Estonian + controlled South Estonian markers | Standard Estonian; dialect markers at home, none in public | Standard, informal |
| Forbidden | Post-1850 identity words; post-1900 coinages; surnames | Post-1940 words; anything Soviet | Nothing forbidden; avoid overdoing slang |
| Signature words | *maarahvas, saksad, kubjas, adramaa, teopäev, vakuraamat* | *asundustalu, maamõõtja, raadio, laen, nimede eestistamine* | *rakendus, telefon, pärand* |
| Documents on screen | Old orthography, German register | Modern orthography, typed forms, newspaper | Screens, a laminated info board |
| Address | Titles and farm names | *Teie* in public, *sina* at home | *Sina* almost everywhere; Leida uses *teie* to the player at first, then stops |

## 6. Localization into English

Estonian is the source; English is the translation. Principles:
- **Do not fake a dialect in English.** No rural-English, no dropped g's. Carry the 1798 and home-1938 registers through *rhythm and vocabulary*: shorter sentences, concrete nouns, no abstractions, no contractions in 1798.
- **Keep the untranslatable words untranslated,** in italics, with the journal's codex explaining them once: *vakuraamat, adramaa, kubjas, asundustalu.* They are the texture; translating them flattens the eras into each other.
- **Render the identity gap explicitly.** Where Mart says *maarahvas*, the English should say "us, the country people" or similar, never "Estonians" — the English reader must also feel that the word isn't there yet.
- **The German register pages** appear untranslated in both languages, with a hover/tap gloss. This is one asset serving both locales.
- **The name story** survives translation intact (*Birkenbach → Kaseoja* needs one line of explanation in the codex: "birch brook").
- **Era-specific English tone:** 1798 plain and slightly formal, no archaisms like *thee/thou*; 1938 warm and period-neutral, no Americanisms; 2026 contemporary.

## 7. Resources and checks
- **Vana kirjakeele sõnastik** (University of Tartu) — the dictionary of the old written language; the place to check whether a word existed and what it meant in 1798.
- **The Estonian Encyclopaedia and EKI (Institute of the Estonian Language)** entries on *tartu keel* and the history of the written language.
- **The Palupera local-history blog** (paluperaajalugu.blogspot.com) — farm names, the 1863 school record, excerpts of the Mellin and Rücker maps for the exact area.
- **Rahvusarhiiv Onomastika** — the searchable database of 1919–1940 surname changes; use it both to verify *Kaseoja* and to mine authentic period examples.
- **Get one South Estonian dialect reader** (a Tartu or Võru speaker, or a philologist) to review the 1798 and home-1938 lines before recording or shipping. The dialect markers are easy to get slightly and audibly wrong, and this is the one place a native South Estonian player will judge the game hardest.
