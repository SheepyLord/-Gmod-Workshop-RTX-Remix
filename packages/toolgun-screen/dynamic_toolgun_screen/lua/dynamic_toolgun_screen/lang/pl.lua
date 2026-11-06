--[[
	Dynamic Toolgun Screen - Polski (pl)

	Made from lang/en.lua with tools/i18n.py (see TRANSLATING.md). Above each phrase, "-- en:" holds the
	English it translates; "tools/i18n.py check" lists phrases whose English changed since. A phrase
	missing here falls back to English.
]]

return {

	-- name of the language in that language, shown in the language list
	-- en: English
	[ "_name" ] = "Polski",

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
	[ "tool.name" ] = "Dynamiczny ekran działka narzędziowego",

	-- en: Customize the tool gun's live screen and track entities on it
	[ "tool.desc" ] = "Dostosuj ekran działka narzędziowego na żywo i śledź na nim obiekty",

	-- en: Track the entity you are aiming at
	[ "tool.left" ] = "Śledź obiekt, w który celujesz",

	-- en: Switch to the next screen layout
	[ "tool.right" ] = "Przełącz na następny układ ekranu",

	-- en: Stop tracking
	[ "tool.reload" ] = "Zakończ śledzenie",

	-- context menu entry (right click an entity while holding C)
	-- en: Track on tool gun screen
	[ "prop.track" ] = "Śledź na ekranie działka narzędziowego",

	-- Utilities tab: category and its only entry
	-- en: Dynamic Toolgun Screen
	[ "menu.category" ] = "Dynamiczny ekran działka narzędziowego",

	-- en: Settings
	[ "menu.settings_item" ] = "Ustawienia",

	-- status line; {name} is an entity name such as "oildrum001" or a player's name
	-- en: Aiming at **{name}**
	[ "target.entity" ] = "Cel: **{name}**",

	-- en: Aiming at the **sky**
	[ "target.sky" ] = "Cel: **niebo**",

	-- en: World
	[ "target.world" ] = "Świat",

	-- {surface} is a material from the mat.* phrases below
	-- en: World - **{surface}**
	[ "target.world_surface" ] = "Świat - **{surface}**",

	-- en: Nothing in range
	[ "target.nothing" ] = "Nic w zasięgu",

	-- what you aim at, when it is the sky
	-- en: sky
	[ "aim.sky" ] = "niebo",

	-- multi-click tools (weld, rope...): which click comes next
	-- en: Stage {n}
	[ "tool.progress" ] = "Etap {n}",

	-- health of the tracked entity, e.g. "HP 40/100"
	-- en: HP {hp}
	[ "track.hp" ] = "HP {hp}",

	-- en: Noclip
	[ "noclip" ] = "No Clip",

	-- view angles: P = pitch, Y = yaw
	-- en: P {p}  Y {y}
	[ "eye_ang" ] = "Pochylenie {p}  Odchylenie {y}",

	-- compass heading, e.g. "NE 45°"
	-- en: {dir} {deg}°
	[ "heading" ] = "{dir} {deg}°",

	-- en: N
	[ "compass.n" ] = "N",

	-- en: NE
	[ "compass.ne" ] = "NE",

	-- en: E
	[ "compass.e" ] = "E",

	-- en: SE
	[ "compass.se" ] = "SE",

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
	[ "error.title" ] = "Błąd ekranu",

	-- en: See the console for details. Change the layout or run dts_reset to recover.
	[ "error.hint" ] = "Szczegóły znajdziesz w konsoli. Zmień układ lub wpisz dts_reset, aby przywrócić ekran.",

	-- tabs of the Advanced Toolgun [Hotbar] addon's tool list, for the {atg_tab} token
	-- en: Tools
	[ "atg.tab.tools" ] = "Narzędzia",

	-- en: Wire
	[ "atg.tab.wire" ] = "Wire",

	-- en: Favorites
	[ "atg.tab.favorites" ] = "Ulubione",

	-- the device's battery, next to the battery icon and in {battery}: {n} is the charge in percent;
	-- "Plugged in" is shown while the device runs on mains power instead of its battery
	-- en: {n}%
	[ "battery.percent" ] = "{n}%",

	-- en: Plugged in
	[ "battery.plugged" ] = "Zasilanie sieciowe",

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
	[ "unit.hu" ] = "{v} j.",

	-- en: {v} km/h
	[ "unit.kmh" ] = "{v} km/h",

	-- en: {v} mph
	[ "unit.mph" ] = "{v} mph",

	-- en: {v} u/s
	[ "unit.ups" ] = "{v} j./s",

	-- en: {v} kg
	[ "unit.kg" ] = "{v} kg",

	-- en: {v} MB
	[ "unit.mb" ] = "{v} MB",

	-- Durations: {h} hours, {m} minutes, {s} seconds (minutes and seconds come with two digits)
	-- en: {h}h {m}m
	[ "duration.hm" ] = "{h} godz. {m} min",

	-- en: {m}m {s}s
	[ "duration.ms" ] = "{m} min {s} s",

	-- en: {s}s
	[ "duration.s" ] = "{s} s",

	-- 12 hour clock: AM/PM and where they go around the time
	-- en: AM
	[ "clock.am" ] = "AM",

	-- en: PM
	[ "clock.pm" ] = "PM",

	-- en: {time} {ampm}
	[ "clock.ampm" ] = "{time} {ampm}",

	-- Date: {wday} day of week (short), {day} day number, {month} month (short), {year}
	-- en: {wday} {day} {month}
	[ "date.format" ] = "{wday}, {day} {month}",

	-- en: Sun
	[ "date.wday.1" ] = "niedz.",

	-- en: Mon
	[ "date.wday.2" ] = "pon.",

	-- en: Tue
	[ "date.wday.3" ] = "wt.",

	-- en: Wed
	[ "date.wday.4" ] = "śr.",

	-- en: Thu
	[ "date.wday.5" ] = "czw.",

	-- en: Fri
	[ "date.wday.6" ] = "pt.",

	-- en: Sat
	[ "date.wday.7" ] = "sob.",

	-- en: Sunday
	[ "date.wday_full.1" ] = "niedziela",

	-- en: Monday
	[ "date.wday_full.2" ] = "poniedziałek",

	-- en: Tuesday
	[ "date.wday_full.3" ] = "wtorek",

	-- en: Wednesday
	[ "date.wday_full.4" ] = "środa",

	-- en: Thursday
	[ "date.wday_full.5" ] = "czwartek",

	-- en: Friday
	[ "date.wday_full.6" ] = "piątek",

	-- en: Saturday
	[ "date.wday_full.7" ] = "sobota",

	-- short month names, used in dates ({month} above and %b): use the form your dates need
	-- en: Jan
	[ "date.month.1" ] = "sty",

	-- en: Feb
	[ "date.month.2" ] = "lut",

	-- en: Mar
	[ "date.month.3" ] = "mar",

	-- en: Apr
	[ "date.month.4" ] = "kwi",

	-- en: May
	[ "date.month.5" ] = "maj",

	-- en: Jun
	[ "date.month.6" ] = "cze",

	-- en: Jul
	[ "date.month.7" ] = "lip",

	-- en: Aug
	[ "date.month.8" ] = "sie",

	-- en: Sep
	[ "date.month.9" ] = "wrz",

	-- en: Oct
	[ "date.month.10" ] = "paź",

	-- en: Nov
	[ "date.month.11" ] = "lis",

	-- en: Dec
	[ "date.month.12" ] = "gru",

	-- full month names (%B), usually written right after a day number
	-- en: January
	[ "date.month_full.1" ] = "stycznia",

	-- en: February
	[ "date.month_full.2" ] = "lutego",

	-- en: March
	[ "date.month_full.3" ] = "marca",

	-- en: April
	[ "date.month_full.4" ] = "kwietnia",

	-- en: May
	[ "date.month_full.5" ] = "maja",

	-- en: June
	[ "date.month_full.6" ] = "czerwca",

	-- en: July
	[ "date.month_full.7" ] = "lipca",

	-- en: August
	[ "date.month_full.8" ] = "sierpnia",

	-- en: September
	[ "date.month_full.9" ] = "września",

	-- en: October
	[ "date.month_full.10" ] = "października",

	-- en: November
	[ "date.month_full.11" ] = "listopada",

	-- en: December
	[ "date.month_full.12" ] = "grudnia",

	-- Kinds of surface material (the game's material types), shown as "World - Concrete"
	-- en: Antlion
	[ "mat.antlion" ] = "Mrówkolew",

	-- en: Bloody flesh
	[ "mat.bloodyflesh" ] = "Zakrwawione ciało",

	-- en: Concrete
	[ "mat.concrete" ] = "Beton",

	-- en: Dirt
	[ "mat.dirt" ] = "Ziemia",

	-- en: Eggshell
	[ "mat.eggshell" ] = "Skorupka jajka",

	-- en: Flesh
	[ "mat.flesh" ] = "Ciało",

	-- en: Grate
	[ "mat.grate" ] = "Krata",

	-- en: Alien flesh
	[ "mat.alienflesh" ] = "Ciało obcego",

	-- en: Clip
	[ "mat.clip" ] = "Niewidzialna ściana",

	-- en: Snow
	[ "mat.snow" ] = "Śnieg",

	-- en: Plastic
	[ "mat.plastic" ] = "Plastik",

	-- en: Metal
	[ "mat.metal" ] = "Metal",

	-- en: Sand
	[ "mat.sand" ] = "Piasek",

	-- en: Foliage
	[ "mat.foliage" ] = "Listowie",

	-- en: Computer
	[ "mat.computer" ] = "Elektronika",

	-- en: Liquid
	[ "mat.slosh" ] = "Ciecz",

	-- en: Tile
	[ "mat.tile" ] = "Płytki",

	-- en: Grass
	[ "mat.grass" ] = "Trawa",

	-- en: Vent
	[ "mat.vent" ] = "Wentylacja",

	-- en: Wood
	[ "mat.wood" ] = "Drewno",

	-- en: Generic
	[ "mat.default" ] = "Ogólny",

	-- en: Glass
	[ "mat.glass" ] = "Szkło",

	-- en: Warp shield
	[ "mat.warpshield" ] = "Tarcza warp",

	-- Notifications on the screen
	-- en: Tracking {name}
	[ "notify.tracking" ] = "Śledzenie: {name}",

	-- en: Stopped tracking
	[ "notify.untracked" ] = "Zakończono śledzenie",

	-- en: Layout: {name}
	[ "notify.layout" ] = "Układ: {name}",

	-- en: Theme: {name}
	[ "notify.theme" ] = "Motyw: {name}",

	-- title bar: tool category, or the game's name when there is none (keep "Garry's Mod")
	-- en: {tool_category|Garry's Mod}
	[ "tpl.title" ] = "{tool_category|Garry's Mod}",

	-- left link of the Pocket PC screen: the previous tool
	-- en: Back to {tool_prev}
	[ "tpl.nav_back" ] = "Wstecz: {tool_prev}",

	-- en: Props {props}/{props_max}
	[ "tpl.props" ] = "Przedmioty {props}/{props_max}",

	-- en: {fps} fps  {ping} ms
	[ "tpl.perf" ] = "{fps} FPS  {ping} ms",

	-- en: Slope {aim_slope}
	[ "tpl.slope" ] = "Nachylenie {aim_slope}",

	-- en: HP {ent_health}
	[ "tpl.hp" ] = "HP {ent_health}",

	-- en: Owner: {ent_owner}
	[ "tpl.owner" ] = "Właściciel: {ent_owner}",

	-- HP = health, AP = armor
	-- en: HP {health}  AP {armor}
	[ "tpl.health_armor" ] = "HP {health}  Pancerz {armor}",

	-- en: {players} players
	[ "tpl.players" ] = "Gracze: {players}",

	-- Terminal lines: a short upper case label, a tab, then the value
	-- en: TOOL\t**{tool}**
	[ "tpl.term_tool" ] = "NARZ.\t**{tool}**",

	-- en: AIM\t**{aim_what}**
	[ "tpl.term_aim" ] = "CEL\t**{aim_what}**",

	-- en: CLASS\t**{ent_class|-}**
	[ "tpl.term_class" ] = "KLASA\t**{ent_class|-}**",

	-- en: POS\t**{aim_pos}**
	[ "tpl.term_pos" ] = "POZ.\t**{aim_pos}**",

	-- en: DIST\t**{aim_dist}**  {aim_slope}
	[ "tpl.term_dist" ] = "ODL.\t**{aim_dist}**  {aim_slope}",

	-- en: OWNER\t**{ent_owner|-}**
	[ "tpl.term_owner" ] = "WŁAŚC.\t**{ent_owner|-}**",

	-- en: HP\t**{ent_health|-}**
	[ "tpl.term_hp" ] = "HP\t**{ent_health|-}**",

	-- en: TRACK\t**{track_name|-}** {track_dist}
	[ "tpl.term_track" ] = "ŚLEDZ.\t**{track_name|-}** {track_dist}",

	-- en: Pocket PC
	[ "layout.pocketpc.name" ] = "Pocket PC",

	-- en: The original screen rebuilt with live data: clock, status icons, tool history links, big tool name, status line, six readouts and a hint bar.
	[ "layout.pocketpc.desc" ] = "Oryginalny ekran odtworzony z danymi na żywo: zegar, ikony stanu, odnośniki do historii narzędzi, duża nazwa narzędzia, wiersz stanu, sześć odczytów i pasek podpowiedzi.",

	-- en: Title bar
	[ "layout.pocketpc.title" ] = "Pasek tytułu",

	-- en: Clock
	[ "layout.pocketpc.clock" ] = "Zegar",

	-- en: Left link
	[ "layout.pocketpc.nav_l" ] = "Lewy odnośnik",

	-- en: Right link
	[ "layout.pocketpc.nav_r" ] = "Prawy odnośnik",

	-- en: Big text
	[ "layout.pocketpc.hero" ] = "Duży tekst",

	-- en: Under the big text
	[ "layout.pocketpc.sub" ] = "Pod dużym tekstem",

	-- en: Status line
	[ "layout.pocketpc.status" ] = "Wiersz stanu",

	-- en: Readout, left 1
	[ "layout.pocketpc.l1" ] = "Odczyt, lewy 1",

	-- en: Readout, left 2
	[ "layout.pocketpc.l2" ] = "Odczyt, lewy 2",

	-- en: Readout, left 3
	[ "layout.pocketpc.l3" ] = "Odczyt, lewy 3",

	-- en: Readout, right 1
	[ "layout.pocketpc.r1" ] = "Odczyt, prawy 1",

	-- en: Readout, right 2
	[ "layout.pocketpc.r2" ] = "Odczyt, prawy 2",

	-- en: Readout, right 3
	[ "layout.pocketpc.r3" ] = "Odczyt, prawy 3",

	-- en: Menu bar
	[ "layout.pocketpc.menu" ] = "Pasek menu",

	-- en: Terminal
	[ "layout.terminal.name" ] = "Terminal",

	-- en: Developer readout: eight lines of labels and values, an FPS graph and a prompt line with the tool hints.
	[ "layout.terminal.desc" ] = "Widok dla programistów: osiem wierszy etykiet i wartości, wykres FPS i wiersz poleceń z podpowiedziami narzędzia.",

	-- en: Header
	[ "layout.terminal.head" ] = "Nagłówek",

	-- en: Header, right
	[ "layout.terminal.clock" ] = "Nagłówek, prawa strona",

	-- en: Line 1
	[ "layout.terminal.l1" ] = "Wiersz 1",

	-- en: Line 2
	[ "layout.terminal.l2" ] = "Wiersz 2",

	-- en: Line 3
	[ "layout.terminal.l3" ] = "Wiersz 3",

	-- en: Line 4
	[ "layout.terminal.l4" ] = "Wiersz 4",

	-- en: Line 5
	[ "layout.terminal.l5" ] = "Wiersz 5",

	-- en: Line 6
	[ "layout.terminal.l6" ] = "Wiersz 6",

	-- en: Line 7
	[ "layout.terminal.l7" ] = "Wiersz 7",

	-- en: Line 8
	[ "layout.terminal.l8" ] = "Wiersz 8",

	-- en: Prompt line
	[ "layout.terminal.foot" ] = "Wiersz poleceń",

	-- en: Minimal
	[ "layout.minimal.name" ] = "Minimalny",

	-- en: Large, glanceable text: clock, compass, the tool name sized to fit, what you aim at and two corner values.
	[ "layout.minimal.desc" ] = "Duży tekst czytelny na pierwszy rzut oka: zegar, kompas, nazwa narzędzia dopasowana do miejsca, twój cel i dwie wartości w rogach.",

	-- en: Top left
	[ "layout.minimal.top_l" ] = "Lewy górny róg",

	-- en: Top right
	[ "layout.minimal.top_r" ] = "Prawy górny róg",

	-- en: Big text
	[ "layout.minimal.hero" ] = "Duży tekst",

	-- en: Under the big text
	[ "layout.minimal.sub" ] = "Pod dużym tekstem",

	-- en: Bottom left
	[ "layout.minimal.foot_l" ] = "Lewy dolny róg",

	-- en: Bottom right
	[ "layout.minimal.foot_r" ] = "Prawy dolny róg",

	-- en: Pocket PC (original)
	[ "theme.winmobile" ] = "Pocket PC (oryginalny)",

	-- en: Graphite
	[ "theme.graphite" ] = "Grafit",

	-- en: Green phosphor
	[ "theme.phosphor" ] = "Zielony luminofor",

	-- en: Amber CRT
	[ "theme.amber" ] = "Bursztynowy CRT",

	-- en: Sakura
	[ "theme.sakura" ] = "Sakura",

	-- en: Sandbox blue
	[ "theme.sandbox" ] = "Niebieski Sandbox",

	-- parts of the screen whose colour can be changed
	-- en: Title bar
	[ "color.bar" ] = "Pasek tytułu",

	-- en: Links and highlights
	[ "color.accent" ] = "Odnośniki i wyróżnienia",

	-- en: Big text
	[ "color.hero" ] = "Duży tekst",

	-- en: Status line
	[ "color.strip" ] = "Wiersz stanu",

	-- en: Readout panel
	[ "color.panel" ] = "Panel odczytów",

	-- en: Menu bar
	[ "color.menu" ] = "Pasek menu",

	-- en: Terminal text
	[ "color.term" ] = "Tekst terminala",

	-- en: Text
	[ "category.text" ] = "Tekst",

	-- en: Time
	[ "category.time" ] = "Czas",

	-- en: Tool
	[ "category.tool" ] = "Narzędzie",

	-- en: Aim
	[ "category.aim" ] = "Celowanie",

	-- en: Aimed entity
	[ "category.entity" ] = "Obiekt na celowniku",

	-- en: Tracked entity
	[ "category.tracked" ] = "Śledzony obiekt",

	-- en: You
	[ "category.player" ] = "Ty",

	-- en: Game
	[ "category.game" ] = "Gra",

	-- the Advanced Toolgun [Hotbar] addon; keep its name as it is
	-- en: Advanced Toolgun
	[ "category.atg" ] = "Advanced Toolgun",

	-- en: A line in your language from the language files, e.g. {tr:nav_back} or {tr:props}.
	[ "token.tr" ] = "Wiersz w twoim języku z plików językowych, np. {tr:nav_back} lub {tr:props}.",

	-- en: Local time, formatted by the clock settings. {time:%H:%M:%S} takes an os.date format.
	[ "token.time" ] = "Czas lokalny w formacie z ustawień zegara. {time:%H:%M:%S} przyjmuje format os.date.",

	-- en: Today's date. {date:%Y-%m-%d} takes an os.date format.
	[ "token.date" ] = "Dzisiejsza data. {date:%Y-%m-%d} przyjmuje format os.date.",

	-- en: How long you have been in this game.
	[ "token.session" ] = "Jak długo jesteś w tej grze.",

	-- en: How long the map has been running.
	[ "token.map_time" ] = "Jak długo działa mapa.",

	-- en: Name of the selected tool.
	[ "token.tool" ] = "Nazwa wybranego narzędzia.",

	-- en: Internal name of the selected tool.
	[ "token.tool_id" ] = "Wewnętrzna nazwa wybranego narzędzia.",

	-- en: Description of the selected tool.
	[ "token.tool_desc" ] = "Opis wybranego narzędzia.",

	-- en: Tool menu category of the selected tool.
	[ "token.tool_category" ] = "Kategoria wybranego narzędzia w menu narzędzi.",

	-- en: Stage of the selected tool (0 = nothing selected yet).
	[ "token.tool_stage" ] = "Etap wybranego narzędzia (0 = jeszcze nic nie wybrano).",

	-- en: The stage while a multi-click tool is in progress, otherwise empty.
	[ "token.tool_progress" ] = "Etap, gdy trwa praca narzędziem wymagającym kilku kliknięć, w przeciwnym razie pusto.",

	-- en: The tool you used before this one (dts_tool_back switches to it).
	[ "token.tool_prev" ] = "Narzędzie używane przed obecnym (dts_tool_back przełącza na nie).",

	-- en: The next tool in the same menu category (dts_tool_next switches to it).
	[ "token.tool_next" ] = "Następne narzędzie z tej samej kategorii menu (dts_tool_next przełącza na nie).",

	-- en: Successful tool gun shots this session.
	[ "token.tool_uses" ] = "Udane strzały z działka narzędziowego w tej sesji.",

	-- en: A setting of the selected tool, e.g. {tool_cvar:forcelimit} reads weld_forcelimit.
	[ "token.tool_cvar" ] = "Ustawienie wybranego narzędzia, np. {tool_cvar:forcelimit} odczytuje weld_forcelimit.",

	-- en: All settings of the selected tool as name=value pairs.
	[ "token.tool_settings" ] = "Wszystkie ustawienia wybranego narzędzia jako pary nazwa=wartość.",

	-- en: The current stage's instructions with mouse and key icons.
	[ "token.hints" ] = "Instrukcje bieżącego etapu z ikonami myszy i klawiszy.",

	-- en: What left click does right now.
	[ "token.hint_left" ] = "Co teraz robi lewy przycisk myszy.",

	-- en: What right click does right now.
	[ "token.hint_right" ] = "Co teraz robi prawy przycisk myszy.",

	-- en: What reload does right now.
	[ "token.hint_reload" ] = "Co teraz robi klawisz przeładowania.",

	-- en: What you are aiming at, with the name highlighted.
	[ "token.target" ] = "W co celujesz, z wyróżnioną nazwą.",

	-- en: Entity name, or the surface material when aiming at the world.
	[ "token.aim_what" ] = "Nazwa obiektu albo materiał powierzchni, gdy celujesz w świat.",

	-- en: Position you are aiming at.
	[ "token.aim_pos" ] = "Punkt, w który celujesz.",

	-- en: X of the aim position.
	[ "token.aim_x" ] = "X punktu celowania.",

	-- en: Y of the aim position.
	[ "token.aim_y" ] = "Y punktu celowania.",

	-- en: Z of the aim position.
	[ "token.aim_z" ] = "Z punktu celowania.",

	-- en: Distance to the aim position.
	[ "token.aim_dist" ] = "Odległość do punktu celowania.",

	-- en: Surface normal at the aim position.
	[ "token.aim_normal" ] = "Normalna powierzchni w punkcie celowania.",

	-- en: Steepness of the surface (0 = flat floor, 90 = wall).
	[ "token.aim_slope" ] = "Nachylenie powierzchni (0 = płaska podłoga, 90 = ściana).",

	-- en: Kind of surface material (metal, wood, concrete...).
	[ "token.aim_surface" ] = "Rodzaj materiału powierzchni (metal, drewno, beton...).",

	-- en: Surface property as the engine names it (metal box, wood crate...).
	[ "token.aim_surfaceprop" ] = "Właściwość powierzchni pod nazwą używaną przez silnik (metal box, wood crate...).",

	-- en: World texture you are aiming at.
	[ "token.aim_texture" ] = "Tekstura świata, w którą celujesz.",

	-- en: Friendly name of the aimed entity.
	[ "token.ent_name" ] = "Czytelna nazwa obiektu na celowniku.",

	-- en: Class of the aimed entity.
	[ "token.ent_class" ] = "Klasa obiektu na celowniku.",

	-- en: Model file name of the aimed entity.
	[ "token.ent_model" ] = "Nazwa pliku modelu obiektu na celowniku.",

	-- en: Full model path of the aimed entity.
	[ "token.ent_model_path" ] = "Pełna ścieżka modelu obiektu na celowniku.",

	-- en: Entity index.
	[ "token.ent_index" ] = "Indeks obiektu.",

	-- en: Health of the aimed entity (players, NPCs, breakable props).
	[ "token.ent_health" ] = "Zdrowie obiektu na celowniku (gracze, NPC, zniszczalne przedmioty).",

	-- en: Owner of the aimed entity (in multiplayer this needs a CPPI prop protection addon).
	[ "token.ent_owner" ] = "Właściciel obiektu na celowniku (w trybie wieloosobowym wymaga dodatku do ochrony przedmiotów z obsługą CPPI).",

	-- en: Material of the aimed entity.
	[ "token.ent_material" ] = "Materiał obiektu na celowniku.",

	-- en: Colour of the aimed entity.
	[ "token.ent_color" ] = "Kolor obiektu na celowniku.",

	-- en: Skin of the aimed entity.
	[ "token.ent_skin" ] = "Skórka obiektu na celowniku.",

	-- en: Speed of the aimed entity.
	[ "token.ent_speed" ] = "Prędkość obiektu na celowniku.",

	-- en: Position of the aimed entity.
	[ "token.ent_pos" ] = "Położenie obiektu na celowniku.",

	-- en: Angles of the aimed entity.
	[ "token.ent_ang" ] = "Kąty obiektu na celowniku.",

	-- en: Mass of the aimed entity, when your game knows its physics.
	[ "token.ent_mass" ] = "Masa obiektu na celowniku, jeśli twoja gra zna jego fizykę.",

	-- en: Tracked entity summary: name, distance, speed, health.
	[ "token.track" ] = "Podsumowanie śledzonego obiektu: nazwa, odległość, prędkość, zdrowie.",

	-- en: Name of the tracked entity.
	[ "token.track_name" ] = "Nazwa śledzonego obiektu.",

	-- en: Class of the tracked entity.
	[ "token.track_class" ] = "Klasa śledzonego obiektu.",

	-- en: Your distance to the tracked entity.
	[ "token.track_dist" ] = "Twoja odległość od śledzonego obiektu.",

	-- en: Speed of the tracked entity.
	[ "token.track_speed" ] = "Prędkość śledzonego obiektu.",

	-- en: Health of the tracked entity.
	[ "token.track_health" ] = "Zdrowie śledzonego obiektu.",

	-- en: Position of the tracked entity.
	[ "token.track_pos" ] = "Położenie śledzonego obiektu.",

	-- en: Your name.
	[ "token.player" ] = "Twój nick.",

	-- en: Your health.
	[ "token.health" ] = "Twoje zdrowie.",

	-- en: Your armor.
	[ "token.armor" ] = "Twój pancerz.",

	-- en: Your speed.
	[ "token.speed" ] = "Twoja prędkość.",

	-- en: Your position.
	[ "token.pos" ] = "Twoje położenie.",

	-- en: Your view pitch and yaw.
	[ "token.eye_ang" ] = "Pochylenie i odchylenie twojego wzroku.",

	-- en: Compass heading (north is +Y on the map).
	[ "token.heading" ] = "Kierunek na kompasie (północ to +Y na mapie).",

	-- en: Shows a word while you are noclipping, otherwise empty.
	[ "token.noclip" ] = "Wyświetla słowo, gdy włączony jest No Clip, w przeciwnym razie pusto.",

	-- en: Frames per second (smoothed).
	[ "token.fps" ] = "Klatki na sekundę (wygładzone).",

	-- en: Your ping in milliseconds.
	[ "token.ping" ] = "Twój ping w milisekundach.",

	-- en: Your device's battery charge while it runs on battery, or \"Plugged in\".
	[ "token.battery" ] = "Poziom naładowania baterii urządzenia podczas pracy na baterii, w przeciwnym razie „Zasilanie sieciowe”.",

	-- en: Current map.
	[ "token.map" ] = "Bieżąca mapa.",

	-- en: Players on the server and its player limit.
	[ "token.players" ] = "Gracze na serwerze i limit graczy.",

	-- en: Server name.
	[ "token.server" ] = "Nazwa serwera.",

	-- en: Active gamemode.
	[ "token.gamemode" ] = "Aktywny tryb gry.",

	-- en: Server tick rate.
	[ "token.tickrate" ] = "Tickrate serwera.",

	-- en: Memory used by Lua in your game.
	[ "token.lua_mem" ] = "Pamięć używana przez Lua w twojej grze.",

	-- en: Entities known to your game.
	[ "token.entities" ] = "Obiekty znane twojej grze.",

	-- en: Props you have spawned.
	[ "token.props" ] = "Przedmioty utworzone przez ciebie.",

	-- en: Your prop limit.
	[ "token.props_max" ] = "Twój limit przedmiotów.",

	-- en: Spawn count and limit of a type, e.g. {count:ragdolls} or {count:thrusters}.
	[ "token.count" ] = "Liczba i limit danego typu, np. {count:ragdolls} lub {count:thrusters}.",

	-- en: Value of any console variable, e.g. {cvar:sv_gravity}.
	[ "token.cvar" ] = "Wartość dowolnej zmiennej konsoli, np. {cvar:sv_gravity}.",

	-- en: Advanced Toolgun [Hotbar]: its open tab (Tools, Wire or Favorites).
	[ "token.atg_tab" ] = "Advanced Toolgun [Hotbar]: jego otwarta karta (Narzędzia, Wire lub Ulubione).",

	-- en: Advanced Toolgun [Hotbar]: the section of its list the selection is in.
	[ "token.atg_section" ] = "Advanced Toolgun [Hotbar]: sekcja jego listy, w której jest zaznaczenie.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel up.
	[ "token.atg_prev" ] = "Advanced Toolgun [Hotbar]: narzędzie, na które przełącza jego szybki wybór kółkiem myszy w górę.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel down.
	[ "token.atg_next" ] = "Advanced Toolgun [Hotbar]: narzędzie, na które przełącza jego szybki wybór kółkiem myszy w dół.",

	-- en: Turns the tool gun's mini screen into a live display. Changes apply instantly; the preview shows what the screen draws right now.
	[ "menu.intro" ] = "Zamienia mały ekran działka narzędziowego w wyświetlacz na żywo. Zmiany działają od razu; podgląd pokazuje, co ekran rysuje w tej chwili.",

	-- en: Dynamic screen is off
	[ "menu.preview_off" ] = "Dynamiczny ekran jest wyłączony",

	-- en: Enable the dynamic screen
	[ "menu.enable" ] = "Włącz dynamiczny ekran",

	-- en: Language
	[ "menu.language" ] = "Język",

	-- first entry of the language list; {name} is the game's language, e.g. "English"
	-- en: Automatic: {name}
	[ "menu.language.auto" ] = "Automatycznie: {name}",

	-- en: Inspect: read the screen up close
	[ "menu.inspect.title" ] = "Oglądanie: czytaj ekran z bliska",

	-- en: Hold a key while holding the tool gun to raise its screen to your eyes.
	[ "menu.inspect.help" ] = "Przytrzymaj klawisz, trzymając działko narzędziowe, aby podnieść jego ekran do oczu.",

	-- en: Inspect key
	[ "menu.inspect.key" ] = "Klawisz oglądania",

	-- en: Screen size while inspecting
	[ "menu.inspect.size" ] = "Rozmiar ekranu podczas oglądania",

	-- en: Or use the console: bind <key> +dts_inspect (hold) or dts_inspect_toggle.
	[ "menu.inspect.console" ] = "Albo w konsoli: bind <klawisz> +dts_inspect (przytrzymaj) lub dts_inspect_toggle.",

	-- the tool gun model has a paper note glued on, which overlaps the screen's top right corner
	-- en: Screen in front of the paper note
	[ "menu.inspect.on_top" ] = "Ekran przed karteczką",

	-- en: While inspecting, the whole screen stays readable. Untick to let the paper note glued to the tool gun cover the top right corner of the screen, as on the model.
	[ "menu.inspect.on_top_help" ] = "Podczas oglądania cały ekran pozostaje czytelny. Odznacz, aby karteczka przyklejona do działka narzędziowego zasłaniała prawy górny róg ekranu, tak jak na modelu.",

	-- en: Layout and look
	[ "menu.look.title" ] = "Układ i wygląd",

	-- en: Layout
	[ "menu.look.layout" ] = "Układ",

	-- en: Theme
	[ "menu.look.theme" ] = "Motyw",

	-- en: Background
	[ "menu.look.background" ] = "Tło",

	-- en: Automatic (layout's choice)
	[ "menu.bg.auto" ] = "Automatyczne (wybór układu)",

	-- the whole original screen picture without its text
	-- en: Original screen
	[ "menu.bg.original" ] = "Oryginalny ekran",

	-- only the blurred photo from the original picture, filling the screen
	-- en: Original photo
	[ "menu.bg.art" ] = "Oryginalne zdjęcie",

	-- en: Theme gradient
	[ "menu.bg.gradient" ] = "Gradient motywu",

	-- en: Live camera: zoom
	[ "menu.bg.camera" ] = "Kamera na żywo: przybliżenie",

	-- en: Live camera: rear view
	[ "menu.bg.rear" ] = "Kamera na żywo: widok do tyłu",

	-- en: Custom image
	[ "menu.bg.image" ] = "Własny obraz",

	-- en: Black
	[ "menu.bg.black" ] = "Czarne",

	-- en: Custom image
	[ "menu.look.image" ] = "Własny obraz",

	-- en: A material path, or an image in garrysmod/data written as ../data/name.png
	[ "menu.look.image_help" ] = "Ścieżka materiału albo obraz z garrysmod/data zapisany jako ../data/nazwa.png",

	-- en: Darken background
	[ "menu.look.dim" ] = "Przyciemnij tło",

	-- en: Camera field of view
	[ "menu.look.cam_fov" ] = "Pole widzenia kamery",

	-- en: Camera updates per second
	[ "menu.look.cam_fps" ] = "Odświeżenia kamery na sekundę",

	-- en: Text font
	[ "menu.look.font" ] = "Czcionka tekstu",

	-- en: Big text font
	[ "menu.look.font_hero" ] = "Czcionka dużego tekstu",

	-- en: Terminal font
	[ "menu.look.font_mono" ] = "Czcionka terminala",

	-- first entry of the font lists; {font} is the font your language uses
	-- en: Automatic ({font})
	[ "menu.font.auto" ] = "Automatyczna ({font})",

	-- en: Colours
	[ "menu.colors.title" ] = "Kolory",

	-- en: Override single colours of the theme. Click a swatch to change it.
	[ "menu.colors.help" ] = "Zastąp pojedyncze kolory motywu. Kliknij próbkę, aby ją zmienić.",

	-- written on a colour swatch that still uses the theme's colour
	-- en: theme
	[ "menu.colors.theme_tag" ] = "motyw",

	-- en: Click to pick a colour
	[ "menu.colors.pick" ] = "Kliknij, aby wybrać kolor",

	-- en: Use the theme's colours everywhere
	[ "menu.colors.reset_all" ] = "Używaj wszędzie kolorów motywu",

	-- en: Screen colour: {name}
	[ "menu.colors.picker_title" ] = "Kolor ekranu: {name}",

	-- en: Use the theme's colour
	[ "menu.colors.use_theme" ] = "Użyj koloru motywu",

	-- en: Big text
	[ "menu.hero.title" ] = "Duży tekst",

	-- en: Behaviour
	[ "menu.hero.mode" ] = "Zachowanie",

	-- en: Always scroll (original)
	[ "menu.hero.scroll" ] = "Zawsze przewijaj (oryginał)",

	-- en: Scroll only when too long
	[ "menu.hero.auto" ] = "Przewijaj tylko, gdy się nie mieści",

	-- en: Shrink to fit
	[ "menu.hero.fit" ] = "Zmniejsz, aby się zmieścił",

	-- en: Scroll speed
	[ "menu.hero.speed" ] = "Prędkość przewijania",

	-- en: Upper case tool names
	[ "menu.hero.upper" ] = "Nazwy narzędzi wielkimi literami",

	-- en: Screen content
	[ "menu.content.title" ] = "Zawartość ekranu",

	-- keep {tokens}, **stars**, {token|fallback} and {tr:...} as they are: they show the syntax
	-- en: Every line of the {layout} layout is a template. Type text and {tokens}; **stars** highlight text, {token|fallback} gives a default, and a line whose tokens are all empty hides itself. {tr:...} writes a line in your language. See the token reference below.
	[ "menu.content.help" ] = "Każdy wiersz układu „{layout}” to szablon. Wpisz tekst i {tokens}; **gwiazdki** wyróżniają tekst, {token|fallback} podaje wartość domyślną, a wiersz, którego wszystkie tokeny są puste, sam się ukrywa. {tr:...} wpisuje wiersz w twoim języku. Lista tokenów znajduje się poniżej.",

	-- en: Pick a ready-made line
	[ "menu.content.presets_tip" ] = "Wybierz gotowy wiersz",

	-- en: Back to the default: {value}
	[ "menu.content.reset_tip" ] = "Przywróć domyślny: {value}",

	-- en: (empty)
	[ "menu.content.empty" ] = "(pusty)",

	-- shown in an empty line's text box
	-- en: (hidden)
	[ "menu.content.placeholder" ] = "(ukryty)",

	-- under each line: what it shows right now
	-- en: = {text}
	[ "menu.content.now" ] = "= {text}",

	-- en: (hidden right now)
	[ "menu.content.hidden_now" ] = "(teraz ukryty)",

	-- en: Reset these lines to the layout's defaults
	[ "menu.content.reset_all" ] = "Przywróć domyślne wiersze układu",

	-- ready-made lines in the list next to each line
	-- en: Tool name
	[ "menu.preset.tool" ] = "Nazwa narzędzia",

	-- en: Tool category
	[ "menu.preset.tool_category" ] = "Kategoria narzędzia",

	-- en: Tool instructions
	[ "menu.preset.hints" ] = "Instrukcje narzędzia",

	-- en: Previous tool
	[ "menu.preset.prev_tool" ] = "Poprzednie narzędzie",

	-- en: Next tool
	[ "menu.preset.next_tool" ] = "Następne narzędzie",

	-- en: Tool progress
	[ "menu.preset.progress" ] = "Postęp narzędzia",

	-- en: Tool settings
	[ "menu.preset.tool_settings" ] = "Ustawienia narzędzia",

	-- en: What you aim at
	[ "menu.preset.target" ] = "Twój cel",

	-- en: Aim position
	[ "menu.preset.aim_pos" ] = "Punkt celowania",

	-- en: Aim distance
	[ "menu.preset.aim_dist" ] = "Odległość do celu",

	-- en: Entity or surface
	[ "menu.preset.aim_what" ] = "Obiekt lub powierzchnia",

	-- en: Surface slope
	[ "menu.preset.slope" ] = "Nachylenie powierzchni",

	-- en: Entity class
	[ "menu.preset.ent_class" ] = "Klasa obiektu",

	-- en: Entity model
	[ "menu.preset.ent_model" ] = "Model obiektu",

	-- en: Entity health
	[ "menu.preset.ent_health" ] = "Zdrowie obiektu",

	-- en: Entity owner
	[ "menu.preset.ent_owner" ] = "Właściciel obiektu",

	-- en: Entity speed
	[ "menu.preset.ent_speed" ] = "Prędkość obiektu",

	-- en: Tracked entity
	[ "menu.preset.track" ] = "Śledzony obiekt",

	-- en: Clock
	[ "menu.preset.clock" ] = "Zegar",

	-- en: Clock with seconds
	[ "menu.preset.clock_seconds" ] = "Zegar z sekundami",

	-- en: Date
	[ "menu.preset.date" ] = "Data",

	-- en: Time in game
	[ "menu.preset.session" ] = "Czas w grze",

	-- en: Your speed
	[ "menu.preset.speed" ] = "Twoja prędkość",

	-- en: Your position
	[ "menu.preset.pos" ] = "Twoje położenie",

	-- en: Compass
	[ "menu.preset.heading" ] = "Kompas",

	-- en: Health and armor
	[ "menu.preset.health_armor" ] = "Zdrowie i pancerz",

	-- en: FPS and ping
	[ "menu.preset.perf" ] = "FPS i ping",

	-- en: Prop count
	[ "menu.preset.props" ] = "Liczba przedmiotów",

	-- en: Map
	[ "menu.preset.map" ] = "Mapa",

	-- en: Players
	[ "menu.preset.players" ] = "Gracze",

	-- en: Empty (hide the line)
	[ "menu.preset.empty" ] = "Pusty (ukryj wiersz)",

	-- en: Clock and units
	[ "menu.clock.title" ] = "Zegar i jednostki",

	-- en: Clock
	[ "menu.clock.style" ] = "Zegar",

	-- {language} is the name of the active language
	-- en: As usual in {language}
	[ "menu.clock.auto" ] = "Zgodnie z językiem ({language})",

	-- en: 12 hour
	[ "menu.clock.12h" ] = "12-godzinny",

	-- en: 24 hour
	[ "menu.clock.24h" ] = "24-godzinny",

	-- en: Show seconds
	[ "menu.clock.seconds" ] = "Pokazuj sekundy",

	-- en: Show AM / PM (12 hour clock)
	[ "menu.clock.ampm" ] = "Pokazuj AM / PM (zegar 12-godzinny)",

	-- en: Blink the colon
	[ "menu.clock.blink" ] = "Migający dwukropek",

	-- en: Units
	[ "menu.units.label" ] = "Jednostki",

	-- en: Metric (m, km/h)
	[ "menu.units.m" ] = "Metryczne (m, km/h)",

	-- en: Imperial (ft, mph)
	[ "menu.units.ft" ] = "Imperialne (ft, mph)",

	-- en: Hammer units
	[ "menu.units.hu" ] = "Jednostki Hammera",

	-- en: Distance decimals
	[ "menu.units.decimals" ] = "Miejsca po przecinku w odległościach",

	-- en: Icons and effects
	[ "menu.fx.title" ] = "Ikony i efekty",

	-- en: Speaker icon (volume, voice chat)
	[ "menu.fx.speaker" ] = "Ikona głośnika (głośność, czat głosowy)",

	-- en: Signal icon (connection)
	[ "menu.fx.signal" ] = "Ikona sygnału (połączenie)",

	-- en: Battery icon (your device's battery)
	[ "menu.fx.battery" ] = "Ikona baterii (bateria urządzenia)",

	-- en: Boot animation when taking out the tool gun
	[ "menu.fx.boot" ] = "Animacja uruchamiania przy wyjmowaniu działka narzędziowego",

	-- en: Flash when the tool gun fires
	[ "menu.fx.flash" ] = "Błysk przy strzale z działka narzędziowego",

	-- en: Show game notifications on the screen
	[ "menu.fx.notify" ] = "Pokazuj powiadomienia gry na ekranie",

	-- en: Notification time
	[ "menu.fx.notify_time" ] = "Czas wyświetlania powiadomień",

	-- en: Scanlines
	[ "menu.fx.scanlines" ] = "Linie skanowania",

	-- en: Darker edges
	[ "menu.fx.vignette" ] = "Ciemniejsze krawędzie",

	-- en: Backlight
	[ "menu.fx.backlight" ] = "Podświetlenie",

	-- en: HUD mirror
	[ "menu.mirror.title" ] = "Lustro na HUD",

	-- en: Shows the screen on your HUD while you hold the tool gun, for reading the small print.
	[ "menu.mirror.help" ] = "Pokazuje ekran także na HUD, gdy trzymasz działko narzędziowe, żeby łatwiej czytać drobny druk.",

	-- en: Show the screen on the HUD
	[ "menu.mirror.enable" ] = "Pokazuj ekran na HUD",

	-- en: Corner
	[ "menu.mirror.corner" ] = "Róg",

	-- en: Top right
	[ "menu.corner.tr" ] = "Prawy górny",

	-- en: Bottom right
	[ "menu.corner.br" ] = "Prawy dolny",

	-- en: Bottom left
	[ "menu.corner.bl" ] = "Lewy dolny",

	-- en: Top left
	[ "menu.corner.tl" ] = "Lewy górny",

	-- en: Size
	[ "menu.mirror.size" ] = "Rozmiar",

	-- en: Opacity
	[ "menu.mirror.alpha" ] = "Krycie",

	-- en: Advanced
	[ "menu.adv.title" ] = "Zaawansowane",

	-- en: Keep the own screens of tools that draw one
	[ "menu.adv.respect" ] = "Zachowaj własne ekrany narzędzi, które je rysują",

	-- en: e.g. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod tools
	[ "menu.adv.respect_help" ] = "np. Easy Entity Inspector, Ragdoll Puppeteer, narzędzia Wiremod",

	-- en: Live value updates per second
	[ "menu.adv.refresh" ] = "Odświeżenia wartości na sekundę",

	-- en: Screen redraws per second (0 = every frame)
	[ "menu.adv.fps" ] = "Odświeżenia ekranu na sekundę (0 = każda klatka)",

	-- en: Resolution
	[ "menu.adv.resolution" ] = "Rozdzielczość",

	-- en: 256 x 256 (original)
	[ "menu.res.256" ] = "256 x 256 (oryginalna)",

	-- en: 512 x 512 (sharper, for 1440p and up)
	[ "menu.res.512" ] = "512 x 512 (ostrzejsza, dla 1440p i wyżej)",

	-- keep the commands as they are
	-- en: Key binds (bind <key> <command>):\n  dts_tool_back  -  previous tool\n  dts_tool_next / dts_tool_prev  -  cycle the category\n  dts_layout_next, dts_theme_next  -  cycle layouts, themes\n  dts_track / dts_untrack  -  follow an entity
	[ "menu.adv.binds" ] = "Przypisania klawiszy (bind <klawisz> <polecenie>):\n  dts_tool_back  -  poprzednie narzędzie\n  dts_tool_next / dts_tool_prev  -  przełączanie w kategorii\n  dts_layout_next, dts_theme_next  -  przełączanie układów, motywów\n  dts_track / dts_untrack  -  śledzenie obiektu",

	-- en: Copy my settings to the clipboard
	[ "menu.adv.copy" ] = "Skopiuj moje ustawienia do schowka",

	-- en: Screen settings copied to the clipboard
	[ "menu.adv.copied" ] = "Skopiowano ustawienia ekranu do schowka",

	-- en: Import settings...
	[ "menu.adv.import" ] = "Importuj ustawienia...",

	-- en: Import screen settings
	[ "menu.adv.import_title" ] = "Import ustawień ekranu",

	-- en: Paste a DTS1:... settings string
	[ "menu.adv.import_prompt" ] = "Wklej ciąg ustawień DTS1:...",

	-- en: Import
	[ "menu.adv.import_ok" ] = "Importuj",

	-- en: Imported screen settings ({n} changed)
	[ "menu.adv.imported" ] = "Zaimportowano ustawienia ekranu (zmienione: {n})",

	-- en: Reset everything to defaults
	[ "menu.adv.reset" ] = "Przywróć wszystko do domyślnych",

	-- en: Reset
	[ "menu.adv.reset_title" ] = "Resetowanie",

	-- en: Reset every Dynamic Toolgun Screen setting?
	[ "menu.adv.reset_question" ] = "Zresetować wszystkie ustawienia Dynamicznego ekranu działka narzędziowego?",

	-- en: Reset
	[ "menu.adv.reset_yes" ] = "Resetuj",

	-- en: Cancel
	[ "menu.adv.cancel" ] = "Anuluj",

	-- en: Another addon replaced the tool gun screen ({file}). Use the button below to take over.
	[ "menu.adv.diag_conflict" ] = "Inny dodatek zastąpił ekran działka narzędziowego ({file}). Użyj przycisku poniżej, aby go przejąć.",

	-- en: v{version} installed. Each redraw takes {ms} ms.
	[ "menu.adv.diag_ok" ] = "v{version} zainstalowana. Każde odświeżenie zajmuje {ms} ms.",

	-- en: Last error: {error}
	[ "menu.adv.diag_error" ] = "Ostatni błąd: {error}",

	-- en: Waiting for the tool gun to load...
	[ "menu.adv.diag_wait" ] = "Oczekiwanie na załadowanie działka narzędziowego...",

	-- en: Take over the tool gun screen
	[ "menu.adv.takeover" ] = "Przejmij ekran działka narzędziowego",

	-- en: Only needed if another addon replaced the tool gun's screen after this one
	[ "menu.adv.takeover_tip" ] = "Potrzebne tylko, jeśli inny dodatek zastąpił ekran działka narzędziowego po tym dodatku",

	-- en: Dynamic Toolgun Screen installed
	[ "menu.adv.takeover_done" ] = "Zainstalowano Dynamiczny ekran działka narzędziowego",

	-- answers to "Import settings..." when the pasted text is wrong
	-- en: This is not a Dynamic Toolgun Screen settings string.
	[ "import.not_ours" ] = "To nie jest ciąg ustawień Dynamicznego ekranu działka narzędziowego.",

	-- en: The settings string is damaged.
	[ "import.damaged" ] = "Ciąg ustawień jest uszkodzony.",

	-- en: Token reference
	[ "menu.tokens.title" ] = "Lista tokenów",

	-- en: Hover a token for what it does, double-click to copy it.
	[ "menu.tokens.help" ] = "Najedź na token, aby zobaczyć, co robi; kliknij dwukrotnie, aby go skopiować.",

	-- en: Token
	[ "menu.tokens.col_token" ] = "Token",

	-- en: Right now
	[ "menu.tokens.col_now" ] = "Teraz",

	-- en: Copied {token}
	[ "menu.tokens.copied" ] = "Skopiowano {token}",

}
