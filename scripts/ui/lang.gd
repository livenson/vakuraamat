# The interface languages and the order the language key and menu entries step through them. The
# main menu, the pause menu and the L key all switch through here, so a new language is one line.
class_name Lang
extends RefCounted

const LOCALES := ["et", "en", "lv"]
const NAMES := {"et": "Eesti keel", "en": "English", "lv": "Latviešu valoda"}


## The locale after the current one (the first when the current one is not in the list).
static func next() -> String:
	var at := LOCALES.find(current())
	return LOCALES[(at + 1) % LOCALES.size()] if at >= 0 else LOCALES[0]


## The current locale as one of LOCALES' two-letter codes.
static func current() -> String:
	return TranslationServer.get_locale().substr(0, 2)


## Switch to the next language; returns its name for a notice.
static func cycle() -> String:
	var n := next()
	TranslationServer.set_locale(n)
	return str(NAMES[n])
