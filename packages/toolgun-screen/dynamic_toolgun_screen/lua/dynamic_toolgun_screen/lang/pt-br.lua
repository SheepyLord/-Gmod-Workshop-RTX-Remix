--[[
	Dynamic Toolgun Screen - Português (Brasil) (pt-br)

	Made from lang/en.lua with tools/i18n.py (see TRANSLATING.md). Above each phrase, "-- en:" holds the
	English it translates; "tools/i18n.py check" lists phrases whose English changed since. A phrase
	missing here falls back to English.
]]

return {

	-- name of the language in that language, shown in the language list
	-- en: English
	[ "_name" ] = "Português (Brasil)",

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
	[ "tool.name" ] = "Tela dinâmica da Arma de Ferramentas",

	-- en: Customize the tool gun's live screen and track entities on it
	[ "tool.desc" ] = "Personalize a tela ao vivo da Arma de Ferramentas e rastreie entidades nela",

	-- en: Track the entity you are aiming at
	[ "tool.left" ] = "Rastrear a entidade na sua mira",

	-- en: Switch to the next screen layout
	[ "tool.right" ] = "Mudar para o próximo layout da tela",

	-- en: Stop tracking
	[ "tool.reload" ] = "Parar de rastrear",

	-- context menu entry (right click an entity while holding C)
	-- en: Track on tool gun screen
	[ "prop.track" ] = "Rastrear na tela da Arma de Ferramentas",

	-- Utilities tab: category and its only entry
	-- en: Dynamic Toolgun Screen
	[ "menu.category" ] = "Tela dinâmica da Arma de Ferramentas",

	-- en: Settings
	[ "menu.settings_item" ] = "Configurações",

	-- status line; {name} is an entity name such as "oildrum001" or a player's name
	-- en: Aiming at **{name}**
	[ "target.entity" ] = "Mirando em **{name}**",

	-- en: Aiming at the **sky**
	[ "target.sky" ] = "Mirando no **céu**",

	-- en: World
	[ "target.world" ] = "Mundo",

	-- {surface} is a material from the mat.* phrases below
	-- en: World - **{surface}**
	[ "target.world_surface" ] = "Mundo - **{surface}**",

	-- en: Nothing in range
	[ "target.nothing" ] = "Nada ao alcance",

	-- what you aim at, when it is the sky
	-- en: sky
	[ "aim.sky" ] = "céu",

	-- multi-click tools (weld, rope...): which click comes next
	-- en: Stage {n}
	[ "tool.progress" ] = "Etapa {n}",

	-- health of the tracked entity, e.g. "HP 40/100"
	-- en: HP {hp}
	[ "track.hp" ] = "Vida {hp}",

	-- en: Noclip
	[ "noclip" ] = "No Clip",

	-- view angles: P = pitch, Y = yaw
	-- en: P {p}  Y {y}
	[ "eye_ang" ] = "Arfagem {p}  Guinada {y}",

	-- compass heading, e.g. "NE 45°"
	-- en: {dir} {deg}°
	[ "heading" ] = "{dir} {deg}°",

	-- en: N
	[ "compass.n" ] = "N",

	-- en: NE
	[ "compass.ne" ] = "NE",

	-- en: E
	[ "compass.e" ] = "L",

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
	[ "error.title" ] = "Erro na tela",

	-- en: See the console for details. Change the layout or run dts_reset to recover.
	[ "error.hint" ] = "Veja os detalhes no console. Mude o layout ou execute dts_reset para recuperar a tela.",

	-- tabs of the Advanced Toolgun [Hotbar] addon's tool list, for the {atg_tab} token
	-- en: Tools
	[ "atg.tab.tools" ] = "Ferramentas",

	-- en: Wire
	[ "atg.tab.wire" ] = "Wire",

	-- en: Favorites
	[ "atg.tab.favorites" ] = "Favoritos",

	-- the device's battery, next to the battery icon and in {battery}: {n} is the charge in percent;
	-- "Plugged in" is shown while the device runs on mains power instead of its battery
	-- en: {n}%
	[ "battery.percent" ] = "{n}%",

	-- en: Plugged in
	[ "battery.plugged" ] = "Na tomada",

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
	[ "clock.am" ] = "AM",

	-- en: PM
	[ "clock.pm" ] = "PM",

	-- en: {time} {ampm}
	[ "clock.ampm" ] = "{time} {ampm}",

	-- Date: {wday} day of week (short), {day} day number, {month} month (short), {year}
	-- en: {wday} {day} {month}
	[ "date.format" ] = "{wday}, {day} de {month}",

	-- en: Sun
	[ "date.wday.1" ] = "dom.",

	-- en: Mon
	[ "date.wday.2" ] = "seg.",

	-- en: Tue
	[ "date.wday.3" ] = "ter.",

	-- en: Wed
	[ "date.wday.4" ] = "qua.",

	-- en: Thu
	[ "date.wday.5" ] = "qui.",

	-- en: Fri
	[ "date.wday.6" ] = "sex.",

	-- en: Sat
	[ "date.wday.7" ] = "sáb.",

	-- en: Sunday
	[ "date.wday_full.1" ] = "domingo",

	-- en: Monday
	[ "date.wday_full.2" ] = "segunda-feira",

	-- en: Tuesday
	[ "date.wday_full.3" ] = "terça-feira",

	-- en: Wednesday
	[ "date.wday_full.4" ] = "quarta-feira",

	-- en: Thursday
	[ "date.wday_full.5" ] = "quinta-feira",

	-- en: Friday
	[ "date.wday_full.6" ] = "sexta-feira",

	-- en: Saturday
	[ "date.wday_full.7" ] = "sábado",

	-- short month names, used in dates ({month} above and %b): use the form your dates need
	-- en: Jan
	[ "date.month.1" ] = "jan.",

	-- en: Feb
	[ "date.month.2" ] = "fev.",

	-- en: Mar
	[ "date.month.3" ] = "mar.",

	-- en: Apr
	[ "date.month.4" ] = "abr.",

	-- en: May
	[ "date.month.5" ] = "mai.",

	-- en: Jun
	[ "date.month.6" ] = "jun.",

	-- en: Jul
	[ "date.month.7" ] = "jul.",

	-- en: Aug
	[ "date.month.8" ] = "ago.",

	-- en: Sep
	[ "date.month.9" ] = "set.",

	-- en: Oct
	[ "date.month.10" ] = "out.",

	-- en: Nov
	[ "date.month.11" ] = "nov.",

	-- en: Dec
	[ "date.month.12" ] = "dez.",

	-- full month names (%B), usually written right after a day number
	-- en: January
	[ "date.month_full.1" ] = "janeiro",

	-- en: February
	[ "date.month_full.2" ] = "fevereiro",

	-- en: March
	[ "date.month_full.3" ] = "março",

	-- en: April
	[ "date.month_full.4" ] = "abril",

	-- en: May
	[ "date.month_full.5" ] = "maio",

	-- en: June
	[ "date.month_full.6" ] = "junho",

	-- en: July
	[ "date.month_full.7" ] = "julho",

	-- en: August
	[ "date.month_full.8" ] = "agosto",

	-- en: September
	[ "date.month_full.9" ] = "setembro",

	-- en: October
	[ "date.month_full.10" ] = "outubro",

	-- en: November
	[ "date.month_full.11" ] = "novembro",

	-- en: December
	[ "date.month_full.12" ] = "dezembro",

	-- Kinds of surface material (the game's material types), shown as "World - Concrete"
	-- en: Antlion
	[ "mat.antlion" ] = "Formiga-leão",

	-- en: Bloody flesh
	[ "mat.bloodyflesh" ] = "Carne ensanguentada",

	-- en: Concrete
	[ "mat.concrete" ] = "Concreto",

	-- en: Dirt
	[ "mat.dirt" ] = "Terra",

	-- en: Eggshell
	[ "mat.eggshell" ] = "Casca de ovo",

	-- en: Flesh
	[ "mat.flesh" ] = "Carne",

	-- en: Grate
	[ "mat.grate" ] = "Grade",

	-- en: Alien flesh
	[ "mat.alienflesh" ] = "Carne alienígena",

	-- en: Clip
	[ "mat.clip" ] = "Parede invisível",

	-- en: Snow
	[ "mat.snow" ] = "Neve",

	-- en: Plastic
	[ "mat.plastic" ] = "Plástico",

	-- en: Metal
	[ "mat.metal" ] = "Metal",

	-- en: Sand
	[ "mat.sand" ] = "Areia",

	-- en: Foliage
	[ "mat.foliage" ] = "Folhagem",

	-- en: Computer
	[ "mat.computer" ] = "Eletrônicos",

	-- en: Liquid
	[ "mat.slosh" ] = "Líquido",

	-- en: Tile
	[ "mat.tile" ] = "Azulejo",

	-- en: Grass
	[ "mat.grass" ] = "Grama",

	-- en: Vent
	[ "mat.vent" ] = "Ventilação",

	-- en: Wood
	[ "mat.wood" ] = "Madeira",

	-- en: Generic
	[ "mat.default" ] = "Genérico",

	-- en: Glass
	[ "mat.glass" ] = "Vidro",

	-- en: Warp shield
	[ "mat.warpshield" ] = "Escudo de distorção",

	-- Notifications on the screen
	-- en: Tracking {name}
	[ "notify.tracking" ] = "Rastreando: {name}",

	-- en: Stopped tracking
	[ "notify.untracked" ] = "Rastreamento encerrado",

	-- en: Layout: {name}
	[ "notify.layout" ] = "Layout: {name}",

	-- en: Theme: {name}
	[ "notify.theme" ] = "Tema: {name}",

	-- title bar: tool category, or the game's name when there is none (keep "Garry's Mod")
	-- en: {tool_category|Garry's Mod}
	[ "tpl.title" ] = "{tool_category|Garry's Mod}",

	-- left link of the Pocket PC screen: the previous tool
	-- en: Back to {tool_prev}
	[ "tpl.nav_back" ] = "Voltar para {tool_prev}",

	-- en: Props {props}/{props_max}
	[ "tpl.props" ] = "Objetos {props}/{props_max}",

	-- en: {fps} fps  {ping} ms
	[ "tpl.perf" ] = "{fps} FPS  {ping} ms",

	-- en: Slope {aim_slope}
	[ "tpl.slope" ] = "Inclinação {aim_slope}",

	-- en: HP {ent_health}
	[ "tpl.hp" ] = "Vida {ent_health}",

	-- en: Owner: {ent_owner}
	[ "tpl.owner" ] = "Dono: {ent_owner}",

	-- HP = health, AP = armor
	-- en: HP {health}  AP {armor}
	[ "tpl.health_armor" ] = "Vida {health}  Proteção {armor}",

	-- en: {players} players
	[ "tpl.players" ] = "Jogadores: {players}",

	-- Terminal lines: a short upper case label, a tab, then the value
	-- en: TOOL\t**{tool}**
	[ "tpl.term_tool" ] = "FERRAM\t**{tool}**",

	-- en: AIM\t**{aim_what}**
	[ "tpl.term_aim" ] = "ALVO\t**{aim_what}**",

	-- en: CLASS\t**{ent_class|-}**
	[ "tpl.term_class" ] = "CLASSE\t**{ent_class|-}**",

	-- en: POS\t**{aim_pos}**
	[ "tpl.term_pos" ] = "POS\t**{aim_pos}**",

	-- en: DIST\t**{aim_dist}**  {aim_slope}
	[ "tpl.term_dist" ] = "DIST\t**{aim_dist}**  {aim_slope}",

	-- en: OWNER\t**{ent_owner|-}**
	[ "tpl.term_owner" ] = "DONO\t**{ent_owner|-}**",

	-- en: HP\t**{ent_health|-}**
	[ "tpl.term_hp" ] = "VIDA\t**{ent_health|-}**",

	-- en: TRACK\t**{track_name|-}** {track_dist}
	[ "tpl.term_track" ] = "RASTREIO\t**{track_name|-}** {track_dist}",

	-- en: Pocket PC
	[ "layout.pocketpc.name" ] = "Pocket PC",

	-- en: The original screen rebuilt with live data: clock, status icons, tool history links, big tool name, status line, six readouts and a hint bar.
	[ "layout.pocketpc.desc" ] = "A tela original reconstruída com dados ao vivo: relógio, ícones de status, links do histórico de ferramentas, nome grande da ferramenta, linha de status, seis indicadores e uma barra de dicas.",

	-- en: Title bar
	[ "layout.pocketpc.title" ] = "Barra de título",

	-- en: Clock
	[ "layout.pocketpc.clock" ] = "Relógio",

	-- en: Left link
	[ "layout.pocketpc.nav_l" ] = "Link esquerdo",

	-- en: Right link
	[ "layout.pocketpc.nav_r" ] = "Link direito",

	-- en: Big text
	[ "layout.pocketpc.hero" ] = "Texto grande",

	-- en: Under the big text
	[ "layout.pocketpc.sub" ] = "Abaixo do texto grande",

	-- en: Status line
	[ "layout.pocketpc.status" ] = "Linha de status",

	-- en: Readout, left 1
	[ "layout.pocketpc.l1" ] = "Indicador, esquerda 1",

	-- en: Readout, left 2
	[ "layout.pocketpc.l2" ] = "Indicador, esquerda 2",

	-- en: Readout, left 3
	[ "layout.pocketpc.l3" ] = "Indicador, esquerda 3",

	-- en: Readout, right 1
	[ "layout.pocketpc.r1" ] = "Indicador, direita 1",

	-- en: Readout, right 2
	[ "layout.pocketpc.r2" ] = "Indicador, direita 2",

	-- en: Readout, right 3
	[ "layout.pocketpc.r3" ] = "Indicador, direita 3",

	-- en: Menu bar
	[ "layout.pocketpc.menu" ] = "Barra de menu",

	-- en: Terminal
	[ "layout.terminal.name" ] = "Terminal",

	-- en: Developer readout: eight lines of labels and values, an FPS graph and a prompt line with the tool hints.
	[ "layout.terminal.desc" ] = "Painel para desenvolvedores: oito linhas de rótulos e valores, um gráfico de FPS e uma linha de comando com as dicas da ferramenta.",

	-- en: Header
	[ "layout.terminal.head" ] = "Cabeçalho",

	-- en: Header, right
	[ "layout.terminal.clock" ] = "Cabeçalho, direita",

	-- en: Line 1
	[ "layout.terminal.l1" ] = "Linha 1",

	-- en: Line 2
	[ "layout.terminal.l2" ] = "Linha 2",

	-- en: Line 3
	[ "layout.terminal.l3" ] = "Linha 3",

	-- en: Line 4
	[ "layout.terminal.l4" ] = "Linha 4",

	-- en: Line 5
	[ "layout.terminal.l5" ] = "Linha 5",

	-- en: Line 6
	[ "layout.terminal.l6" ] = "Linha 6",

	-- en: Line 7
	[ "layout.terminal.l7" ] = "Linha 7",

	-- en: Line 8
	[ "layout.terminal.l8" ] = "Linha 8",

	-- en: Prompt line
	[ "layout.terminal.foot" ] = "Linha de comando",

	-- en: Minimal
	[ "layout.minimal.name" ] = "Minimalista",

	-- en: Large, glanceable text: clock, compass, the tool name sized to fit, what you aim at and two corner values.
	[ "layout.minimal.desc" ] = "Texto grande, legível num relance: relógio, bússola, o nome da ferramenta ajustado ao espaço, onde você está mirando e dois valores nos cantos.",

	-- en: Top left
	[ "layout.minimal.top_l" ] = "Superior esquerdo",

	-- en: Top right
	[ "layout.minimal.top_r" ] = "Superior direito",

	-- en: Big text
	[ "layout.minimal.hero" ] = "Texto grande",

	-- en: Under the big text
	[ "layout.minimal.sub" ] = "Abaixo do texto grande",

	-- en: Bottom left
	[ "layout.minimal.foot_l" ] = "Inferior esquerdo",

	-- en: Bottom right
	[ "layout.minimal.foot_r" ] = "Inferior direito",

	-- en: Pocket PC (original)
	[ "theme.winmobile" ] = "Pocket PC (original)",

	-- en: Graphite
	[ "theme.graphite" ] = "Grafite",

	-- en: Green phosphor
	[ "theme.phosphor" ] = "Fósforo verde",

	-- en: Amber CRT
	[ "theme.amber" ] = "CRT âmbar",

	-- en: Sakura
	[ "theme.sakura" ] = "Sakura",

	-- en: Sandbox blue
	[ "theme.sandbox" ] = "Azul Sandbox",

	-- parts of the screen whose colour can be changed
	-- en: Title bar
	[ "color.bar" ] = "Barra de título",

	-- en: Links and highlights
	[ "color.accent" ] = "Links e destaques",

	-- en: Big text
	[ "color.hero" ] = "Texto grande",

	-- en: Status line
	[ "color.strip" ] = "Linha de status",

	-- en: Readout panel
	[ "color.panel" ] = "Painel de indicadores",

	-- en: Menu bar
	[ "color.menu" ] = "Barra de menu",

	-- en: Terminal text
	[ "color.term" ] = "Texto do terminal",

	-- en: Text
	[ "category.text" ] = "Texto",

	-- en: Time
	[ "category.time" ] = "Tempo",

	-- en: Tool
	[ "category.tool" ] = "Ferramenta",

	-- en: Aim
	[ "category.aim" ] = "Mira",

	-- en: Aimed entity
	[ "category.entity" ] = "Entidade na mira",

	-- en: Tracked entity
	[ "category.tracked" ] = "Entidade rastreada",

	-- en: You
	[ "category.player" ] = "Você",

	-- en: Game
	[ "category.game" ] = "Jogo",

	-- the Advanced Toolgun [Hotbar] addon; keep its name as it is
	-- en: Advanced Toolgun
	[ "category.atg" ] = "Advanced Toolgun",

	-- en: A line in your language from the language files, e.g. {tr:nav_back} or {tr:props}.
	[ "token.tr" ] = "Uma linha no seu idioma, vinda dos arquivos de idioma, ex.: {tr:nav_back} ou {tr:props}.",

	-- en: Local time, formatted by the clock settings. {time:%H:%M:%S} takes an os.date format.
	[ "token.time" ] = "Hora local, no formato das configurações do relógio. {time:%H:%M:%S} aceita um formato os.date.",

	-- en: Today's date. {date:%Y-%m-%d} takes an os.date format.
	[ "token.date" ] = "Data de hoje. {date:%Y-%m-%d} aceita um formato os.date.",

	-- en: How long you have been in this game.
	[ "token.session" ] = "Há quanto tempo você está neste jogo.",

	-- en: How long the map has been running.
	[ "token.map_time" ] = "Há quanto tempo o mapa está rodando.",

	-- en: Name of the selected tool.
	[ "token.tool" ] = "Nome da ferramenta selecionada.",

	-- en: Internal name of the selected tool.
	[ "token.tool_id" ] = "Nome interno da ferramenta selecionada.",

	-- en: Description of the selected tool.
	[ "token.tool_desc" ] = "Descrição da ferramenta selecionada.",

	-- en: Tool menu category of the selected tool.
	[ "token.tool_category" ] = "Categoria da ferramenta selecionada no menu de ferramentas.",

	-- en: Stage of the selected tool (0 = nothing selected yet).
	[ "token.tool_stage" ] = "Etapa da ferramenta selecionada (0 = nada selecionado ainda).",

	-- en: The stage while a multi-click tool is in progress, otherwise empty.
	[ "token.tool_progress" ] = "A etapa enquanto uma ferramenta de vários cliques está em uso; caso contrário, vazio.",

	-- en: The tool you used before this one (dts_tool_back switches to it).
	[ "token.tool_prev" ] = "A ferramenta que você usou antes desta (dts_tool_back volta para ela).",

	-- en: The next tool in the same menu category (dts_tool_next switches to it).
	[ "token.tool_next" ] = "A próxima ferramenta da mesma categoria do menu (dts_tool_next muda para ela).",

	-- en: Successful tool gun shots this session.
	[ "token.tool_uses" ] = "Disparos bem-sucedidos da Arma de Ferramentas nesta sessão.",

	-- en: A setting of the selected tool, e.g. {tool_cvar:forcelimit} reads weld_forcelimit.
	[ "token.tool_cvar" ] = "Uma configuração da ferramenta selecionada, ex.: {tool_cvar:forcelimit} lê weld_forcelimit.",

	-- en: All settings of the selected tool as name=value pairs.
	[ "token.tool_settings" ] = "Todas as configurações da ferramenta selecionada como pares nome=valor.",

	-- en: The current stage's instructions with mouse and key icons.
	[ "token.hints" ] = "As instruções da etapa atual com ícones de mouse e teclas.",

	-- en: What left click does right now.
	[ "token.hint_left" ] = "O que o clique esquerdo faz agora.",

	-- en: What right click does right now.
	[ "token.hint_right" ] = "O que o clique direito faz agora.",

	-- en: What reload does right now.
	[ "token.hint_reload" ] = "O que a tecla de recarregar faz agora.",

	-- en: What you are aiming at, with the name highlighted.
	[ "token.target" ] = "Para onde você está mirando, com o nome destacado.",

	-- en: Entity name, or the surface material when aiming at the world.
	[ "token.aim_what" ] = "Nome da entidade, ou o material da superfície ao mirar no mundo.",

	-- en: Position you are aiming at.
	[ "token.aim_pos" ] = "Posição na sua mira.",

	-- en: X of the aim position.
	[ "token.aim_x" ] = "X da posição na mira.",

	-- en: Y of the aim position.
	[ "token.aim_y" ] = "Y da posição na mira.",

	-- en: Z of the aim position.
	[ "token.aim_z" ] = "Z da posição na mira.",

	-- en: Distance to the aim position.
	[ "token.aim_dist" ] = "Distância até a posição na mira.",

	-- en: Surface normal at the aim position.
	[ "token.aim_normal" ] = "Normal da superfície na posição na mira.",

	-- en: Steepness of the surface (0 = flat floor, 90 = wall).
	[ "token.aim_slope" ] = "Inclinação da superfície (0 = chão plano, 90 = parede).",

	-- en: Kind of surface material (metal, wood, concrete...).
	[ "token.aim_surface" ] = "Tipo de material da superfície (metal, madeira, concreto...).",

	-- en: Surface property as the engine names it (metal box, wood crate...).
	[ "token.aim_surfaceprop" ] = "Propriedade da superfície com o nome usado pelo motor (metal box, wood crate...).",

	-- en: World texture you are aiming at.
	[ "token.aim_texture" ] = "Textura do mundo na sua mira.",

	-- en: Friendly name of the aimed entity.
	[ "token.ent_name" ] = "Nome legível da entidade na mira.",

	-- en: Class of the aimed entity.
	[ "token.ent_class" ] = "Classe da entidade na mira.",

	-- en: Model file name of the aimed entity.
	[ "token.ent_model" ] = "Nome do arquivo de modelo da entidade na mira.",

	-- en: Full model path of the aimed entity.
	[ "token.ent_model_path" ] = "Caminho completo do modelo da entidade na mira.",

	-- en: Entity index.
	[ "token.ent_index" ] = "Índice da entidade.",

	-- en: Health of the aimed entity (players, NPCs, breakable props).
	[ "token.ent_health" ] = "Vida da entidade na mira (jogadores, NPCs, objetos quebráveis).",

	-- en: Owner of the aimed entity (in multiplayer this needs a CPPI prop protection addon).
	[ "token.ent_owner" ] = "Dono da entidade na mira (no multijogador, é preciso um addon de proteção de objetos com CPPI).",

	-- en: Material of the aimed entity.
	[ "token.ent_material" ] = "Material da entidade na mira.",

	-- en: Colour of the aimed entity.
	[ "token.ent_color" ] = "Cor da entidade na mira.",

	-- en: Skin of the aimed entity.
	[ "token.ent_skin" ] = "Aparência (skin) da entidade na mira.",

	-- en: Speed of the aimed entity.
	[ "token.ent_speed" ] = "Velocidade da entidade na mira.",

	-- en: Position of the aimed entity.
	[ "token.ent_pos" ] = "Posição da entidade na mira.",

	-- en: Angles of the aimed entity.
	[ "token.ent_ang" ] = "Ângulos da entidade na mira.",

	-- en: Mass of the aimed entity, when your game knows its physics.
	[ "token.ent_mass" ] = "Massa da entidade na mira, quando o seu jogo conhece a física dela.",

	-- en: Tracked entity summary: name, distance, speed, health.
	[ "token.track" ] = "Resumo da entidade rastreada: nome, distância, velocidade, vida.",

	-- en: Name of the tracked entity.
	[ "token.track_name" ] = "Nome da entidade rastreada.",

	-- en: Class of the tracked entity.
	[ "token.track_class" ] = "Classe da entidade rastreada.",

	-- en: Your distance to the tracked entity.
	[ "token.track_dist" ] = "Sua distância até a entidade rastreada.",

	-- en: Speed of the tracked entity.
	[ "token.track_speed" ] = "Velocidade da entidade rastreada.",

	-- en: Health of the tracked entity.
	[ "token.track_health" ] = "Vida da entidade rastreada.",

	-- en: Position of the tracked entity.
	[ "token.track_pos" ] = "Posição da entidade rastreada.",

	-- en: Your name.
	[ "token.player" ] = "Seu nome.",

	-- en: Your health.
	[ "token.health" ] = "Sua vida.",

	-- en: Your armor.
	[ "token.armor" ] = "Sua proteção.",

	-- en: Your speed.
	[ "token.speed" ] = "Sua velocidade.",

	-- en: Your position.
	[ "token.pos" ] = "Sua posição.",

	-- en: Your view pitch and yaw.
	[ "token.eye_ang" ] = "Arfagem e guinada da sua visão.",

	-- en: Compass heading (north is +Y on the map).
	[ "token.heading" ] = "Rumo da bússola (o norte é +Y no mapa).",

	-- en: Shows a word while you are noclipping, otherwise empty.
	[ "token.noclip" ] = "Mostra uma palavra enquanto o No Clip está ativo; caso contrário, vazio.",

	-- en: Frames per second (smoothed).
	[ "token.fps" ] = "Quadros por segundo (suavizados).",

	-- en: Your ping in milliseconds.
	[ "token.ping" ] = "Seu ping em milissegundos.",

	-- en: Your device's battery charge while it runs on battery, or \"Plugged in\".
	[ "token.battery" ] = "A carga da bateria do seu aparelho quando ele funciona na bateria, ou “Na tomada”.",

	-- en: Current map.
	[ "token.map" ] = "Mapa atual.",

	-- en: Players on the server and its player limit.
	[ "token.players" ] = "Jogadores no servidor e o limite de jogadores.",

	-- en: Server name.
	[ "token.server" ] = "Nome do servidor.",

	-- en: Active gamemode.
	[ "token.gamemode" ] = "Modo de jogo ativo.",

	-- en: Server tick rate.
	[ "token.tickrate" ] = "Tickrate do servidor.",

	-- en: Memory used by Lua in your game.
	[ "token.lua_mem" ] = "Memória usada pela Lua no seu jogo.",

	-- en: Entities known to your game.
	[ "token.entities" ] = "Entidades que o seu jogo conhece.",

	-- en: Props you have spawned.
	[ "token.props" ] = "Objetos que você criou.",

	-- en: Your prop limit.
	[ "token.props_max" ] = "Seu limite de objetos.",

	-- en: Spawn count and limit of a type, e.g. {count:ragdolls} or {count:thrusters}.
	[ "token.count" ] = "Quantidade e limite de um tipo, ex.: {count:ragdolls} ou {count:thrusters}.",

	-- en: Value of any console variable, e.g. {cvar:sv_gravity}.
	[ "token.cvar" ] = "Valor de qualquer variável de console, ex.: {cvar:sv_gravity}.",

	-- en: Advanced Toolgun [Hotbar]: its open tab (Tools, Wire or Favorites).
	[ "token.atg_tab" ] = "Advanced Toolgun [Hotbar]: a aba aberta dele (Ferramentas, Wire ou Favoritos).",

	-- en: Advanced Toolgun [Hotbar]: the section of its list the selection is in.
	[ "token.atg_section" ] = "Advanced Toolgun [Hotbar]: a seção da lista dele em que está a seleção.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel up.
	[ "token.atg_prev" ] = "Advanced Toolgun [Hotbar]: a ferramenta para a qual a seleção rápida dele vai com a roda do mouse para cima.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel down.
	[ "token.atg_next" ] = "Advanced Toolgun [Hotbar]: a ferramenta para a qual a seleção rápida dele vai com a roda do mouse para baixo.",

	-- en: Turns the tool gun's mini screen into a live display. Changes apply instantly; the preview shows what the screen draws right now.
	[ "menu.intro" ] = "Transforma a pequena tela da Arma de Ferramentas em um painel ao vivo. As mudanças valem na hora; a prévia mostra o que a tela está desenhando agora.",

	-- en: Dynamic screen is off
	[ "menu.preview_off" ] = "A tela dinâmica está desligada",

	-- en: Enable the dynamic screen
	[ "menu.enable" ] = "Ativar a tela dinâmica",

	-- en: Language
	[ "menu.language" ] = "Idioma",

	-- first entry of the language list; {name} is the game's language, e.g. "English"
	-- en: Automatic: {name}
	[ "menu.language.auto" ] = "Automático: {name}",

	-- en: Inspect: read the screen up close
	[ "menu.inspect.title" ] = "Examinar: ler a tela de perto",

	-- en: Hold a key while holding the tool gun to raise its screen to your eyes.
	[ "menu.inspect.help" ] = "Segure uma tecla enquanto empunha a Arma de Ferramentas para levar a tela até os olhos.",

	-- en: Inspect key
	[ "menu.inspect.key" ] = "Tecla para examinar",

	-- en: Screen size while inspecting
	[ "menu.inspect.size" ] = "Tamanho da tela ao examinar",

	-- en: Or use the console: bind <key> +dts_inspect (hold) or dts_inspect_toggle.
	[ "menu.inspect.console" ] = "Ou pelo console: bind <tecla> +dts_inspect (segurar) ou dts_inspect_toggle.",

	-- the tool gun model has a paper note glued on, which overlaps the screen's top right corner
	-- en: Screen in front of the paper note
	[ "menu.inspect.on_top" ] = "Tela na frente do bilhete de papel",

	-- en: While inspecting, the whole screen stays readable. Untick to let the paper note glued to the tool gun cover the top right corner of the screen, as on the model.
	[ "menu.inspect.on_top_help" ] = "Ao examinar, a tela inteira fica legível. Desmarque para que o bilhete de papel colado na Arma de Ferramentas cubra o canto superior direito da tela, como no modelo.",

	-- en: Layout and look
	[ "menu.look.title" ] = "Layout e aparência",

	-- en: Layout
	[ "menu.look.layout" ] = "Layout",

	-- en: Theme
	[ "menu.look.theme" ] = "Tema",

	-- en: Background
	[ "menu.look.background" ] = "Fundo",

	-- en: Automatic (layout's choice)
	[ "menu.bg.auto" ] = "Automático (escolha do layout)",

	-- the whole original screen picture without its text
	-- en: Original screen
	[ "menu.bg.original" ] = "Tela original",

	-- only the blurred photo from the original picture, filling the screen
	-- en: Original photo
	[ "menu.bg.art" ] = "Foto original",

	-- en: Theme gradient
	[ "menu.bg.gradient" ] = "Degradê do tema",

	-- en: Live camera: zoom
	[ "menu.bg.camera" ] = "Câmera ao vivo: zoom",

	-- en: Live camera: rear view
	[ "menu.bg.rear" ] = "Câmera ao vivo: visão traseira",

	-- en: Custom image
	[ "menu.bg.image" ] = "Imagem personalizada",

	-- en: Black
	[ "menu.bg.black" ] = "Preto",

	-- en: Custom image
	[ "menu.look.image" ] = "Imagem personalizada",

	-- en: A material path, or an image in garrysmod/data written as ../data/name.png
	[ "menu.look.image_help" ] = "Um caminho de material, ou uma imagem em garrysmod/data escrita como ../data/nome.png",

	-- en: Darken background
	[ "menu.look.dim" ] = "Escurecer o fundo",

	-- en: Camera field of view
	[ "menu.look.cam_fov" ] = "Campo de visão da câmera",

	-- en: Camera updates per second
	[ "menu.look.cam_fps" ] = "Atualizações da câmera por segundo",

	-- en: Text font
	[ "menu.look.font" ] = "Fonte do texto",

	-- en: Big text font
	[ "menu.look.font_hero" ] = "Fonte do texto grande",

	-- en: Terminal font
	[ "menu.look.font_mono" ] = "Fonte do terminal",

	-- first entry of the font lists; {font} is the font your language uses
	-- en: Automatic ({font})
	[ "menu.font.auto" ] = "Automática ({font})",

	-- en: Colours
	[ "menu.colors.title" ] = "Cores",

	-- en: Override single colours of the theme. Click a swatch to change it.
	[ "menu.colors.help" ] = "Substitua cores avulsas do tema. Clique em uma amostra para alterá-la.",

	-- written on a colour swatch that still uses the theme's colour
	-- en: theme
	[ "menu.colors.theme_tag" ] = "tema",

	-- en: Click to pick a colour
	[ "menu.colors.pick" ] = "Clique para escolher uma cor",

	-- en: Use the theme's colours everywhere
	[ "menu.colors.reset_all" ] = "Usar as cores do tema em tudo",

	-- en: Screen colour: {name}
	[ "menu.colors.picker_title" ] = "Cor da tela: {name}",

	-- en: Use the theme's colour
	[ "menu.colors.use_theme" ] = "Usar a cor do tema",

	-- en: Big text
	[ "menu.hero.title" ] = "Texto grande",

	-- en: Behaviour
	[ "menu.hero.mode" ] = "Comportamento",

	-- en: Always scroll (original)
	[ "menu.hero.scroll" ] = "Sempre rolar (original)",

	-- en: Scroll only when too long
	[ "menu.hero.auto" ] = "Rolar só quando não couber",

	-- en: Shrink to fit
	[ "menu.hero.fit" ] = "Reduzir para caber",

	-- en: Scroll speed
	[ "menu.hero.speed" ] = "Velocidade de rolagem",

	-- en: Upper case tool names
	[ "menu.hero.upper" ] = "Nomes de ferramentas em maiúsculas",

	-- en: Screen content
	[ "menu.content.title" ] = "Conteúdo da tela",

	-- keep {tokens}, **stars**, {token|fallback} and {tr:...} as they are: they show the syntax
	-- en: Every line of the {layout} layout is a template. Type text and {tokens}; **stars** highlight text, {token|fallback} gives a default, and a line whose tokens are all empty hides itself. {tr:...} writes a line in your language. See the token reference below.
	[ "menu.content.help" ] = "Cada linha do layout “{layout}” é um modelo. Digite texto e {tokens}; **asteriscos** destacam texto, {token|fallback} define um valor padrão, e uma linha cujos tokens estão todos vazios se esconde sozinha. {tr:...} escreve uma linha no seu idioma. Veja a lista de tokens abaixo.",

	-- en: Pick a ready-made line
	[ "menu.content.presets_tip" ] = "Escolher uma linha pronta",

	-- en: Back to the default: {value}
	[ "menu.content.reset_tip" ] = "Voltar ao padrão: {value}",

	-- en: (empty)
	[ "menu.content.empty" ] = "(vazia)",

	-- shown in an empty line's text box
	-- en: (hidden)
	[ "menu.content.placeholder" ] = "(oculta)",

	-- under each line: what it shows right now
	-- en: = {text}
	[ "menu.content.now" ] = "= {text}",

	-- en: (hidden right now)
	[ "menu.content.hidden_now" ] = "(oculta no momento)",

	-- en: Reset these lines to the layout's defaults
	[ "menu.content.reset_all" ] = "Restaurar as linhas padrão do layout",

	-- ready-made lines in the list next to each line
	-- en: Tool name
	[ "menu.preset.tool" ] = "Nome da ferramenta",

	-- en: Tool category
	[ "menu.preset.tool_category" ] = "Categoria da ferramenta",

	-- en: Tool instructions
	[ "menu.preset.hints" ] = "Instruções da ferramenta",

	-- en: Previous tool
	[ "menu.preset.prev_tool" ] = "Ferramenta anterior",

	-- en: Next tool
	[ "menu.preset.next_tool" ] = "Próxima ferramenta",

	-- en: Tool progress
	[ "menu.preset.progress" ] = "Progresso da ferramenta",

	-- en: Tool settings
	[ "menu.preset.tool_settings" ] = "Configurações da ferramenta",

	-- en: What you aim at
	[ "menu.preset.target" ] = "Para onde você mira",

	-- en: Aim position
	[ "menu.preset.aim_pos" ] = "Posição na mira",

	-- en: Aim distance
	[ "menu.preset.aim_dist" ] = "Distância da mira",

	-- en: Entity or surface
	[ "menu.preset.aim_what" ] = "Entidade ou superfície",

	-- en: Surface slope
	[ "menu.preset.slope" ] = "Inclinação da superfície",

	-- en: Entity class
	[ "menu.preset.ent_class" ] = "Classe da entidade",

	-- en: Entity model
	[ "menu.preset.ent_model" ] = "Modelo da entidade",

	-- en: Entity health
	[ "menu.preset.ent_health" ] = "Vida da entidade",

	-- en: Entity owner
	[ "menu.preset.ent_owner" ] = "Dono da entidade",

	-- en: Entity speed
	[ "menu.preset.ent_speed" ] = "Velocidade da entidade",

	-- en: Tracked entity
	[ "menu.preset.track" ] = "Entidade rastreada",

	-- en: Clock
	[ "menu.preset.clock" ] = "Relógio",

	-- en: Clock with seconds
	[ "menu.preset.clock_seconds" ] = "Relógio com segundos",

	-- en: Date
	[ "menu.preset.date" ] = "Data",

	-- en: Time in game
	[ "menu.preset.session" ] = "Tempo de jogo",

	-- en: Your speed
	[ "menu.preset.speed" ] = "Sua velocidade",

	-- en: Your position
	[ "menu.preset.pos" ] = "Sua posição",

	-- en: Compass
	[ "menu.preset.heading" ] = "Bússola",

	-- en: Health and armor
	[ "menu.preset.health_armor" ] = "Vida e proteção",

	-- en: FPS and ping
	[ "menu.preset.perf" ] = "FPS e ping",

	-- en: Prop count
	[ "menu.preset.props" ] = "Contagem de objetos",

	-- en: Map
	[ "menu.preset.map" ] = "Mapa",

	-- en: Players
	[ "menu.preset.players" ] = "Jogadores",

	-- en: Empty (hide the line)
	[ "menu.preset.empty" ] = "Vazia (esconder a linha)",

	-- en: Clock and units
	[ "menu.clock.title" ] = "Relógio e unidades",

	-- en: Clock
	[ "menu.clock.style" ] = "Relógio",

	-- {language} is the name of the active language
	-- en: As usual in {language}
	[ "menu.clock.auto" ] = "Padrão do idioma ({language})",

	-- en: 12 hour
	[ "menu.clock.12h" ] = "12 horas",

	-- en: 24 hour
	[ "menu.clock.24h" ] = "24 horas",

	-- en: Show seconds
	[ "menu.clock.seconds" ] = "Mostrar segundos",

	-- en: Show AM / PM (12 hour clock)
	[ "menu.clock.ampm" ] = "Mostrar AM / PM (relógio de 12 horas)",

	-- en: Blink the colon
	[ "menu.clock.blink" ] = "Piscar os dois-pontos",

	-- en: Units
	[ "menu.units.label" ] = "Unidades",

	-- en: Metric (m, km/h)
	[ "menu.units.m" ] = "Métricas (m, km/h)",

	-- en: Imperial (ft, mph)
	[ "menu.units.ft" ] = "Imperiais (ft, mph)",

	-- en: Hammer units
	[ "menu.units.hu" ] = "Unidades do Hammer",

	-- en: Distance decimals
	[ "menu.units.decimals" ] = "Casas decimais das distâncias",

	-- en: Icons and effects
	[ "menu.fx.title" ] = "Ícones e efeitos",

	-- en: Speaker icon (volume, voice chat)
	[ "menu.fx.speaker" ] = "Ícone de alto-falante (volume, chat de voz)",

	-- en: Signal icon (connection)
	[ "menu.fx.signal" ] = "Ícone de sinal (conexão)",

	-- en: Battery icon (your device's battery)
	[ "menu.fx.battery" ] = "Ícone de bateria (a bateria do seu aparelho)",

	-- en: Boot animation when taking out the tool gun
	[ "menu.fx.boot" ] = "Animação de inicialização ao sacar a Arma de Ferramentas",

	-- en: Flash when the tool gun fires
	[ "menu.fx.flash" ] = "Clarão quando a Arma de Ferramentas dispara",

	-- en: Show game notifications on the screen
	[ "menu.fx.notify" ] = "Mostrar as notificações do jogo na tela",

	-- en: Notification time
	[ "menu.fx.notify_time" ] = "Duração das notificações",

	-- en: Scanlines
	[ "menu.fx.scanlines" ] = "Linhas de varredura",

	-- en: Darker edges
	[ "menu.fx.vignette" ] = "Bordas mais escuras",

	-- en: Backlight
	[ "menu.fx.backlight" ] = "Luz de fundo",

	-- en: HUD mirror
	[ "menu.mirror.title" ] = "Espelho no HUD",

	-- en: Shows the screen on your HUD while you hold the tool gun, for reading the small print.
	[ "menu.mirror.help" ] = "Mostra a tela também no seu HUD enquanto você segura a Arma de Ferramentas, para ler as letras miúdas.",

	-- en: Show the screen on the HUD
	[ "menu.mirror.enable" ] = "Mostrar a tela no HUD",

	-- en: Corner
	[ "menu.mirror.corner" ] = "Canto",

	-- en: Top right
	[ "menu.corner.tr" ] = "Superior direito",

	-- en: Bottom right
	[ "menu.corner.br" ] = "Inferior direito",

	-- en: Bottom left
	[ "menu.corner.bl" ] = "Inferior esquerdo",

	-- en: Top left
	[ "menu.corner.tl" ] = "Superior esquerdo",

	-- en: Size
	[ "menu.mirror.size" ] = "Tamanho",

	-- en: Opacity
	[ "menu.mirror.alpha" ] = "Opacidade",

	-- en: Advanced
	[ "menu.adv.title" ] = "Avançado",

	-- en: Keep the own screens of tools that draw one
	[ "menu.adv.respect" ] = "Manter a tela própria das ferramentas que desenham uma",

	-- en: e.g. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod tools
	[ "menu.adv.respect_help" ] = "ex.: Easy Entity Inspector, Ragdoll Puppeteer, ferramentas do Wiremod",

	-- en: Live value updates per second
	[ "menu.adv.refresh" ] = "Atualizações dos valores por segundo",

	-- en: Screen redraws per second (0 = every frame)
	[ "menu.adv.fps" ] = "Redesenhos da tela por segundo (0 = todo quadro)",

	-- en: Resolution
	[ "menu.adv.resolution" ] = "Resolução",

	-- en: 256 x 256 (original)
	[ "menu.res.256" ] = "256 x 256 (original)",

	-- en: 512 x 512 (sharper, for 1440p and up)
	[ "menu.res.512" ] = "512 x 512 (mais nítida, para 1440p ou mais)",

	-- keep the commands as they are
	-- en: Key binds (bind <key> <command>):\n  dts_tool_back  -  previous tool\n  dts_tool_next / dts_tool_prev  -  cycle the category\n  dts_layout_next, dts_theme_next  -  cycle layouts, themes\n  dts_track / dts_untrack  -  follow an entity
	[ "menu.adv.binds" ] = "Atalhos de teclas (bind <tecla> <comando>):\n  dts_tool_back  -  ferramenta anterior\n  dts_tool_next / dts_tool_prev  -  percorrer a categoria\n  dts_layout_next, dts_theme_next  -  alternar layouts, temas\n  dts_track / dts_untrack  -  rastrear uma entidade",

	-- en: Copy my settings to the clipboard
	[ "menu.adv.copy" ] = "Copiar minhas configurações para a área de transferência",

	-- en: Screen settings copied to the clipboard
	[ "menu.adv.copied" ] = "Configurações da tela copiadas para a área de transferência",

	-- en: Import settings...
	[ "menu.adv.import" ] = "Importar configurações...",

	-- en: Import screen settings
	[ "menu.adv.import_title" ] = "Importar configurações da tela",

	-- en: Paste a DTS1:... settings string
	[ "menu.adv.import_prompt" ] = "Cole um texto de configurações DTS1:...",

	-- en: Import
	[ "menu.adv.import_ok" ] = "Importar",

	-- en: Imported screen settings ({n} changed)
	[ "menu.adv.imported" ] = "Configurações da tela importadas ({n} alteradas)",

	-- en: Reset everything to defaults
	[ "menu.adv.reset" ] = "Restaurar tudo ao padrão",

	-- en: Reset
	[ "menu.adv.reset_title" ] = "Restaurar",

	-- en: Reset every Dynamic Toolgun Screen setting?
	[ "menu.adv.reset_question" ] = "Restaurar todas as configurações da Tela dinâmica da Arma de Ferramentas?",

	-- en: Reset
	[ "menu.adv.reset_yes" ] = "Restaurar",

	-- en: Cancel
	[ "menu.adv.cancel" ] = "Cancelar",

	-- en: Another addon replaced the tool gun screen ({file}). Use the button below to take over.
	[ "menu.adv.diag_conflict" ] = "Outro addon substituiu a tela da Arma de Ferramentas ({file}). Use o botão abaixo para retomá-la.",

	-- en: v{version} installed. Each redraw takes {ms} ms.
	[ "menu.adv.diag_ok" ] = "v{version} instalada. Cada redesenho leva {ms} ms.",

	-- en: Last error: {error}
	[ "menu.adv.diag_error" ] = "Último erro: {error}",

	-- en: Waiting for the tool gun to load...
	[ "menu.adv.diag_wait" ] = "Aguardando a Arma de Ferramentas carregar...",

	-- en: Take over the tool gun screen
	[ "menu.adv.takeover" ] = "Retomar a tela da Arma de Ferramentas",

	-- en: Only needed if another addon replaced the tool gun's screen after this one
	[ "menu.adv.takeover_tip" ] = "Só é necessário se outro addon substituiu a tela da Arma de Ferramentas depois deste",

	-- en: Dynamic Toolgun Screen installed
	[ "menu.adv.takeover_done" ] = "Tela dinâmica da Arma de Ferramentas instalada",

	-- answers to "Import settings..." when the pasted text is wrong
	-- en: This is not a Dynamic Toolgun Screen settings string.
	[ "import.not_ours" ] = "Este não é um texto de configurações da Tela dinâmica da Arma de Ferramentas.",

	-- en: The settings string is damaged.
	[ "import.damaged" ] = "O texto de configurações está danificado.",

	-- en: Token reference
	[ "menu.tokens.title" ] = "Lista de tokens",

	-- en: Hover a token for what it does, double-click to copy it.
	[ "menu.tokens.help" ] = "Passe o mouse sobre um token para ver o que ele faz; clique duas vezes para copiá-lo.",

	-- en: Token
	[ "menu.tokens.col_token" ] = "Token",

	-- en: Right now
	[ "menu.tokens.col_now" ] = "Agora",

	-- en: Copied {token}
	[ "menu.tokens.copied" ] = "{token} copiado",

}
