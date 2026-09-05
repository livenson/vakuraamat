EXTERNAL flag(name)
EXTERNAL has_item(id)
EXTERNAL give_item(id, target)
EXTERNAL take_item(id)
EXTERNAL set_flag(name)
EXTERNAL end_chapter()
EXTERNAL chapter()
EXTERNAL trigger(cp_id)
-> END

== aino ==
{ not flag("met_aino"):
    ~ set_flag("met_aino")
    Kaseoja Aino. Jah, Kaseoja, mitte Birkenbach, mis iganes maamõõtja paberid ütlevad. # en: Aino Kaseoja. Yes, Kaseoja, not Birkenbach, whatever the surveyor's papers say.
    Uksel olev nimi on vanem kui paberitel olev. # en: The name on the door is older than the name on the papers.
    Vana paruni õunapuude istikud on kooli all keldris, öeldakse. Kellelgi pole sada aastat võtit olnud. # en: The old baron's orchard stock is under the school, they say. Nobody's had the key for a hundred years.
- else:
    Sa jälle. Juhan on põllul, kui sa teda otsid. Ader on katki. Jälle. # en: You again. Juhan's in the field if you want him. The plough's broken. Again.
}
-> aino_menu

= aino_menu
+ { has_item("manor_key") and not flag("cellar_opened") } [Anna Ainole mõisa võti. %% Give Aino the manor key.]
    -> give_key
+ { flag("family_recorded_1798") and not flag("aino_thanked") } [Maamõõtja leidis nime. %% The surveyor found the name.]
    ~ set_flag("aino_thanked")
    Leidis! Kaseoja Mart, 1798, paruni enda raamatus. Ma ütlesin talle. Ma ütlesin. # en: He found it! Kaseoja Mart, 1798, in the baron's own book. I told him. I told him.
    -> aino_menu
+ [Kes te olete? %% Who are you?]
    Esimesed, kes selle maa peal omad on. Vanaisa vanaisa oli siin sunnismaine. Nüüd on see meie. Laenuga, aga meie. # en: The first who own this ground. Grandfather's grandfather was bound here. Now it's ours. On credit, but ours.
    -> aino_menu
+ [Kus Juhan on? %% Where's Juhan?]
    Põhjapõllul, katkise adra juures. Ta parandab kõike, mis ei liigu, ja kõik liigub kiiremini kui tema. # en: In the north field, by the broken plough. He mends everything that doesn't move, and everything moves faster than he does.
    -> aino_menu
+ [Ma lähen. %% I'll go.]
    Mine. Tüdruk on kuskil siin, ära komista. # en: Go. The girl is somewhere here, don't trip over her.
    -> aino_done

= give_key
~ give_item("manor_key", "npc_aino")
Ta vaatab võtit nagu asja, mis ei tohiks olemas olla. # en: She looks at the key like a thing that should not exist.
Kool ei pane pahaks. Õpetaja on ise uudishimulik. # en: The school won't mind. The teacher's curious herself.
Sel kevadel lähevad istikud maha. Mõisa alla, nõlvale. Sa näed. # en: This spring the saplings go in. Below the manor, on the slope. You'll see.
-> aino_menu

= aino_done
-> chapter_check

== juhan ==
{ not flag("met_juhan"):
    ~ set_flag("met_juhan")
    Kaseoja Juhan. Ära astu vakku. # en: Juhan Kaseoja. Don't step in the furrow.
    Uus ader, uus tera, pooleks. Keset hooaega. # en: New plough, new share, in two. Mid-season.
    Vanaisa vana raud oleks selle ära teinud. See asi ei murdunud kunagi. # en: Grandfather's old iron would've done it. That thing never broke.
- else:
    Ikka katki. # en: Still broken.
}
-> juhan_menu

= juhan_menu
+ { has_item("ploughshare") and not flag("north_field_ploughed") } [Anna Juhanile sahatera. %% Give Juhan the ploughshare.]
    -> give_share
+ { flag("north_field_ploughed") } [Kuidas põld? %% How's the field?]
    Sees. Terve põhjapõld, enne vihma. Ma ei küsi, kust sa selle raua said. # en: In. The whole north field, before the rain. I'm not asking where you got that iron.
    -> juhan_menu
+ [Mis sa siia külvad? %% What are you sowing here?]
    Rukist, kui ader lubab. Kaera, kui ei luba. Metsa, kui ma midagi ei tee. # en: Rye, if the plough allows. Oats, if it doesn't. Forest, if I do nothing.
    -> juhan_menu
+ [Edu. %% Good luck.]
    Mhm. # en: Mhm.
    -> chapter_check

= give_share
~ give_item("ploughshare", "npc_juhan")
Ta kaalub seda käes. Pöörab ümber. Lööb küünega. # en: He weighs it in his hand. Turns it over. Taps it with a nail.
See on see. See on täpselt see. # en: That's it. That's exactly it.
Ta ei ütle aitäh. Ta on juba adra juures. # en: He does not say thank you. He is already at the plough.
-> juhan_menu

== villem ==
{ not flag("met_villem"):
    ~ set_flag("met_villem")
    Tamberg, maakonna maamõõtja. Te ei ole juhuslikult Kaseoja? Ei? Kahju. Keegi pole. # en: Tamberg, county surveyor. You wouldn't happen to be a Kaseoja? No? Pity. Nobody is.
    Minu toimikutes on Birkenbach. Nemad ütlevad Kaseoja. Kuni miski vanem ei ütle mõlemat, pole mul siin talu. # en: My files say Birkenbach. They say Kaseoja. Until something older says both, I have no farm here.
- else:
    Ikka sama piir, ikka sama nimi, ikka sama küsimus. # en: Same boundary, same name, same question.
}
-> villem_menu

= villem_menu
+ { flag("family_recorded_1798") and not flag("villem_resolved") } [Paruni raamat ütleb mõlemat. %% The baron's book says both.]
    ~ set_flag("villem_resolved")
    Ta paneb prillid ette. Võtab ära. Paneb uuesti ette. # en: He puts on his glasses. Takes them off. Puts them on again.
    Kaseoja Mart, 1798. Sama talu. Sama pere. Sada nelikümmend aastat. # en: Kaseoja Mart, 1798. The same farm. The same family. A hundred and forty years.
    Noh. Siis on piir seal, kus nad ütlevad. Ma märgin selle ära. Kiviga, kui nad tahavad. # en: Well. Then the boundary is where they say. I'll mark it. With a stone, if they want.
    -> villem_menu
+ [Mis vahet on nimel? %% What does the name matter?]
    Vahet on sellel, kellele maa kuulub. Maaseadus annab talu sellele, kes seda hariis. Toimik ütleb, kes hariis. Toimik ütleb Birkenbach. # en: The difference is who owns the land. The Land Act gives the farm to whoever worked it. The file says who worked it. The file says Birkenbach.
    -> villem_menu
+ [Kus on vana raamat? %% Where is the old book?]
    Vakuraamat? Mõisas, kui mõisa veel oli. Keegi pole seda inimpõlve jooksul näinud. # en: The register? In the manor, when there still was a manor. Nobody has seen it in a lifetime.
    -> villem_menu
+ [Head päeva. %% Good day.]
    Kui te Kaseojasid näete, öelge, et ma olen ikka veel siin. Ja ikka veel eksinud. # en: If you see the Kaseojas, tell them I'm still here. And still lost.
    -> chapter_check

== chapter_check ==
{ flag("met_aino") and flag("met_juhan") and flag("met_villem") and chapter() == 2:
    ~ end_chapter()
}
-> END
