--[[
	Dynamic Toolgun Screen - Українська (uk)

	Made from lang/en.lua with tools/i18n.py (see TRANSLATING.md). Above each phrase, "-- en:" holds the
	English it translates; "tools/i18n.py check" lists phrases whose English changed since. A phrase
	missing here falls back to English.
]]

return {

	-- name of the language in that language, shown in the language list
	-- en: English
	[ "_name" ] = "Українська",

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
	[ "tool.name" ] = "Динамічний екран Пістолета-знаряддя",

	-- en: Customize the tool gun's live screen and track entities on it
	[ "tool.desc" ] = "Налаштування живого екрана Пістолета-знаряддя та відстеження сутностей на ньому",

	-- en: Track the entity you are aiming at
	[ "tool.left" ] = "Відстежувати сутність, у яку ви цілитесь",

	-- en: Switch to the next screen layout
	[ "tool.right" ] = "Наступний макет екрана",

	-- en: Stop tracking
	[ "tool.reload" ] = "Зупинити відстеження",

	-- context menu entry (right click an entity while holding C)
	-- en: Track on tool gun screen
	[ "prop.track" ] = "Відстежувати на екрані Пістолета-знаряддя",

	-- Utilities tab: category and its only entry
	-- en: Dynamic Toolgun Screen
	[ "menu.category" ] = "Динамічний екран Пістолета-знаряддя",

	-- en: Settings
	[ "menu.settings_item" ] = "Налаштування",

	-- status line; {name} is an entity name such as "oildrum001" or a player's name
	-- en: Aiming at **{name}**
	[ "target.entity" ] = "Ціль: **{name}**",

	-- en: Aiming at the **sky**
	[ "target.sky" ] = "Ціль: **небо**",

	-- en: World
	[ "target.world" ] = "Світ",

	-- {surface} is a material from the mat.* phrases below
	-- en: World - **{surface}**
	[ "target.world_surface" ] = "Світ - **{surface}**",

	-- en: Nothing in range
	[ "target.nothing" ] = "Немає цілі",

	-- what you aim at, when it is the sky
	-- en: sky
	[ "aim.sky" ] = "небо",

	-- multi-click tools (weld, rope...): which click comes next
	-- en: Stage {n}
	[ "tool.progress" ] = "Етап {n}",

	-- health of the tracked entity, e.g. "HP 40/100"
	-- en: HP {hp}
	[ "track.hp" ] = "ОЗ {hp}",

	-- en: Noclip
	[ "noclip" ] = "Режим привида",

	-- view angles: P = pitch, Y = yaw
	-- en: P {p}  Y {y}
	[ "eye_ang" ] = "Нахил {p}  Поворот {y}",

	-- compass heading, e.g. "NE 45°"
	-- en: {dir} {deg}°
	[ "heading" ] = "{dir} {deg}°",

	-- en: N
	[ "compass.n" ] = "Пн",

	-- en: NE
	[ "compass.ne" ] = "ПнСх",

	-- en: E
	[ "compass.e" ] = "Сх",

	-- en: SE
	[ "compass.se" ] = "ПдСх",

	-- en: S
	[ "compass.s" ] = "Пд",

	-- en: SW
	[ "compass.sw" ] = "ПдЗх",

	-- en: W
	[ "compass.w" ] = "Зх",

	-- en: NW
	[ "compass.nw" ] = "ПнЗх",

	-- label of the FPS graph in the Terminal layout
	-- en: {n} fps
	[ "term.fps" ] = "{n} FPS",

	-- shown on the screen when it fails to draw
	-- en: Screen error
	[ "error.title" ] = "Помилка екрана",

	-- en: See the console for details. Change the layout or run dts_reset to recover.
	[ "error.hint" ] = "Подробиці в консолі. Змініть макет або виконайте dts_reset, щоб усе відновити.",

	-- tabs of the Advanced Toolgun [Hotbar] addon's tool list, for the {atg_tab} token
	-- en: Tools
	[ "atg.tab.tools" ] = "Інструменти",

	-- en: Wire
	[ "atg.tab.wire" ] = "Wire",

	-- en: Favorites
	[ "atg.tab.favorites" ] = "Улюблені",

	-- the device's battery, next to the battery icon and in {battery}: {n} is the charge in percent;
	-- "Plugged in" is shown while the device runs on mains power instead of its battery
	-- en: {n}%
	[ "battery.percent" ] = "{n}%",

	-- en: Plugged in
	[ "battery.plugged" ] = "Від мережі",

	-- Units: {v} is the number, already written with the decimal separator above
	-- en: {v} m
	[ "unit.m" ] = "{v} м",

	-- en: {v} km
	[ "unit.km" ] = "{v} км",

	-- en: {v} ft
	[ "unit.ft" ] = "{v} фт",

	-- en: {v} mi
	[ "unit.mi" ] = "{v} миль",

	-- Hammer units, the game's own distance unit
	-- en: {v} u
	[ "unit.hu" ] = "{v} од.",

	-- en: {v} km/h
	[ "unit.kmh" ] = "{v} км/год",

	-- en: {v} mph
	[ "unit.mph" ] = "{v} миль/год",

	-- en: {v} u/s
	[ "unit.ups" ] = "{v} од./с",

	-- en: {v} kg
	[ "unit.kg" ] = "{v} кг",

	-- en: {v} MB
	[ "unit.mb" ] = "{v} МБ",

	-- Durations: {h} hours, {m} minutes, {s} seconds (minutes and seconds come with two digits)
	-- en: {h}h {m}m
	[ "duration.hm" ] = "{h} год {m} хв",

	-- en: {m}m {s}s
	[ "duration.ms" ] = "{m} хв {s} с",

	-- en: {s}s
	[ "duration.s" ] = "{s} с",

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
	[ "date.wday.1" ] = "Нд",

	-- en: Mon
	[ "date.wday.2" ] = "Пн",

	-- en: Tue
	[ "date.wday.3" ] = "Вт",

	-- en: Wed
	[ "date.wday.4" ] = "Ср",

	-- en: Thu
	[ "date.wday.5" ] = "Чт",

	-- en: Fri
	[ "date.wday.6" ] = "Пт",

	-- en: Sat
	[ "date.wday.7" ] = "Сб",

	-- en: Sunday
	[ "date.wday_full.1" ] = "неділя",

	-- en: Monday
	[ "date.wday_full.2" ] = "понеділок",

	-- en: Tuesday
	[ "date.wday_full.3" ] = "вівторок",

	-- en: Wednesday
	[ "date.wday_full.4" ] = "середа",

	-- en: Thursday
	[ "date.wday_full.5" ] = "четвер",

	-- en: Friday
	[ "date.wday_full.6" ] = "п’ятниця",

	-- en: Saturday
	[ "date.wday_full.7" ] = "субота",

	-- short month names, used in dates ({month} above and %b): use the form your dates need
	-- en: Jan
	[ "date.month.1" ] = "січ.",

	-- en: Feb
	[ "date.month.2" ] = "лют.",

	-- en: Mar
	[ "date.month.3" ] = "бер.",

	-- en: Apr
	[ "date.month.4" ] = "квіт.",

	-- en: May
	[ "date.month.5" ] = "трав.",

	-- en: Jun
	[ "date.month.6" ] = "черв.",

	-- en: Jul
	[ "date.month.7" ] = "лип.",

	-- en: Aug
	[ "date.month.8" ] = "серп.",

	-- en: Sep
	[ "date.month.9" ] = "вер.",

	-- en: Oct
	[ "date.month.10" ] = "жовт.",

	-- en: Nov
	[ "date.month.11" ] = "лист.",

	-- en: Dec
	[ "date.month.12" ] = "груд.",

	-- full month names (%B), usually written right after a day number
	-- en: January
	[ "date.month_full.1" ] = "січня",

	-- en: February
	[ "date.month_full.2" ] = "лютого",

	-- en: March
	[ "date.month_full.3" ] = "березня",

	-- en: April
	[ "date.month_full.4" ] = "квітня",

	-- en: May
	[ "date.month_full.5" ] = "травня",

	-- en: June
	[ "date.month_full.6" ] = "червня",

	-- en: July
	[ "date.month_full.7" ] = "липня",

	-- en: August
	[ "date.month_full.8" ] = "серпня",

	-- en: September
	[ "date.month_full.9" ] = "вересня",

	-- en: October
	[ "date.month_full.10" ] = "жовтня",

	-- en: November
	[ "date.month_full.11" ] = "листопада",

	-- en: December
	[ "date.month_full.12" ] = "грудня",

	-- Kinds of surface material (the game's material types), shown as "World - Concrete"
	-- en: Antlion
	[ "mat.antlion" ] = "Мурашиний лев",

	-- en: Bloody flesh
	[ "mat.bloodyflesh" ] = "Закривавлена плоть",

	-- en: Concrete
	[ "mat.concrete" ] = "Бетон",

	-- en: Dirt
	[ "mat.dirt" ] = "Земля",

	-- en: Eggshell
	[ "mat.eggshell" ] = "Шкаралупа",

	-- en: Flesh
	[ "mat.flesh" ] = "Плоть",

	-- en: Grate
	[ "mat.grate" ] = "Решітка",

	-- en: Alien flesh
	[ "mat.alienflesh" ] = "Плоть прибульця",

	-- en: Clip
	[ "mat.clip" ] = "Невидима стіна",

	-- en: Snow
	[ "mat.snow" ] = "Сніг",

	-- en: Plastic
	[ "mat.plastic" ] = "Пластик",

	-- en: Metal
	[ "mat.metal" ] = "Метал",

	-- en: Sand
	[ "mat.sand" ] = "Пісок",

	-- en: Foliage
	[ "mat.foliage" ] = "Листя",

	-- en: Computer
	[ "mat.computer" ] = "Електроніка",

	-- en: Liquid
	[ "mat.slosh" ] = "Рідина",

	-- en: Tile
	[ "mat.tile" ] = "Плитка",

	-- en: Grass
	[ "mat.grass" ] = "Трава",

	-- en: Vent
	[ "mat.vent" ] = "Вентиляція",

	-- en: Wood
	[ "mat.wood" ] = "Дерево",

	-- en: Generic
	[ "mat.default" ] = "Звичайний",

	-- en: Glass
	[ "mat.glass" ] = "Скло",

	-- en: Warp shield
	[ "mat.warpshield" ] = "Варп-щит",

	-- Notifications on the screen
	-- en: Tracking {name}
	[ "notify.tracking" ] = "Відстеження: {name}",

	-- en: Stopped tracking
	[ "notify.untracked" ] = "Відстеження зупинено",

	-- en: Layout: {name}
	[ "notify.layout" ] = "Макет: {name}",

	-- en: Theme: {name}
	[ "notify.theme" ] = "Тема: {name}",

	-- title bar: tool category, or the game's name when there is none (keep "Garry's Mod")
	-- en: {tool_category|Garry's Mod}
	[ "tpl.title" ] = "{tool_category|Garry's Mod}",

	-- left link of the Pocket PC screen: the previous tool
	-- en: Back to {tool_prev}
	[ "tpl.nav_back" ] = "Назад: {tool_prev}",

	-- en: Props {props}/{props_max}
	[ "tpl.props" ] = "Об’єкти {props}/{props_max}",

	-- en: {fps} fps  {ping} ms
	[ "tpl.perf" ] = "{fps} FPS  {ping} мс",

	-- en: Slope {aim_slope}
	[ "tpl.slope" ] = "Ухил {aim_slope}",

	-- en: HP {ent_health}
	[ "tpl.hp" ] = "ОЗ {ent_health}",

	-- en: Owner: {ent_owner}
	[ "tpl.owner" ] = "Власник: {ent_owner}",

	-- HP = health, AP = armor
	-- en: HP {health}  AP {armor}
	[ "tpl.health_armor" ] = "ОЗ {health}  Броня {armor}",

	-- en: {players} players
	[ "tpl.players" ] = "Гравці: {players}",

	-- Terminal lines: a short upper case label, a tab, then the value
	-- en: TOOL\t**{tool}**
	[ "tpl.term_tool" ] = "ІНСТР\t**{tool}**",

	-- en: AIM\t**{aim_what}**
	[ "tpl.term_aim" ] = "ЦІЛЬ\t**{aim_what}**",

	-- en: CLASS\t**{ent_class|-}**
	[ "tpl.term_class" ] = "КЛАС\t**{ent_class|-}**",

	-- en: POS\t**{aim_pos}**
	[ "tpl.term_pos" ] = "ПОЗ\t**{aim_pos}**",

	-- en: DIST\t**{aim_dist}**  {aim_slope}
	[ "tpl.term_dist" ] = "ДИСТ\t**{aim_dist}**  {aim_slope}",

	-- en: OWNER\t**{ent_owner|-}**
	[ "tpl.term_owner" ] = "ВЛАСН\t**{ent_owner|-}**",

	-- en: HP\t**{ent_health|-}**
	[ "tpl.term_hp" ] = "ОЗ\t**{ent_health|-}**",

	-- en: TRACK\t**{track_name|-}** {track_dist}
	[ "tpl.term_track" ] = "СТЕЖ\t**{track_name|-}** {track_dist}",

	-- en: Pocket PC
	[ "layout.pocketpc.name" ] = "Pocket PC",

	-- en: The original screen rebuilt with live data: clock, status icons, tool history links, big tool name, status line, six readouts and a hint bar.
	[ "layout.pocketpc.desc" ] = "Оригінальний екран із живими даними: годинник, значки стану, посилання історії інструментів, велика назва інструмента, рядок стану, шість показників і рядок підказок.",

	-- en: Title bar
	[ "layout.pocketpc.title" ] = "Заголовок",

	-- en: Clock
	[ "layout.pocketpc.clock" ] = "Годинник",

	-- en: Left link
	[ "layout.pocketpc.nav_l" ] = "Ліве посилання",

	-- en: Right link
	[ "layout.pocketpc.nav_r" ] = "Праве посилання",

	-- en: Big text
	[ "layout.pocketpc.hero" ] = "Великий текст",

	-- en: Under the big text
	[ "layout.pocketpc.sub" ] = "Під великим текстом",

	-- en: Status line
	[ "layout.pocketpc.status" ] = "Рядок стану",

	-- en: Readout, left 1
	[ "layout.pocketpc.l1" ] = "Показник ліворуч 1",

	-- en: Readout, left 2
	[ "layout.pocketpc.l2" ] = "Показник ліворуч 2",

	-- en: Readout, left 3
	[ "layout.pocketpc.l3" ] = "Показник ліворуч 3",

	-- en: Readout, right 1
	[ "layout.pocketpc.r1" ] = "Показник праворуч 1",

	-- en: Readout, right 2
	[ "layout.pocketpc.r2" ] = "Показник праворуч 2",

	-- en: Readout, right 3
	[ "layout.pocketpc.r3" ] = "Показник праворуч 3",

	-- en: Menu bar
	[ "layout.pocketpc.menu" ] = "Рядок меню",

	-- en: Terminal
	[ "layout.terminal.name" ] = "Термінал",

	-- en: Developer readout: eight lines of labels and values, an FPS graph and a prompt line with the tool hints.
	[ "layout.terminal.desc" ] = "Зведення для розробника: вісім рядків «підпис — значення», графік FPS і рядок вводу з підказками інструмента.",

	-- en: Header
	[ "layout.terminal.head" ] = "Заголовок",

	-- en: Header, right
	[ "layout.terminal.clock" ] = "Заголовок праворуч",

	-- en: Line 1
	[ "layout.terminal.l1" ] = "Рядок 1",

	-- en: Line 2
	[ "layout.terminal.l2" ] = "Рядок 2",

	-- en: Line 3
	[ "layout.terminal.l3" ] = "Рядок 3",

	-- en: Line 4
	[ "layout.terminal.l4" ] = "Рядок 4",

	-- en: Line 5
	[ "layout.terminal.l5" ] = "Рядок 5",

	-- en: Line 6
	[ "layout.terminal.l6" ] = "Рядок 6",

	-- en: Line 7
	[ "layout.terminal.l7" ] = "Рядок 7",

	-- en: Line 8
	[ "layout.terminal.l8" ] = "Рядок 8",

	-- en: Prompt line
	[ "layout.terminal.foot" ] = "Рядок вводу",

	-- en: Minimal
	[ "layout.minimal.name" ] = "Мінімальний",

	-- en: Large, glanceable text: clock, compass, the tool name sized to fit, what you aim at and two corner values.
	[ "layout.minimal.desc" ] = "Великий текст, який видно з першого погляду: годинник, компас, назва інструмента за розміром, ваша ціль і два значення в кутах.",

	-- en: Top left
	[ "layout.minimal.top_l" ] = "Згори ліворуч",

	-- en: Top right
	[ "layout.minimal.top_r" ] = "Згори праворуч",

	-- en: Big text
	[ "layout.minimal.hero" ] = "Великий текст",

	-- en: Under the big text
	[ "layout.minimal.sub" ] = "Під великим текстом",

	-- en: Bottom left
	[ "layout.minimal.foot_l" ] = "Знизу ліворуч",

	-- en: Bottom right
	[ "layout.minimal.foot_r" ] = "Знизу праворуч",

	-- en: Pocket PC (original)
	[ "theme.winmobile" ] = "Pocket PC (оригінал)",

	-- en: Graphite
	[ "theme.graphite" ] = "Графіт",

	-- en: Green phosphor
	[ "theme.phosphor" ] = "Зелений люмінофор",

	-- en: Amber CRT
	[ "theme.amber" ] = "Бурштиновий ЕПТ",

	-- en: Sakura
	[ "theme.sakura" ] = "Сакура",

	-- en: Sandbox blue
	[ "theme.sandbox" ] = "Синій Sandbox",

	-- parts of the screen whose colour can be changed
	-- en: Title bar
	[ "color.bar" ] = "Заголовок",

	-- en: Links and highlights
	[ "color.accent" ] = "Посилання та виділення",

	-- en: Big text
	[ "color.hero" ] = "Великий текст",

	-- en: Status line
	[ "color.strip" ] = "Рядок стану",

	-- en: Readout panel
	[ "color.panel" ] = "Панель показників",

	-- en: Menu bar
	[ "color.menu" ] = "Рядок меню",

	-- en: Terminal text
	[ "color.term" ] = "Текст термінала",

	-- en: Text
	[ "category.text" ] = "Текст",

	-- en: Time
	[ "category.time" ] = "Час",

	-- en: Tool
	[ "category.tool" ] = "Інструмент",

	-- en: Aim
	[ "category.aim" ] = "Приціл",

	-- en: Aimed entity
	[ "category.entity" ] = "Сутність під прицілом",

	-- en: Tracked entity
	[ "category.tracked" ] = "Відстежувана сутність",

	-- en: You
	[ "category.player" ] = "Ви",

	-- en: Game
	[ "category.game" ] = "Гра",

	-- the Advanced Toolgun [Hotbar] addon; keep its name as it is
	-- en: Advanced Toolgun
	[ "category.atg" ] = "Advanced Toolgun",

	-- en: A line in your language from the language files, e.g. {tr:nav_back} or {tr:props}.
	[ "token.tr" ] = "Рядок вашою мовою з мовних файлів, наприклад {tr:nav_back} або {tr:props}.",

	-- en: Local time, formatted by the clock settings. {time:%H:%M:%S} takes an os.date format.
	[ "token.time" ] = "Місцевий час у форматі з налаштувань годинника. {time:%H:%M:%S} приймає формат os.date.",

	-- en: Today's date. {date:%Y-%m-%d} takes an os.date format.
	[ "token.date" ] = "Сьогоднішня дата. {date:%Y-%m-%d} приймає формат os.date.",

	-- en: How long you have been in this game.
	[ "token.session" ] = "Скільки ви вже в цій грі.",

	-- en: How long the map has been running.
	[ "token.map_time" ] = "Скільки триває поточна карта.",

	-- en: Name of the selected tool.
	[ "token.tool" ] = "Назва вибраного інструмента.",

	-- en: Internal name of the selected tool.
	[ "token.tool_id" ] = "Внутрішня назва вибраного інструмента.",

	-- en: Description of the selected tool.
	[ "token.tool_desc" ] = "Опис вибраного інструмента.",

	-- en: Tool menu category of the selected tool.
	[ "token.tool_category" ] = "Категорія вибраного інструмента в меню інструментів.",

	-- en: Stage of the selected tool (0 = nothing selected yet).
	[ "token.tool_stage" ] = "Етап вибраного інструмента (0 = ще нічого не вибрано).",

	-- en: The stage while a multi-click tool is in progress, otherwise empty.
	[ "token.tool_progress" ] = "Етап, поки триває робота інструментом у кілька кліків, інакше порожньо.",

	-- en: The tool you used before this one (dts_tool_back switches to it).
	[ "token.tool_prev" ] = "Інструмент, вибраний перед поточним (dts_tool_back перемикає на нього).",

	-- en: The next tool in the same menu category (dts_tool_next switches to it).
	[ "token.tool_next" ] = "Наступний інструмент тієї ж категорії меню (dts_tool_next перемикає на нього).",

	-- en: Successful tool gun shots this session.
	[ "token.tool_uses" ] = "Вдалі постріли Пістолета-знаряддя за цю гру.",

	-- en: A setting of the selected tool, e.g. {tool_cvar:forcelimit} reads weld_forcelimit.
	[ "token.tool_cvar" ] = "Налаштування вибраного інструмента, наприклад {tool_cvar:forcelimit} читає weld_forcelimit.",

	-- en: All settings of the selected tool as name=value pairs.
	[ "token.tool_settings" ] = "Усі налаштування вибраного інструмента у вигляді назва=значення.",

	-- en: The current stage's instructions with mouse and key icons.
	[ "token.hints" ] = "Підказки поточного етапу зі значками миші та клавіш.",

	-- en: What left click does right now.
	[ "token.hint_left" ] = "Що зараз робить лівий клік.",

	-- en: What right click does right now.
	[ "token.hint_right" ] = "Що зараз робить правий клік.",

	-- en: What reload does right now.
	[ "token.hint_reload" ] = "Що зараз робить клавіша перезаряджання.",

	-- en: What you are aiming at, with the name highlighted.
	[ "token.target" ] = "У що ви цілитесь, з виділеною назвою.",

	-- en: Entity name, or the surface material when aiming at the world.
	[ "token.aim_what" ] = "Назва сутності або матеріал поверхні, якщо ви цілитесь у світ.",

	-- en: Position you are aiming at.
	[ "token.aim_pos" ] = "Точка, у яку ви цілитесь.",

	-- en: X of the aim position.
	[ "token.aim_x" ] = "X точки прицілу.",

	-- en: Y of the aim position.
	[ "token.aim_y" ] = "Y точки прицілу.",

	-- en: Z of the aim position.
	[ "token.aim_z" ] = "Z точки прицілу.",

	-- en: Distance to the aim position.
	[ "token.aim_dist" ] = "Відстань до точки прицілу.",

	-- en: Surface normal at the aim position.
	[ "token.aim_normal" ] = "Нормаль поверхні в точці прицілу.",

	-- en: Steepness of the surface (0 = flat floor, 90 = wall).
	[ "token.aim_slope" ] = "Крутизна поверхні (0 = рівна підлога, 90 = стіна).",

	-- en: Kind of surface material (metal, wood, concrete...).
	[ "token.aim_surface" ] = "Вид матеріалу поверхні (метал, дерево, бетон...).",

	-- en: Surface property as the engine names it (metal box, wood crate...).
	[ "token.aim_surfaceprop" ] = "Властивість поверхні в назві рушія (metal box, wood crate...).",

	-- en: World texture you are aiming at.
	[ "token.aim_texture" ] = "Текстура світу, у яку ви цілитесь.",

	-- en: Friendly name of the aimed entity.
	[ "token.ent_name" ] = "Зрозуміла назва сутності під прицілом.",

	-- en: Class of the aimed entity.
	[ "token.ent_class" ] = "Клас сутності під прицілом.",

	-- en: Model file name of the aimed entity.
	[ "token.ent_model" ] = "Назва файлу моделі сутності під прицілом.",

	-- en: Full model path of the aimed entity.
	[ "token.ent_model_path" ] = "Повний шлях моделі сутності під прицілом.",

	-- en: Entity index.
	[ "token.ent_index" ] = "Номер сутності.",

	-- en: Health of the aimed entity (players, NPCs, breakable props).
	[ "token.ent_health" ] = "Здоров’я сутності під прицілом (гравці, NPC, руйнівні об’єкти).",

	-- en: Owner of the aimed entity (in multiplayer this needs a CPPI prop protection addon).
	[ "token.ent_owner" ] = "Власник сутності під прицілом (у мультиплеєрі потрібен аддон захисту об’єктів із підтримкою CPPI).",

	-- en: Material of the aimed entity.
	[ "token.ent_material" ] = "Матеріал сутності під прицілом.",

	-- en: Colour of the aimed entity.
	[ "token.ent_color" ] = "Колір сутності під прицілом.",

	-- en: Skin of the aimed entity.
	[ "token.ent_skin" ] = "Вигляд (скін) сутності під прицілом.",

	-- en: Speed of the aimed entity.
	[ "token.ent_speed" ] = "Швидкість сутності під прицілом.",

	-- en: Position of the aimed entity.
	[ "token.ent_pos" ] = "Положення сутності під прицілом.",

	-- en: Angles of the aimed entity.
	[ "token.ent_ang" ] = "Кути повороту сутності під прицілом.",

	-- en: Mass of the aimed entity, when your game knows its physics.
	[ "token.ent_mass" ] = "Маса сутності під прицілом, якщо гра знає її фізику.",

	-- en: Tracked entity summary: name, distance, speed, health.
	[ "token.track" ] = "Зведення про відстежувану сутність: назва, відстань, швидкість, здоров’я.",

	-- en: Name of the tracked entity.
	[ "token.track_name" ] = "Назва відстежуваної сутності.",

	-- en: Class of the tracked entity.
	[ "token.track_class" ] = "Клас відстежуваної сутності.",

	-- en: Your distance to the tracked entity.
	[ "token.track_dist" ] = "Відстань до відстежуваної сутності.",

	-- en: Speed of the tracked entity.
	[ "token.track_speed" ] = "Швидкість відстежуваної сутності.",

	-- en: Health of the tracked entity.
	[ "token.track_health" ] = "Здоров’я відстежуваної сутності.",

	-- en: Position of the tracked entity.
	[ "token.track_pos" ] = "Положення відстежуваної сутності.",

	-- en: Your name.
	[ "token.player" ] = "Ваш нік.",

	-- en: Your health.
	[ "token.health" ] = "Ваше здоров’я.",

	-- en: Your armor.
	[ "token.armor" ] = "Ваша броня.",

	-- en: Your speed.
	[ "token.speed" ] = "Ваша швидкість.",

	-- en: Your position.
	[ "token.pos" ] = "Ваше положення.",

	-- en: Your view pitch and yaw.
	[ "token.eye_ang" ] = "Нахил і поворот вашого погляду.",

	-- en: Compass heading (north is +Y on the map).
	[ "token.heading" ] = "Напрямок за компасом (північ — це +Y на карті).",

	-- en: Shows a word while you are noclipping, otherwise empty.
	[ "token.noclip" ] = "Слово, поки ввімкнено режим привида (noclip), інакше порожньо.",

	-- en: Frames per second (smoothed).
	[ "token.fps" ] = "Кадри за секунду (згладжено).",

	-- en: Your ping in milliseconds.
	[ "token.ping" ] = "Ваш пінг у мілісекундах.",

	-- en: Your device's battery charge while it runs on battery, or \"Plugged in\".
	[ "token.battery" ] = "Заряд батареї вашого пристрою під час роботи від батареї, інакше «Від мережі».",

	-- en: Current map.
	[ "token.map" ] = "Поточна карта.",

	-- en: Players on the server and its player limit.
	[ "token.players" ] = "Гравці на сервері та їхній ліміт.",

	-- en: Server name.
	[ "token.server" ] = "Назва сервера.",

	-- en: Active gamemode.
	[ "token.gamemode" ] = "Поточний режим гри.",

	-- en: Server tick rate.
	[ "token.tickrate" ] = "Тікрейт сервера.",

	-- en: Memory used by Lua in your game.
	[ "token.lua_mem" ] = "Пам’ять, яку займає Lua у вашій грі.",

	-- en: Entities known to your game.
	[ "token.entities" ] = "Кількість сутностей, відомих вашій грі.",

	-- en: Props you have spawned.
	[ "token.props" ] = "Створені вами об’єкти.",

	-- en: Your prop limit.
	[ "token.props_max" ] = "Ваш ліміт об’єктів.",

	-- en: Spawn count and limit of a type, e.g. {count:ragdolls} or {count:thrusters}.
	[ "token.count" ] = "Кількість створених об’єктів типу та ліміт, наприклад {count:ragdolls} або {count:thrusters}.",

	-- en: Value of any console variable, e.g. {cvar:sv_gravity}.
	[ "token.cvar" ] = "Значення будь-якої консольної змінної, наприклад {cvar:sv_gravity}.",

	-- en: Advanced Toolgun [Hotbar]: its open tab (Tools, Wire or Favorites).
	[ "token.atg_tab" ] = "Advanced Toolgun [Hotbar]: його відкрита вкладка (Інструменти, Wire або Улюблені).",

	-- en: Advanced Toolgun [Hotbar]: the section of its list the selection is in.
	[ "token.atg_section" ] = "Advanced Toolgun [Hotbar]: розділ його списку, у якому стоїть вибір.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel up.
	[ "token.atg_prev" ] = "Advanced Toolgun [Hotbar]: інструмент, на який його швидкий вибір перемкне колесом миші вгору.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel down.
	[ "token.atg_next" ] = "Advanced Toolgun [Hotbar]: інструмент, на який його швидкий вибір перемкне колесом миші вниз.",

	-- en: Turns the tool gun's mini screen into a live display. Changes apply instantly; the preview shows what the screen draws right now.
	[ "menu.intro" ] = "Перетворює маленький екран Пістолета-знаряддя на живий дисплей. Зміни застосовуються одразу; попередній перегляд показує, що екран малює саме зараз.",

	-- en: Dynamic screen is off
	[ "menu.preview_off" ] = "Динамічний екран вимкнено",

	-- en: Enable the dynamic screen
	[ "menu.enable" ] = "Увімкнути динамічний екран",

	-- en: Language
	[ "menu.language" ] = "Мова",

	-- first entry of the language list; {name} is the game's language, e.g. "English"
	-- en: Automatic: {name}
	[ "menu.language.auto" ] = "Автоматично: {name}",

	-- en: Inspect: read the screen up close
	[ "menu.inspect.title" ] = "Огляд: читати екран зблизька",

	-- en: Hold a key while holding the tool gun to raise its screen to your eyes.
	[ "menu.inspect.help" ] = "Утримуйте клавішу з Пістолетом-знаряддям у руках, щоб піднести екран до очей.",

	-- en: Inspect key
	[ "menu.inspect.key" ] = "Клавіша огляду",

	-- en: Screen size while inspecting
	[ "menu.inspect.size" ] = "Розмір екрана під час огляду",

	-- en: Or use the console: bind <key> +dts_inspect (hold) or dts_inspect_toggle.
	[ "menu.inspect.console" ] = "Або через консоль: bind <клавіша> +dts_inspect (утримувати) чи dts_inspect_toggle.",

	-- the tool gun model has a paper note glued on, which overlaps the screen's top right corner
	-- en: Screen in front of the paper note
	[ "menu.inspect.on_top" ] = "Екран поверх паперової записки",

	-- en: While inspecting, the whole screen stays readable. Untick to let the paper note glued to the tool gun cover the top right corner of the screen, as on the model.
	[ "menu.inspect.on_top_help" ] = "Під час огляду весь екран залишається читабельним. Вимкніть, щоб паперова записка, приклеєна до Пістолета-знаряддя, закривала правий верхній кут екрана, як на моделі.",

	-- en: Layout and look
	[ "menu.look.title" ] = "Макет і вигляд",

	-- en: Layout
	[ "menu.look.layout" ] = "Макет",

	-- en: Theme
	[ "menu.look.theme" ] = "Тема",

	-- en: Background
	[ "menu.look.background" ] = "Тло",

	-- en: Automatic (layout's choice)
	[ "menu.bg.auto" ] = "Автоматично (за макетом)",

	-- the whole original screen picture without its text
	-- en: Original screen
	[ "menu.bg.original" ] = "Оригінальний екран",

	-- only the blurred photo from the original picture, filling the screen
	-- en: Original photo
	[ "menu.bg.art" ] = "Оригінальне фото",

	-- en: Theme gradient
	[ "menu.bg.gradient" ] = "Градієнт теми",

	-- en: Live camera: zoom
	[ "menu.bg.camera" ] = "Жива камера: наближення",

	-- en: Live camera: rear view
	[ "menu.bg.rear" ] = "Жива камера: вигляд назад",

	-- en: Custom image
	[ "menu.bg.image" ] = "Власне зображення",

	-- en: Black
	[ "menu.bg.black" ] = "Чорне",

	-- en: Custom image
	[ "menu.look.image" ] = "Власне зображення",

	-- en: A material path, or an image in garrysmod/data written as ../data/name.png
	[ "menu.look.image_help" ] = "Шлях до матеріалу або зображення з garrysmod/data у вигляді ../data/назва.png",

	-- en: Darken background
	[ "menu.look.dim" ] = "Затемнити тло",

	-- en: Camera field of view
	[ "menu.look.cam_fov" ] = "Поле зору камери",

	-- en: Camera updates per second
	[ "menu.look.cam_fps" ] = "Оновлень камери за секунду",

	-- en: Text font
	[ "menu.look.font" ] = "Шрифт тексту",

	-- en: Big text font
	[ "menu.look.font_hero" ] = "Шрифт великого тексту",

	-- en: Terminal font
	[ "menu.look.font_mono" ] = "Шрифт термінала",

	-- first entry of the font lists; {font} is the font your language uses
	-- en: Automatic ({font})
	[ "menu.font.auto" ] = "Автоматично ({font})",

	-- en: Colours
	[ "menu.colors.title" ] = "Кольори",

	-- en: Override single colours of the theme. Click a swatch to change it.
	[ "menu.colors.help" ] = "Заміна окремих кольорів теми. Натисніть на зразок, щоб змінити колір.",

	-- written on a colour swatch that still uses the theme's colour
	-- en: theme
	[ "menu.colors.theme_tag" ] = "тема",

	-- en: Click to pick a colour
	[ "menu.colors.pick" ] = "Натисніть, щоб вибрати колір",

	-- en: Use the theme's colours everywhere
	[ "menu.colors.reset_all" ] = "Усюди використовувати кольори теми",

	-- en: Screen colour: {name}
	[ "menu.colors.picker_title" ] = "Колір екрана: {name}",

	-- en: Use the theme's colour
	[ "menu.colors.use_theme" ] = "Колір теми",

	-- en: Big text
	[ "menu.hero.title" ] = "Великий текст",

	-- en: Behaviour
	[ "menu.hero.mode" ] = "Поведінка",

	-- en: Always scroll (original)
	[ "menu.hero.scroll" ] = "Завжди прокручувати (оригінал)",

	-- en: Scroll only when too long
	[ "menu.hero.auto" ] = "Прокручувати, лише якщо не вміщується",

	-- en: Shrink to fit
	[ "menu.hero.fit" ] = "Зменшувати до розміру",

	-- en: Scroll speed
	[ "menu.hero.speed" ] = "Швидкість прокручування",

	-- en: Upper case tool names
	[ "menu.hero.upper" ] = "Назви інструментів великими літерами",

	-- en: Screen content
	[ "menu.content.title" ] = "Вміст екрана",

	-- keep {tokens}, **stars**, {token|fallback} and {tr:...} as they are: they show the syntax
	-- en: Every line of the {layout} layout is a template. Type text and {tokens}; **stars** highlight text, {token|fallback} gives a default, and a line whose tokens are all empty hides itself. {tr:...} writes a line in your language. See the token reference below.
	[ "menu.content.help" ] = "Кожен рядок макета «{layout}» — це шаблон. Пишіть текст і {tokens}; **зірочки** виділяють текст, {token|fallback} задає текст на випадок, коли значення порожнє, а рядок, у якому всі змінні порожні, ховається сам. {tr:...} пише рядок вашою мовою. Список змінних — нижче.",

	-- en: Pick a ready-made line
	[ "menu.content.presets_tip" ] = "Вибрати готовий рядок",

	-- en: Back to the default: {value}
	[ "menu.content.reset_tip" ] = "Повернути типове: {value}",

	-- en: (empty)
	[ "menu.content.empty" ] = "(порожньо)",

	-- shown in an empty line's text box
	-- en: (hidden)
	[ "menu.content.placeholder" ] = "(приховано)",

	-- under each line: what it shows right now
	-- en: = {text}
	[ "menu.content.now" ] = "= {text}",

	-- en: (hidden right now)
	[ "menu.content.hidden_now" ] = "(зараз прихований)",

	-- en: Reset these lines to the layout's defaults
	[ "menu.content.reset_all" ] = "Повернути типові рядки макета",

	-- ready-made lines in the list next to each line
	-- en: Tool name
	[ "menu.preset.tool" ] = "Назва інструмента",

	-- en: Tool category
	[ "menu.preset.tool_category" ] = "Категорія інструмента",

	-- en: Tool instructions
	[ "menu.preset.hints" ] = "Підказки інструмента",

	-- en: Previous tool
	[ "menu.preset.prev_tool" ] = "Попередній інструмент",

	-- en: Next tool
	[ "menu.preset.next_tool" ] = "Наступний інструмент",

	-- en: Tool progress
	[ "menu.preset.progress" ] = "Етап інструмента",

	-- en: Tool settings
	[ "menu.preset.tool_settings" ] = "Налаштування інструмента",

	-- en: What you aim at
	[ "menu.preset.target" ] = "Ціль",

	-- en: Aim position
	[ "menu.preset.aim_pos" ] = "Точка прицілу",

	-- en: Aim distance
	[ "menu.preset.aim_dist" ] = "Відстань до цілі",

	-- en: Entity or surface
	[ "menu.preset.aim_what" ] = "Сутність або поверхня",

	-- en: Surface slope
	[ "menu.preset.slope" ] = "Ухил поверхні",

	-- en: Entity class
	[ "menu.preset.ent_class" ] = "Клас сутності",

	-- en: Entity model
	[ "menu.preset.ent_model" ] = "Модель сутності",

	-- en: Entity health
	[ "menu.preset.ent_health" ] = "Здоров’я сутності",

	-- en: Entity owner
	[ "menu.preset.ent_owner" ] = "Власник сутності",

	-- en: Entity speed
	[ "menu.preset.ent_speed" ] = "Швидкість сутності",

	-- en: Tracked entity
	[ "menu.preset.track" ] = "Відстежувана сутність",

	-- en: Clock
	[ "menu.preset.clock" ] = "Годинник",

	-- en: Clock with seconds
	[ "menu.preset.clock_seconds" ] = "Годинник із секундами",

	-- en: Date
	[ "menu.preset.date" ] = "Дата",

	-- en: Time in game
	[ "menu.preset.session" ] = "Час у грі",

	-- en: Your speed
	[ "menu.preset.speed" ] = "Ваша швидкість",

	-- en: Your position
	[ "menu.preset.pos" ] = "Ваше положення",

	-- en: Compass
	[ "menu.preset.heading" ] = "Компас",

	-- en: Health and armor
	[ "menu.preset.health_armor" ] = "Здоров’я та броня",

	-- en: FPS and ping
	[ "menu.preset.perf" ] = "FPS і пінг",

	-- en: Prop count
	[ "menu.preset.props" ] = "Кількість об’єктів",

	-- en: Map
	[ "menu.preset.map" ] = "Карта",

	-- en: Players
	[ "menu.preset.players" ] = "Гравці",

	-- en: Empty (hide the line)
	[ "menu.preset.empty" ] = "Порожньо (сховати рядок)",

	-- en: Clock and units
	[ "menu.clock.title" ] = "Годинник і одиниці",

	-- en: Clock
	[ "menu.clock.style" ] = "Годинник",

	-- {language} is the name of the active language
	-- en: As usual in {language}
	[ "menu.clock.auto" ] = "Як прийнято: {language}",

	-- en: 12 hour
	[ "menu.clock.12h" ] = "12-годинний",

	-- en: 24 hour
	[ "menu.clock.24h" ] = "24-годинний",

	-- en: Show seconds
	[ "menu.clock.seconds" ] = "Показувати секунди",

	-- en: Show AM / PM (12 hour clock)
	[ "menu.clock.ampm" ] = "Показувати AM / PM (12-годинний годинник)",

	-- en: Blink the colon
	[ "menu.clock.blink" ] = "Блимаюча двокрапка",

	-- en: Units
	[ "menu.units.label" ] = "Одиниці",

	-- en: Metric (m, km/h)
	[ "menu.units.m" ] = "Метричні (м, км/год)",

	-- en: Imperial (ft, mph)
	[ "menu.units.ft" ] = "Імперські (фт, миль/год)",

	-- en: Hammer units
	[ "menu.units.hu" ] = "Одиниці Hammer",

	-- en: Distance decimals
	[ "menu.units.decimals" ] = "Знаків після коми у відстанях",

	-- en: Icons and effects
	[ "menu.fx.title" ] = "Значки та ефекти",

	-- en: Speaker icon (volume, voice chat)
	[ "menu.fx.speaker" ] = "Значок динаміка (гучність, голосовий чат)",

	-- en: Signal icon (connection)
	[ "menu.fx.signal" ] = "Значок сигналу (з’єднання)",

	-- en: Battery icon (your device's battery)
	[ "menu.fx.battery" ] = "Значок батареї (батарея вашого пристрою)",

	-- en: Boot animation when taking out the tool gun
	[ "menu.fx.boot" ] = "Анімація завантаження, коли ви дістаєте Пістолет-знаряддя",

	-- en: Flash when the tool gun fires
	[ "menu.fx.flash" ] = "Спалах екрана під час пострілу Пістолета-знаряддя",

	-- en: Show game notifications on the screen
	[ "menu.fx.notify" ] = "Показувати сповіщення гри на екрані",

	-- en: Notification time
	[ "menu.fx.notify_time" ] = "Час показу сповіщень",

	-- en: Scanlines
	[ "menu.fx.scanlines" ] = "Рядки розгортки",

	-- en: Darker edges
	[ "menu.fx.vignette" ] = "Затемнювати краї",

	-- en: Backlight
	[ "menu.fx.backlight" ] = "Підсвічування",

	-- en: HUD mirror
	[ "menu.mirror.title" ] = "Дзеркало на HUD",

	-- en: Shows the screen on your HUD while you hold the tool gun, for reading the small print.
	[ "menu.mirror.help" ] = "Показує екран ще й на HUD, поки у вас у руках Пістолет-знаряддя, щоб зручно читати дрібний текст.",

	-- en: Show the screen on the HUD
	[ "menu.mirror.enable" ] = "Показувати екран на HUD",

	-- en: Corner
	[ "menu.mirror.corner" ] = "Кут",

	-- en: Top right
	[ "menu.corner.tr" ] = "Праворуч згори",

	-- en: Bottom right
	[ "menu.corner.br" ] = "Праворуч знизу",

	-- en: Bottom left
	[ "menu.corner.bl" ] = "Ліворуч знизу",

	-- en: Top left
	[ "menu.corner.tl" ] = "Ліворуч згори",

	-- en: Size
	[ "menu.mirror.size" ] = "Розмір",

	-- en: Opacity
	[ "menu.mirror.alpha" ] = "Непрозорість",

	-- en: Advanced
	[ "menu.adv.title" ] = "Додатково",

	-- en: Keep the own screens of tools that draw one
	[ "menu.adv.respect" ] = "Залишати власні екрани інструментів, які їх мають",

	-- en: e.g. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod tools
	[ "menu.adv.respect_help" ] = "наприклад, Easy Entity Inspector, Ragdoll Puppeteer, інструменти Wiremod",

	-- en: Live value updates per second
	[ "menu.adv.refresh" ] = "Оновлень значень за секунду",

	-- en: Screen redraws per second (0 = every frame)
	[ "menu.adv.fps" ] = "Перемальовувань екрана за секунду (0 = кожен кадр)",

	-- en: Resolution
	[ "menu.adv.resolution" ] = "Роздільність",

	-- en: 256 x 256 (original)
	[ "menu.res.256" ] = "256 x 256 (оригінал)",

	-- en: 512 x 512 (sharper, for 1440p and up)
	[ "menu.res.512" ] = "512 x 512 (чіткіше, для 1440p і вище)",

	-- keep the commands as they are
	-- en: Key binds (bind <key> <command>):\n  dts_tool_back  -  previous tool\n  dts_tool_next / dts_tool_prev  -  cycle the category\n  dts_layout_next, dts_theme_next  -  cycle layouts, themes\n  dts_track / dts_untrack  -  follow an entity
	[ "menu.adv.binds" ] = "Прив’язки клавіш (bind <клавіша> <команда>):\n  dts_tool_back  -  попередній інструмент\n  dts_tool_next / dts_tool_prev  -  гортати категорію\n  dts_layout_next, dts_theme_next  -  гортати макети, теми\n  dts_track / dts_untrack  -  відстежувати сутність",

	-- en: Copy my settings to the clipboard
	[ "menu.adv.copy" ] = "Скопіювати мої налаштування в буфер обміну",

	-- en: Screen settings copied to the clipboard
	[ "menu.adv.copied" ] = "Налаштування екрана скопійовано в буфер обміну",

	-- en: Import settings...
	[ "menu.adv.import" ] = "Імпорт налаштувань...",

	-- en: Import screen settings
	[ "menu.adv.import_title" ] = "Імпорт налаштувань екрана",

	-- en: Paste a DTS1:... settings string
	[ "menu.adv.import_prompt" ] = "Вставте рядок налаштувань DTS1:...",

	-- en: Import
	[ "menu.adv.import_ok" ] = "Імпортувати",

	-- en: Imported screen settings ({n} changed)
	[ "menu.adv.imported" ] = "Налаштування екрана імпортовано (змінено: {n})",

	-- en: Reset everything to defaults
	[ "menu.adv.reset" ] = "Скинути все до типових",

	-- en: Reset
	[ "menu.adv.reset_title" ] = "Скидання",

	-- en: Reset every Dynamic Toolgun Screen setting?
	[ "menu.adv.reset_question" ] = "Скинути всі налаштування динамічного екрана Пістолета-знаряддя?",

	-- en: Reset
	[ "menu.adv.reset_yes" ] = "Скинути",

	-- en: Cancel
	[ "menu.adv.cancel" ] = "Скасувати",

	-- en: Another addon replaced the tool gun screen ({file}). Use the button below to take over.
	[ "menu.adv.diag_conflict" ] = "Інший аддон замінив екран Пістолета-знаряддя ({file}). Кнопка нижче поверне керування.",

	-- en: v{version} installed. Each redraw takes {ms} ms.
	[ "menu.adv.diag_ok" ] = "v{version} встановлено. Одне перемальовування займає {ms} мс.",

	-- en: Last error: {error}
	[ "menu.adv.diag_error" ] = "Остання помилка: {error}",

	-- en: Waiting for the tool gun to load...
	[ "menu.adv.diag_wait" ] = "Очікування завантаження Пістолета-знаряддя...",

	-- en: Take over the tool gun screen
	[ "menu.adv.takeover" ] = "Повернути керування екраном Пістолета-знаряддя",

	-- en: Only needed if another addon replaced the tool gun's screen after this one
	[ "menu.adv.takeover_tip" ] = "Потрібно, лише якщо інший аддон замінив екран Пістолета-знаряддя після цього аддона",

	-- en: Dynamic Toolgun Screen installed
	[ "menu.adv.takeover_done" ] = "Керування екраном Пістолета-знаряддя повернуто",

	-- answers to "Import settings..." when the pasted text is wrong
	-- en: This is not a Dynamic Toolgun Screen settings string.
	[ "import.not_ours" ] = "Це не рядок налаштувань динамічного екрана Пістолета-знаряддя.",

	-- en: The settings string is damaged.
	[ "import.damaged" ] = "Рядок налаштувань пошкоджено.",

	-- en: Token reference
	[ "menu.tokens.title" ] = "Список змінних",

	-- en: Hover a token for what it does, double-click to copy it.
	[ "menu.tokens.help" ] = "Наведіть курсор на змінну, щоб побачити, що вона робить; подвійний клік — скопіювати.",

	-- en: Token
	[ "menu.tokens.col_token" ] = "Змінна",

	-- en: Right now
	[ "menu.tokens.col_now" ] = "Зараз",

	-- en: Copied {token}
	[ "menu.tokens.copied" ] = "Скопійовано: {token}",

}
