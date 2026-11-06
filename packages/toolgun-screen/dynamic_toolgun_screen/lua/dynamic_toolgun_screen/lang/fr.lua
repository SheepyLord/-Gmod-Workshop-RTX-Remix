--[[
	Dynamic Toolgun Screen - Français (fr)

	Made from lang/en.lua with tools/i18n.py (see TRANSLATING.md). Above each phrase, "-- en:" holds the
	English it translates; "tools/i18n.py check" lists phrases whose English changed since. A phrase
	missing here falls back to English.
]]

return {

	-- name of the language in that language, shown in the language list
	-- en: English
	[ "_name" ] = "Français",

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
	[ "tool.name" ] = "Écran dynamique du pistolet à outils",

	-- en: Customize the tool gun's live screen and track entities on it
	[ "tool.desc" ] = "Personnaliser l'écran en direct du pistolet à outils et y suivre des entités",

	-- en: Track the entity you are aiming at
	[ "tool.left" ] = "Suivre l'entité visée",

	-- en: Switch to the next screen layout
	[ "tool.right" ] = "Passer à la disposition d'écran suivante",

	-- en: Stop tracking
	[ "tool.reload" ] = "Arrêter le suivi",

	-- context menu entry (right click an entity while holding C)
	-- en: Track on tool gun screen
	[ "prop.track" ] = "Suivre sur l'écran du pistolet à outils",

	-- Utilities tab: category and its only entry
	-- en: Dynamic Toolgun Screen
	[ "menu.category" ] = "Écran dynamique du pistolet à outils",

	-- en: Settings
	[ "menu.settings_item" ] = "Paramètres",

	-- status line; {name} is an entity name such as "oildrum001" or a player's name
	-- en: Aiming at **{name}**
	[ "target.entity" ] = "Cible : **{name}**",

	-- en: Aiming at the **sky**
	[ "target.sky" ] = "Cible : **ciel**",

	-- en: World
	[ "target.world" ] = "Monde",

	-- {surface} is a material from the mat.* phrases below
	-- en: World - **{surface}**
	[ "target.world_surface" ] = "Monde - **{surface}**",

	-- en: Nothing in range
	[ "target.nothing" ] = "Rien à portée",

	-- what you aim at, when it is the sky
	-- en: sky
	[ "aim.sky" ] = "ciel",

	-- multi-click tools (weld, rope...): which click comes next
	-- en: Stage {n}
	[ "tool.progress" ] = "Étape {n}",

	-- health of the tracked entity, e.g. "HP 40/100"
	-- en: HP {hp}
	[ "track.hp" ] = "PV {hp}",

	-- en: Noclip
	[ "noclip" ] = "Noclip",

	-- view angles: P = pitch, Y = yaw
	-- en: P {p}  Y {y}
	[ "eye_ang" ] = "Tangage {p}  Lacet {y}",

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
	[ "compass.sw" ] = "SO",

	-- en: W
	[ "compass.w" ] = "O",

	-- en: NW
	[ "compass.nw" ] = "NO",

	-- label of the FPS graph in the Terminal layout
	-- en: {n} fps
	[ "term.fps" ] = "{n} ips",

	-- shown on the screen when it fails to draw
	-- en: Screen error
	[ "error.title" ] = "Erreur d'écran",

	-- en: See the console for details. Change the layout or run dts_reset to recover.
	[ "error.hint" ] = "Détails dans la console. Changez de disposition ou lancez dts_reset pour tout rétablir.",

	-- tabs of the Advanced Toolgun [Hotbar] addon's tool list, for the {atg_tab} token
	-- en: Tools
	[ "atg.tab.tools" ] = "Outils",

	-- en: Wire
	[ "atg.tab.wire" ] = "Wire",

	-- en: Favorites
	[ "atg.tab.favorites" ] = "Favoris",

	-- the device's battery, next to the battery icon and in {battery}: {n} is the charge in percent;
	-- "Plugged in" is shown while the device runs on mains power instead of its battery
	-- en: {n}%
	[ "battery.percent" ] = "{n} %",

	-- en: Plugged in
	[ "battery.plugged" ] = "Sur secteur",

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
	[ "unit.hu" ] = "{v} u",

	-- en: {v} km/h
	[ "unit.kmh" ] = "{v} km/h",

	-- en: {v} mph
	[ "unit.mph" ] = "{v} mi/h",

	-- en: {v} u/s
	[ "unit.ups" ] = "{v} u/s",

	-- en: {v} kg
	[ "unit.kg" ] = "{v} kg",

	-- en: {v} MB
	[ "unit.mb" ] = "{v} Mo",

	-- Durations: {h} hours, {m} minutes, {s} seconds (minutes and seconds come with two digits)
	-- en: {h}h {m}m
	[ "duration.hm" ] = "{h} h {m} min",

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
	[ "date.format" ] = "{wday} {day} {month}",

	-- en: Sun
	[ "date.wday.1" ] = "dim.",

	-- en: Mon
	[ "date.wday.2" ] = "lun.",

	-- en: Tue
	[ "date.wday.3" ] = "mar.",

	-- en: Wed
	[ "date.wday.4" ] = "mer.",

	-- en: Thu
	[ "date.wday.5" ] = "jeu.",

	-- en: Fri
	[ "date.wday.6" ] = "ven.",

	-- en: Sat
	[ "date.wday.7" ] = "sam.",

	-- en: Sunday
	[ "date.wday_full.1" ] = "dimanche",

	-- en: Monday
	[ "date.wday_full.2" ] = "lundi",

	-- en: Tuesday
	[ "date.wday_full.3" ] = "mardi",

	-- en: Wednesday
	[ "date.wday_full.4" ] = "mercredi",

	-- en: Thursday
	[ "date.wday_full.5" ] = "jeudi",

	-- en: Friday
	[ "date.wday_full.6" ] = "vendredi",

	-- en: Saturday
	[ "date.wday_full.7" ] = "samedi",

	-- short month names, used in dates ({month} above and %b): use the form your dates need
	-- en: Jan
	[ "date.month.1" ] = "janv.",

	-- en: Feb
	[ "date.month.2" ] = "févr.",

	-- en: Mar
	[ "date.month.3" ] = "mars",

	-- en: Apr
	[ "date.month.4" ] = "avr.",

	-- en: May
	[ "date.month.5" ] = "mai",

	-- en: Jun
	[ "date.month.6" ] = "juin",

	-- en: Jul
	[ "date.month.7" ] = "juil.",

	-- en: Aug
	[ "date.month.8" ] = "août",

	-- en: Sep
	[ "date.month.9" ] = "sept.",

	-- en: Oct
	[ "date.month.10" ] = "oct.",

	-- en: Nov
	[ "date.month.11" ] = "nov.",

	-- en: Dec
	[ "date.month.12" ] = "déc.",

	-- full month names (%B), usually written right after a day number
	-- en: January
	[ "date.month_full.1" ] = "janvier",

	-- en: February
	[ "date.month_full.2" ] = "février",

	-- en: March
	[ "date.month_full.3" ] = "mars",

	-- en: April
	[ "date.month_full.4" ] = "avril",

	-- en: May
	[ "date.month_full.5" ] = "mai",

	-- en: June
	[ "date.month_full.6" ] = "juin",

	-- en: July
	[ "date.month_full.7" ] = "juillet",

	-- en: August
	[ "date.month_full.8" ] = "août",

	-- en: September
	[ "date.month_full.9" ] = "septembre",

	-- en: October
	[ "date.month_full.10" ] = "octobre",

	-- en: November
	[ "date.month_full.11" ] = "novembre",

	-- en: December
	[ "date.month_full.12" ] = "décembre",

	-- Kinds of surface material (the game's material types), shown as "World - Concrete"
	-- en: Antlion
	[ "mat.antlion" ] = "Fourmi-lion",

	-- en: Bloody flesh
	[ "mat.bloodyflesh" ] = "Chair ensanglantée",

	-- en: Concrete
	[ "mat.concrete" ] = "Béton",

	-- en: Dirt
	[ "mat.dirt" ] = "Terre",

	-- en: Eggshell
	[ "mat.eggshell" ] = "Coquille d'œuf",

	-- en: Flesh
	[ "mat.flesh" ] = "Chair",

	-- en: Grate
	[ "mat.grate" ] = "Grille",

	-- en: Alien flesh
	[ "mat.alienflesh" ] = "Chair extraterrestre",

	-- en: Clip
	[ "mat.clip" ] = "Mur invisible",

	-- en: Snow
	[ "mat.snow" ] = "Neige",

	-- en: Plastic
	[ "mat.plastic" ] = "Plastique",

	-- en: Metal
	[ "mat.metal" ] = "Métal",

	-- en: Sand
	[ "mat.sand" ] = "Sable",

	-- en: Foliage
	[ "mat.foliage" ] = "Feuillage",

	-- en: Computer
	[ "mat.computer" ] = "Électronique",

	-- en: Liquid
	[ "mat.slosh" ] = "Liquide",

	-- en: Tile
	[ "mat.tile" ] = "Carrelage",

	-- en: Grass
	[ "mat.grass" ] = "Herbe",

	-- en: Vent
	[ "mat.vent" ] = "Ventilation",

	-- en: Wood
	[ "mat.wood" ] = "Bois",

	-- en: Generic
	[ "mat.default" ] = "Générique",

	-- en: Glass
	[ "mat.glass" ] = "Verre",

	-- en: Warp shield
	[ "mat.warpshield" ] = "Bouclier de distorsion",

	-- Notifications on the screen
	-- en: Tracking {name}
	[ "notify.tracking" ] = "Suivi : {name}",

	-- en: Stopped tracking
	[ "notify.untracked" ] = "Suivi arrêté",

	-- en: Layout: {name}
	[ "notify.layout" ] = "Disposition : {name}",

	-- en: Theme: {name}
	[ "notify.theme" ] = "Thème : {name}",

	-- title bar: tool category, or the game's name when there is none (keep "Garry's Mod")
	-- en: {tool_category|Garry's Mod}
	[ "tpl.title" ] = "{tool_category|Garry's Mod}",

	-- left link of the Pocket PC screen: the previous tool
	-- en: Back to {tool_prev}
	[ "tpl.nav_back" ] = "Retour à {tool_prev}",

	-- en: Props {props}/{props_max}
	[ "tpl.props" ] = "Objets {props}/{props_max}",

	-- en: {fps} fps  {ping} ms
	[ "tpl.perf" ] = "{fps} ips  {ping} ms",

	-- en: Slope {aim_slope}
	[ "tpl.slope" ] = "Pente {aim_slope}",

	-- en: HP {ent_health}
	[ "tpl.hp" ] = "PV {ent_health}",

	-- en: Owner: {ent_owner}
	[ "tpl.owner" ] = "Propriétaire : {ent_owner}",

	-- HP = health, AP = armor
	-- en: HP {health}  AP {armor}
	[ "tpl.health_armor" ] = "PV {health}  Armure {armor}",

	-- en: {players} players
	[ "tpl.players" ] = "Joueurs : {players}",

	-- Terminal lines: a short upper case label, a tab, then the value
	-- en: TOOL\t**{tool}**
	[ "tpl.term_tool" ] = "OUTIL\t**{tool}**",

	-- en: AIM\t**{aim_what}**
	[ "tpl.term_aim" ] = "CIBLE\t**{aim_what}**",

	-- en: CLASS\t**{ent_class|-}**
	[ "tpl.term_class" ] = "CLASSE\t**{ent_class|-}**",

	-- en: POS\t**{aim_pos}**
	[ "tpl.term_pos" ] = "POS\t**{aim_pos}**",

	-- en: DIST\t**{aim_dist}**  {aim_slope}
	[ "tpl.term_dist" ] = "DIST\t**{aim_dist}**  {aim_slope}",

	-- en: OWNER\t**{ent_owner|-}**
	[ "tpl.term_owner" ] = "PROPRIO\t**{ent_owner|-}**",

	-- en: HP\t**{ent_health|-}**
	[ "tpl.term_hp" ] = "PV\t**{ent_health|-}**",

	-- en: TRACK\t**{track_name|-}** {track_dist}
	[ "tpl.term_track" ] = "SUIVI\t**{track_name|-}** {track_dist}",

	-- en: Pocket PC
	[ "layout.pocketpc.name" ] = "Pocket PC",

	-- en: The original screen rebuilt with live data: clock, status icons, tool history links, big tool name, status line, six readouts and a hint bar.
	[ "layout.pocketpc.desc" ] = "L'écran d'origine reconstruit avec des données en direct : horloge, icônes d'état, liens vers l'historique des outils, grand nom de l'outil, ligne d'état, six indicateurs et une barre d'aide.",

	-- en: Title bar
	[ "layout.pocketpc.title" ] = "Barre de titre",

	-- en: Clock
	[ "layout.pocketpc.clock" ] = "Horloge",

	-- en: Left link
	[ "layout.pocketpc.nav_l" ] = "Lien de gauche",

	-- en: Right link
	[ "layout.pocketpc.nav_r" ] = "Lien de droite",

	-- en: Big text
	[ "layout.pocketpc.hero" ] = "Grand texte",

	-- en: Under the big text
	[ "layout.pocketpc.sub" ] = "Sous le grand texte",

	-- en: Status line
	[ "layout.pocketpc.status" ] = "Ligne d'état",

	-- en: Readout, left 1
	[ "layout.pocketpc.l1" ] = "Indicateur, gauche 1",

	-- en: Readout, left 2
	[ "layout.pocketpc.l2" ] = "Indicateur, gauche 2",

	-- en: Readout, left 3
	[ "layout.pocketpc.l3" ] = "Indicateur, gauche 3",

	-- en: Readout, right 1
	[ "layout.pocketpc.r1" ] = "Indicateur, droite 1",

	-- en: Readout, right 2
	[ "layout.pocketpc.r2" ] = "Indicateur, droite 2",

	-- en: Readout, right 3
	[ "layout.pocketpc.r3" ] = "Indicateur, droite 3",

	-- en: Menu bar
	[ "layout.pocketpc.menu" ] = "Barre de menu",

	-- en: Terminal
	[ "layout.terminal.name" ] = "Terminal",

	-- en: Developer readout: eight lines of labels and values, an FPS graph and a prompt line with the tool hints.
	[ "layout.terminal.desc" ] = "Affichage pour développeurs : huit lignes d'étiquettes et de valeurs, un graphique des ips et une ligne d'invite avec les aides de l'outil.",

	-- en: Header
	[ "layout.terminal.head" ] = "En-tête",

	-- en: Header, right
	[ "layout.terminal.clock" ] = "En-tête, droite",

	-- en: Line 1
	[ "layout.terminal.l1" ] = "Ligne 1",

	-- en: Line 2
	[ "layout.terminal.l2" ] = "Ligne 2",

	-- en: Line 3
	[ "layout.terminal.l3" ] = "Ligne 3",

	-- en: Line 4
	[ "layout.terminal.l4" ] = "Ligne 4",

	-- en: Line 5
	[ "layout.terminal.l5" ] = "Ligne 5",

	-- en: Line 6
	[ "layout.terminal.l6" ] = "Ligne 6",

	-- en: Line 7
	[ "layout.terminal.l7" ] = "Ligne 7",

	-- en: Line 8
	[ "layout.terminal.l8" ] = "Ligne 8",

	-- en: Prompt line
	[ "layout.terminal.foot" ] = "Ligne d'invite",

	-- en: Minimal
	[ "layout.minimal.name" ] = "Minimal",

	-- en: Large, glanceable text: clock, compass, the tool name sized to fit, what you aim at and two corner values.
	[ "layout.minimal.desc" ] = "Du grand texte lisible d'un coup d'œil : horloge, boussole, nom de l'outil ajusté à la place, ce que vous visez et deux valeurs dans les coins.",

	-- en: Top left
	[ "layout.minimal.top_l" ] = "En haut à gauche",

	-- en: Top right
	[ "layout.minimal.top_r" ] = "En haut à droite",

	-- en: Big text
	[ "layout.minimal.hero" ] = "Grand texte",

	-- en: Under the big text
	[ "layout.minimal.sub" ] = "Sous le grand texte",

	-- en: Bottom left
	[ "layout.minimal.foot_l" ] = "En bas à gauche",

	-- en: Bottom right
	[ "layout.minimal.foot_r" ] = "En bas à droite",

	-- en: Pocket PC (original)
	[ "theme.winmobile" ] = "Pocket PC (d'origine)",

	-- en: Graphite
	[ "theme.graphite" ] = "Graphite",

	-- en: Green phosphor
	[ "theme.phosphor" ] = "Phosphore vert",

	-- en: Amber CRT
	[ "theme.amber" ] = "Cathodique ambre",

	-- en: Sakura
	[ "theme.sakura" ] = "Sakura",

	-- en: Sandbox blue
	[ "theme.sandbox" ] = "Bleu Sandbox",

	-- parts of the screen whose colour can be changed
	-- en: Title bar
	[ "color.bar" ] = "Barre de titre",

	-- en: Links and highlights
	[ "color.accent" ] = "Liens et mises en évidence",

	-- en: Big text
	[ "color.hero" ] = "Grand texte",

	-- en: Status line
	[ "color.strip" ] = "Ligne d'état",

	-- en: Readout panel
	[ "color.panel" ] = "Panneau des indicateurs",

	-- en: Menu bar
	[ "color.menu" ] = "Barre de menu",

	-- en: Terminal text
	[ "color.term" ] = "Texte du terminal",

	-- en: Text
	[ "category.text" ] = "Texte",

	-- en: Time
	[ "category.time" ] = "Temps",

	-- en: Tool
	[ "category.tool" ] = "Outil",

	-- en: Aim
	[ "category.aim" ] = "Visée",

	-- en: Aimed entity
	[ "category.entity" ] = "Entité visée",

	-- en: Tracked entity
	[ "category.tracked" ] = "Entité suivie",

	-- en: You
	[ "category.player" ] = "Vous",

	-- en: Game
	[ "category.game" ] = "Jeu",

	-- the Advanced Toolgun [Hotbar] addon; keep its name as it is
	-- en: Advanced Toolgun
	[ "category.atg" ] = "Advanced Toolgun",

	-- en: A line in your language from the language files, e.g. {tr:nav_back} or {tr:props}.
	[ "token.tr" ] = "Une ligne dans votre langue, tirée des fichiers de langue, par ex. {tr:nav_back} ou {tr:props}.",

	-- en: Local time, formatted by the clock settings. {time:%H:%M:%S} takes an os.date format.
	[ "token.time" ] = "Heure locale, au format des réglages de l'horloge. {time:%H:%M:%S} accepte un format os.date.",

	-- en: Today's date. {date:%Y-%m-%d} takes an os.date format.
	[ "token.date" ] = "Date du jour. {date:%Y-%m-%d} accepte un format os.date.",

	-- en: How long you have been in this game.
	[ "token.session" ] = "Depuis combien de temps vous êtes dans cette partie.",

	-- en: How long the map has been running.
	[ "token.map_time" ] = "Depuis combien de temps la carte tourne.",

	-- en: Name of the selected tool.
	[ "token.tool" ] = "Nom de l'outil sélectionné.",

	-- en: Internal name of the selected tool.
	[ "token.tool_id" ] = "Nom interne de l'outil sélectionné.",

	-- en: Description of the selected tool.
	[ "token.tool_desc" ] = "Description de l'outil sélectionné.",

	-- en: Tool menu category of the selected tool.
	[ "token.tool_category" ] = "Catégorie de l'outil sélectionné dans le menu des outils.",

	-- en: Stage of the selected tool (0 = nothing selected yet).
	[ "token.tool_stage" ] = "Étape de l'outil sélectionné (0 = rien n'est encore sélectionné).",

	-- en: The stage while a multi-click tool is in progress, otherwise empty.
	[ "token.tool_progress" ] = "L'étape pendant l'utilisation d'un outil à plusieurs clics, sinon vide.",

	-- en: The tool you used before this one (dts_tool_back switches to it).
	[ "token.tool_prev" ] = "L'outil utilisé avant celui-ci (dts_tool_back y revient).",

	-- en: The next tool in the same menu category (dts_tool_next switches to it).
	[ "token.tool_next" ] = "L'outil suivant de la même catégorie du menu (dts_tool_next y passe).",

	-- en: Successful tool gun shots this session.
	[ "token.tool_uses" ] = "Tirs réussis du pistolet à outils pendant cette session.",

	-- en: A setting of the selected tool, e.g. {tool_cvar:forcelimit} reads weld_forcelimit.
	[ "token.tool_cvar" ] = "Un réglage de l'outil sélectionné, par ex. {tool_cvar:forcelimit} lit weld_forcelimit.",

	-- en: All settings of the selected tool as name=value pairs.
	[ "token.tool_settings" ] = "Tous les réglages de l'outil sélectionné, sous forme de paires nom=valeur.",

	-- en: The current stage's instructions with mouse and key icons.
	[ "token.hints" ] = "Les instructions de l'étape en cours, avec les icônes de la souris et des touches.",

	-- en: What left click does right now.
	[ "token.hint_left" ] = "Ce que fait le clic gauche en ce moment.",

	-- en: What right click does right now.
	[ "token.hint_right" ] = "Ce que fait le clic droit en ce moment.",

	-- en: What reload does right now.
	[ "token.hint_reload" ] = "Ce que fait la touche de rechargement en ce moment.",

	-- en: What you are aiming at, with the name highlighted.
	[ "token.target" ] = "Ce que vous visez, avec le nom mis en évidence.",

	-- en: Entity name, or the surface material when aiming at the world.
	[ "token.aim_what" ] = "Nom de l'entité, ou matériau de la surface quand vous visez le monde.",

	-- en: Position you are aiming at.
	[ "token.aim_pos" ] = "Position visée.",

	-- en: X of the aim position.
	[ "token.aim_x" ] = "X de la position visée.",

	-- en: Y of the aim position.
	[ "token.aim_y" ] = "Y de la position visée.",

	-- en: Z of the aim position.
	[ "token.aim_z" ] = "Z de la position visée.",

	-- en: Distance to the aim position.
	[ "token.aim_dist" ] = "Distance jusqu'à la position visée.",

	-- en: Surface normal at the aim position.
	[ "token.aim_normal" ] = "Normale de la surface à la position visée.",

	-- en: Steepness of the surface (0 = flat floor, 90 = wall).
	[ "token.aim_slope" ] = "Inclinaison de la surface (0 = sol plat, 90 = mur).",

	-- en: Kind of surface material (metal, wood, concrete...).
	[ "token.aim_surface" ] = "Type de matériau de la surface (métal, bois, béton...).",

	-- en: Surface property as the engine names it (metal box, wood crate...).
	[ "token.aim_surfaceprop" ] = "Propriété de surface telle que le moteur la nomme (metal box, wood crate...).",

	-- en: World texture you are aiming at.
	[ "token.aim_texture" ] = "Texture du monde que vous visez.",

	-- en: Friendly name of the aimed entity.
	[ "token.ent_name" ] = "Nom lisible de l'entité visée.",

	-- en: Class of the aimed entity.
	[ "token.ent_class" ] = "Classe de l'entité visée.",

	-- en: Model file name of the aimed entity.
	[ "token.ent_model" ] = "Nom du fichier de modèle de l'entité visée.",

	-- en: Full model path of the aimed entity.
	[ "token.ent_model_path" ] = "Chemin complet du modèle de l'entité visée.",

	-- en: Entity index.
	[ "token.ent_index" ] = "Index de l'entité.",

	-- en: Health of the aimed entity (players, NPCs, breakable props).
	[ "token.ent_health" ] = "Santé de l'entité visée (joueurs, PNJ, objets destructibles).",

	-- en: Owner of the aimed entity (in multiplayer this needs a CPPI prop protection addon).
	[ "token.ent_owner" ] = "Propriétaire de l'entité visée (en multijoueur, il faut un addon de protection des objets compatible CPPI).",

	-- en: Material of the aimed entity.
	[ "token.ent_material" ] = "Matériau de l'entité visée.",

	-- en: Colour of the aimed entity.
	[ "token.ent_color" ] = "Couleur de l'entité visée.",

	-- en: Skin of the aimed entity.
	[ "token.ent_skin" ] = "Apparence (skin) de l'entité visée.",

	-- en: Speed of the aimed entity.
	[ "token.ent_speed" ] = "Vitesse de l'entité visée.",

	-- en: Position of the aimed entity.
	[ "token.ent_pos" ] = "Position de l'entité visée.",

	-- en: Angles of the aimed entity.
	[ "token.ent_ang" ] = "Angles de l'entité visée.",

	-- en: Mass of the aimed entity, when your game knows its physics.
	[ "token.ent_mass" ] = "Masse de l'entité visée, quand votre jeu connaît sa physique.",

	-- en: Tracked entity summary: name, distance, speed, health.
	[ "token.track" ] = "Résumé de l'entité suivie : nom, distance, vitesse, santé.",

	-- en: Name of the tracked entity.
	[ "token.track_name" ] = "Nom de l'entité suivie.",

	-- en: Class of the tracked entity.
	[ "token.track_class" ] = "Classe de l'entité suivie.",

	-- en: Your distance to the tracked entity.
	[ "token.track_dist" ] = "Votre distance jusqu'à l'entité suivie.",

	-- en: Speed of the tracked entity.
	[ "token.track_speed" ] = "Vitesse de l'entité suivie.",

	-- en: Health of the tracked entity.
	[ "token.track_health" ] = "Santé de l'entité suivie.",

	-- en: Position of the tracked entity.
	[ "token.track_pos" ] = "Position de l'entité suivie.",

	-- en: Your name.
	[ "token.player" ] = "Votre pseudo.",

	-- en: Your health.
	[ "token.health" ] = "Votre santé.",

	-- en: Your armor.
	[ "token.armor" ] = "Votre armure.",

	-- en: Your speed.
	[ "token.speed" ] = "Votre vitesse.",

	-- en: Your position.
	[ "token.pos" ] = "Votre position.",

	-- en: Your view pitch and yaw.
	[ "token.eye_ang" ] = "Tangage et lacet de votre regard.",

	-- en: Compass heading (north is +Y on the map).
	[ "token.heading" ] = "Cap de la boussole (le nord est +Y sur la carte).",

	-- en: Shows a word while you are noclipping, otherwise empty.
	[ "token.noclip" ] = "Affiche un mot quand le noclip est actif, sinon vide.",

	-- en: Frames per second (smoothed).
	[ "token.fps" ] = "Images par seconde (lissées).",

	-- en: Your ping in milliseconds.
	[ "token.ping" ] = "Votre latence en millisecondes.",

	-- en: Your device's battery charge while it runs on battery, or \"Plugged in\".
	[ "token.battery" ] = "La charge de la batterie de votre appareil quand il fonctionne sur batterie, sinon « Sur secteur ».",

	-- en: Current map.
	[ "token.map" ] = "Carte actuelle.",

	-- en: Players on the server and its player limit.
	[ "token.players" ] = "Joueurs sur le serveur et limite de joueurs.",

	-- en: Server name.
	[ "token.server" ] = "Nom du serveur.",

	-- en: Active gamemode.
	[ "token.gamemode" ] = "Mode de jeu actif.",

	-- en: Server tick rate.
	[ "token.tickrate" ] = "Tickrate du serveur.",

	-- en: Memory used by Lua in your game.
	[ "token.lua_mem" ] = "Mémoire utilisée par Lua dans votre jeu.",

	-- en: Entities known to your game.
	[ "token.entities" ] = "Entités connues de votre jeu.",

	-- en: Props you have spawned.
	[ "token.props" ] = "Objets que vous avez fait apparaître.",

	-- en: Your prop limit.
	[ "token.props_max" ] = "Votre limite d'objets.",

	-- en: Spawn count and limit of a type, e.g. {count:ragdolls} or {count:thrusters}.
	[ "token.count" ] = "Nombre et limite d'un type, par ex. {count:ragdolls} ou {count:thrusters}.",

	-- en: Value of any console variable, e.g. {cvar:sv_gravity}.
	[ "token.cvar" ] = "Valeur de n'importe quelle variable de console, par ex. {cvar:sv_gravity}.",

	-- en: Advanced Toolgun [Hotbar]: its open tab (Tools, Wire or Favorites).
	[ "token.atg_tab" ] = "Advanced Toolgun [Hotbar] : son onglet ouvert (Outils, Wire ou Favoris).",

	-- en: Advanced Toolgun [Hotbar]: the section of its list the selection is in.
	[ "token.atg_section" ] = "Advanced Toolgun [Hotbar] : la section de sa liste où se trouve la sélection.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel up.
	[ "token.atg_prev" ] = "Advanced Toolgun [Hotbar] : l'outil que choisit sa sélection rapide avec la molette vers le haut.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel down.
	[ "token.atg_next" ] = "Advanced Toolgun [Hotbar] : l'outil que choisit sa sélection rapide avec la molette vers le bas.",

	-- en: Turns the tool gun's mini screen into a live display. Changes apply instantly; the preview shows what the screen draws right now.
	[ "menu.intro" ] = "Transforme le petit écran du pistolet à outils en affichage en direct. Les changements s'appliquent immédiatement ; l'aperçu montre ce que l'écran affiche en ce moment.",

	-- en: Dynamic screen is off
	[ "menu.preview_off" ] = "L'écran dynamique est désactivé",

	-- en: Enable the dynamic screen
	[ "menu.enable" ] = "Activer l'écran dynamique",

	-- en: Language
	[ "menu.language" ] = "Langue",

	-- first entry of the language list; {name} is the game's language, e.g. "English"
	-- en: Automatic: {name}
	[ "menu.language.auto" ] = "Automatique : {name}",

	-- en: Inspect: read the screen up close
	[ "menu.inspect.title" ] = "Examiner : lire l'écran de près",

	-- en: Hold a key while holding the tool gun to raise its screen to your eyes.
	[ "menu.inspect.help" ] = "Maintenez une touche en tenant le pistolet à outils pour approcher son écran de vos yeux.",

	-- en: Inspect key
	[ "menu.inspect.key" ] = "Touche d'examen",

	-- en: Screen size while inspecting
	[ "menu.inspect.size" ] = "Taille de l'écran pendant l'examen",

	-- en: Or use the console: bind <key> +dts_inspect (hold) or dts_inspect_toggle.
	[ "menu.inspect.console" ] = "Ou par la console : bind <touche> +dts_inspect (maintenir) ou dts_inspect_toggle.",

	-- the tool gun model has a paper note glued on, which overlaps the screen's top right corner
	-- en: Screen in front of the paper note
	[ "menu.inspect.on_top" ] = "Écran devant la note en papier",

	-- en: While inspecting, the whole screen stays readable. Untick to let the paper note glued to the tool gun cover the top right corner of the screen, as on the model.
	[ "menu.inspect.on_top_help" ] = "Pendant l'examen, tout l'écran reste lisible. Décochez cette case pour que la note en papier collée sur le pistolet à outils cache le coin supérieur droit de l'écran, comme sur le modèle.",

	-- en: Layout and look
	[ "menu.look.title" ] = "Disposition et apparence",

	-- en: Layout
	[ "menu.look.layout" ] = "Disposition",

	-- en: Theme
	[ "menu.look.theme" ] = "Thème",

	-- en: Background
	[ "menu.look.background" ] = "Arrière-plan",

	-- en: Automatic (layout's choice)
	[ "menu.bg.auto" ] = "Automatique (choix de la disposition)",

	-- the whole original screen picture without its text
	-- en: Original screen
	[ "menu.bg.original" ] = "Écran d'origine",

	-- only the blurred photo from the original picture, filling the screen
	-- en: Original photo
	[ "menu.bg.art" ] = "Photo d'origine",

	-- en: Theme gradient
	[ "menu.bg.gradient" ] = "Dégradé du thème",

	-- en: Live camera: zoom
	[ "menu.bg.camera" ] = "Caméra en direct : zoom",

	-- en: Live camera: rear view
	[ "menu.bg.rear" ] = "Caméra en direct : vue arrière",

	-- en: Custom image
	[ "menu.bg.image" ] = "Image personnalisée",

	-- en: Black
	[ "menu.bg.black" ] = "Noir",

	-- en: Custom image
	[ "menu.look.image" ] = "Image personnalisée",

	-- en: A material path, or an image in garrysmod/data written as ../data/name.png
	[ "menu.look.image_help" ] = "Un chemin de matériau, ou une image de garrysmod/data écrite ../data/nom.png",

	-- en: Darken background
	[ "menu.look.dim" ] = "Assombrir l'arrière-plan",

	-- en: Camera field of view
	[ "menu.look.cam_fov" ] = "Champ de vision de la caméra",

	-- en: Camera updates per second
	[ "menu.look.cam_fps" ] = "Mises à jour de la caméra par seconde",

	-- en: Text font
	[ "menu.look.font" ] = "Police du texte",

	-- en: Big text font
	[ "menu.look.font_hero" ] = "Police du grand texte",

	-- en: Terminal font
	[ "menu.look.font_mono" ] = "Police du terminal",

	-- first entry of the font lists; {font} is the font your language uses
	-- en: Automatic ({font})
	[ "menu.font.auto" ] = "Automatique ({font})",

	-- en: Colours
	[ "menu.colors.title" ] = "Couleurs",

	-- en: Override single colours of the theme. Click a swatch to change it.
	[ "menu.colors.help" ] = "Remplacez certaines couleurs du thème. Cliquez sur un échantillon pour le modifier.",

	-- written on a colour swatch that still uses the theme's colour
	-- en: theme
	[ "menu.colors.theme_tag" ] = "thème",

	-- en: Click to pick a colour
	[ "menu.colors.pick" ] = "Cliquer pour choisir une couleur",

	-- en: Use the theme's colours everywhere
	[ "menu.colors.reset_all" ] = "Utiliser partout les couleurs du thème",

	-- en: Screen colour: {name}
	[ "menu.colors.picker_title" ] = "Couleur de l'écran : {name}",

	-- en: Use the theme's colour
	[ "menu.colors.use_theme" ] = "Utiliser la couleur du thème",

	-- en: Big text
	[ "menu.hero.title" ] = "Grand texte",

	-- en: Behaviour
	[ "menu.hero.mode" ] = "Comportement",

	-- en: Always scroll (original)
	[ "menu.hero.scroll" ] = "Toujours défiler (d'origine)",

	-- en: Scroll only when too long
	[ "menu.hero.auto" ] = "Défiler seulement si trop long",

	-- en: Shrink to fit
	[ "menu.hero.fit" ] = "Réduire pour tenir",

	-- en: Scroll speed
	[ "menu.hero.speed" ] = "Vitesse de défilement",

	-- en: Upper case tool names
	[ "menu.hero.upper" ] = "Noms d'outils en majuscules",

	-- en: Screen content
	[ "menu.content.title" ] = "Contenu de l'écran",

	-- keep {tokens}, **stars**, {token|fallback} and {tr:...} as they are: they show the syntax
	-- en: Every line of the {layout} layout is a template. Type text and {tokens}; **stars** highlight text, {token|fallback} gives a default, and a line whose tokens are all empty hides itself. {tr:...} writes a line in your language. See the token reference below.
	[ "menu.content.help" ] = "Chaque ligne de la disposition « {layout} » est un modèle. Tapez du texte et des {tokens} ; les **étoiles** mettent du texte en évidence, {token|fallback} donne une valeur par défaut, et une ligne dont tous les jetons sont vides se masque. {tr:...} écrit une ligne dans votre langue. Voir la liste des jetons ci-dessous.",

	-- en: Pick a ready-made line
	[ "menu.content.presets_tip" ] = "Choisir une ligne toute faite",

	-- en: Back to the default: {value}
	[ "menu.content.reset_tip" ] = "Revenir à la valeur par défaut : {value}",

	-- en: (empty)
	[ "menu.content.empty" ] = "(vide)",

	-- shown in an empty line's text box
	-- en: (hidden)
	[ "menu.content.placeholder" ] = "(masquée)",

	-- under each line: what it shows right now
	-- en: = {text}
	[ "menu.content.now" ] = "= {text}",

	-- en: (hidden right now)
	[ "menu.content.hidden_now" ] = "(masquée en ce moment)",

	-- en: Reset these lines to the layout's defaults
	[ "menu.content.reset_all" ] = "Rétablir les lignes par défaut de la disposition",

	-- ready-made lines in the list next to each line
	-- en: Tool name
	[ "menu.preset.tool" ] = "Nom de l'outil",

	-- en: Tool category
	[ "menu.preset.tool_category" ] = "Catégorie de l'outil",

	-- en: Tool instructions
	[ "menu.preset.hints" ] = "Instructions de l'outil",

	-- en: Previous tool
	[ "menu.preset.prev_tool" ] = "Outil précédent",

	-- en: Next tool
	[ "menu.preset.next_tool" ] = "Outil suivant",

	-- en: Tool progress
	[ "menu.preset.progress" ] = "Progression de l'outil",

	-- en: Tool settings
	[ "menu.preset.tool_settings" ] = "Réglages de l'outil",

	-- en: What you aim at
	[ "menu.preset.target" ] = "Ce que vous visez",

	-- en: Aim position
	[ "menu.preset.aim_pos" ] = "Position visée",

	-- en: Aim distance
	[ "menu.preset.aim_dist" ] = "Distance visée",

	-- en: Entity or surface
	[ "menu.preset.aim_what" ] = "Entité ou surface",

	-- en: Surface slope
	[ "menu.preset.slope" ] = "Pente de la surface",

	-- en: Entity class
	[ "menu.preset.ent_class" ] = "Classe de l'entité",

	-- en: Entity model
	[ "menu.preset.ent_model" ] = "Modèle de l'entité",

	-- en: Entity health
	[ "menu.preset.ent_health" ] = "Santé de l'entité",

	-- en: Entity owner
	[ "menu.preset.ent_owner" ] = "Propriétaire de l'entité",

	-- en: Entity speed
	[ "menu.preset.ent_speed" ] = "Vitesse de l'entité",

	-- en: Tracked entity
	[ "menu.preset.track" ] = "Entité suivie",

	-- en: Clock
	[ "menu.preset.clock" ] = "Horloge",

	-- en: Clock with seconds
	[ "menu.preset.clock_seconds" ] = "Horloge avec secondes",

	-- en: Date
	[ "menu.preset.date" ] = "Date",

	-- en: Time in game
	[ "menu.preset.session" ] = "Temps de jeu",

	-- en: Your speed
	[ "menu.preset.speed" ] = "Votre vitesse",

	-- en: Your position
	[ "menu.preset.pos" ] = "Votre position",

	-- en: Compass
	[ "menu.preset.heading" ] = "Boussole",

	-- en: Health and armor
	[ "menu.preset.health_armor" ] = "Santé et armure",

	-- en: FPS and ping
	[ "menu.preset.perf" ] = "Ips et latence",

	-- en: Prop count
	[ "menu.preset.props" ] = "Nombre d'objets",

	-- en: Map
	[ "menu.preset.map" ] = "Carte",

	-- en: Players
	[ "menu.preset.players" ] = "Joueurs",

	-- en: Empty (hide the line)
	[ "menu.preset.empty" ] = "Vide (masquer la ligne)",

	-- en: Clock and units
	[ "menu.clock.title" ] = "Horloge et unités",

	-- en: Clock
	[ "menu.clock.style" ] = "Horloge",

	-- {language} is the name of the active language
	-- en: As usual in {language}
	[ "menu.clock.auto" ] = "Selon la langue ({language})",

	-- en: 12 hour
	[ "menu.clock.12h" ] = "12 heures",

	-- en: 24 hour
	[ "menu.clock.24h" ] = "24 heures",

	-- en: Show seconds
	[ "menu.clock.seconds" ] = "Afficher les secondes",

	-- en: Show AM / PM (12 hour clock)
	[ "menu.clock.ampm" ] = "Afficher AM / PM (horloge de 12 heures)",

	-- en: Blink the colon
	[ "menu.clock.blink" ] = "Faire clignoter les deux-points",

	-- en: Units
	[ "menu.units.label" ] = "Unités",

	-- en: Metric (m, km/h)
	[ "menu.units.m" ] = "Métriques (m, km/h)",

	-- en: Imperial (ft, mph)
	[ "menu.units.ft" ] = "Impériales (ft, mi/h)",

	-- en: Hammer units
	[ "menu.units.hu" ] = "Unités Hammer",

	-- en: Distance decimals
	[ "menu.units.decimals" ] = "Décimales des distances",

	-- en: Icons and effects
	[ "menu.fx.title" ] = "Icônes et effets",

	-- en: Speaker icon (volume, voice chat)
	[ "menu.fx.speaker" ] = "Icône de haut-parleur (volume, chat vocal)",

	-- en: Signal icon (connection)
	[ "menu.fx.signal" ] = "Icône de signal (connexion)",

	-- en: Battery icon (your device's battery)
	[ "menu.fx.battery" ] = "Icône de batterie (la batterie de votre appareil)",

	-- en: Boot animation when taking out the tool gun
	[ "menu.fx.boot" ] = "Animation de démarrage en sortant le pistolet à outils",

	-- en: Flash when the tool gun fires
	[ "menu.fx.flash" ] = "Flash quand le pistolet à outils tire",

	-- en: Show game notifications on the screen
	[ "menu.fx.notify" ] = "Afficher les notifications du jeu sur l'écran",

	-- en: Notification time
	[ "menu.fx.notify_time" ] = "Durée des notifications",

	-- en: Scanlines
	[ "menu.fx.scanlines" ] = "Lignes de balayage",

	-- en: Darker edges
	[ "menu.fx.vignette" ] = "Bords assombris",

	-- en: Backlight
	[ "menu.fx.backlight" ] = "Rétroéclairage",

	-- en: HUD mirror
	[ "menu.mirror.title" ] = "Miroir sur le HUD",

	-- en: Shows the screen on your HUD while you hold the tool gun, for reading the small print.
	[ "menu.mirror.help" ] = "Affiche aussi l'écran sur votre HUD quand vous tenez le pistolet à outils, pour lire les petits caractères.",

	-- en: Show the screen on the HUD
	[ "menu.mirror.enable" ] = "Afficher l'écran sur le HUD",

	-- en: Corner
	[ "menu.mirror.corner" ] = "Coin",

	-- en: Top right
	[ "menu.corner.tr" ] = "En haut à droite",

	-- en: Bottom right
	[ "menu.corner.br" ] = "En bas à droite",

	-- en: Bottom left
	[ "menu.corner.bl" ] = "En bas à gauche",

	-- en: Top left
	[ "menu.corner.tl" ] = "En haut à gauche",

	-- en: Size
	[ "menu.mirror.size" ] = "Taille",

	-- en: Opacity
	[ "menu.mirror.alpha" ] = "Opacité",

	-- en: Advanced
	[ "menu.adv.title" ] = "Avancé",

	-- en: Keep the own screens of tools that draw one
	[ "menu.adv.respect" ] = "Garder l'écran propre des outils qui en dessinent un",

	-- en: e.g. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod tools
	[ "menu.adv.respect_help" ] = "par ex. Easy Entity Inspector, Ragdoll Puppeteer, outils Wiremod",

	-- en: Live value updates per second
	[ "menu.adv.refresh" ] = "Mises à jour des valeurs par seconde",

	-- en: Screen redraws per second (0 = every frame)
	[ "menu.adv.fps" ] = "Rafraîchissements de l'écran par seconde (0 = chaque image)",

	-- en: Resolution
	[ "menu.adv.resolution" ] = "Résolution",

	-- en: 256 x 256 (original)
	[ "menu.res.256" ] = "256 x 256 (d'origine)",

	-- en: 512 x 512 (sharper, for 1440p and up)
	[ "menu.res.512" ] = "512 x 512 (plus net, pour 1440p et plus)",

	-- keep the commands as they are
	-- en: Key binds (bind <key> <command>):\n  dts_tool_back  -  previous tool\n  dts_tool_next / dts_tool_prev  -  cycle the category\n  dts_layout_next, dts_theme_next  -  cycle layouts, themes\n  dts_track / dts_untrack  -  follow an entity
	[ "menu.adv.binds" ] = "Raccourcis (bind <touche> <commande>) :\n  dts_tool_back  -  outil précédent\n  dts_tool_next / dts_tool_prev  -  parcourir la catégorie\n  dts_layout_next, dts_theme_next  -  changer de disposition, de thème\n  dts_track / dts_untrack  -  suivre une entité",

	-- en: Copy my settings to the clipboard
	[ "menu.adv.copy" ] = "Copier mes réglages dans le presse-papiers",

	-- en: Screen settings copied to the clipboard
	[ "menu.adv.copied" ] = "Réglages de l'écran copiés dans le presse-papiers",

	-- en: Import settings...
	[ "menu.adv.import" ] = "Importer des réglages...",

	-- en: Import screen settings
	[ "menu.adv.import_title" ] = "Importer des réglages d'écran",

	-- en: Paste a DTS1:... settings string
	[ "menu.adv.import_prompt" ] = "Collez une chaîne de réglages DTS1:...",

	-- en: Import
	[ "menu.adv.import_ok" ] = "Importer",

	-- en: Imported screen settings ({n} changed)
	[ "menu.adv.imported" ] = "Réglages de l'écran importés ({n} modifiés)",

	-- en: Reset everything to defaults
	[ "menu.adv.reset" ] = "Tout rétablir par défaut",

	-- en: Reset
	[ "menu.adv.reset_title" ] = "Réinitialiser",

	-- en: Reset every Dynamic Toolgun Screen setting?
	[ "menu.adv.reset_question" ] = "Réinitialiser tous les réglages de l'Écran dynamique du pistolet à outils ?",

	-- en: Reset
	[ "menu.adv.reset_yes" ] = "Réinitialiser",

	-- en: Cancel
	[ "menu.adv.cancel" ] = "Annuler",

	-- en: Another addon replaced the tool gun screen ({file}). Use the button below to take over.
	[ "menu.adv.diag_conflict" ] = "Un autre addon a remplacé l'écran du pistolet à outils ({file}). Utilisez le bouton ci-dessous pour le reprendre.",

	-- en: v{version} installed. Each redraw takes {ms} ms.
	[ "menu.adv.diag_ok" ] = "v{version} installée. Chaque rafraîchissement prend {ms} ms.",

	-- en: Last error: {error}
	[ "menu.adv.diag_error" ] = "Dernière erreur : {error}",

	-- en: Waiting for the tool gun to load...
	[ "menu.adv.diag_wait" ] = "En attente du chargement du pistolet à outils...",

	-- en: Take over the tool gun screen
	[ "menu.adv.takeover" ] = "Reprendre l'écran du pistolet à outils",

	-- en: Only needed if another addon replaced the tool gun's screen after this one
	[ "menu.adv.takeover_tip" ] = "Utile seulement si un autre addon a remplacé l'écran du pistolet à outils après celui-ci",

	-- en: Dynamic Toolgun Screen installed
	[ "menu.adv.takeover_done" ] = "Écran dynamique du pistolet à outils installé",

	-- answers to "Import settings..." when the pasted text is wrong
	-- en: This is not a Dynamic Toolgun Screen settings string.
	[ "import.not_ours" ] = "Ce n'est pas une chaîne de réglages de l'Écran dynamique du pistolet à outils.",

	-- en: The settings string is damaged.
	[ "import.damaged" ] = "La chaîne de réglages est endommagée.",

	-- en: Token reference
	[ "menu.tokens.title" ] = "Liste des jetons",

	-- en: Hover a token for what it does, double-click to copy it.
	[ "menu.tokens.help" ] = "Survolez un jeton pour voir ce qu'il fait, double-cliquez pour le copier.",

	-- en: Token
	[ "menu.tokens.col_token" ] = "Jeton",

	-- en: Right now
	[ "menu.tokens.col_now" ] = "En ce moment",

	-- en: Copied {token}
	[ "menu.tokens.copied" ] = "{token} copié",

}
