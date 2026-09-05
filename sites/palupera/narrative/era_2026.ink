EXTERNAL flag(name)
EXTERNAL has_item(id)
EXTERNAL give_item(id, target)
EXTERNAL take_item(id)
EXTERNAL set_flag(name)
EXTERNAL end_chapter()
EXTERNAL chapter()
EXTERNAL trigger(cp_id)
-> END

== leida ==
{ not flag("met_leida"):
    ~ set_flag("met_leida")
    Sa oled see uus pärija. Ma nägin autot. # en: You're the new heir. I saw the car.
    Leida Kaseoja. Üheksakümmend üks. Ära vaata nii, ma kuulen paremini kui sina. # en: Leida Kaseoja. Ninety-one. Don't look like that, I hear better than you do.
    Ema ütles, et ta kirjutas kõik üles. Ma ei leidnud seda kunagi. # en: Mother said she wrote it all down. I never found it.
- else:
    Jälle sina. Istu, kui tahad. Tamm ei pahanda. # en: You again. Sit, if you like. The oak doesn't mind.
}
-> leida_menu

= leida_menu
+ { has_item("aino_letter") and not flag("letter_delivered") } [Anna Leidale kiri. %% Give Leida the letter.]
    -> give_letter
+ { flag("north_field_ploughed") } [Põhjapõld on niit. %% The north field is meadow.]
    See aasta, kui nad selle lõpuks sisse said. Isa ütles, et vanaisa raud ei murdu kunagi. Ei murdunudki. # en: The year they finally got it in. Father said grandfather's iron never broke. It never did.
    -> leida_menu
+ { flag("well_kept_open") } [Kaev on veel alles. %% The well is still here.]
    Magus vesi. Mõisa oma oli kibe, ütles ema. Ma ei tea, kust ta seda teadis. # en: Sweet water. The manor's was bitter, mother said. I don't know how she knew.
    -> leida_menu
+ { flag("cellar_opened") } [Õunaaed. %% The orchard.]
    Kolm puud kannavad veel. Ma korjan need iga sügis, ja iga sügis on neid vähem. # en: Three trees still bear. I pick them every autumn, and every autumn there are fewer.
    -> leida_menu
+ { flag("family_recorded_1798") } [Kivi põllu serval. %% The stone at the field edge.]
    Isa raius selle ise. Esimene kord tuli viltu. Teine kord õigesti. # en: Father cut it himself. The first time came out crooked. The second time right.
    -> leida_menu
+ { chapter() >= 3 and not flag("epilogue") } [Istu Leidaga. %% Sit with Leida.]
    -> sit
+ [Mis siin enne oli? %% What was here before?]
    Kõik. Mõis, kool, meie talu, kaev. Sa seisad selle peal. # en: Everything. The manor, the school, our farm, the well. You're standing on it.
    -> leida_menu
+ [Ma lähen vaatan. %% I'll go and look.]
    Mine. Ma olen siin. Ma olen alati siin. # en: Go. I'm here. I'm always here.
    -> END

= give_letter
~ give_item("aino_letter", "npc_leida")
Ta ei loe seda kohe. Ta hoiab seda. # en: She does not read it at once. She holds it.
„Esimesest lõikusest.“ Ema käekiri. Ma tundsin selle ära enne, kui lugesin. # en: "From the first harvest." Mother's hand. I knew it before I read it.
Kast on kõige vanema õunapuu all. Ta ütleb seda siin. Ma oleksin pidanud arvama. # en: The box is under the oldest apple tree. She says so here. I should have guessed.
-> leida_menu

= sit
~ set_flag("epilogue")
~ end_chapter()
Ta patsutab juurt enda kõrval. # en: She pats the root beside her.
Noh. Räägime siis sellest, mis alles on. # en: Well. Let's talk about what's still here.
-> END
