EXTERNAL flag(name)
EXTERNAL has_item(id)
EXTERNAL give_item(id, target)
EXTERNAL take_item(id)
EXTERNAL set_flag(name)
EXTERNAL end_chapter()
EXTERNAL chapter()
EXTERNAL trigger(cp_id)
-> END

== mart ==
{ not flag("met_mart"):
    ~ set_flag("met_mart")
    Kaseoja Mart. Sa ei ole saksa. Sa ei ole ka meie oma. Mis sa siis oled? # en: Mart of Kaseoja. You're not a German. You're not one of us either. What are you, then?
    Ütle, kui välja mõtled. Mul om töö pooleli. # en: Tell me when you've worked it out. I've work half done.
- else:
    Jälle sina. Kubjas käis. Kaev tuleb täis ajada, ütles. # en: You again. The steward came by. The well is to be filled, he said.
}
-> mart_menu

= mart_menu
+ [Miks kaev täis aetakse? %% Why fill the well?]
    Mõisa kaev teenib, ütleb ta. Keda teenib. # en: The manor's well will serve, he says. Serve whom.
    Ma kaevasin selle kahe suvega. Vesi om magus. Mõisa oma om kibe. # en: I dug it in two summers. The water is sweet. The manor's is bitter.
    -> mart_menu
+ [Vana raud seal seina ääres? %% The old iron by the wall?]
    Sahatera. Isa oma. Ei murdu. Võta, kui tahad, mul om uus. Uus murdub. # en: A ploughshare. Father's. Doesn't break. Take it if you want, I've a new one. The new one breaks.
    -> mart_menu
+ [Kes sa oled? %% Who are you?]
    Kaseoja Mart. Kaseoja om talu. Mart om mina. Rohkem nime mul ei ole ja rohkem ei ole vaja. # en: Mart of Kaseoja. Kaseoja is the farm. Mart is me. I have no more name than that and need no more.
    Maarahvas, ütleks kubjas. Tema om saks. Meie oleme need, kes maa pääl om. # en: Country people, the steward would say. He's a German. We're the ones who are on the land.
    -> mart_menu
+ [Ma lähen. %% I'll go.]
    Mine. Kui kubjast näed, ära ütle, et ma kaevu juures olen. # en: Go. If you see the steward, don't say I'm at the well.
    -> END

== hans ==
{ not flag("met_hans"):
    ~ set_flag("met_hans")
    Hans. Kubjas. Sa ei ole raamatus. Kõik, kes siin om, om raamatus. # en: Hans. Steward. You're not in the book. Everyone who is here is in the book.
    Paruni raamat. Vakuraamat, kui sa maakeelt räägid. Iga talu, iga pere, iga päev, mis mõisale võlgu. # en: The baron's book. The register, if you speak the country tongue. Every farm, every family, every day owed to the manor.
- else:
    Sa oled ikka veel siin ja ikka veel mitte raamatus. # en: Still here and still not in the book.
}
-> hans_menu

= hans_menu
+ { has_item("register_page") and not flag("family_recorded_1798") } [Näita Hansule registrilehte. %% Show Hans the register page.]
    -> give_page
+ { flag("family_recorded_1798") } [Kaseoja pere. %% The Kaseoja family.]
    Sisse kantud. Talu nime all, nii nagu peab. Mis sellest saja aasta pärast saab, pole minu asi. # en: Entered. Under the farm's name, as it should be. What becomes of it in a hundred years is not my business.
    -> hans_menu
+ [Mis kaevust saab? %% What about the well?]
    Täis aetakse. Paruni kaev teenib kõiki. Kaks kaevu om üks kaev liiga palju. # en: It gets filled. The baron's well serves all. Two wells is one well too many.
    -> hans_menu
+ [See võti trepil? %% That key on the steps?]
    Keldri oma. Paruni õunapuud om seal, pooked, kastides. Ta ei tule neid kunagi istutama. Ta ei tule üldse. # en: The cellar's. The baron's apple grafts are down there, in boxes. He never comes to plant them. He never comes at all.
    -> hans_menu
+ [Head päeva. %% Good day.]
    Paruni päev, mitte minu. # en: The baron's day, not mine.
    -> END

= give_page
~ give_item("register_page", "npc_hans")
Ta loeb kaua. Käekiri om võõras, paber om võõras, nimi om tema oma raamatust. # en: He reads for a long time. The hand is strange, the paper is strange, the name is from his own book.
Kaseoja Mart. Talu nime all. Nii ma selle sisse kirjutan, nii jääb. # en: Kaseoja Mart. Under the farm's name. That is how I enter it and how it stays.
Ta kirjutab. Ta ei küsi, kust leht tuli. Raamat ei küsi. # en: He writes. He does not ask where the page came from. The book does not ask.
-> hans_menu

== well ==
{ flag("well_kept_open"):
    Kaev seisab. Mart toestas selle ja kubjas ei tulnud tagasi. # en: The well stands. Mart shored it up and the steward did not come back. # speaker: LOC_WELL
    -> END
}
Mart on kaevu juures, palgid käes. # en: Mart is at the well, logs in his arms. # speaker: LOC_WELL
Kubjas ütleb täis ajada. Ma ütlen, et enne ma toestan. Kumb sa oled? # en: The steward says fill it. I say I shore it up first. Which are you? # speaker: NPC_MART
+ [Aita Mardil kaevu toestada. %% Help Mart shore up the well.]
    ~ trigger("cp3_well_kept")
    Palgid lähevad kohale. Kivid pääle. Kubjas näeb seda homme ja homme om juba hilja. # en: The logs go in. Stones on top. The steward will see it tomorrow and tomorrow is already too late. # speaker: NPC_MART
    Vesi om magus. Proovi. # en: The water is sweet. Try it. # speaker: NPC_MART
    -> END
+ [Jäta see kubjase asjaks. %% Leave it to the steward.]
    Ta noogutab. Ta ei ole üllatunud. # en: He nods. He is not surprised. # speaker: LOC_WELL
    Saksad om saksad, ütleb ta, ja läheb palkidega minema. # en: Germans are Germans, he says, and walks off with the logs. # speaker: LOC_WELL
    -> END
