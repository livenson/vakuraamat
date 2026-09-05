EXTERNAL flag(name)
EXTERNAL has_item(id)
EXTERNAL give_item(id, target)
EXTERNAL take_item(id)
EXTERNAL set_flag(name)
EXTERNAL end_chapter()
EXTERNAL chapter()
EXTERNAL trigger(cp_id)
-> END

== greeter ==
{ not flag("met_era_1938"):
    ~ set_flag("met_era_1938")
    Uus nägu. Kvissentali on väike koht, siin märgatakse. # en: A new face. Kvissentali is a small place, people notice.
    Mis sa siit otsid? # en: What are you looking for here?
- else:
    Jälle sina. # en: You again.
}
-> menu

= menu
+ { flag("well_kept") } [Kaev on veel alles. %% The well is still here.]
    Magus vesi. Vanad ütlesid, et see oleks peaaegu täis aetud. Keegi aitas. # en: Sweet water. The old people said it was nearly filled in. Somebody helped.
    -> menu
+ { not has_item("harvest_letter") and not flag("letter_delivered") } [Kas sa kirjutad? %% Do you write?]
    Kirjutasin ühe kirja. Kellele, ei tea. Panin sinna, kus keegi selle kord leiab. # en: I wrote one letter. To whom, I don't know. I put it where somebody will find it one day.
    -> menu
+ { has_item("graft_bundle") and not flag("orchard_planted") } [Anna pookoksad. %% Hand over the grafting stock.]
    ~ give_item("graft_bundle", "npc_era_1938")
    Need on vanemad kui mina. Ja veel elus. # en: These are older than I am. And still alive.
    Põllu serv. Homme hommikul. Enne kui keegi ütleb, et ei tasu. # en: The edge of the field. Tomorrow morning. Before anyone says it is not worth it.
    -> check_chapter
+ { not has_item("graft_bundle") and not flag("orchard_planted") } [Kas siin õunapuid on? %% Are there apple trees here?]
    Ei. Vanad räägivad, et mõisal oli pookoksi. Kadusid koos mõisaga. # en: No. The old people say the manor had grafting stock. It went with the manor.
    -> menu
+ { not has_item("deed_page") and not flag("boundary_marked") } [Kust see lehekülg pärit on? %% Where is that page from?]
    Vanast raamatust. Keegi rebis välja, keegi hoidis alles. Meie nimi on seal, aga kellele seda näidata. # en: From an old book. Somebody tore it out, somebody kept it. Our name is on it, but who is there to show it to.
    -> menu
+ { flag("boundary_marked") } [Värav põllu serval. %% The gate at the field's edge.]
    Piir on kirjas. Alati oli. Sellepärast värav veel seisab. # en: The boundary is written. Always was. That is why the gate still stands.
    -> menu
+ { flag("keepsake_returned") } [Kivi maamärgi juures. %% The stone by the landmark.]
    Keegi pani selle sinna ammu. Nimi on veel peal. Meie omad hoidsid seda puhtana. # en: Somebody set it there long ago. The name is still on it. Our people kept it clean.
    -> menu
+ [Mis koht see on? %% What is this place?]
    Kvissentali. Kõik, mis siin on, seisab millegi vanema peal. # en: Kvissentali. Everything here stands on something older.
    -> menu
+ [Ma lähen. %% I'll go.]
    Mine. Ma olen siin. # en: Go. I'm here.
    -> END

= check_chapter
{ chapter() == 2 and (flag("well_kept") + flag("orchard_planted") + flag("boundary_marked") + flag("keepsake_returned")) >= 2:
    ~ end_chapter()
}
-> menu
