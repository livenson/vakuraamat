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
{ not flag("met_era_1798"):
    ~ set_flag("met_era_1798")
    Sa ei ole siit. Aasta on 1798. # en: You're not from here. The year is 1798.
- else:
    Jälle sina. # en: You again.
}
-> menu

= menu
+ { has_item("keepsake") and not flag("keepsake_returned") } [Anna mälestusese. %% Hand over the keepsake.]
    ~ give_item("keepsake", "npc_era_1798")
    Ta hoiab seda kaua käes. # en: They hold it for a long time.
    { chapter() == 2:
        ~ end_chapter()
    }
    -> menu
+ [Mis koht see on? %% What is this place?]
    Vaata ringi. Maa räägib ise. # en: Look around. The ground speaks for itself.
    -> menu
+ [Ma lähen. %% I'll go.]
    Mine. # en: Go.
    -> END
