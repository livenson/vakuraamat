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
{ not flag("met_era_1798"):
    ~ set_flag("met_era_1798")
    Võõras. Kvissentali ei näe võõraid tihti. # en: A stranger. Kvissentali does not see strangers often.
    Räägi, aga lühidalt. Päev on lühike. # en: Speak, but briefly. The day is short.
- else:
    Jälle sina. # en: You again.
}
-> menu

= menu
+ { has_item("deed_page") and not flag("boundary_marked") } [Näita lehekülge. %% Show the page.]
    ~ give_item("deed_page", "npc_era_1798")
    Ta loeb. Loeb veel kord. # en: They read it. Read it again.
    See on minu käekiri. Ma ei mäleta, et oleksin selle kirjutanud. Aga nüüd kirjutan. # en: That is my hand. I do not remember writing it. But I will write it now.
    -> check_chapter
+ { not has_item("deed_page") and not flag("boundary_marked") } [Kes siin raamatut peab? %% Who keeps the book here?]
    Mina. Talud, kohustused, piirid. Kui midagi ei ole kirjas, ei ole seda olemas. # en: I do. Farms, obligations, bounds. What is not written does not exist.
    -> menu
+ { not flag("well_kept") } [Miks kaev täis aetakse? %% Why fill the well?]
    Sest käsk on nii. Mõisa kaev teenib, öeldakse. Keda teenib. # en: Because the order says so. The manor's well will serve, they say. Serve whom.
    Kui keegi aitaks kivid paika tõsta, ei saaks seda enam täita. # en: If somebody helped set the stones, it could not be filled any more.
    -> menu
+ { has_item("keepsake") and not flag("keepsake_returned") } [Anna mälestusese. %% Hand over the keepsake.]
    ~ give_item("keepsake", "npc_era_1798")
    Ta keerab seda kaua käes. Siis noogutab. # en: They turn it over in their hands for a long time. Then nod.
    See panen ma kivi alla. Et keegi teaks. # en: This I will put under a stone. So that somebody knows.
    -> check_chapter
+ { not has_item("keepsake") and not flag("keepsake_returned") } [Kas siit on midagi kadunud? %% Has anything gone missing here?]
    Vasktükk, nimega. Isa oma. Kadus ühel sügisel ja ei tulnud tagasi. # en: A piece of copper, with a name. Father's. It vanished one autumn and never came back.
    -> menu
+ { not has_item("bell_clapper") and not flag("bell_hung") } [Mis raud see seal maas on? %% What iron is that on the ground?]
    Kellakeel. Kell läks mõisaga. Keel jäi. Meie omad ei tohi seda viia, nii on vana sõna. # en: A bell clapper. The bell went with the manor. The clapper stayed. Our own may not carry it, so the old word goes.
    -> menu
+ { not has_item("graft_bundle") and not flag("orchard_planted") } [Mis kimp see seal on? %% What is that bundle over there?]
    Pookoksad. Mõisa aednik jättis. Meil ei ole aega ega maad. Võta, kui tahad. # en: Grafting stock. The manor's gardener left them. We have neither time nor ground. Take them if you like.
    -> menu
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

== well_choice ==
Kivid on kuhjas. Kaevaja vaatab sind. # en: The stones lie in a heap. The digger looks at you.
+ [Aita kivid paika. %% Help set the stones.]
    ~ trigger("cp_well")
    Pool päeva. Käed on marraskil. Ring on kinni. # en: Half a day. Hands raw. The ring is closed.
    -> END
+ [Jäta. %% Leave it.]
    Kaevaja pöörab selja. # en: The digger turns away.
    -> END
