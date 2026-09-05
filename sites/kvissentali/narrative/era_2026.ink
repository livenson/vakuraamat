EXTERNAL flag(name)
EXTERNAL has_item(id)
EXTERNAL give_item(id, target)
EXTERNAL take_item(id)
EXTERNAL set_flag(name)
EXTERNAL end_chapter()
EXTERNAL chapter()
EXTERNAL trigger(cp_id)
EXTERNAL visiting()
-> END

== greeter ==
{ not flag("met_era_2026"):
    ~ set_flag("met_era_2026")
    Tere. Sa vaatad maad nagu keegi, kes tahab midagi leida. # en: Hello. You look at the ground like somebody who wants to find something.
    Ma olen siin kogu elu olnud. Küsi. # en: I've been here all my life. Ask.
- else:
    Jälle sina. # en: You again.
}
-> menu

= menu
+ { flag("boundary_marked") } [Värav põllu serval. %% The gate at the field's edge.]
    Piir on kirjas. Alati oli. Sellepärast värav veel seisab. # en: The boundary is written. Always was. That is why the gate still stands.
    -> menu
+ { has_item("harvest_letter") and not flag("letter_delivered") } [Anna kiri. %% Give the letter.]
    ~ give_item("harvest_letter", "npc_era_2026")
    Ta ei loe seda kohe. Ta hoiab seda. # en: They do not read it at once. They hold it.
    „Esimesest lõikusest.“ Ma tundsin käekirja ära enne, kui lugesin. # en: "From the first harvest." I knew the hand before I read it.
    Kast on kõige vanema puu all. Ma oleksin pidanud arvama. # en: The box is under the oldest tree. I should have guessed.
    -> check_chapter
+ { not has_item("harvest_letter") and not flag("letter_delivered") } [Mida siit otsida oleks? %% What would there be to look for here?]
    Ema ütles, et ta kirjutas kõik üles. Ma ei leidnud seda kunagi. # en: Mother said she wrote it all down. I never found it.
    -> menu
+ { flag("well_kept") } [Kaev on veel alles. %% The well is still here.]
    Magus vesi. Vanad ütlesid, et see oleks peaaegu täis aetud. Keegi aitas. # en: Sweet water. The old people said it was nearly filled in. Somebody helped.
    -> menu
+ { not has_item("keepsake") and not flag("keepsake_returned") } [Vana raamatu juures on midagi. %% There is something by the old book.]
    Jah. Vasktükk. Ma ei tea, kelle oma. Nimi on peal, aga mitte meie oma. # en: Yes. A piece of copper. I don't know whose. There is a name on it, but not ours.
    -> menu
+ { flag("keepsake_returned") } [Kivi maamärgi juures. %% The stone by the landmark.]
    Keegi pani selle sinna ammu. Nimi on veel peal. Meie omad hoidsid seda puhtana. # en: Somebody set it there long ago. The name is still on it. Our people kept it clean.
    -> menu
+ { flag("bell_hung") } [Kellapost poe juures. %% The bell post by the shop.]
    Keel on võõras, öeldakse. Keegi tõi. Heli on ikka omal. # en: The clapper is foreign, they say. Somebody brought it. The sound is its own.
    -> menu
+ { flag("orchard_planted") } [Õunaaed. %% The orchard.]
    Kolm puud kannavad veel. Igal sügisel vähem. Aga kannavad. # en: Three trees still bear. Fewer every autumn. But they bear.
    -> menu
+ { chapter() >= 3 and not flag("epilogue") } [Räägime lõpuni. %% Let's finish the conversation.]
    -> sit
+ [Mis koht see on? %% What is this place?]
    Kvissentali. Kõik, mis siin on, seisab millegi vanema peal. # en: Kvissentali. Everything here stands on something older.
    -> menu
+ [Ma lähen. %% I'll go.]
    Mine. Ma olen siin. # en: Go. I'm here.
    -> END

= check_chapter
{ chapter() == 2 and (flag("boundary_marked") + flag("well_kept") + flag("keepsake_returned") + flag("orchard_planted")) >= 2:
    ~ end_chapter()
}
-> menu

= sit
~ set_flag("epilogue")
~ end_chapter()
Noh. Räägime siis sellest, mis alles on. # en: Well. Let's talk about what's still here.
-> END
