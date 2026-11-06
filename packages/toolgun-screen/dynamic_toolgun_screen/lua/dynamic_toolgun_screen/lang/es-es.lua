--[[
	Dynamic Toolgun Screen - Español (es-es)

	Made from lang/en.lua with tools/i18n.py (see TRANSLATING.md). Above each phrase, "-- en:" holds the
	English it translates; "tools/i18n.py check" lists phrases whose English changed since. A phrase
	missing here falls back to English.
]]

return {

	-- name of the language in that language, shown in the language list
	-- en: English
	[ "_name" ] = "Español",

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
	[ "tool.name" ] = "Pantalla dinámica de la pistoherramienta",

	-- en: Customize the tool gun's live screen and track entities on it
	[ "tool.desc" ] = "Personaliza la pantalla en vivo de la pistoherramienta y sigue entidades en ella",

	-- en: Track the entity you are aiming at
	[ "tool.left" ] = "Sigue la entidad a la que apuntas",

	-- en: Switch to the next screen layout
	[ "tool.right" ] = "Cambia al siguiente diseño de pantalla",

	-- en: Stop tracking
	[ "tool.reload" ] = "Deja de seguir",

	-- context menu entry (right click an entity while holding C)
	-- en: Track on tool gun screen
	[ "prop.track" ] = "Seguir en la pantalla de la pistoherramienta",

	-- Utilities tab: category and its only entry
	-- en: Dynamic Toolgun Screen
	[ "menu.category" ] = "Pantalla dinámica de la pistoherramienta",

	-- en: Settings
	[ "menu.settings_item" ] = "Ajustes",

	-- status line; {name} is an entity name such as "oildrum001" or a player's name
	-- en: Aiming at **{name}**
	[ "target.entity" ] = "Apuntando a **{name}**",

	-- en: Aiming at the **sky**
	[ "target.sky" ] = "Apuntando al **cielo**",

	-- en: World
	[ "target.world" ] = "Mundo",

	-- {surface} is a material from the mat.* phrases below
	-- en: World - **{surface}**
	[ "target.world_surface" ] = "Mundo - **{surface}**",

	-- en: Nothing in range
	[ "target.nothing" ] = "Nada al alcance",

	-- what you aim at, when it is the sky
	-- en: sky
	[ "aim.sky" ] = "cielo",

	-- multi-click tools (weld, rope...): which click comes next
	-- en: Stage {n}
	[ "tool.progress" ] = "Paso {n}",

	-- health of the tracked entity, e.g. "HP 40/100"
	-- en: HP {hp}
	[ "track.hp" ] = "Vida {hp}",

	-- en: Noclip
	[ "noclip" ] = "Noclip",

	-- view angles: P = pitch, Y = yaw
	-- en: P {p}  Y {y}
	[ "eye_ang" ] = "Cabeceo {p}  Guiñada {y}",

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
	[ "term.fps" ] = "{n} FPS",

	-- shown on the screen when it fails to draw
	-- en: Screen error
	[ "error.title" ] = "Error de pantalla",

	-- en: See the console for details. Change the layout or run dts_reset to recover.
	[ "error.hint" ] = "Consulta la consola para ver los detalles. Cambia el diseño o ejecuta dts_reset para recuperarla.",

	-- tabs of the Advanced Toolgun [Hotbar] addon's tool list, for the {atg_tab} token
	-- en: Tools
	[ "atg.tab.tools" ] = "Herramientas",

	-- en: Wire
	[ "atg.tab.wire" ] = "Wire",

	-- en: Favorites
	[ "atg.tab.favorites" ] = "Favoritos",

	-- the device's battery, next to the battery icon and in {battery}: {n} is the charge in percent;
	-- "Plugged in" is shown while the device runs on mains power instead of its battery
	-- en: {n}%
	[ "battery.percent" ] = "{n} %",

	-- en: Plugged in
	[ "battery.plugged" ] = "Enchufado",

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
	[ "unit.mph" ] = "{v} mph",

	-- en: {v} u/s
	[ "unit.ups" ] = "{v} u/s",

	-- en: {v} kg
	[ "unit.kg" ] = "{v} kg",

	-- en: {v} MB
	[ "unit.mb" ] = "{v} MB",

	-- Durations: {h} hours, {m} minutes, {s} seconds (minutes and seconds come with two digits)
	-- en: {h}h {m}m
	[ "duration.hm" ] = "{h} h {m} min",

	-- en: {m}m {s}s
	[ "duration.ms" ] = "{m} min {s} s",

	-- en: {s}s
	[ "duration.s" ] = "{s} s",

	-- 12 hour clock: AM/PM and where they go around the time
	-- en: AM
	[ "clock.am" ] = "a. m.",

	-- en: PM
	[ "clock.pm" ] = "p. m.",

	-- en: {time} {ampm}
	[ "clock.ampm" ] = "{time} {ampm}",

	-- Date: {wday} day of week (short), {day} day number, {month} month (short), {year}
	-- en: {wday} {day} {month}
	[ "date.format" ] = "{wday}, {day} {month}",

	-- en: Sun
	[ "date.wday.1" ] = "dom",

	-- en: Mon
	[ "date.wday.2" ] = "lun",

	-- en: Tue
	[ "date.wday.3" ] = "mar",

	-- en: Wed
	[ "date.wday.4" ] = "mié",

	-- en: Thu
	[ "date.wday.5" ] = "jue",

	-- en: Fri
	[ "date.wday.6" ] = "vie",

	-- en: Sat
	[ "date.wday.7" ] = "sáb",

	-- en: Sunday
	[ "date.wday_full.1" ] = "domingo",

	-- en: Monday
	[ "date.wday_full.2" ] = "lunes",

	-- en: Tuesday
	[ "date.wday_full.3" ] = "martes",

	-- en: Wednesday
	[ "date.wday_full.4" ] = "miércoles",

	-- en: Thursday
	[ "date.wday_full.5" ] = "jueves",

	-- en: Friday
	[ "date.wday_full.6" ] = "viernes",

	-- en: Saturday
	[ "date.wday_full.7" ] = "sábado",

	-- short month names, used in dates ({month} above and %b): use the form your dates need
	-- en: Jan
	[ "date.month.1" ] = "ene",

	-- en: Feb
	[ "date.month.2" ] = "feb",

	-- en: Mar
	[ "date.month.3" ] = "mar",

	-- en: Apr
	[ "date.month.4" ] = "abr",

	-- en: May
	[ "date.month.5" ] = "may",

	-- en: Jun
	[ "date.month.6" ] = "jun",

	-- en: Jul
	[ "date.month.7" ] = "jul",

	-- en: Aug
	[ "date.month.8" ] = "ago",

	-- en: Sep
	[ "date.month.9" ] = "sept",

	-- en: Oct
	[ "date.month.10" ] = "oct",

	-- en: Nov
	[ "date.month.11" ] = "nov",

	-- en: Dec
	[ "date.month.12" ] = "dic",

	-- full month names (%B), usually written right after a day number
	-- en: January
	[ "date.month_full.1" ] = "enero",

	-- en: February
	[ "date.month_full.2" ] = "febrero",

	-- en: March
	[ "date.month_full.3" ] = "marzo",

	-- en: April
	[ "date.month_full.4" ] = "abril",

	-- en: May
	[ "date.month_full.5" ] = "mayo",

	-- en: June
	[ "date.month_full.6" ] = "junio",

	-- en: July
	[ "date.month_full.7" ] = "julio",

	-- en: August
	[ "date.month_full.8" ] = "agosto",

	-- en: September
	[ "date.month_full.9" ] = "septiembre",

	-- en: October
	[ "date.month_full.10" ] = "octubre",

	-- en: November
	[ "date.month_full.11" ] = "noviembre",

	-- en: December
	[ "date.month_full.12" ] = "diciembre",

	-- Kinds of surface material (the game's material types), shown as "World - Concrete"
	-- en: Antlion
	[ "mat.antlion" ] = "Hormiga león",

	-- en: Bloody flesh
	[ "mat.bloodyflesh" ] = "Carne ensangrentada",

	-- en: Concrete
	[ "mat.concrete" ] = "Hormigón",

	-- en: Dirt
	[ "mat.dirt" ] = "Tierra",

	-- en: Eggshell
	[ "mat.eggshell" ] = "Cáscara de huevo",

	-- en: Flesh
	[ "mat.flesh" ] = "Carne",

	-- en: Grate
	[ "mat.grate" ] = "Rejilla",

	-- en: Alien flesh
	[ "mat.alienflesh" ] = "Carne alienígena",

	-- en: Clip
	[ "mat.clip" ] = "Pared invisible",

	-- en: Snow
	[ "mat.snow" ] = "Nieve",

	-- en: Plastic
	[ "mat.plastic" ] = "Plástico",

	-- en: Metal
	[ "mat.metal" ] = "Metal",

	-- en: Sand
	[ "mat.sand" ] = "Arena",

	-- en: Foliage
	[ "mat.foliage" ] = "Follaje",

	-- en: Computer
	[ "mat.computer" ] = "Electrónica",

	-- en: Liquid
	[ "mat.slosh" ] = "Líquido",

	-- en: Tile
	[ "mat.tile" ] = "Baldosa",

	-- en: Grass
	[ "mat.grass" ] = "Hierba",

	-- en: Vent
	[ "mat.vent" ] = "Ventilación",

	-- en: Wood
	[ "mat.wood" ] = "Madera",

	-- en: Generic
	[ "mat.default" ] = "Genérico",

	-- en: Glass
	[ "mat.glass" ] = "Cristal",

	-- en: Warp shield
	[ "mat.warpshield" ] = "Escudo de distorsión",

	-- Notifications on the screen
	-- en: Tracking {name}
	[ "notify.tracking" ] = "Siguiendo: {name}",

	-- en: Stopped tracking
	[ "notify.untracked" ] = "Seguimiento detenido",

	-- en: Layout: {name}
	[ "notify.layout" ] = "Diseño: {name}",

	-- en: Theme: {name}
	[ "notify.theme" ] = "Tema: {name}",

	-- title bar: tool category, or the game's name when there is none (keep "Garry's Mod")
	-- en: {tool_category|Garry's Mod}
	[ "tpl.title" ] = "{tool_category|Garry's Mod}",

	-- left link of the Pocket PC screen: the previous tool
	-- en: Back to {tool_prev}
	[ "tpl.nav_back" ] = "Volver a {tool_prev}",

	-- en: Props {props}/{props_max}
	[ "tpl.props" ] = "Objetos {props}/{props_max}",

	-- en: {fps} fps  {ping} ms
	[ "tpl.perf" ] = "{fps} FPS  {ping} ms",

	-- en: Slope {aim_slope}
	[ "tpl.slope" ] = "Pendiente {aim_slope}",

	-- en: HP {ent_health}
	[ "tpl.hp" ] = "Vida {ent_health}",

	-- en: Owner: {ent_owner}
	[ "tpl.owner" ] = "Propietario: {ent_owner}",

	-- HP = health, AP = armor
	-- en: HP {health}  AP {armor}
	[ "tpl.health_armor" ] = "Vida {health}  Armadura {armor}",

	-- en: {players} players
	[ "tpl.players" ] = "Jugadores: {players}",

	-- Terminal lines: a short upper case label, a tab, then the value
	-- en: TOOL\t**{tool}**
	[ "tpl.term_tool" ] = "HERRAM\t**{tool}**",

	-- en: AIM\t**{aim_what}**
	[ "tpl.term_aim" ] = "OBJETIVO\t**{aim_what}**",

	-- en: CLASS\t**{ent_class|-}**
	[ "tpl.term_class" ] = "CLASE\t**{ent_class|-}**",

	-- en: POS\t**{aim_pos}**
	[ "tpl.term_pos" ] = "POS\t**{aim_pos}**",

	-- en: DIST\t**{aim_dist}**  {aim_slope}
	[ "tpl.term_dist" ] = "DIST\t**{aim_dist}**  {aim_slope}",

	-- en: OWNER\t**{ent_owner|-}**
	[ "tpl.term_owner" ] = "DUEÑO\t**{ent_owner|-}**",

	-- en: HP\t**{ent_health|-}**
	[ "tpl.term_hp" ] = "VIDA\t**{ent_health|-}**",

	-- en: TRACK\t**{track_name|-}** {track_dist}
	[ "tpl.term_track" ] = "SEGUIDO\t**{track_name|-}** {track_dist}",

	-- en: Pocket PC
	[ "layout.pocketpc.name" ] = "Pocket PC",

	-- en: The original screen rebuilt with live data: clock, status icons, tool history links, big tool name, status line, six readouts and a hint bar.
	[ "layout.pocketpc.desc" ] = "La pantalla original reconstruida con datos en vivo: reloj, iconos de estado, enlaces al historial de herramientas, nombre grande de la herramienta, línea de estado, seis indicadores y una barra de ayuda.",

	-- en: Title bar
	[ "layout.pocketpc.title" ] = "Barra de título",

	-- en: Clock
	[ "layout.pocketpc.clock" ] = "Reloj",

	-- en: Left link
	[ "layout.pocketpc.nav_l" ] = "Enlace izquierdo",

	-- en: Right link
	[ "layout.pocketpc.nav_r" ] = "Enlace derecho",

	-- en: Big text
	[ "layout.pocketpc.hero" ] = "Texto grande",

	-- en: Under the big text
	[ "layout.pocketpc.sub" ] = "Bajo el texto grande",

	-- en: Status line
	[ "layout.pocketpc.status" ] = "Línea de estado",

	-- en: Readout, left 1
	[ "layout.pocketpc.l1" ] = "Indicador, izquierda 1",

	-- en: Readout, left 2
	[ "layout.pocketpc.l2" ] = "Indicador, izquierda 2",

	-- en: Readout, left 3
	[ "layout.pocketpc.l3" ] = "Indicador, izquierda 3",

	-- en: Readout, right 1
	[ "layout.pocketpc.r1" ] = "Indicador, derecha 1",

	-- en: Readout, right 2
	[ "layout.pocketpc.r2" ] = "Indicador, derecha 2",

	-- en: Readout, right 3
	[ "layout.pocketpc.r3" ] = "Indicador, derecha 3",

	-- en: Menu bar
	[ "layout.pocketpc.menu" ] = "Barra de menú",

	-- en: Terminal
	[ "layout.terminal.name" ] = "Terminal",

	-- en: Developer readout: eight lines of labels and values, an FPS graph and a prompt line with the tool hints.
	[ "layout.terminal.desc" ] = "Vista para desarrolladores: ocho líneas de etiquetas y valores, un gráfico de FPS y una línea de comandos con las ayudas de la herramienta.",

	-- en: Header
	[ "layout.terminal.head" ] = "Encabezado",

	-- en: Header, right
	[ "layout.terminal.clock" ] = "Encabezado, derecha",

	-- en: Line 1
	[ "layout.terminal.l1" ] = "Línea 1",

	-- en: Line 2
	[ "layout.terminal.l2" ] = "Línea 2",

	-- en: Line 3
	[ "layout.terminal.l3" ] = "Línea 3",

	-- en: Line 4
	[ "layout.terminal.l4" ] = "Línea 4",

	-- en: Line 5
	[ "layout.terminal.l5" ] = "Línea 5",

	-- en: Line 6
	[ "layout.terminal.l6" ] = "Línea 6",

	-- en: Line 7
	[ "layout.terminal.l7" ] = "Línea 7",

	-- en: Line 8
	[ "layout.terminal.l8" ] = "Línea 8",

	-- en: Prompt line
	[ "layout.terminal.foot" ] = "Línea de comandos",

	-- en: Minimal
	[ "layout.minimal.name" ] = "Minimalista",

	-- en: Large, glanceable text: clock, compass, the tool name sized to fit, what you aim at and two corner values.
	[ "layout.minimal.desc" ] = "Texto grande que se lee de un vistazo: reloj, brújula, el nombre de la herramienta ajustado al espacio, a qué apuntas y dos valores en las esquinas.",

	-- en: Top left
	[ "layout.minimal.top_l" ] = "Arriba a la izquierda",

	-- en: Top right
	[ "layout.minimal.top_r" ] = "Arriba a la derecha",

	-- en: Big text
	[ "layout.minimal.hero" ] = "Texto grande",

	-- en: Under the big text
	[ "layout.minimal.sub" ] = "Bajo el texto grande",

	-- en: Bottom left
	[ "layout.minimal.foot_l" ] = "Abajo a la izquierda",

	-- en: Bottom right
	[ "layout.minimal.foot_r" ] = "Abajo a la derecha",

	-- en: Pocket PC (original)
	[ "theme.winmobile" ] = "Pocket PC (original)",

	-- en: Graphite
	[ "theme.graphite" ] = "Grafito",

	-- en: Green phosphor
	[ "theme.phosphor" ] = "Fósforo verde",

	-- en: Amber CRT
	[ "theme.amber" ] = "CRT ámbar",

	-- en: Sakura
	[ "theme.sakura" ] = "Sakura",

	-- en: Sandbox blue
	[ "theme.sandbox" ] = "Azul Sandbox",

	-- parts of the screen whose colour can be changed
	-- en: Title bar
	[ "color.bar" ] = "Barra de título",

	-- en: Links and highlights
	[ "color.accent" ] = "Enlaces y resaltados",

	-- en: Big text
	[ "color.hero" ] = "Texto grande",

	-- en: Status line
	[ "color.strip" ] = "Línea de estado",

	-- en: Readout panel
	[ "color.panel" ] = "Panel de indicadores",

	-- en: Menu bar
	[ "color.menu" ] = "Barra de menú",

	-- en: Terminal text
	[ "color.term" ] = "Texto del terminal",

	-- en: Text
	[ "category.text" ] = "Texto",

	-- en: Time
	[ "category.time" ] = "Tiempo",

	-- en: Tool
	[ "category.tool" ] = "Herramienta",

	-- en: Aim
	[ "category.aim" ] = "Mira",

	-- en: Aimed entity
	[ "category.entity" ] = "Entidad apuntada",

	-- en: Tracked entity
	[ "category.tracked" ] = "Entidad seguida",

	-- en: You
	[ "category.player" ] = "Tú",

	-- en: Game
	[ "category.game" ] = "Juego",

	-- the Advanced Toolgun [Hotbar] addon; keep its name as it is
	-- en: Advanced Toolgun
	[ "category.atg" ] = "Advanced Toolgun",

	-- en: A line in your language from the language files, e.g. {tr:nav_back} or {tr:props}.
	[ "token.tr" ] = "Una línea en tu idioma sacada de los archivos de idioma, p. ej. {tr:nav_back} o {tr:props}.",

	-- en: Local time, formatted by the clock settings. {time:%H:%M:%S} takes an os.date format.
	[ "token.time" ] = "Hora local, con el formato de los ajustes del reloj. {time:%H:%M:%S} acepta un formato de os.date.",

	-- en: Today's date. {date:%Y-%m-%d} takes an os.date format.
	[ "token.date" ] = "Fecha de hoy. {date:%Y-%m-%d} acepta un formato de os.date.",

	-- en: How long you have been in this game.
	[ "token.session" ] = "Cuánto tiempo llevas en esta partida.",

	-- en: How long the map has been running.
	[ "token.map_time" ] = "Cuánto tiempo lleva el mapa en marcha.",

	-- en: Name of the selected tool.
	[ "token.tool" ] = "Nombre de la herramienta seleccionada.",

	-- en: Internal name of the selected tool.
	[ "token.tool_id" ] = "Nombre interno de la herramienta seleccionada.",

	-- en: Description of the selected tool.
	[ "token.tool_desc" ] = "Descripción de la herramienta seleccionada.",

	-- en: Tool menu category of the selected tool.
	[ "token.tool_category" ] = "Categoría de la herramienta seleccionada en el menú de herramientas.",

	-- en: Stage of the selected tool (0 = nothing selected yet).
	[ "token.tool_stage" ] = "Paso de la herramienta seleccionada (0 = aún no hay nada seleccionado).",

	-- en: The stage while a multi-click tool is in progress, otherwise empty.
	[ "token.tool_progress" ] = "El paso mientras una herramienta de varios clics está en curso; si no, vacío.",

	-- en: The tool you used before this one (dts_tool_back switches to it).
	[ "token.tool_prev" ] = "La herramienta que usaste antes de esta (dts_tool_back vuelve a ella).",

	-- en: The next tool in the same menu category (dts_tool_next switches to it).
	[ "token.tool_next" ] = "La siguiente herramienta de la misma categoría del menú (dts_tool_next cambia a ella).",

	-- en: Successful tool gun shots this session.
	[ "token.tool_uses" ] = "Disparos acertados de la pistoherramienta en esta sesión.",

	-- en: A setting of the selected tool, e.g. {tool_cvar:forcelimit} reads weld_forcelimit.
	[ "token.tool_cvar" ] = "Un ajuste de la herramienta seleccionada, p. ej. {tool_cvar:forcelimit} lee weld_forcelimit.",

	-- en: All settings of the selected tool as name=value pairs.
	[ "token.tool_settings" ] = "Todos los ajustes de la herramienta seleccionada como pares nombre=valor.",

	-- en: The current stage's instructions with mouse and key icons.
	[ "token.hints" ] = "Las instrucciones del paso actual con iconos de ratón y teclas.",

	-- en: What left click does right now.
	[ "token.hint_left" ] = "Lo que hace ahora el clic izquierdo.",

	-- en: What right click does right now.
	[ "token.hint_right" ] = "Lo que hace ahora el clic derecho.",

	-- en: What reload does right now.
	[ "token.hint_reload" ] = "Lo que hace ahora la tecla de recarga.",

	-- en: What you are aiming at, with the name highlighted.
	[ "token.target" ] = "A qué apuntas, con el nombre resaltado.",

	-- en: Entity name, or the surface material when aiming at the world.
	[ "token.aim_what" ] = "Nombre de la entidad, o el material de la superficie si apuntas al mundo.",

	-- en: Position you are aiming at.
	[ "token.aim_pos" ] = "Posición a la que apuntas.",

	-- en: X of the aim position.
	[ "token.aim_x" ] = "X de la posición apuntada.",

	-- en: Y of the aim position.
	[ "token.aim_y" ] = "Y de la posición apuntada.",

	-- en: Z of the aim position.
	[ "token.aim_z" ] = "Z de la posición apuntada.",

	-- en: Distance to the aim position.
	[ "token.aim_dist" ] = "Distancia hasta la posición apuntada.",

	-- en: Surface normal at the aim position.
	[ "token.aim_normal" ] = "Normal de la superficie en la posición apuntada.",

	-- en: Steepness of the surface (0 = flat floor, 90 = wall).
	[ "token.aim_slope" ] = "Inclinación de la superficie (0 = suelo plano, 90 = pared).",

	-- en: Kind of surface material (metal, wood, concrete...).
	[ "token.aim_surface" ] = "Tipo de material de la superficie (metal, madera, hormigón...).",

	-- en: Surface property as the engine names it (metal box, wood crate...).
	[ "token.aim_surfaceprop" ] = "Propiedad de superficie con el nombre que le da el motor (metal box, wood crate...).",

	-- en: World texture you are aiming at.
	[ "token.aim_texture" ] = "Textura del mundo a la que apuntas.",

	-- en: Friendly name of the aimed entity.
	[ "token.ent_name" ] = "Nombre legible de la entidad apuntada.",

	-- en: Class of the aimed entity.
	[ "token.ent_class" ] = "Clase de la entidad apuntada.",

	-- en: Model file name of the aimed entity.
	[ "token.ent_model" ] = "Nombre del archivo de modelo de la entidad apuntada.",

	-- en: Full model path of the aimed entity.
	[ "token.ent_model_path" ] = "Ruta completa del modelo de la entidad apuntada.",

	-- en: Entity index.
	[ "token.ent_index" ] = "Índice de la entidad.",

	-- en: Health of the aimed entity (players, NPCs, breakable props).
	[ "token.ent_health" ] = "Salud de la entidad apuntada (jugadores, PNJ, objetos rompibles).",

	-- en: Owner of the aimed entity (in multiplayer this needs a CPPI prop protection addon).
	[ "token.ent_owner" ] = "Propietario de la entidad apuntada (en multijugador necesita un addon de protección de objetos compatible con CPPI).",

	-- en: Material of the aimed entity.
	[ "token.ent_material" ] = "Material de la entidad apuntada.",

	-- en: Colour of the aimed entity.
	[ "token.ent_color" ] = "Color de la entidad apuntada.",

	-- en: Skin of the aimed entity.
	[ "token.ent_skin" ] = "Apariencia (skin) de la entidad apuntada.",

	-- en: Speed of the aimed entity.
	[ "token.ent_speed" ] = "Velocidad de la entidad apuntada.",

	-- en: Position of the aimed entity.
	[ "token.ent_pos" ] = "Posición de la entidad apuntada.",

	-- en: Angles of the aimed entity.
	[ "token.ent_ang" ] = "Ángulos de la entidad apuntada.",

	-- en: Mass of the aimed entity, when your game knows its physics.
	[ "token.ent_mass" ] = "Masa de la entidad apuntada, cuando tu juego conoce su física.",

	-- en: Tracked entity summary: name, distance, speed, health.
	[ "token.track" ] = "Resumen de la entidad seguida: nombre, distancia, velocidad, salud.",

	-- en: Name of the tracked entity.
	[ "token.track_name" ] = "Nombre de la entidad seguida.",

	-- en: Class of the tracked entity.
	[ "token.track_class" ] = "Clase de la entidad seguida.",

	-- en: Your distance to the tracked entity.
	[ "token.track_dist" ] = "Tu distancia a la entidad seguida.",

	-- en: Speed of the tracked entity.
	[ "token.track_speed" ] = "Velocidad de la entidad seguida.",

	-- en: Health of the tracked entity.
	[ "token.track_health" ] = "Salud de la entidad seguida.",

	-- en: Position of the tracked entity.
	[ "token.track_pos" ] = "Posición de la entidad seguida.",

	-- en: Your name.
	[ "token.player" ] = "Tu nombre.",

	-- en: Your health.
	[ "token.health" ] = "Tu salud.",

	-- en: Your armor.
	[ "token.armor" ] = "Tu armadura.",

	-- en: Your speed.
	[ "token.speed" ] = "Tu velocidad.",

	-- en: Your position.
	[ "token.pos" ] = "Tu posición.",

	-- en: Your view pitch and yaw.
	[ "token.eye_ang" ] = "Cabeceo y guiñada de tu vista.",

	-- en: Compass heading (north is +Y on the map).
	[ "token.heading" ] = "Rumbo de la brújula (el norte es +Y en el mapa).",

	-- en: Shows a word while you are noclipping, otherwise empty.
	[ "token.noclip" ] = "Muestra una palabra mientras usas el noclip; si no, vacío.",

	-- en: Frames per second (smoothed).
	[ "token.fps" ] = "Fotogramas por segundo (suavizados).",

	-- en: Your ping in milliseconds.
	[ "token.ping" ] = "Tu ping en milisegundos.",

	-- en: Your device's battery charge while it runs on battery, or \"Plugged in\".
	[ "token.battery" ] = "La carga de la batería de tu dispositivo cuando funciona con batería, o «Enchufado».",

	-- en: Current map.
	[ "token.map" ] = "Mapa actual.",

	-- en: Players on the server and its player limit.
	[ "token.players" ] = "Jugadores en el servidor y su límite de jugadores.",

	-- en: Server name.
	[ "token.server" ] = "Nombre del servidor.",

	-- en: Active gamemode.
	[ "token.gamemode" ] = "Modo de juego activo.",

	-- en: Server tick rate.
	[ "token.tickrate" ] = "Tickrate del servidor.",

	-- en: Memory used by Lua in your game.
	[ "token.lua_mem" ] = "Memoria que usa Lua en tu juego.",

	-- en: Entities known to your game.
	[ "token.entities" ] = "Entidades que conoce tu juego.",

	-- en: Props you have spawned.
	[ "token.props" ] = "Objetos que has creado.",

	-- en: Your prop limit.
	[ "token.props_max" ] = "Tu límite de objetos.",

	-- en: Spawn count and limit of a type, e.g. {count:ragdolls} or {count:thrusters}.
	[ "token.count" ] = "Cantidad y límite de un tipo, p. ej. {count:ragdolls} o {count:thrusters}.",

	-- en: Value of any console variable, e.g. {cvar:sv_gravity}.
	[ "token.cvar" ] = "Valor de cualquier variable de consola, p. ej. {cvar:sv_gravity}.",

	-- en: Advanced Toolgun [Hotbar]: its open tab (Tools, Wire or Favorites).
	[ "token.atg_tab" ] = "Advanced Toolgun [Hotbar]: su pestaña abierta (Herramientas, Wire o Favoritos).",

	-- en: Advanced Toolgun [Hotbar]: the section of its list the selection is in.
	[ "token.atg_section" ] = "Advanced Toolgun [Hotbar]: la sección de su lista en la que está la selección.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel up.
	[ "token.atg_prev" ] = "Advanced Toolgun [Hotbar]: la herramienta a la que pasa su selección rápida con la rueda del ratón hacia arriba.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel down.
	[ "token.atg_next" ] = "Advanced Toolgun [Hotbar]: la herramienta a la que pasa su selección rápida con la rueda del ratón hacia abajo.",

	-- en: Turns the tool gun's mini screen into a live display. Changes apply instantly; the preview shows what the screen draws right now.
	[ "menu.intro" ] = "Convierte la pequeña pantalla de la pistoherramienta en una pantalla en vivo. Los cambios se aplican al instante; la vista previa muestra lo que dibuja la pantalla ahora mismo.",

	-- en: Dynamic screen is off
	[ "menu.preview_off" ] = "La pantalla dinámica está desactivada",

	-- en: Enable the dynamic screen
	[ "menu.enable" ] = "Activar la pantalla dinámica",

	-- en: Language
	[ "menu.language" ] = "Idioma",

	-- first entry of the language list; {name} is the game's language, e.g. "English"
	-- en: Automatic: {name}
	[ "menu.language.auto" ] = "Automático: {name}",

	-- en: Inspect: read the screen up close
	[ "menu.inspect.title" ] = "Examinar: leer la pantalla de cerca",

	-- en: Hold a key while holding the tool gun to raise its screen to your eyes.
	[ "menu.inspect.help" ] = "Mantén pulsada una tecla con la pistoherramienta en la mano para acercar su pantalla a tus ojos.",

	-- en: Inspect key
	[ "menu.inspect.key" ] = "Tecla para examinar",

	-- en: Screen size while inspecting
	[ "menu.inspect.size" ] = "Tamaño de la pantalla al examinar",

	-- en: Or use the console: bind <key> +dts_inspect (hold) or dts_inspect_toggle.
	[ "menu.inspect.console" ] = "O desde la consola: bind <tecla> +dts_inspect (mantener) o dts_inspect_toggle.",

	-- the tool gun model has a paper note glued on, which overlaps the screen's top right corner
	-- en: Screen in front of the paper note
	[ "menu.inspect.on_top" ] = "Pantalla delante de la nota de papel",

	-- en: While inspecting, the whole screen stays readable. Untick to let the paper note glued to the tool gun cover the top right corner of the screen, as on the model.
	[ "menu.inspect.on_top_help" ] = "Al examinar, se puede leer toda la pantalla. Desmárcalo para que la nota de papel pegada a la pistoherramienta tape la esquina superior derecha de la pantalla, como en el modelo.",

	-- en: Layout and look
	[ "menu.look.title" ] = "Diseño y aspecto",

	-- en: Layout
	[ "menu.look.layout" ] = "Diseño",

	-- en: Theme
	[ "menu.look.theme" ] = "Tema",

	-- en: Background
	[ "menu.look.background" ] = "Fondo",

	-- en: Automatic (layout's choice)
	[ "menu.bg.auto" ] = "Automático (según el diseño)",

	-- the whole original screen picture without its text
	-- en: Original screen
	[ "menu.bg.original" ] = "Pantalla original",

	-- only the blurred photo from the original picture, filling the screen
	-- en: Original photo
	[ "menu.bg.art" ] = "Foto original",

	-- en: Theme gradient
	[ "menu.bg.gradient" ] = "Degradado del tema",

	-- en: Live camera: zoom
	[ "menu.bg.camera" ] = "Cámara en vivo: zoom",

	-- en: Live camera: rear view
	[ "menu.bg.rear" ] = "Cámara en vivo: vista trasera",

	-- en: Custom image
	[ "menu.bg.image" ] = "Imagen personalizada",

	-- en: Black
	[ "menu.bg.black" ] = "Negro",

	-- en: Custom image
	[ "menu.look.image" ] = "Imagen personalizada",

	-- en: A material path, or an image in garrysmod/data written as ../data/name.png
	[ "menu.look.image_help" ] = "Una ruta de material, o una imagen de garrysmod/data escrita como ../data/nombre.png",

	-- en: Darken background
	[ "menu.look.dim" ] = "Oscurecer el fondo",

	-- en: Camera field of view
	[ "menu.look.cam_fov" ] = "Campo de visión de la cámara",

	-- en: Camera updates per second
	[ "menu.look.cam_fps" ] = "Actualizaciones de la cámara por segundo",

	-- en: Text font
	[ "menu.look.font" ] = "Fuente del texto",

	-- en: Big text font
	[ "menu.look.font_hero" ] = "Fuente del texto grande",

	-- en: Terminal font
	[ "menu.look.font_mono" ] = "Fuente del terminal",

	-- first entry of the font lists; {font} is the font your language uses
	-- en: Automatic ({font})
	[ "menu.font.auto" ] = "Automática ({font})",

	-- en: Colours
	[ "menu.colors.title" ] = "Colores",

	-- en: Override single colours of the theme. Click a swatch to change it.
	[ "menu.colors.help" ] = "Cambia colores sueltos del tema. Haz clic en una muestra para cambiarla.",

	-- written on a colour swatch that still uses the theme's colour
	-- en: theme
	[ "menu.colors.theme_tag" ] = "tema",

	-- en: Click to pick a colour
	[ "menu.colors.pick" ] = "Haz clic para elegir un color",

	-- en: Use the theme's colours everywhere
	[ "menu.colors.reset_all" ] = "Usar los colores del tema en todo",

	-- en: Screen colour: {name}
	[ "menu.colors.picker_title" ] = "Color de la pantalla: {name}",

	-- en: Use the theme's colour
	[ "menu.colors.use_theme" ] = "Usar el color del tema",

	-- en: Big text
	[ "menu.hero.title" ] = "Texto grande",

	-- en: Behaviour
	[ "menu.hero.mode" ] = "Comportamiento",

	-- en: Always scroll (original)
	[ "menu.hero.scroll" ] = "Desplazar siempre (original)",

	-- en: Scroll only when too long
	[ "menu.hero.auto" ] = "Desplazar solo si no cabe",

	-- en: Shrink to fit
	[ "menu.hero.fit" ] = "Reducir hasta que quepa",

	-- en: Scroll speed
	[ "menu.hero.speed" ] = "Velocidad de desplazamiento",

	-- en: Upper case tool names
	[ "menu.hero.upper" ] = "Nombres de herramientas en mayúsculas",

	-- en: Screen content
	[ "menu.content.title" ] = "Contenido de la pantalla",

	-- keep {tokens}, **stars**, {token|fallback} and {tr:...} as they are: they show the syntax
	-- en: Every line of the {layout} layout is a template. Type text and {tokens}; **stars** highlight text, {token|fallback} gives a default, and a line whose tokens are all empty hides itself. {tr:...} writes a line in your language. See the token reference below.
	[ "menu.content.help" ] = "Cada línea del diseño «{layout}» es una plantilla. Escribe texto y {tokens}; las **estrellas** resaltan texto, {token|fallback} da un valor por defecto y una línea cuyos tokens están todos vacíos se oculta sola. {tr:...} escribe una línea en tu idioma. Consulta la lista de tokens más abajo.",

	-- en: Pick a ready-made line
	[ "menu.content.presets_tip" ] = "Elegir una línea predefinida",

	-- en: Back to the default: {value}
	[ "menu.content.reset_tip" ] = "Volver al valor por defecto: {value}",

	-- en: (empty)
	[ "menu.content.empty" ] = "(vacía)",

	-- shown in an empty line's text box
	-- en: (hidden)
	[ "menu.content.placeholder" ] = "(oculta)",

	-- under each line: what it shows right now
	-- en: = {text}
	[ "menu.content.now" ] = "= {text}",

	-- en: (hidden right now)
	[ "menu.content.hidden_now" ] = "(oculta ahora mismo)",

	-- en: Reset these lines to the layout's defaults
	[ "menu.content.reset_all" ] = "Restablecer estas líneas a las del diseño",

	-- ready-made lines in the list next to each line
	-- en: Tool name
	[ "menu.preset.tool" ] = "Nombre de la herramienta",

	-- en: Tool category
	[ "menu.preset.tool_category" ] = "Categoría de la herramienta",

	-- en: Tool instructions
	[ "menu.preset.hints" ] = "Instrucciones de la herramienta",

	-- en: Previous tool
	[ "menu.preset.prev_tool" ] = "Herramienta anterior",

	-- en: Next tool
	[ "menu.preset.next_tool" ] = "Herramienta siguiente",

	-- en: Tool progress
	[ "menu.preset.progress" ] = "Progreso de la herramienta",

	-- en: Tool settings
	[ "menu.preset.tool_settings" ] = "Ajustes de la herramienta",

	-- en: What you aim at
	[ "menu.preset.target" ] = "A qué apuntas",

	-- en: Aim position
	[ "menu.preset.aim_pos" ] = "Posición apuntada",

	-- en: Aim distance
	[ "menu.preset.aim_dist" ] = "Distancia apuntada",

	-- en: Entity or surface
	[ "menu.preset.aim_what" ] = "Entidad o superficie",

	-- en: Surface slope
	[ "menu.preset.slope" ] = "Pendiente de la superficie",

	-- en: Entity class
	[ "menu.preset.ent_class" ] = "Clase de la entidad",

	-- en: Entity model
	[ "menu.preset.ent_model" ] = "Modelo de la entidad",

	-- en: Entity health
	[ "menu.preset.ent_health" ] = "Salud de la entidad",

	-- en: Entity owner
	[ "menu.preset.ent_owner" ] = "Propietario de la entidad",

	-- en: Entity speed
	[ "menu.preset.ent_speed" ] = "Velocidad de la entidad",

	-- en: Tracked entity
	[ "menu.preset.track" ] = "Entidad seguida",

	-- en: Clock
	[ "menu.preset.clock" ] = "Reloj",

	-- en: Clock with seconds
	[ "menu.preset.clock_seconds" ] = "Reloj con segundos",

	-- en: Date
	[ "menu.preset.date" ] = "Fecha",

	-- en: Time in game
	[ "menu.preset.session" ] = "Tiempo de juego",

	-- en: Your speed
	[ "menu.preset.speed" ] = "Tu velocidad",

	-- en: Your position
	[ "menu.preset.pos" ] = "Tu posición",

	-- en: Compass
	[ "menu.preset.heading" ] = "Brújula",

	-- en: Health and armor
	[ "menu.preset.health_armor" ] = "Salud y armadura",

	-- en: FPS and ping
	[ "menu.preset.perf" ] = "FPS y ping",

	-- en: Prop count
	[ "menu.preset.props" ] = "Número de objetos",

	-- en: Map
	[ "menu.preset.map" ] = "Mapa",

	-- en: Players
	[ "menu.preset.players" ] = "Jugadores",

	-- en: Empty (hide the line)
	[ "menu.preset.empty" ] = "Vacía (ocultar la línea)",

	-- en: Clock and units
	[ "menu.clock.title" ] = "Reloj y unidades",

	-- en: Clock
	[ "menu.clock.style" ] = "Reloj",

	-- {language} is the name of the active language
	-- en: As usual in {language}
	[ "menu.clock.auto" ] = "Según el idioma ({language})",

	-- en: 12 hour
	[ "menu.clock.12h" ] = "12 horas",

	-- en: 24 hour
	[ "menu.clock.24h" ] = "24 horas",

	-- en: Show seconds
	[ "menu.clock.seconds" ] = "Mostrar los segundos",

	-- en: Show AM / PM (12 hour clock)
	[ "menu.clock.ampm" ] = "Mostrar a. m. / p. m. (reloj de 12 horas)",

	-- en: Blink the colon
	[ "menu.clock.blink" ] = "Hacer parpadear los dos puntos",

	-- en: Units
	[ "menu.units.label" ] = "Unidades",

	-- en: Metric (m, km/h)
	[ "menu.units.m" ] = "Métricas (m, km/h)",

	-- en: Imperial (ft, mph)
	[ "menu.units.ft" ] = "Imperiales (ft, mph)",

	-- en: Hammer units
	[ "menu.units.hu" ] = "Unidades de Hammer",

	-- en: Distance decimals
	[ "menu.units.decimals" ] = "Decimales de las distancias",

	-- en: Icons and effects
	[ "menu.fx.title" ] = "Iconos y efectos",

	-- en: Speaker icon (volume, voice chat)
	[ "menu.fx.speaker" ] = "Icono de altavoz (volumen, chat de voz)",

	-- en: Signal icon (connection)
	[ "menu.fx.signal" ] = "Icono de señal (conexión)",

	-- en: Battery icon (your device's battery)
	[ "menu.fx.battery" ] = "Icono de batería (la batería de tu dispositivo)",

	-- en: Boot animation when taking out the tool gun
	[ "menu.fx.boot" ] = "Animación de arranque al sacar la pistoherramienta",

	-- en: Flash when the tool gun fires
	[ "menu.fx.flash" ] = "Destello al disparar la pistoherramienta",

	-- en: Show game notifications on the screen
	[ "menu.fx.notify" ] = "Mostrar las notificaciones del juego en la pantalla",

	-- en: Notification time
	[ "menu.fx.notify_time" ] = "Duración de las notificaciones",

	-- en: Scanlines
	[ "menu.fx.scanlines" ] = "Líneas de barrido",

	-- en: Darker edges
	[ "menu.fx.vignette" ] = "Bordes más oscuros",

	-- en: Backlight
	[ "menu.fx.backlight" ] = "Retroiluminación",

	-- en: HUD mirror
	[ "menu.mirror.title" ] = "Espejo en el HUD",

	-- en: Shows the screen on your HUD while you hold the tool gun, for reading the small print.
	[ "menu.mirror.help" ] = "Muestra también la pantalla en tu HUD mientras llevas la pistoherramienta, para leer la letra pequeña.",

	-- en: Show the screen on the HUD
	[ "menu.mirror.enable" ] = "Mostrar la pantalla en el HUD",

	-- en: Corner
	[ "menu.mirror.corner" ] = "Esquina",

	-- en: Top right
	[ "menu.corner.tr" ] = "Arriba a la derecha",

	-- en: Bottom right
	[ "menu.corner.br" ] = "Abajo a la derecha",

	-- en: Bottom left
	[ "menu.corner.bl" ] = "Abajo a la izquierda",

	-- en: Top left
	[ "menu.corner.tl" ] = "Arriba a la izquierda",

	-- en: Size
	[ "menu.mirror.size" ] = "Tamaño",

	-- en: Opacity
	[ "menu.mirror.alpha" ] = "Opacidad",

	-- en: Advanced
	[ "menu.adv.title" ] = "Avanzado",

	-- en: Keep the own screens of tools that draw one
	[ "menu.adv.respect" ] = "Respetar la pantalla propia de las herramientas que dibujan una",

	-- en: e.g. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod tools
	[ "menu.adv.respect_help" ] = "p. ej. Easy Entity Inspector, Ragdoll Puppeteer, herramientas de Wiremod",

	-- en: Live value updates per second
	[ "menu.adv.refresh" ] = "Actualizaciones de valores por segundo",

	-- en: Screen redraws per second (0 = every frame)
	[ "menu.adv.fps" ] = "Redibujados de la pantalla por segundo (0 = cada fotograma)",

	-- en: Resolution
	[ "menu.adv.resolution" ] = "Resolución",

	-- en: 256 x 256 (original)
	[ "menu.res.256" ] = "256 x 256 (original)",

	-- en: 512 x 512 (sharper, for 1440p and up)
	[ "menu.res.512" ] = "512 x 512 (más nítida, para 1440p o más)",

	-- keep the commands as they are
	-- en: Key binds (bind <key> <command>):\n  dts_tool_back  -  previous tool\n  dts_tool_next / dts_tool_prev  -  cycle the category\n  dts_layout_next, dts_theme_next  -  cycle layouts, themes\n  dts_track / dts_untrack  -  follow an entity
	[ "menu.adv.binds" ] = "Asignaciones de teclas (bind <tecla> <comando>):\n  dts_tool_back  -  herramienta anterior\n  dts_tool_next / dts_tool_prev  -  recorrer la categoría\n  dts_layout_next, dts_theme_next  -  cambiar de diseño, de tema\n  dts_track / dts_untrack  -  seguir una entidad",

	-- en: Copy my settings to the clipboard
	[ "menu.adv.copy" ] = "Copiar mis ajustes al portapapeles",

	-- en: Screen settings copied to the clipboard
	[ "menu.adv.copied" ] = "Ajustes de la pantalla copiados al portapapeles",

	-- en: Import settings...
	[ "menu.adv.import" ] = "Importar ajustes...",

	-- en: Import screen settings
	[ "menu.adv.import_title" ] = "Importar ajustes de la pantalla",

	-- en: Paste a DTS1:... settings string
	[ "menu.adv.import_prompt" ] = "Pega una cadena de ajustes DTS1:...",

	-- en: Import
	[ "menu.adv.import_ok" ] = "Importar",

	-- en: Imported screen settings ({n} changed)
	[ "menu.adv.imported" ] = "Ajustes de la pantalla importados ({n} cambiados)",

	-- en: Reset everything to defaults
	[ "menu.adv.reset" ] = "Restablecer todo por defecto",

	-- en: Reset
	[ "menu.adv.reset_title" ] = "Restablecer",

	-- en: Reset every Dynamic Toolgun Screen setting?
	[ "menu.adv.reset_question" ] = "¿Restablecer todos los ajustes de la Pantalla dinámica de la pistoherramienta?",

	-- en: Reset
	[ "menu.adv.reset_yes" ] = "Restablecer",

	-- en: Cancel
	[ "menu.adv.cancel" ] = "Cancelar",

	-- en: Another addon replaced the tool gun screen ({file}). Use the button below to take over.
	[ "menu.adv.diag_conflict" ] = "Otro addon ha sustituido la pantalla de la pistoherramienta ({file}). Usa el botón de abajo para recuperarla.",

	-- en: v{version} installed. Each redraw takes {ms} ms.
	[ "menu.adv.diag_ok" ] = "v{version} instalada. Cada redibujado tarda {ms} ms.",

	-- en: Last error: {error}
	[ "menu.adv.diag_error" ] = "Último error: {error}",

	-- en: Waiting for the tool gun to load...
	[ "menu.adv.diag_wait" ] = "Esperando a que cargue la pistoherramienta...",

	-- en: Take over the tool gun screen
	[ "menu.adv.takeover" ] = "Recuperar la pantalla de la pistoherramienta",

	-- en: Only needed if another addon replaced the tool gun's screen after this one
	[ "menu.adv.takeover_tip" ] = "Solo hace falta si otro addon sustituyó la pantalla de la pistoherramienta después de este",

	-- en: Dynamic Toolgun Screen installed
	[ "menu.adv.takeover_done" ] = "Pantalla dinámica de la pistoherramienta instalada",

	-- answers to "Import settings..." when the pasted text is wrong
	-- en: This is not a Dynamic Toolgun Screen settings string.
	[ "import.not_ours" ] = "Esto no es una cadena de ajustes de la Pantalla dinámica de la pistoherramienta.",

	-- en: The settings string is damaged.
	[ "import.damaged" ] = "La cadena de ajustes está dañada.",

	-- en: Token reference
	[ "menu.tokens.title" ] = "Lista de tokens",

	-- en: Hover a token for what it does, double-click to copy it.
	[ "menu.tokens.help" ] = "Pasa el ratón por un token para ver qué hace; haz doble clic para copiarlo.",

	-- en: Token
	[ "menu.tokens.col_token" ] = "Token",

	-- en: Right now
	[ "menu.tokens.col_now" ] = "Ahora",

	-- en: Copied {token}
	[ "menu.tokens.copied" ] = "{token} copiado",

}
