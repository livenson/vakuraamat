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
    Sa ei ole siit. Aasta on 1938. # en: You're not from here. The year is 1938.
- else:
    Jälle sina. # en: You again.
}
-> menu

= menu
+ { flag("keepsake_returned") } [Kivi maamärgi juures. %% The stone by the landmark.]
    Keegi pani selle sinna ammu. Nimi on veel peal. # en: Somebody set it there long ago. The name is still on it.
    -> menu
+ [Mis koht see on? %% What is this place?]
    Vaata ringi. Maa räägib ise. # en: Look around. The ground speaks for itself.
    -> menu
+ [Ma lähen. %% I'll go.]
    Mine. # en: Go.
    -> END
