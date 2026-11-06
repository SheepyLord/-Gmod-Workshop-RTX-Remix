--[[
	Dynamic Toolgun Screen - Deutsch (de)

	Made from lang/en.lua with tools/i18n.py (see TRANSLATING.md). Above each phrase, "-- en:" holds the
	English it translates; "tools/i18n.py check" lists phrases whose English changed since. A phrase
	missing here falls back to English.
]]

return {

	-- name of the language in that language, shown in the language list
	-- en: English
	[ "_name" ] = "Deutsch",

	-- decimal separator for numbers on the screen
	-- en: .
	[ "_decimal" ] = ",",

	-- 1 if a 24 hour clock is usual in this language, 0 for 12 hour
	-- en: 0
	[ "_clock24" ] = "1",

	-- fonts that have every letter of the language; size factor and weight snapping (1/0) for them
	-- en: Tahoma
	[ "_font.ui" ] = "Tahoma",

	-- en: Helvetica
	[ "_font.hero" ] = "Helvetica",

	-- en: Consolas
	[ "_font.mono" ] = "Consolas",

	-- en: 1
	[ "_font.scale" ] = "1",

	-- en: 0
	[ "_font.snap" ] = "0",

	-- Shown by the game: the tool list, the tool's help on the HUD, the context menu, the Utilities tab --
	-- en: Dynamic Toolgun Screen
	[ "tool.name" ] = "Dynamisches Werkzeugpistolen-Display",

	-- en: Customize the tool gun's live screen and track entities on it
	[ "tool.desc" ] = "Passe das Live-Display der Werkzeugpistole an und verfolge Objekte darauf",

	-- en: Track the entity you are aiming at
	[ "tool.left" ] = "Verfolge das anvisierte Objekt",

	-- en: Switch to the next screen layout
	[ "tool.right" ] = "Wechsle zum nächsten Display-Layout",

	-- en: Stop tracking
	[ "tool.reload" ] = "Beende die Verfolgung",

	-- context menu entry (right click an entity while holding C)
	-- en: Track on tool gun screen
	[ "prop.track" ] = "Auf dem Werkzeugpistolen-Display verfolgen",

	-- Utilities tab: category and its only entry
	-- en: Dynamic Toolgun Screen
	[ "menu.category" ] = "Dynamisches Werkzeugpistolen-Display",

	-- en: Settings
	[ "menu.settings_item" ] = "Einstellungen",

	-- status line; {name} is an entity name such as "oildrum001" or a player's name
	-- en: Aiming at **{name}**
	[ "target.entity" ] = "Ziel: **{name}**",

	-- en: Aiming at the **sky**
	[ "target.sky" ] = "Ziel: **Himmel**",

	-- en: World
	[ "target.world" ] = "Welt",

	-- {surface} is a material from the mat.* phrases below
	-- en: World - **{surface}**
	[ "target.world_surface" ] = "Welt - **{surface}**",

	-- en: Nothing in range
	[ "target.nothing" ] = "Nichts in Reichweite",

	-- what you aim at, when it is the sky
	-- en: sky
	[ "aim.sky" ] = "Himmel",

	-- multi-click tools (weld, rope...): which click comes next
	-- en: Stage {n}
	[ "tool.progress" ] = "Schritt {n}",

	-- health of the tracked entity, e.g. "HP 40/100"
	-- en: HP {hp}
	[ "track.hp" ] = "HP {hp}",

	-- en: Noclip
	[ "noclip" ] = "No Clip",

	-- view angles: P = pitch, Y = yaw
	-- en: P {p}  Y {y}
	[ "eye_ang" ] = "Nick {p}  Gier {y}",

	-- compass heading, e.g. "NE 45°"
	-- en: {dir} {deg}°
	[ "heading" ] = "{dir} {deg}°",

	-- en: N
	[ "compass.n" ] = "N",

	-- en: NE
	[ "compass.ne" ] = "NO",

	-- en: E
	[ "compass.e" ] = "O",

	-- en: SE
	[ "compass.se" ] = "SO",

	-- en: S
	[ "compass.s" ] = "S",

	-- en: SW
	[ "compass.sw" ] = "SW",

	-- en: W
	[ "compass.w" ] = "W",

	-- en: NW
	[ "compass.nw" ] = "NW",

	-- label of the FPS graph in the Terminal layout
	-- en: {n} fps
	[ "term.fps" ] = "{n} FPS",

	-- shown on the screen when it fails to draw
	-- en: Screen error
	[ "error.title" ] = "Display-Fehler",

	-- en: See the console for details. Change the layout or run dts_reset to recover.
	[ "error.hint" ] = "Details stehen in der Konsole. Wechsle das Layout oder führe dts_reset aus, um alles wiederherzustellen.",

	-- tabs of the Advanced Toolgun [Hotbar] addon's tool list, for the {atg_tab} token
	-- en: Tools
	[ "atg.tab.tools" ] = "Werkzeuge",

	-- en: Wire
	[ "atg.tab.wire" ] = "Wire",

	-- en: Favorites
	[ "atg.tab.favorites" ] = "Favoriten",

	-- the device's battery, next to the battery icon and in {battery}: {n} is the charge in percent;
	-- "Plugged in" is shown while the device runs on mains power instead of its battery
	-- en: {n}%
	[ "battery.percent" ] = "{n} %",

	-- en: Plugged in
	[ "battery.plugged" ] = "Netzbetrieb",

	-- Units: {v} is the number, already written with the decimal separator above
	-- en: {v} m
	[ "unit.m" ] = "{v} m",

	-- en: {v} km
	[ "unit.km" ] = "{v} km",

	-- en: {v} ft
	[ "unit.ft" ] = "{v} ft",

	-- en: {v} mi
	[ "unit.mi" ] = "{v} mi",

	-- Hammer units, the game's own distance unit
	-- en: {v} u
	[ "unit.hu" ] = "{v} E",

	-- en: {v} km/h
	[ "unit.kmh" ] = "{v} km/h",

	-- en: {v} mph
	[ "unit.mph" ] = "{v} mph",

	-- en: {v} u/s
	[ "unit.ups" ] = "{v} E/s",

	-- en: {v} kg
	[ "unit.kg" ] = "{v} kg",

	-- en: {v} MB
	[ "unit.mb" ] = "{v} MB",

	-- Durations: {h} hours, {m} minutes, {s} seconds (minutes and seconds come with two digits)
	-- en: {h}h {m}m
	[ "duration.hm" ] = "{h} Std. {m} Min.",

	-- en: {m}m {s}s
	[ "duration.ms" ] = "{m} Min. {s} Sek.",

	-- en: {s}s
	[ "duration.s" ] = "{s} Sek.",

	-- 12 hour clock: AM/PM and where they go around the time
	-- en: AM
	[ "clock.am" ] = "AM",

	-- en: PM
	[ "clock.pm" ] = "PM",

	-- en: {time} {ampm}
	[ "clock.ampm" ] = "{time} {ampm}",

	-- Date: {wday} day of week (short), {day} day number, {month} month (short), {year}
	-- en: {wday} {day} {month}
	[ "date.format" ] = "{wday}, {day}. {month}",

	-- en: Sun
	[ "date.wday.1" ] = "So.",

	-- en: Mon
	[ "date.wday.2" ] = "Mo.",

	-- en: Tue
	[ "date.wday.3" ] = "Di.",

	-- en: Wed
	[ "date.wday.4" ] = "Mi.",

	-- en: Thu
	[ "date.wday.5" ] = "Do.",

	-- en: Fri
	[ "date.wday.6" ] = "Fr.",

	-- en: Sat
	[ "date.wday.7" ] = "Sa.",

	-- en: Sunday
	[ "date.wday_full.1" ] = "Sonntag",

	-- en: Monday
	[ "date.wday_full.2" ] = "Montag",

	-- en: Tuesday
	[ "date.wday_full.3" ] = "Dienstag",

	-- en: Wednesday
	[ "date.wday_full.4" ] = "Mittwoch",

	-- en: Thursday
	[ "date.wday_full.5" ] = "Donnerstag",

	-- en: Friday
	[ "date.wday_full.6" ] = "Freitag",

	-- en: Saturday
	[ "date.wday_full.7" ] = "Samstag",

	-- short month names, used in dates ({month} above and %b): use the form your dates need
	-- en: Jan
	[ "date.month.1" ] = "Jan.",

	-- en: Feb
	[ "date.month.2" ] = "Feb.",

	-- en: Mar
	[ "date.month.3" ] = "März",

	-- en: Apr
	[ "date.month.4" ] = "Apr.",

	-- en: May
	[ "date.month.5" ] = "Mai",

	-- en: Jun
	[ "date.month.6" ] = "Juni",

	-- en: Jul
	[ "date.month.7" ] = "Juli",

	-- en: Aug
	[ "date.month.8" ] = "Aug.",

	-- en: Sep
	[ "date.month.9" ] = "Sept.",

	-- en: Oct
	[ "date.month.10" ] = "Okt.",

	-- en: Nov
	[ "date.month.11" ] = "Nov.",

	-- en: Dec
	[ "date.month.12" ] = "Dez.",

	-- full month names (%B), usually written right after a day number
	-- en: January
	[ "date.month_full.1" ] = "Januar",

	-- en: February
	[ "date.month_full.2" ] = "Februar",

	-- en: March
	[ "date.month_full.3" ] = "März",

	-- en: April
	[ "date.month_full.4" ] = "April",

	-- en: May
	[ "date.month_full.5" ] = "Mai",

	-- en: June
	[ "date.month_full.6" ] = "Juni",

	-- en: July
	[ "date.month_full.7" ] = "Juli",

	-- en: August
	[ "date.month_full.8" ] = "August",

	-- en: September
	[ "date.month_full.9" ] = "September",

	-- en: October
	[ "date.month_full.10" ] = "Oktober",

	-- en: November
	[ "date.month_full.11" ] = "November",

	-- en: December
	[ "date.month_full.12" ] = "Dezember",

	-- Kinds of surface material (the game's material types), shown as "World - Concrete"
	-- en: Antlion
	[ "mat.antlion" ] = "Ameisenlöwe",

	-- en: Bloody flesh
	[ "mat.bloodyflesh" ] = "Blutiges Fleisch",

	-- en: Concrete
	[ "mat.concrete" ] = "Beton",

	-- en: Dirt
	[ "mat.dirt" ] = "Erde",

	-- en: Eggshell
	[ "mat.eggshell" ] = "Eierschale",

	-- en: Flesh
	[ "mat.flesh" ] = "Fleisch",

	-- en: Grate
	[ "mat.grate" ] = "Gitter",

	-- en: Alien flesh
	[ "mat.alienflesh" ] = "Alien-Fleisch",

	-- en: Clip
	[ "mat.clip" ] = "Unsichtbare Wand",

	-- en: Snow
	[ "mat.snow" ] = "Schnee",

	-- en: Plastic
	[ "mat.plastic" ] = "Kunststoff",

	-- en: Metal
	[ "mat.metal" ] = "Metall",

	-- en: Sand
	[ "mat.sand" ] = "Sand",

	-- en: Foliage
	[ "mat.foliage" ] = "Laub",

	-- en: Computer
	[ "mat.computer" ] = "Elektronik",

	-- en: Liquid
	[ "mat.slosh" ] = "Flüssigkeit",

	-- en: Tile
	[ "mat.tile" ] = "Fliesen",

	-- en: Grass
	[ "mat.grass" ] = "Gras",

	-- en: Vent
	[ "mat.vent" ] = "Lüftung",

	-- en: Wood
	[ "mat.wood" ] = "Holz",

	-- en: Generic
	[ "mat.default" ] = "Allgemein",

	-- en: Glass
	[ "mat.glass" ] = "Glas",

	-- en: Warp shield
	[ "mat.warpshield" ] = "Warp-Schild",

	-- Notifications on the screen
	-- en: Tracking {name}
	[ "notify.tracking" ] = "Verfolgung: {name}",

	-- en: Stopped tracking
	[ "notify.untracked" ] = "Verfolgung beendet",

	-- en: Layout: {name}
	[ "notify.layout" ] = "Layout: {name}",

	-- en: Theme: {name}
	[ "notify.theme" ] = "Design: {name}",

	-- title bar: tool category, or the game's name when there is none (keep "Garry's Mod")
	-- en: {tool_category|Garry's Mod}
	[ "tpl.title" ] = "{tool_category|Garry's Mod}",

	-- left link of the Pocket PC screen: the previous tool
	-- en: Back to {tool_prev}
	[ "tpl.nav_back" ] = "Zurück zu {tool_prev}",

	-- en: Props {props}/{props_max}
	[ "tpl.props" ] = "Objekte {props}/{props_max}",

	-- en: {fps} fps  {ping} ms
	[ "tpl.perf" ] = "{fps} FPS  {ping} ms",

	-- en: Slope {aim_slope}
	[ "tpl.slope" ] = "Neigung {aim_slope}",

	-- en: HP {ent_health}
	[ "tpl.hp" ] = "HP {ent_health}",

	-- en: Owner: {ent_owner}
	[ "tpl.owner" ] = "Besitzer: {ent_owner}",

	-- HP = health, AP = armor
	-- en: HP {health}  AP {armor}
	[ "tpl.health_armor" ] = "HP {health}  Rüstung {armor}",

	-- en: {players} players
	[ "tpl.players" ] = "{players} Spieler",

	-- Terminal lines: a short upper case label, a tab, then the value
	-- en: TOOL\t**{tool}**
	[ "tpl.term_tool" ] = "WERKZEUG\t**{tool}**",

	-- en: AIM\t**{aim_what}**
	[ "tpl.term_aim" ] = "ZIEL\t**{aim_what}**",

	-- en: CLASS\t**{ent_class|-}**
	[ "tpl.term_class" ] = "KLASSE\t**{ent_class|-}**",

	-- en: POS\t**{aim_pos}**
	[ "tpl.term_pos" ] = "POS\t**{aim_pos}**",

	-- en: DIST\t**{aim_dist}**  {aim_slope}
	[ "tpl.term_dist" ] = "DIST\t**{aim_dist}**  {aim_slope}",

	-- en: OWNER\t**{ent_owner|-}**
	[ "tpl.term_owner" ] = "BESITZER\t**{ent_owner|-}**",

	-- en: HP\t**{ent_health|-}**
	[ "tpl.term_hp" ] = "HP\t**{ent_health|-}**",

	-- en: TRACK\t**{track_name|-}** {track_dist}
	[ "tpl.term_track" ] = "VERFOLGT\t**{track_name|-}** {track_dist}",

	-- en: Pocket PC
	[ "layout.pocketpc.name" ] = "Pocket PC",

	-- en: The original screen rebuilt with live data: clock, status icons, tool history links, big tool name, status line, six readouts and a hint bar.
	[ "layout.pocketpc.desc" ] = "Das ursprüngliche Display, neu aufgebaut mit Live-Daten: Uhr, Statussymbole, Links zum Werkzeugverlauf, großer Werkzeugname, Statuszeile, sechs Anzeigen und eine Hinweisleiste.",

	-- en: Title bar
	[ "layout.pocketpc.title" ] = "Titelleiste",

	-- en: Clock
	[ "layout.pocketpc.clock" ] = "Uhr",

	-- en: Left link
	[ "layout.pocketpc.nav_l" ] = "Linker Link",

	-- en: Right link
	[ "layout.pocketpc.nav_r" ] = "Rechter Link",

	-- en: Big text
	[ "layout.pocketpc.hero" ] = "Großer Text",

	-- en: Under the big text
	[ "layout.pocketpc.sub" ] = "Unter dem großen Text",

	-- en: Status line
	[ "layout.pocketpc.status" ] = "Statuszeile",

	-- en: Readout, left 1
	[ "layout.pocketpc.l1" ] = "Anzeige links 1",

	-- en: Readout, left 2
	[ "layout.pocketpc.l2" ] = "Anzeige links 2",

	-- en: Readout, left 3
	[ "layout.pocketpc.l3" ] = "Anzeige links 3",

	-- en: Readout, right 1
	[ "layout.pocketpc.r1" ] = "Anzeige rechts 1",

	-- en: Readout, right 2
	[ "layout.pocketpc.r2" ] = "Anzeige rechts 2",

	-- en: Readout, right 3
	[ "layout.pocketpc.r3" ] = "Anzeige rechts 3",

	-- en: Menu bar
	[ "layout.pocketpc.menu" ] = "Menüleiste",

	-- en: Terminal
	[ "layout.terminal.name" ] = "Terminal",

	-- en: Developer readout: eight lines of labels and values, an FPS graph and a prompt line with the tool hints.
	[ "layout.terminal.desc" ] = "Entwickleransicht: acht Zeilen mit Bezeichnungen und Werten, ein FPS-Graph und eine Eingabezeile mit den Werkzeughinweisen.",

	-- en: Header
	[ "layout.terminal.head" ] = "Kopfzeile",

	-- en: Header, right
	[ "layout.terminal.clock" ] = "Kopfzeile rechts",

	-- en: Line 1
	[ "layout.terminal.l1" ] = "Zeile 1",

	-- en: Line 2
	[ "layout.terminal.l2" ] = "Zeile 2",

	-- en: Line 3
	[ "layout.terminal.l3" ] = "Zeile 3",

	-- en: Line 4
	[ "layout.terminal.l4" ] = "Zeile 4",

	-- en: Line 5
	[ "layout.terminal.l5" ] = "Zeile 5",

	-- en: Line 6
	[ "layout.terminal.l6" ] = "Zeile 6",

	-- en: Line 7
	[ "layout.terminal.l7" ] = "Zeile 7",

	-- en: Line 8
	[ "layout.terminal.l8" ] = "Zeile 8",

	-- en: Prompt line
	[ "layout.terminal.foot" ] = "Eingabezeile",

	-- en: Minimal
	[ "layout.minimal.name" ] = "Minimal",

	-- en: Large, glanceable text: clock, compass, the tool name sized to fit, what you aim at and two corner values.
	[ "layout.minimal.desc" ] = "Großer Text, auf einen Blick lesbar: Uhr, Kompass, der passend skalierte Werkzeugname, dein Ziel und zwei Eckwerte.",

	-- en: Top left
	[ "layout.minimal.top_l" ] = "Oben links",

	-- en: Top right
	[ "layout.minimal.top_r" ] = "Oben rechts",

	-- en: Big text
	[ "layout.minimal.hero" ] = "Großer Text",

	-- en: Under the big text
	[ "layout.minimal.sub" ] = "Unter dem großen Text",

	-- en: Bottom left
	[ "layout.minimal.foot_l" ] = "Unten links",

	-- en: Bottom right
	[ "layout.minimal.foot_r" ] = "Unten rechts",

	-- en: Pocket PC (original)
	[ "theme.winmobile" ] = "Pocket PC (Original)",

	-- en: Graphite
	[ "theme.graphite" ] = "Graphit",

	-- en: Green phosphor
	[ "theme.phosphor" ] = "Grüner Phosphor",

	-- en: Amber CRT
	[ "theme.amber" ] = "Bernstein-CRT",

	-- en: Sakura
	[ "theme.sakura" ] = "Sakura",

	-- en: Sandbox blue
	[ "theme.sandbox" ] = "Sandbox-Blau",

	-- parts of the screen whose colour can be changed
	-- en: Title bar
	[ "color.bar" ] = "Titelleiste",

	-- en: Links and highlights
	[ "color.accent" ] = "Links und Hervorhebungen",

	-- en: Big text
	[ "color.hero" ] = "Großer Text",

	-- en: Status line
	[ "color.strip" ] = "Statuszeile",

	-- en: Readout panel
	[ "color.panel" ] = "Anzeigefeld",

	-- en: Menu bar
	[ "color.menu" ] = "Menüleiste",

	-- en: Terminal text
	[ "color.term" ] = "Terminaltext",

	-- en: Text
	[ "category.text" ] = "Text",

	-- en: Time
	[ "category.time" ] = "Zeit",

	-- en: Tool
	[ "category.tool" ] = "Werkzeug",

	-- en: Aim
	[ "category.aim" ] = "Zielen",

	-- en: Aimed entity
	[ "category.entity" ] = "Anvisiertes Objekt",

	-- en: Tracked entity
	[ "category.tracked" ] = "Verfolgtes Objekt",

	-- en: You
	[ "category.player" ] = "Du",

	-- en: Game
	[ "category.game" ] = "Spiel",

	-- the Advanced Toolgun [Hotbar] addon; keep its name as it is
	-- en: Advanced Toolgun
	[ "category.atg" ] = "Advanced Toolgun",

	-- en: A line in your language from the language files, e.g. {tr:nav_back} or {tr:props}.
	[ "token.tr" ] = "Eine Zeile in deiner Sprache aus den Sprachdateien, z. B. {tr:nav_back} oder {tr:props}.",

	-- en: Local time, formatted by the clock settings. {time:%H:%M:%S} takes an os.date format.
	[ "token.time" ] = "Ortszeit im Format der Uhreinstellungen. {time:%H:%M:%S} nimmt ein os.date-Format.",

	-- en: Today's date. {date:%Y-%m-%d} takes an os.date format.
	[ "token.date" ] = "Das heutige Datum. {date:%Y-%m-%d} nimmt ein os.date-Format.",

	-- en: How long you have been in this game.
	[ "token.session" ] = "Wie lange du schon in diesem Spiel bist.",

	-- en: How long the map has been running.
	[ "token.map_time" ] = "Wie lange die Karte schon läuft.",

	-- en: Name of the selected tool.
	[ "token.tool" ] = "Name des ausgewählten Werkzeugs.",

	-- en: Internal name of the selected tool.
	[ "token.tool_id" ] = "Interner Name des ausgewählten Werkzeugs.",

	-- en: Description of the selected tool.
	[ "token.tool_desc" ] = "Beschreibung des ausgewählten Werkzeugs.",

	-- en: Tool menu category of the selected tool.
	[ "token.tool_category" ] = "Kategorie des ausgewählten Werkzeugs im Werkzeugmenü.",

	-- en: Stage of the selected tool (0 = nothing selected yet).
	[ "token.tool_stage" ] = "Schritt des ausgewählten Werkzeugs (0 = noch nichts ausgewählt).",

	-- en: The stage while a multi-click tool is in progress, otherwise empty.
	[ "token.tool_progress" ] = "Der Schritt, solange ein Werkzeug mit mehreren Klicks in Arbeit ist, sonst leer.",

	-- en: The tool you used before this one (dts_tool_back switches to it).
	[ "token.tool_prev" ] = "Das Werkzeug, das du vor diesem benutzt hast (dts_tool_back wechselt dorthin).",

	-- en: The next tool in the same menu category (dts_tool_next switches to it).
	[ "token.tool_next" ] = "Das nächste Werkzeug derselben Menükategorie (dts_tool_next wechselt dorthin).",

	-- en: Successful tool gun shots this session.
	[ "token.tool_uses" ] = "Erfolgreiche Schüsse mit der Werkzeugpistole in dieser Sitzung.",

	-- en: A setting of the selected tool, e.g. {tool_cvar:forcelimit} reads weld_forcelimit.
	[ "token.tool_cvar" ] = "Eine Einstellung des ausgewählten Werkzeugs, z. B. liest {tool_cvar:forcelimit} weld_forcelimit.",

	-- en: All settings of the selected tool as name=value pairs.
	[ "token.tool_settings" ] = "Alle Einstellungen des ausgewählten Werkzeugs als Name=Wert-Paare.",

	-- en: The current stage's instructions with mouse and key icons.
	[ "token.hints" ] = "Die Anweisungen des aktuellen Schritts mit Maus- und Tastensymbolen.",

	-- en: What left click does right now.
	[ "token.hint_left" ] = "Was ein Linksklick gerade bewirkt.",

	-- en: What right click does right now.
	[ "token.hint_right" ] = "Was ein Rechtsklick gerade bewirkt.",

	-- en: What reload does right now.
	[ "token.hint_reload" ] = "Was Nachladen gerade bewirkt.",

	-- en: What you are aiming at, with the name highlighted.
	[ "token.target" ] = "Was du anvisierst, mit hervorgehobenem Namen.",

	-- en: Entity name, or the surface material when aiming at the world.
	[ "token.aim_what" ] = "Name des Objekts oder das Oberflächenmaterial, wenn du auf die Welt zielst.",

	-- en: Position you are aiming at.
	[ "token.aim_pos" ] = "Die Position, auf die du zielst.",

	-- en: X of the aim position.
	[ "token.aim_x" ] = "X der Zielposition.",

	-- en: Y of the aim position.
	[ "token.aim_y" ] = "Y der Zielposition.",

	-- en: Z of the aim position.
	[ "token.aim_z" ] = "Z der Zielposition.",

	-- en: Distance to the aim position.
	[ "token.aim_dist" ] = "Entfernung zur Zielposition.",

	-- en: Surface normal at the aim position.
	[ "token.aim_normal" ] = "Flächennormale an der Zielposition.",

	-- en: Steepness of the surface (0 = flat floor, 90 = wall).
	[ "token.aim_slope" ] = "Neigung der Oberfläche (0 = ebener Boden, 90 = Wand).",

	-- en: Kind of surface material (metal, wood, concrete...).
	[ "token.aim_surface" ] = "Art des Oberflächenmaterials (Metall, Holz, Beton...).",

	-- en: Surface property as the engine names it (metal box, wood crate...).
	[ "token.aim_surfaceprop" ] = "Oberflächeneigenschaft, wie die Engine sie nennt (metal box, wood crate...).",

	-- en: World texture you are aiming at.
	[ "token.aim_texture" ] = "Welttextur, auf die du zielst.",

	-- en: Friendly name of the aimed entity.
	[ "token.ent_name" ] = "Lesbarer Name des anvisierten Objekts.",

	-- en: Class of the aimed entity.
	[ "token.ent_class" ] = "Klasse des anvisierten Objekts.",

	-- en: Model file name of the aimed entity.
	[ "token.ent_model" ] = "Modelldateiname des anvisierten Objekts.",

	-- en: Full model path of the aimed entity.
	[ "token.ent_model_path" ] = "Vollständiger Modellpfad des anvisierten Objekts.",

	-- en: Entity index.
	[ "token.ent_index" ] = "Objektindex.",

	-- en: Health of the aimed entity (players, NPCs, breakable props).
	[ "token.ent_health" ] = "Gesundheit des anvisierten Objekts (Spieler, NPCs, zerstörbare Objekte).",

	-- en: Owner of the aimed entity (in multiplayer this needs a CPPI prop protection addon).
	[ "token.ent_owner" ] = "Besitzer des anvisierten Objekts (im Mehrspielermodus ist dafür ein Prop-Protection-Addon mit CPPI nötig).",

	-- en: Material of the aimed entity.
	[ "token.ent_material" ] = "Material des anvisierten Objekts.",

	-- en: Colour of the aimed entity.
	[ "token.ent_color" ] = "Farbe des anvisierten Objekts.",

	-- en: Skin of the aimed entity.
	[ "token.ent_skin" ] = "Aussehen (Skin) des anvisierten Objekts.",

	-- en: Speed of the aimed entity.
	[ "token.ent_speed" ] = "Geschwindigkeit des anvisierten Objekts.",

	-- en: Position of the aimed entity.
	[ "token.ent_pos" ] = "Position des anvisierten Objekts.",

	-- en: Angles of the aimed entity.
	[ "token.ent_ang" ] = "Winkel des anvisierten Objekts.",

	-- en: Mass of the aimed entity, when your game knows its physics.
	[ "token.ent_mass" ] = "Masse des anvisierten Objekts, wenn dein Spiel seine Physik kennt.",

	-- en: Tracked entity summary: name, distance, speed, health.
	[ "token.track" ] = "Zusammenfassung des verfolgten Objekts: Name, Entfernung, Geschwindigkeit, Gesundheit.",

	-- en: Name of the tracked entity.
	[ "token.track_name" ] = "Name des verfolgten Objekts.",

	-- en: Class of the tracked entity.
	[ "token.track_class" ] = "Klasse des verfolgten Objekts.",

	-- en: Your distance to the tracked entity.
	[ "token.track_dist" ] = "Deine Entfernung zum verfolgten Objekt.",

	-- en: Speed of the tracked entity.
	[ "token.track_speed" ] = "Geschwindigkeit des verfolgten Objekts.",

	-- en: Health of the tracked entity.
	[ "token.track_health" ] = "Gesundheit des verfolgten Objekts.",

	-- en: Position of the tracked entity.
	[ "token.track_pos" ] = "Position des verfolgten Objekts.",

	-- en: Your name.
	[ "token.player" ] = "Dein Name.",

	-- en: Your health.
	[ "token.health" ] = "Deine Gesundheit.",

	-- en: Your armor.
	[ "token.armor" ] = "Deine Rüstung.",

	-- en: Your speed.
	[ "token.speed" ] = "Deine Geschwindigkeit.",

	-- en: Your position.
	[ "token.pos" ] = "Deine Position.",

	-- en: Your view pitch and yaw.
	[ "token.eye_ang" ] = "Nick- und Gierwinkel deiner Blickrichtung.",

	-- en: Compass heading (north is +Y on the map).
	[ "token.heading" ] = "Kompassrichtung (Norden ist +Y auf der Karte).",

	-- en: Shows a word while you are noclipping, otherwise empty.
	[ "token.noclip" ] = "Zeigt ein Wort, solange No Clip aktiv ist, sonst leer.",

	-- en: Frames per second (smoothed).
	[ "token.fps" ] = "Bilder pro Sekunde (geglättet).",

	-- en: Your ping in milliseconds.
	[ "token.ping" ] = "Dein Ping in Millisekunden.",

	-- en: Your device's battery charge while it runs on battery, or \"Plugged in\".
	[ "token.battery" ] = "Akkustand deines Geräts im Akkubetrieb, sonst „Netzbetrieb“.",

	-- en: Current map.
	[ "token.map" ] = "Aktuelle Karte.",

	-- en: Players on the server and its player limit.
	[ "token.players" ] = "Spieler auf dem Server und das Spielerlimit.",

	-- en: Server name.
	[ "token.server" ] = "Servername.",

	-- en: Active gamemode.
	[ "token.gamemode" ] = "Aktiver Spielmodus.",

	-- en: Server tick rate.
	[ "token.tickrate" ] = "Tickrate des Servers.",

	-- en: Memory used by Lua in your game.
	[ "token.lua_mem" ] = "Von Lua belegter Speicher in deinem Spiel.",

	-- en: Entities known to your game.
	[ "token.entities" ] = "Anzahl der Objekte, die dein Spiel kennt.",

	-- en: Props you have spawned.
	[ "token.props" ] = "Von dir gespawnte Objekte.",

	-- en: Your prop limit.
	[ "token.props_max" ] = "Dein Objektlimit.",

	-- en: Spawn count and limit of a type, e.g. {count:ragdolls} or {count:thrusters}.
	[ "token.count" ] = "Anzahl und Limit eines Typs, z. B. {count:ragdolls} oder {count:thrusters}.",

	-- en: Value of any console variable, e.g. {cvar:sv_gravity}.
	[ "token.cvar" ] = "Wert einer beliebigen Konsolenvariable, z. B. {cvar:sv_gravity}.",

	-- en: Advanced Toolgun [Hotbar]: its open tab (Tools, Wire or Favorites).
	[ "token.atg_tab" ] = "Advanced Toolgun [Hotbar]: der geöffnete Tab (Werkzeuge, Wire oder Favoriten).",

	-- en: Advanced Toolgun [Hotbar]: the section of its list the selection is in.
	[ "token.atg_section" ] = "Advanced Toolgun [Hotbar]: der Abschnitt seiner Liste, in dem die Auswahl steht.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel up.
	[ "token.atg_prev" ] = "Advanced Toolgun [Hotbar]: das Werkzeug, zu dem seine Schnellauswahl mit dem Mausrad nach oben wechselt.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel down.
	[ "token.atg_next" ] = "Advanced Toolgun [Hotbar]: das Werkzeug, zu dem seine Schnellauswahl mit dem Mausrad nach unten wechselt.",

	-- en: Turns the tool gun's mini screen into a live display. Changes apply instantly; the preview shows what the screen draws right now.
	[ "menu.intro" ] = "Verwandelt das kleine Display der Werkzeugpistole in eine Live-Anzeige. Änderungen gelten sofort; die Vorschau zeigt, was das Display gerade darstellt.",

	-- en: Dynamic screen is off
	[ "menu.preview_off" ] = "Das dynamische Display ist aus",

	-- en: Enable the dynamic screen
	[ "menu.enable" ] = "Dynamisches Display aktivieren",

	-- en: Language
	[ "menu.language" ] = "Sprache",

	-- first entry of the language list; {name} is the game's language, e.g. "English"
	-- en: Automatic: {name}
	[ "menu.language.auto" ] = "Automatisch: {name}",

	-- en: Inspect: read the screen up close
	[ "menu.inspect.title" ] = "Betrachten: das Display aus der Nähe lesen",

	-- en: Hold a key while holding the tool gun to raise its screen to your eyes.
	[ "menu.inspect.help" ] = "Halte eine Taste gedrückt, während du die Werkzeugpistole in der Hand hast, um ihr Display vor die Augen zu heben.",

	-- en: Inspect key
	[ "menu.inspect.key" ] = "Taste zum Betrachten",

	-- en: Screen size while inspecting
	[ "menu.inspect.size" ] = "Displaygröße beim Betrachten",

	-- en: Or use the console: bind <key> +dts_inspect (hold) or dts_inspect_toggle.
	[ "menu.inspect.console" ] = "Oder über die Konsole: bind <Taste> +dts_inspect (halten) oder dts_inspect_toggle.",

	-- the tool gun model has a paper note glued on, which overlaps the screen's top right corner
	-- en: Screen in front of the paper note
	[ "menu.inspect.on_top" ] = "Display vor dem Notizzettel",

	-- en: While inspecting, the whole screen stays readable. Untick to let the paper note glued to the tool gun cover the top right corner of the screen, as on the model.
	[ "menu.inspect.on_top_help" ] = "Beim Betrachten bleibt das ganze Display lesbar. Entferne den Haken, damit der auf die Werkzeugpistole geklebte Notizzettel die obere rechte Ecke des Displays verdeckt, wie am Modell.",

	-- en: Layout and look
	[ "menu.look.title" ] = "Layout und Aussehen",

	-- en: Layout
	[ "menu.look.layout" ] = "Layout",

	-- en: Theme
	[ "menu.look.theme" ] = "Design",

	-- en: Background
	[ "menu.look.background" ] = "Hintergrund",

	-- en: Automatic (layout's choice)
	[ "menu.bg.auto" ] = "Automatisch (Wahl des Layouts)",

	-- the whole original screen picture without its text
	-- en: Original screen
	[ "menu.bg.original" ] = "Original-Display",

	-- only the blurred photo from the original picture, filling the screen
	-- en: Original photo
	[ "menu.bg.art" ] = "Originalfoto",

	-- en: Theme gradient
	[ "menu.bg.gradient" ] = "Farbverlauf des Designs",

	-- en: Live camera: zoom
	[ "menu.bg.camera" ] = "Live-Kamera: Zoom",

	-- en: Live camera: rear view
	[ "menu.bg.rear" ] = "Live-Kamera: Rückansicht",

	-- en: Custom image
	[ "menu.bg.image" ] = "Eigenes Bild",

	-- en: Black
	[ "menu.bg.black" ] = "Schwarz",

	-- en: Custom image
	[ "menu.look.image" ] = "Eigenes Bild",

	-- en: A material path, or an image in garrysmod/data written as ../data/name.png
	[ "menu.look.image_help" ] = "Ein Materialpfad oder ein Bild in garrysmod/data, geschrieben als ../data/name.png",

	-- en: Darken background
	[ "menu.look.dim" ] = "Hintergrund abdunkeln",

	-- en: Camera field of view
	[ "menu.look.cam_fov" ] = "Sichtfeld der Kamera",

	-- en: Camera updates per second
	[ "menu.look.cam_fps" ] = "Kamera-Updates pro Sekunde",

	-- en: Text font
	[ "menu.look.font" ] = "Schriftart für Text",

	-- en: Big text font
	[ "menu.look.font_hero" ] = "Schriftart für großen Text",

	-- en: Terminal font
	[ "menu.look.font_mono" ] = "Schriftart für Terminal",

	-- first entry of the font lists; {font} is the font your language uses
	-- en: Automatic ({font})
	[ "menu.font.auto" ] = "Automatisch ({font})",

	-- en: Colours
	[ "menu.colors.title" ] = "Farben",

	-- en: Override single colours of the theme. Click a swatch to change it.
	[ "menu.colors.help" ] = "Einzelne Farben des Designs überschreiben. Klicke auf ein Farbfeld, um es zu ändern.",

	-- written on a colour swatch that still uses the theme's colour
	-- en: theme
	[ "menu.colors.theme_tag" ] = "Design",

	-- en: Click to pick a colour
	[ "menu.colors.pick" ] = "Klicken, um eine Farbe zu wählen",

	-- en: Use the theme's colours everywhere
	[ "menu.colors.reset_all" ] = "Überall die Farben des Designs verwenden",

	-- en: Screen colour: {name}
	[ "menu.colors.picker_title" ] = "Displayfarbe: {name}",

	-- en: Use the theme's colour
	[ "menu.colors.use_theme" ] = "Farbe des Designs verwenden",

	-- en: Big text
	[ "menu.hero.title" ] = "Großer Text",

	-- en: Behaviour
	[ "menu.hero.mode" ] = "Verhalten",

	-- en: Always scroll (original)
	[ "menu.hero.scroll" ] = "Immer scrollen (Original)",

	-- en: Scroll only when too long
	[ "menu.hero.auto" ] = "Nur scrollen, wenn zu lang",

	-- en: Shrink to fit
	[ "menu.hero.fit" ] = "Passend verkleinern",

	-- en: Scroll speed
	[ "menu.hero.speed" ] = "Scrollgeschwindigkeit",

	-- en: Upper case tool names
	[ "menu.hero.upper" ] = "Werkzeugnamen in Großbuchstaben",

	-- en: Screen content
	[ "menu.content.title" ] = "Display-Inhalt",

	-- keep {tokens}, **stars**, {token|fallback} and {tr:...} as they are: they show the syntax
	-- en: Every line of the {layout} layout is a template. Type text and {tokens}; **stars** highlight text, {token|fallback} gives a default, and a line whose tokens are all empty hides itself. {tr:...} writes a line in your language. See the token reference below.
	[ "menu.content.help" ] = "Jede Zeile des Layouts „{layout}“ ist eine Vorlage. Gib Text und {tokens} ein; **Sternchen** heben Text hervor, {token|fallback} legt einen Ersatzwert fest, und eine Zeile, deren Tokens alle leer sind, blendet sich aus. {tr:...} schreibt eine Zeile in deiner Sprache. Siehe die Token-Übersicht unten.",

	-- en: Pick a ready-made line
	[ "menu.content.presets_tip" ] = "Eine fertige Zeile wählen",

	-- en: Back to the default: {value}
	[ "menu.content.reset_tip" ] = "Zurück zum Standard: {value}",

	-- en: (empty)
	[ "menu.content.empty" ] = "(leer)",

	-- shown in an empty line's text box
	-- en: (hidden)
	[ "menu.content.placeholder" ] = "(ausgeblendet)",

	-- under each line: what it shows right now
	-- en: = {text}
	[ "menu.content.now" ] = "= {text}",

	-- en: (hidden right now)
	[ "menu.content.hidden_now" ] = "(gerade ausgeblendet)",

	-- en: Reset these lines to the layout's defaults
	[ "menu.content.reset_all" ] = "Diese Zeilen auf die Standardwerte des Layouts zurücksetzen",

	-- ready-made lines in the list next to each line
	-- en: Tool name
	[ "menu.preset.tool" ] = "Werkzeugname",

	-- en: Tool category
	[ "menu.preset.tool_category" ] = "Werkzeugkategorie",

	-- en: Tool instructions
	[ "menu.preset.hints" ] = "Werkzeuganweisungen",

	-- en: Previous tool
	[ "menu.preset.prev_tool" ] = "Vorheriges Werkzeug",

	-- en: Next tool
	[ "menu.preset.next_tool" ] = "Nächstes Werkzeug",

	-- en: Tool progress
	[ "menu.preset.progress" ] = "Werkzeugfortschritt",

	-- en: Tool settings
	[ "menu.preset.tool_settings" ] = "Werkzeugeinstellungen",

	-- en: What you aim at
	[ "menu.preset.target" ] = "Dein Ziel",

	-- en: Aim position
	[ "menu.preset.aim_pos" ] = "Zielposition",

	-- en: Aim distance
	[ "menu.preset.aim_dist" ] = "Zielentfernung",

	-- en: Entity or surface
	[ "menu.preset.aim_what" ] = "Objekt oder Oberfläche",

	-- en: Surface slope
	[ "menu.preset.slope" ] = "Neigung der Oberfläche",

	-- en: Entity class
	[ "menu.preset.ent_class" ] = "Objektklasse",

	-- en: Entity model
	[ "menu.preset.ent_model" ] = "Objektmodell",

	-- en: Entity health
	[ "menu.preset.ent_health" ] = "Objektgesundheit",

	-- en: Entity owner
	[ "menu.preset.ent_owner" ] = "Objektbesitzer",

	-- en: Entity speed
	[ "menu.preset.ent_speed" ] = "Objektgeschwindigkeit",

	-- en: Tracked entity
	[ "menu.preset.track" ] = "Verfolgtes Objekt",

	-- en: Clock
	[ "menu.preset.clock" ] = "Uhr",

	-- en: Clock with seconds
	[ "menu.preset.clock_seconds" ] = "Uhr mit Sekunden",

	-- en: Date
	[ "menu.preset.date" ] = "Datum",

	-- en: Time in game
	[ "menu.preset.session" ] = "Spielzeit",

	-- en: Your speed
	[ "menu.preset.speed" ] = "Deine Geschwindigkeit",

	-- en: Your position
	[ "menu.preset.pos" ] = "Deine Position",

	-- en: Compass
	[ "menu.preset.heading" ] = "Kompass",

	-- en: Health and armor
	[ "menu.preset.health_armor" ] = "Gesundheit und Rüstung",

	-- en: FPS and ping
	[ "menu.preset.perf" ] = "FPS und Ping",

	-- en: Prop count
	[ "menu.preset.props" ] = "Anzahl der Objekte",

	-- en: Map
	[ "menu.preset.map" ] = "Karte",

	-- en: Players
	[ "menu.preset.players" ] = "Spieler",

	-- en: Empty (hide the line)
	[ "menu.preset.empty" ] = "Leer (Zeile ausblenden)",

	-- en: Clock and units
	[ "menu.clock.title" ] = "Uhr und Einheiten",

	-- en: Clock
	[ "menu.clock.style" ] = "Uhr",

	-- {language} is the name of the active language
	-- en: As usual in {language}
	[ "menu.clock.auto" ] = "Standard für {language}",

	-- en: 12 hour
	[ "menu.clock.12h" ] = "12 Stunden",

	-- en: 24 hour
	[ "menu.clock.24h" ] = "24 Stunden",

	-- en: Show seconds
	[ "menu.clock.seconds" ] = "Sekunden anzeigen",

	-- en: Show AM / PM (12 hour clock)
	[ "menu.clock.ampm" ] = "AM / PM anzeigen (12-Stunden-Uhr)",

	-- en: Blink the colon
	[ "menu.clock.blink" ] = "Doppelpunkt blinken lassen",

	-- en: Units
	[ "menu.units.label" ] = "Einheiten",

	-- en: Metric (m, km/h)
	[ "menu.units.m" ] = "Metrisch (m, km/h)",

	-- en: Imperial (ft, mph)
	[ "menu.units.ft" ] = "Imperial (ft, mph)",

	-- en: Hammer units
	[ "menu.units.hu" ] = "Hammer-Einheiten",

	-- en: Distance decimals
	[ "menu.units.decimals" ] = "Nachkommastellen bei Entfernungen",

	-- en: Icons and effects
	[ "menu.fx.title" ] = "Symbole und Effekte",

	-- en: Speaker icon (volume, voice chat)
	[ "menu.fx.speaker" ] = "Lautsprechersymbol (Lautstärke, Sprachchat)",

	-- en: Signal icon (connection)
	[ "menu.fx.signal" ] = "Signalsymbol (Verbindung)",

	-- en: Battery icon (your device's battery)
	[ "menu.fx.battery" ] = "Batteriesymbol (Akku deines Geräts)",

	-- en: Boot animation when taking out the tool gun
	[ "menu.fx.boot" ] = "Startanimation beim Ziehen der Werkzeugpistole",

	-- en: Flash when the tool gun fires
	[ "menu.fx.flash" ] = "Aufblitzen, wenn die Werkzeugpistole feuert",

	-- en: Show game notifications on the screen
	[ "menu.fx.notify" ] = "Spielbenachrichtigungen auf dem Display zeigen",

	-- en: Notification time
	[ "menu.fx.notify_time" ] = "Anzeigedauer der Benachrichtigungen",

	-- en: Scanlines
	[ "menu.fx.scanlines" ] = "Scanlines",

	-- en: Darker edges
	[ "menu.fx.vignette" ] = "Dunklere Ränder",

	-- en: Backlight
	[ "menu.fx.backlight" ] = "Hintergrundbeleuchtung",

	-- en: HUD mirror
	[ "menu.mirror.title" ] = "HUD-Spiegel",

	-- en: Shows the screen on your HUD while you hold the tool gun, for reading the small print.
	[ "menu.mirror.help" ] = "Zeigt das Display zusätzlich auf deinem HUD, solange du die Werkzeugpistole hältst, damit du das Kleingedruckte lesen kannst.",

	-- en: Show the screen on the HUD
	[ "menu.mirror.enable" ] = "Display auf dem HUD zeigen",

	-- en: Corner
	[ "menu.mirror.corner" ] = "Ecke",

	-- en: Top right
	[ "menu.corner.tr" ] = "Oben rechts",

	-- en: Bottom right
	[ "menu.corner.br" ] = "Unten rechts",

	-- en: Bottom left
	[ "menu.corner.bl" ] = "Unten links",

	-- en: Top left
	[ "menu.corner.tl" ] = "Oben links",

	-- en: Size
	[ "menu.mirror.size" ] = "Größe",

	-- en: Opacity
	[ "menu.mirror.alpha" ] = "Deckkraft",

	-- en: Advanced
	[ "menu.adv.title" ] = "Erweitert",

	-- en: Keep the own screens of tools that draw one
	[ "menu.adv.respect" ] = "Eigene Displays von Werkzeugen beibehalten, die eines zeichnen",

	-- en: e.g. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod tools
	[ "menu.adv.respect_help" ] = "z. B. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod-Werkzeuge",

	-- en: Live value updates per second
	[ "menu.adv.refresh" ] = "Aktualisierungen der Live-Werte pro Sekunde",

	-- en: Screen redraws per second (0 = every frame)
	[ "menu.adv.fps" ] = "Neuzeichnungen des Displays pro Sekunde (0 = jedes Bild)",

	-- en: Resolution
	[ "menu.adv.resolution" ] = "Auflösung",

	-- en: 256 x 256 (original)
	[ "menu.res.256" ] = "256 x 256 (Original)",

	-- en: 512 x 512 (sharper, for 1440p and up)
	[ "menu.res.512" ] = "512 x 512 (schärfer, für 1440p und höher)",

	-- keep the commands as they are
	-- en: Key binds (bind <key> <command>):\n  dts_tool_back  -  previous tool\n  dts_tool_next / dts_tool_prev  -  cycle the category\n  dts_layout_next, dts_theme_next  -  cycle layouts, themes\n  dts_track / dts_untrack  -  follow an entity
	[ "menu.adv.binds" ] = "Tastenbelegung (bind <Taste> <Befehl>):\n  dts_tool_back  -  vorheriges Werkzeug\n  dts_tool_next / dts_tool_prev  -  durch die Kategorie blättern\n  dts_layout_next, dts_theme_next  -  Layouts, Designs durchschalten\n  dts_track / dts_untrack  -  ein Objekt verfolgen",

	-- en: Copy my settings to the clipboard
	[ "menu.adv.copy" ] = "Meine Einstellungen in die Zwischenablage kopieren",

	-- en: Screen settings copied to the clipboard
	[ "menu.adv.copied" ] = "Display-Einstellungen in die Zwischenablage kopiert",

	-- en: Import settings...
	[ "menu.adv.import" ] = "Einstellungen importieren...",

	-- en: Import screen settings
	[ "menu.adv.import_title" ] = "Display-Einstellungen importieren",

	-- en: Paste a DTS1:... settings string
	[ "menu.adv.import_prompt" ] = "Füge eine Einstellungszeichenkette DTS1:... ein",

	-- en: Import
	[ "menu.adv.import_ok" ] = "Importieren",

	-- en: Imported screen settings ({n} changed)
	[ "menu.adv.imported" ] = "Display-Einstellungen importiert ({n} geändert)",

	-- en: Reset everything to defaults
	[ "menu.adv.reset" ] = "Alles auf Standard zurücksetzen",

	-- en: Reset
	[ "menu.adv.reset_title" ] = "Zurücksetzen",

	-- en: Reset every Dynamic Toolgun Screen setting?
	[ "menu.adv.reset_question" ] = "Alle Einstellungen des Dynamischen Werkzeugpistolen-Displays zurücksetzen?",

	-- en: Reset
	[ "menu.adv.reset_yes" ] = "Zurücksetzen",

	-- en: Cancel
	[ "menu.adv.cancel" ] = "Abbrechen",

	-- en: Another addon replaced the tool gun screen ({file}). Use the button below to take over.
	[ "menu.adv.diag_conflict" ] = "Ein anderes Addon hat das Display der Werkzeugpistole ersetzt ({file}). Mit der Schaltfläche unten übernimmst du es wieder.",

	-- en: v{version} installed. Each redraw takes {ms} ms.
	[ "menu.adv.diag_ok" ] = "v{version} installiert. Jede Neuzeichnung dauert {ms} ms.",

	-- en: Last error: {error}
	[ "menu.adv.diag_error" ] = "Letzter Fehler: {error}",

	-- en: Waiting for the tool gun to load...
	[ "menu.adv.diag_wait" ] = "Warte, bis die Werkzeugpistole geladen ist...",

	-- en: Take over the tool gun screen
	[ "menu.adv.takeover" ] = "Display der Werkzeugpistole übernehmen",

	-- en: Only needed if another addon replaced the tool gun's screen after this one
	[ "menu.adv.takeover_tip" ] = "Nur nötig, wenn ein anderes Addon das Display der Werkzeugpistole nach diesem ersetzt hat",

	-- en: Dynamic Toolgun Screen installed
	[ "menu.adv.takeover_done" ] = "Dynamisches Werkzeugpistolen-Display installiert",

	-- answers to "Import settings..." when the pasted text is wrong
	-- en: This is not a Dynamic Toolgun Screen settings string.
	[ "import.not_ours" ] = "Das ist keine Einstellungszeichenkette des Dynamischen Werkzeugpistolen-Displays.",

	-- en: The settings string is damaged.
	[ "import.damaged" ] = "Die Einstellungszeichenkette ist beschädigt.",

	-- en: Token reference
	[ "menu.tokens.title" ] = "Token-Übersicht",

	-- en: Hover a token for what it does, double-click to copy it.
	[ "menu.tokens.help" ] = "Fahre mit der Maus über ein Token, um zu sehen, was es tut; ein Doppelklick kopiert es.",

	-- en: Token
	[ "menu.tokens.col_token" ] = "Token",

	-- en: Right now
	[ "menu.tokens.col_now" ] = "Gerade",

	-- en: Copied {token}
	[ "menu.tokens.copied" ] = "{token} kopiert",

}
