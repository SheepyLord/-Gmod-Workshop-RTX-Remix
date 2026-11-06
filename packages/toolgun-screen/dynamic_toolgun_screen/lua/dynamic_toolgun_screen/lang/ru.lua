--[[
	Dynamic Toolgun Screen - Русский (ru)

	Made from lang/en.lua with tools/i18n.py (see TRANSLATING.md). Above each phrase, "-- en:" holds the
	English it translates; "tools/i18n.py check" lists phrases whose English changed since. A phrase
	missing here falls back to English.
]]

return {

	-- name of the language in that language, shown in the language list
	-- en: English
	[ "_name" ] = "Русский",

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
	[ "tool.name" ] = "Динамический экран Инструмент-пушки",

	-- en: Customize the tool gun's live screen and track entities on it
	[ "tool.desc" ] = "Настройка живого экрана Инструмент-пушки и отслеживание энтити на нём",

	-- en: Track the entity you are aiming at
	[ "tool.left" ] = "Отслеживать энтити, на которую вы целитесь",

	-- en: Switch to the next screen layout
	[ "tool.right" ] = "Следующий макет экрана",

	-- en: Stop tracking
	[ "tool.reload" ] = "Остановить отслеживание",

	-- context menu entry (right click an entity while holding C)
	-- en: Track on tool gun screen
	[ "prop.track" ] = "Отслеживать на экране Инструмент-пушки",

	-- Utilities tab: category and its only entry
	-- en: Dynamic Toolgun Screen
	[ "menu.category" ] = "Динамический экран Инструмент-пушки",

	-- en: Settings
	[ "menu.settings_item" ] = "Настройки",

	-- status line; {name} is an entity name such as "oildrum001" or a player's name
	-- en: Aiming at **{name}**
	[ "target.entity" ] = "Цель: **{name}**",

	-- en: Aiming at the **sky**
	[ "target.sky" ] = "Цель: **небо**",

	-- en: World
	[ "target.world" ] = "Мир",

	-- {surface} is a material from the mat.* phrases below
	-- en: World - **{surface}**
	[ "target.world_surface" ] = "Мир - **{surface}**",

	-- en: Nothing in range
	[ "target.nothing" ] = "Нет цели",

	-- what you aim at, when it is the sky
	-- en: sky
	[ "aim.sky" ] = "небо",

	-- multi-click tools (weld, rope...): which click comes next
	-- en: Stage {n}
	[ "tool.progress" ] = "Этап {n}",

	-- health of the tracked entity, e.g. "HP 40/100"
	-- en: HP {hp}
	[ "track.hp" ] = "ОЗ {hp}",

	-- en: Noclip
	[ "noclip" ] = "Режим полёта",

	-- view angles: P = pitch, Y = yaw
	-- en: P {p}  Y {y}
	[ "eye_ang" ] = "Наклон {p}  Поворот {y}",

	-- compass heading, e.g. "NE 45°"
	-- en: {dir} {deg}°
	[ "heading" ] = "{dir} {deg}°",

	-- en: N
	[ "compass.n" ] = "С",

	-- en: NE
	[ "compass.ne" ] = "СВ",

	-- en: E
	[ "compass.e" ] = "В",

	-- en: SE
	[ "compass.se" ] = "ЮВ",

	-- en: S
	[ "compass.s" ] = "Ю",

	-- en: SW
	[ "compass.sw" ] = "ЮЗ",

	-- en: W
	[ "compass.w" ] = "З",

	-- en: NW
	[ "compass.nw" ] = "СЗ",

	-- label of the FPS graph in the Terminal layout
	-- en: {n} fps
	[ "term.fps" ] = "{n} FPS",

	-- shown on the screen when it fails to draw
	-- en: Screen error
	[ "error.title" ] = "Ошибка экрана",

	-- en: See the console for details. Change the layout or run dts_reset to recover.
	[ "error.hint" ] = "Подробности в консоли. Смените макет или выполните dts_reset, чтобы всё восстановить.",

	-- tabs of the Advanced Toolgun [Hotbar] addon's tool list, for the {atg_tab} token
	-- en: Tools
	[ "atg.tab.tools" ] = "Инструменты",

	-- en: Wire
	[ "atg.tab.wire" ] = "Wire",

	-- en: Favorites
	[ "atg.tab.favorites" ] = "Избранное",

	-- the device's battery, next to the battery icon and in {battery}: {n} is the charge in percent;
	-- "Plugged in" is shown while the device runs on mains power instead of its battery
	-- en: {n}%
	[ "battery.percent" ] = "{n}%",

	-- en: Plugged in
	[ "battery.plugged" ] = "От сети",

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
	[ "unit.hu" ] = "{v} ед.",

	-- en: {v} km/h
	[ "unit.kmh" ] = "{v} км/ч",

	-- en: {v} mph
	[ "unit.mph" ] = "{v} миль/ч",

	-- en: {v} u/s
	[ "unit.ups" ] = "{v} ед./с",

	-- en: {v} kg
	[ "unit.kg" ] = "{v} кг",

	-- en: {v} MB
	[ "unit.mb" ] = "{v} МБ",

	-- Durations: {h} hours, {m} minutes, {s} seconds (minutes and seconds come with two digits)
	-- en: {h}h {m}m
	[ "duration.hm" ] = "{h} ч {m} мин",

	-- en: {m}m {s}s
	[ "duration.ms" ] = "{m} мин {s} с",

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
	[ "date.wday.1" ] = "Вс",

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
	[ "date.wday_full.1" ] = "воскресенье",

	-- en: Monday
	[ "date.wday_full.2" ] = "понедельник",

	-- en: Tuesday
	[ "date.wday_full.3" ] = "вторник",

	-- en: Wednesday
	[ "date.wday_full.4" ] = "среда",

	-- en: Thursday
	[ "date.wday_full.5" ] = "четверг",

	-- en: Friday
	[ "date.wday_full.6" ] = "пятница",

	-- en: Saturday
	[ "date.wday_full.7" ] = "суббота",

	-- short month names, used in dates ({month} above and %b): use the form your dates need
	-- en: Jan
	[ "date.month.1" ] = "янв.",

	-- en: Feb
	[ "date.month.2" ] = "февр.",

	-- en: Mar
	[ "date.month.3" ] = "мар.",

	-- en: Apr
	[ "date.month.4" ] = "апр.",

	-- en: May
	[ "date.month.5" ] = "мая",

	-- en: Jun
	[ "date.month.6" ] = "июня",

	-- en: Jul
	[ "date.month.7" ] = "июля",

	-- en: Aug
	[ "date.month.8" ] = "авг.",

	-- en: Sep
	[ "date.month.9" ] = "сент.",

	-- en: Oct
	[ "date.month.10" ] = "окт.",

	-- en: Nov
	[ "date.month.11" ] = "нояб.",

	-- en: Dec
	[ "date.month.12" ] = "дек.",

	-- full month names (%B), usually written right after a day number
	-- en: January
	[ "date.month_full.1" ] = "января",

	-- en: February
	[ "date.month_full.2" ] = "февраля",

	-- en: March
	[ "date.month_full.3" ] = "марта",

	-- en: April
	[ "date.month_full.4" ] = "апреля",

	-- en: May
	[ "date.month_full.5" ] = "мая",

	-- en: June
	[ "date.month_full.6" ] = "июня",

	-- en: July
	[ "date.month_full.7" ] = "июля",

	-- en: August
	[ "date.month_full.8" ] = "августа",

	-- en: September
	[ "date.month_full.9" ] = "сентября",

	-- en: October
	[ "date.month_full.10" ] = "октября",

	-- en: November
	[ "date.month_full.11" ] = "ноября",

	-- en: December
	[ "date.month_full.12" ] = "декабря",

	-- Kinds of surface material (the game's material types), shown as "World - Concrete"
	-- en: Antlion
	[ "mat.antlion" ] = "Муравьиный лев",

	-- en: Bloody flesh
	[ "mat.bloodyflesh" ] = "Окровавленная плоть",

	-- en: Concrete
	[ "mat.concrete" ] = "Бетон",

	-- en: Dirt
	[ "mat.dirt" ] = "Земля",

	-- en: Eggshell
	[ "mat.eggshell" ] = "Скорлупа",

	-- en: Flesh
	[ "mat.flesh" ] = "Плоть",

	-- en: Grate
	[ "mat.grate" ] = "Решётка",

	-- en: Alien flesh
	[ "mat.alienflesh" ] = "Плоть пришельца",

	-- en: Clip
	[ "mat.clip" ] = "Невидимая стена",

	-- en: Snow
	[ "mat.snow" ] = "Снег",

	-- en: Plastic
	[ "mat.plastic" ] = "Пластик",

	-- en: Metal
	[ "mat.metal" ] = "Металл",

	-- en: Sand
	[ "mat.sand" ] = "Песок",

	-- en: Foliage
	[ "mat.foliage" ] = "Листва",

	-- en: Computer
	[ "mat.computer" ] = "Электроника",

	-- en: Liquid
	[ "mat.slosh" ] = "Жидкость",

	-- en: Tile
	[ "mat.tile" ] = "Плитка",

	-- en: Grass
	[ "mat.grass" ] = "Трава",

	-- en: Vent
	[ "mat.vent" ] = "Вентиляция",

	-- en: Wood
	[ "mat.wood" ] = "Дерево",

	-- en: Generic
	[ "mat.default" ] = "Обычный",

	-- en: Glass
	[ "mat.glass" ] = "Стекло",

	-- en: Warp shield
	[ "mat.warpshield" ] = "Варп-щит",

	-- Notifications on the screen
	-- en: Tracking {name}
	[ "notify.tracking" ] = "Отслеживание: {name}",

	-- en: Stopped tracking
	[ "notify.untracked" ] = "Отслеживание остановлено",

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
	[ "tpl.props" ] = "Объекты {props}/{props_max}",

	-- en: {fps} fps  {ping} ms
	[ "tpl.perf" ] = "{fps} FPS  {ping} мс",

	-- en: Slope {aim_slope}
	[ "tpl.slope" ] = "Уклон {aim_slope}",

	-- en: HP {ent_health}
	[ "tpl.hp" ] = "ОЗ {ent_health}",

	-- en: Owner: {ent_owner}
	[ "tpl.owner" ] = "Владелец: {ent_owner}",

	-- HP = health, AP = armor
	-- en: HP {health}  AP {armor}
	[ "tpl.health_armor" ] = "ОЗ {health}  Броня {armor}",

	-- en: {players} players
	[ "tpl.players" ] = "Игроки: {players}",

	-- Terminal lines: a short upper case label, a tab, then the value
	-- en: TOOL\t**{tool}**
	[ "tpl.term_tool" ] = "ИНСТР\t**{tool}**",

	-- en: AIM\t**{aim_what}**
	[ "tpl.term_aim" ] = "ЦЕЛЬ\t**{aim_what}**",

	-- en: CLASS\t**{ent_class|-}**
	[ "tpl.term_class" ] = "КЛАСС\t**{ent_class|-}**",

	-- en: POS\t**{aim_pos}**
	[ "tpl.term_pos" ] = "ПОЗ\t**{aim_pos}**",

	-- en: DIST\t**{aim_dist}**  {aim_slope}
	[ "tpl.term_dist" ] = "ДИСТ\t**{aim_dist}**  {aim_slope}",

	-- en: OWNER\t**{ent_owner|-}**
	[ "tpl.term_owner" ] = "ВЛАД\t**{ent_owner|-}**",

	-- en: HP\t**{ent_health|-}**
	[ "tpl.term_hp" ] = "ОЗ\t**{ent_health|-}**",

	-- en: TRACK\t**{track_name|-}** {track_dist}
	[ "tpl.term_track" ] = "СЛЕЖ\t**{track_name|-}** {track_dist}",

	-- en: Pocket PC
	[ "layout.pocketpc.name" ] = "Pocket PC",

	-- en: The original screen rebuilt with live data: clock, status icons, tool history links, big tool name, status line, six readouts and a hint bar.
	[ "layout.pocketpc.desc" ] = "Исходный экран с живыми данными: часы, значки состояния, ссылки истории инструментов, крупное название инструмента, строка состояния, шесть показаний и строка подсказок.",

	-- en: Title bar
	[ "layout.pocketpc.title" ] = "Заголовок",

	-- en: Clock
	[ "layout.pocketpc.clock" ] = "Часы",

	-- en: Left link
	[ "layout.pocketpc.nav_l" ] = "Левая ссылка",

	-- en: Right link
	[ "layout.pocketpc.nav_r" ] = "Правая ссылка",

	-- en: Big text
	[ "layout.pocketpc.hero" ] = "Крупный текст",

	-- en: Under the big text
	[ "layout.pocketpc.sub" ] = "Под крупным текстом",

	-- en: Status line
	[ "layout.pocketpc.status" ] = "Строка состояния",

	-- en: Readout, left 1
	[ "layout.pocketpc.l1" ] = "Показание слева 1",

	-- en: Readout, left 2
	[ "layout.pocketpc.l2" ] = "Показание слева 2",

	-- en: Readout, left 3
	[ "layout.pocketpc.l3" ] = "Показание слева 3",

	-- en: Readout, right 1
	[ "layout.pocketpc.r1" ] = "Показание справа 1",

	-- en: Readout, right 2
	[ "layout.pocketpc.r2" ] = "Показание справа 2",

	-- en: Readout, right 3
	[ "layout.pocketpc.r3" ] = "Показание справа 3",

	-- en: Menu bar
	[ "layout.pocketpc.menu" ] = "Строка меню",

	-- en: Terminal
	[ "layout.terminal.name" ] = "Терминал",

	-- en: Developer readout: eight lines of labels and values, an FPS graph and a prompt line with the tool hints.
	[ "layout.terminal.desc" ] = "Сводка для разработчика: восемь строк «подпись — значение», график FPS и строка ввода с подсказками инструмента.",

	-- en: Header
	[ "layout.terminal.head" ] = "Заголовок",

	-- en: Header, right
	[ "layout.terminal.clock" ] = "Заголовок справа",

	-- en: Line 1
	[ "layout.terminal.l1" ] = "Строка 1",

	-- en: Line 2
	[ "layout.terminal.l2" ] = "Строка 2",

	-- en: Line 3
	[ "layout.terminal.l3" ] = "Строка 3",

	-- en: Line 4
	[ "layout.terminal.l4" ] = "Строка 4",

	-- en: Line 5
	[ "layout.terminal.l5" ] = "Строка 5",

	-- en: Line 6
	[ "layout.terminal.l6" ] = "Строка 6",

	-- en: Line 7
	[ "layout.terminal.l7" ] = "Строка 7",

	-- en: Line 8
	[ "layout.terminal.l8" ] = "Строка 8",

	-- en: Prompt line
	[ "layout.terminal.foot" ] = "Строка ввода",

	-- en: Minimal
	[ "layout.minimal.name" ] = "Минимальный",

	-- en: Large, glanceable text: clock, compass, the tool name sized to fit, what you aim at and two corner values.
	[ "layout.minimal.desc" ] = "Крупный текст, читаемый с одного взгляда: часы, компас, название инструмента по размеру, ваша цель и два значения по углам.",

	-- en: Top left
	[ "layout.minimal.top_l" ] = "Сверху слева",

	-- en: Top right
	[ "layout.minimal.top_r" ] = "Сверху справа",

	-- en: Big text
	[ "layout.minimal.hero" ] = "Крупный текст",

	-- en: Under the big text
	[ "layout.minimal.sub" ] = "Под крупным текстом",

	-- en: Bottom left
	[ "layout.minimal.foot_l" ] = "Снизу слева",

	-- en: Bottom right
	[ "layout.minimal.foot_r" ] = "Снизу справа",

	-- en: Pocket PC (original)
	[ "theme.winmobile" ] = "Pocket PC (оригинал)",

	-- en: Graphite
	[ "theme.graphite" ] = "Графит",

	-- en: Green phosphor
	[ "theme.phosphor" ] = "Зелёный люминофор",

	-- en: Amber CRT
	[ "theme.amber" ] = "Янтарный ЭЛТ",

	-- en: Sakura
	[ "theme.sakura" ] = "Сакура",

	-- en: Sandbox blue
	[ "theme.sandbox" ] = "Синий Sandbox",

	-- parts of the screen whose colour can be changed
	-- en: Title bar
	[ "color.bar" ] = "Заголовок",

	-- en: Links and highlights
	[ "color.accent" ] = "Ссылки и выделение",

	-- en: Big text
	[ "color.hero" ] = "Крупный текст",

	-- en: Status line
	[ "color.strip" ] = "Строка состояния",

	-- en: Readout panel
	[ "color.panel" ] = "Панель показаний",

	-- en: Menu bar
	[ "color.menu" ] = "Строка меню",

	-- en: Terminal text
	[ "color.term" ] = "Текст терминала",

	-- en: Text
	[ "category.text" ] = "Текст",

	-- en: Time
	[ "category.time" ] = "Время",

	-- en: Tool
	[ "category.tool" ] = "Инструмент",

	-- en: Aim
	[ "category.aim" ] = "Прицел",

	-- en: Aimed entity
	[ "category.entity" ] = "Энтити под прицелом",

	-- en: Tracked entity
	[ "category.tracked" ] = "Отслеживаемая энтити",

	-- en: You
	[ "category.player" ] = "Вы",

	-- en: Game
	[ "category.game" ] = "Игра",

	-- the Advanced Toolgun [Hotbar] addon; keep its name as it is
	-- en: Advanced Toolgun
	[ "category.atg" ] = "Advanced Toolgun",

	-- en: A line in your language from the language files, e.g. {tr:nav_back} or {tr:props}.
	[ "token.tr" ] = "Строка на вашем языке из языковых файлов, например {tr:nav_back} или {tr:props}.",

	-- en: Local time, formatted by the clock settings. {time:%H:%M:%S} takes an os.date format.
	[ "token.time" ] = "Местное время в формате из настроек часов. {time:%H:%M:%S} принимает формат os.date.",

	-- en: Today's date. {date:%Y-%m-%d} takes an os.date format.
	[ "token.date" ] = "Сегодняшняя дата. {date:%Y-%m-%d} принимает формат os.date.",

	-- en: How long you have been in this game.
	[ "token.session" ] = "Сколько вы уже в этой игре.",

	-- en: How long the map has been running.
	[ "token.map_time" ] = "Сколько идёт текущая карта.",

	-- en: Name of the selected tool.
	[ "token.tool" ] = "Название выбранного инструмента.",

	-- en: Internal name of the selected tool.
	[ "token.tool_id" ] = "Внутреннее имя выбранного инструмента.",

	-- en: Description of the selected tool.
	[ "token.tool_desc" ] = "Описание выбранного инструмента.",

	-- en: Tool menu category of the selected tool.
	[ "token.tool_category" ] = "Категория выбранного инструмента в меню инструментов.",

	-- en: Stage of the selected tool (0 = nothing selected yet).
	[ "token.tool_stage" ] = "Этап выбранного инструмента (0 = ещё ничего не выбрано).",

	-- en: The stage while a multi-click tool is in progress, otherwise empty.
	[ "token.tool_progress" ] = "Этап, пока идёт работа инструментом в несколько кликов, иначе пусто.",

	-- en: The tool you used before this one (dts_tool_back switches to it).
	[ "token.tool_prev" ] = "Инструмент, который был выбран до текущего (dts_tool_back переключает на него).",

	-- en: The next tool in the same menu category (dts_tool_next switches to it).
	[ "token.tool_next" ] = "Следующий инструмент той же категории меню (dts_tool_next переключает на него).",

	-- en: Successful tool gun shots this session.
	[ "token.tool_uses" ] = "Удачные выстрелы Инструмент-пушки за эту игру.",

	-- en: A setting of the selected tool, e.g. {tool_cvar:forcelimit} reads weld_forcelimit.
	[ "token.tool_cvar" ] = "Настройка выбранного инструмента, например {tool_cvar:forcelimit} читает weld_forcelimit.",

	-- en: All settings of the selected tool as name=value pairs.
	[ "token.tool_settings" ] = "Все настройки выбранного инструмента в виде имя=значение.",

	-- en: The current stage's instructions with mouse and key icons.
	[ "token.hints" ] = "Подсказки текущего этапа со значками мыши и клавиш.",

	-- en: What left click does right now.
	[ "token.hint_left" ] = "Что сейчас делает левый клик.",

	-- en: What right click does right now.
	[ "token.hint_right" ] = "Что сейчас делает правый клик.",

	-- en: What reload does right now.
	[ "token.hint_reload" ] = "Что сейчас делает клавиша перезарядки.",

	-- en: What you are aiming at, with the name highlighted.
	[ "token.target" ] = "На что вы целитесь, с выделенным названием.",

	-- en: Entity name, or the surface material when aiming at the world.
	[ "token.aim_what" ] = "Название энтити или материал поверхности, если вы целитесь в мир.",

	-- en: Position you are aiming at.
	[ "token.aim_pos" ] = "Точка, в которую вы целитесь.",

	-- en: X of the aim position.
	[ "token.aim_x" ] = "X точки прицела.",

	-- en: Y of the aim position.
	[ "token.aim_y" ] = "Y точки прицела.",

	-- en: Z of the aim position.
	[ "token.aim_z" ] = "Z точки прицела.",

	-- en: Distance to the aim position.
	[ "token.aim_dist" ] = "Расстояние до точки прицела.",

	-- en: Surface normal at the aim position.
	[ "token.aim_normal" ] = "Нормаль поверхности в точке прицела.",

	-- en: Steepness of the surface (0 = flat floor, 90 = wall).
	[ "token.aim_slope" ] = "Крутизна поверхности (0 = ровный пол, 90 = стена).",

	-- en: Kind of surface material (metal, wood, concrete...).
	[ "token.aim_surface" ] = "Вид материала поверхности (металл, дерево, бетон...).",

	-- en: Surface property as the engine names it (metal box, wood crate...).
	[ "token.aim_surfaceprop" ] = "Свойство поверхности в названии движка (metal box, wood crate...).",

	-- en: World texture you are aiming at.
	[ "token.aim_texture" ] = "Текстура мира, в которую вы целитесь.",

	-- en: Friendly name of the aimed entity.
	[ "token.ent_name" ] = "Понятное название энтити под прицелом.",

	-- en: Class of the aimed entity.
	[ "token.ent_class" ] = "Класс энтити под прицелом.",

	-- en: Model file name of the aimed entity.
	[ "token.ent_model" ] = "Имя файла модели энтити под прицелом.",

	-- en: Full model path of the aimed entity.
	[ "token.ent_model_path" ] = "Полный путь модели энтити под прицелом.",

	-- en: Entity index.
	[ "token.ent_index" ] = "Номер энтити.",

	-- en: Health of the aimed entity (players, NPCs, breakable props).
	[ "token.ent_health" ] = "Здоровье энтити под прицелом (игроки, NPC, разрушаемые объекты).",

	-- en: Owner of the aimed entity (in multiplayer this needs a CPPI prop protection addon).
	[ "token.ent_owner" ] = "Владелец энтити под прицелом (в мультиплеере нужен аддон защиты объектов с поддержкой CPPI).",

	-- en: Material of the aimed entity.
	[ "token.ent_material" ] = "Материал энтити под прицелом.",

	-- en: Colour of the aimed entity.
	[ "token.ent_color" ] = "Цвет энтити под прицелом.",

	-- en: Skin of the aimed entity.
	[ "token.ent_skin" ] = "Скин энтити под прицелом.",

	-- en: Speed of the aimed entity.
	[ "token.ent_speed" ] = "Скорость энтити под прицелом.",

	-- en: Position of the aimed entity.
	[ "token.ent_pos" ] = "Положение энтити под прицелом.",

	-- en: Angles of the aimed entity.
	[ "token.ent_ang" ] = "Углы поворота энтити под прицелом.",

	-- en: Mass of the aimed entity, when your game knows its physics.
	[ "token.ent_mass" ] = "Масса энтити под прицелом, если игра знает её физику.",

	-- en: Tracked entity summary: name, distance, speed, health.
	[ "token.track" ] = "Сводка по отслеживаемой энтити: название, расстояние, скорость, здоровье.",

	-- en: Name of the tracked entity.
	[ "token.track_name" ] = "Название отслеживаемой энтити.",

	-- en: Class of the tracked entity.
	[ "token.track_class" ] = "Класс отслеживаемой энтити.",

	-- en: Your distance to the tracked entity.
	[ "token.track_dist" ] = "Расстояние до отслеживаемой энтити.",

	-- en: Speed of the tracked entity.
	[ "token.track_speed" ] = "Скорость отслеживаемой энтити.",

	-- en: Health of the tracked entity.
	[ "token.track_health" ] = "Здоровье отслеживаемой энтити.",

	-- en: Position of the tracked entity.
	[ "token.track_pos" ] = "Положение отслеживаемой энтити.",

	-- en: Your name.
	[ "token.player" ] = "Ваш ник.",

	-- en: Your health.
	[ "token.health" ] = "Ваше здоровье.",

	-- en: Your armor.
	[ "token.armor" ] = "Ваша броня.",

	-- en: Your speed.
	[ "token.speed" ] = "Ваша скорость.",

	-- en: Your position.
	[ "token.pos" ] = "Ваше положение.",

	-- en: Your view pitch and yaw.
	[ "token.eye_ang" ] = "Наклон и поворот вашего взгляда.",

	-- en: Compass heading (north is +Y on the map).
	[ "token.heading" ] = "Направление по компасу (север — это +Y на карте).",

	-- en: Shows a word while you are noclipping, otherwise empty.
	[ "token.noclip" ] = "Слово, пока включён режим полёта (noclip), иначе пусто.",

	-- en: Frames per second (smoothed).
	[ "token.fps" ] = "Кадры в секунду (сглаженно).",

	-- en: Your ping in milliseconds.
	[ "token.ping" ] = "Ваш пинг в миллисекундах.",

	-- en: Your device's battery charge while it runs on battery, or \"Plugged in\".
	[ "token.battery" ] = "Заряд батареи вашего устройства при работе от батареи, иначе «От сети».",

	-- en: Current map.
	[ "token.map" ] = "Текущая карта.",

	-- en: Players on the server and its player limit.
	[ "token.players" ] = "Игроки на сервере и их лимит.",

	-- en: Server name.
	[ "token.server" ] = "Название сервера.",

	-- en: Active gamemode.
	[ "token.gamemode" ] = "Текущий режим игры.",

	-- en: Server tick rate.
	[ "token.tickrate" ] = "Тикрейт сервера.",

	-- en: Memory used by Lua in your game.
	[ "token.lua_mem" ] = "Память, занятая Lua в вашей игре.",

	-- en: Entities known to your game.
	[ "token.entities" ] = "Число энтити, известных вашей игре.",

	-- en: Props you have spawned.
	[ "token.props" ] = "Созданные вами объекты.",

	-- en: Your prop limit.
	[ "token.props_max" ] = "Ваш лимит объектов.",

	-- en: Spawn count and limit of a type, e.g. {count:ragdolls} or {count:thrusters}.
	[ "token.count" ] = "Число созданных объектов типа и лимит, например {count:ragdolls} или {count:thrusters}.",

	-- en: Value of any console variable, e.g. {cvar:sv_gravity}.
	[ "token.cvar" ] = "Значение любой консольной переменной, например {cvar:sv_gravity}.",

	-- en: Advanced Toolgun [Hotbar]: its open tab (Tools, Wire or Favorites).
	[ "token.atg_tab" ] = "Advanced Toolgun [Hotbar]: его открытая вкладка (Инструменты, Wire или Избранное).",

	-- en: Advanced Toolgun [Hotbar]: the section of its list the selection is in.
	[ "token.atg_section" ] = "Advanced Toolgun [Hotbar]: раздел его списка, в котором находится выбор.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel up.
	[ "token.atg_prev" ] = "Advanced Toolgun [Hotbar]: инструмент, на который его быстрый выбор переключит колесом мыши вверх.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel down.
	[ "token.atg_next" ] = "Advanced Toolgun [Hotbar]: инструмент, на который его быстрый выбор переключит колесом мыши вниз.",

	-- en: Turns the tool gun's mini screen into a live display. Changes apply instantly; the preview shows what the screen draws right now.
	[ "menu.intro" ] = "Превращает маленький экран Инструмент-пушки в живой дисплей. Изменения применяются сразу; превью показывает, что экран рисует прямо сейчас.",

	-- en: Dynamic screen is off
	[ "menu.preview_off" ] = "Динамический экран выключен",

	-- en: Enable the dynamic screen
	[ "menu.enable" ] = "Включить динамический экран",

	-- en: Language
	[ "menu.language" ] = "Язык",

	-- first entry of the language list; {name} is the game's language, e.g. "English"
	-- en: Automatic: {name}
	[ "menu.language.auto" ] = "Автоматически: {name}",

	-- en: Inspect: read the screen up close
	[ "menu.inspect.title" ] = "Осмотр: читать экран вблизи",

	-- en: Hold a key while holding the tool gun to raise its screen to your eyes.
	[ "menu.inspect.help" ] = "Держите клавишу с Инструмент-пушкой в руках, чтобы поднести экран к глазам.",

	-- en: Inspect key
	[ "menu.inspect.key" ] = "Клавиша осмотра",

	-- en: Screen size while inspecting
	[ "menu.inspect.size" ] = "Размер экрана при осмотре",

	-- en: Or use the console: bind <key> +dts_inspect (hold) or dts_inspect_toggle.
	[ "menu.inspect.console" ] = "Или через консоль: bind <клавиша> +dts_inspect (удерживать) или dts_inspect_toggle.",

	-- the tool gun model has a paper note glued on, which overlaps the screen's top right corner
	-- en: Screen in front of the paper note
	[ "menu.inspect.on_top" ] = "Экран поверх бумажной записки",

	-- en: While inspecting, the whole screen stays readable. Untick to let the paper note glued to the tool gun cover the top right corner of the screen, as on the model.
	[ "menu.inspect.on_top_help" ] = "При осмотре весь экран остаётся читаемым. Выключите, чтобы бумажная записка, приклеенная к Инструмент-пушке, закрывала правый верхний угол экрана, как на модели.",

	-- en: Layout and look
	[ "menu.look.title" ] = "Макет и вид",

	-- en: Layout
	[ "menu.look.layout" ] = "Макет",

	-- en: Theme
	[ "menu.look.theme" ] = "Тема",

	-- en: Background
	[ "menu.look.background" ] = "Фон",

	-- en: Automatic (layout's choice)
	[ "menu.bg.auto" ] = "Автоматически (по макету)",

	-- the whole original screen picture without its text
	-- en: Original screen
	[ "menu.bg.original" ] = "Исходный экран",

	-- only the blurred photo from the original picture, filling the screen
	-- en: Original photo
	[ "menu.bg.art" ] = "Исходное фото",

	-- en: Theme gradient
	[ "menu.bg.gradient" ] = "Градиент темы",

	-- en: Live camera: zoom
	[ "menu.bg.camera" ] = "Живая камера: приближение",

	-- en: Live camera: rear view
	[ "menu.bg.rear" ] = "Живая камера: вид назад",

	-- en: Custom image
	[ "menu.bg.image" ] = "Своя картинка",

	-- en: Black
	[ "menu.bg.black" ] = "Чёрный",

	-- en: Custom image
	[ "menu.look.image" ] = "Своя картинка",

	-- en: A material path, or an image in garrysmod/data written as ../data/name.png
	[ "menu.look.image_help" ] = "Путь к материалу или картинка из garrysmod/data в виде ../data/имя.png",

	-- en: Darken background
	[ "menu.look.dim" ] = "Затемнить фон",

	-- en: Camera field of view
	[ "menu.look.cam_fov" ] = "Поле зрения камеры",

	-- en: Camera updates per second
	[ "menu.look.cam_fps" ] = "Обновлений камеры в секунду",

	-- en: Text font
	[ "menu.look.font" ] = "Шрифт текста",

	-- en: Big text font
	[ "menu.look.font_hero" ] = "Шрифт крупного текста",

	-- en: Terminal font
	[ "menu.look.font_mono" ] = "Шрифт терминала",

	-- first entry of the font lists; {font} is the font your language uses
	-- en: Automatic ({font})
	[ "menu.font.auto" ] = "Автоматически ({font})",

	-- en: Colours
	[ "menu.colors.title" ] = "Цвета",

	-- en: Override single colours of the theme. Click a swatch to change it.
	[ "menu.colors.help" ] = "Замена отдельных цветов темы. Нажмите на образец, чтобы изменить цвет.",

	-- written on a colour swatch that still uses the theme's colour
	-- en: theme
	[ "menu.colors.theme_tag" ] = "тема",

	-- en: Click to pick a colour
	[ "menu.colors.pick" ] = "Нажмите, чтобы выбрать цвет",

	-- en: Use the theme's colours everywhere
	[ "menu.colors.reset_all" ] = "Везде использовать цвета темы",

	-- en: Screen colour: {name}
	[ "menu.colors.picker_title" ] = "Цвет экрана: {name}",

	-- en: Use the theme's colour
	[ "menu.colors.use_theme" ] = "Цвет темы",

	-- en: Big text
	[ "menu.hero.title" ] = "Крупный текст",

	-- en: Behaviour
	[ "menu.hero.mode" ] = "Поведение",

	-- en: Always scroll (original)
	[ "menu.hero.scroll" ] = "Всегда прокручивать (оригинал)",

	-- en: Scroll only when too long
	[ "menu.hero.auto" ] = "Прокручивать, только если не помещается",

	-- en: Shrink to fit
	[ "menu.hero.fit" ] = "Уменьшать до размера",

	-- en: Scroll speed
	[ "menu.hero.speed" ] = "Скорость прокрутки",

	-- en: Upper case tool names
	[ "menu.hero.upper" ] = "Названия инструментов заглавными буквами",

	-- en: Screen content
	[ "menu.content.title" ] = "Содержимое экрана",

	-- keep {tokens}, **stars**, {token|fallback} and {tr:...} as they are: they show the syntax
	-- en: Every line of the {layout} layout is a template. Type text and {tokens}; **stars** highlight text, {token|fallback} gives a default, and a line whose tokens are all empty hides itself. {tr:...} writes a line in your language. See the token reference below.
	[ "menu.content.help" ] = "Каждая строка макета «{layout}» — это шаблон. Пишите текст и {tokens}; **звёздочки** выделяют текст, {token|fallback} задаёт текст на случай, когда значение пустое, а строка, в которой все переменные пусты, скрывается сама. {tr:...} пишет строку на вашем языке. Список переменных — ниже.",

	-- en: Pick a ready-made line
	[ "menu.content.presets_tip" ] = "Выбрать готовую строку",

	-- en: Back to the default: {value}
	[ "menu.content.reset_tip" ] = "Вернуть по умолчанию: {value}",

	-- en: (empty)
	[ "menu.content.empty" ] = "(пусто)",

	-- shown in an empty line's text box
	-- en: (hidden)
	[ "menu.content.placeholder" ] = "(скрыто)",

	-- under each line: what it shows right now
	-- en: = {text}
	[ "menu.content.now" ] = "= {text}",

	-- en: (hidden right now)
	[ "menu.content.hidden_now" ] = "(сейчас скрыта)",

	-- en: Reset these lines to the layout's defaults
	[ "menu.content.reset_all" ] = "Вернуть строки макета по умолчанию",

	-- ready-made lines in the list next to each line
	-- en: Tool name
	[ "menu.preset.tool" ] = "Название инструмента",

	-- en: Tool category
	[ "menu.preset.tool_category" ] = "Категория инструмента",

	-- en: Tool instructions
	[ "menu.preset.hints" ] = "Подсказки инструмента",

	-- en: Previous tool
	[ "menu.preset.prev_tool" ] = "Предыдущий инструмент",

	-- en: Next tool
	[ "menu.preset.next_tool" ] = "Следующий инструмент",

	-- en: Tool progress
	[ "menu.preset.progress" ] = "Этап инструмента",

	-- en: Tool settings
	[ "menu.preset.tool_settings" ] = "Настройки инструмента",

	-- en: What you aim at
	[ "menu.preset.target" ] = "Цель",

	-- en: Aim position
	[ "menu.preset.aim_pos" ] = "Точка прицела",

	-- en: Aim distance
	[ "menu.preset.aim_dist" ] = "Расстояние до цели",

	-- en: Entity or surface
	[ "menu.preset.aim_what" ] = "Энтити или поверхность",

	-- en: Surface slope
	[ "menu.preset.slope" ] = "Уклон поверхности",

	-- en: Entity class
	[ "menu.preset.ent_class" ] = "Класс энтити",

	-- en: Entity model
	[ "menu.preset.ent_model" ] = "Модель энтити",

	-- en: Entity health
	[ "menu.preset.ent_health" ] = "Здоровье энтити",

	-- en: Entity owner
	[ "menu.preset.ent_owner" ] = "Владелец энтити",

	-- en: Entity speed
	[ "menu.preset.ent_speed" ] = "Скорость энтити",

	-- en: Tracked entity
	[ "menu.preset.track" ] = "Отслеживаемая энтити",

	-- en: Clock
	[ "menu.preset.clock" ] = "Часы",

	-- en: Clock with seconds
	[ "menu.preset.clock_seconds" ] = "Часы с секундами",

	-- en: Date
	[ "menu.preset.date" ] = "Дата",

	-- en: Time in game
	[ "menu.preset.session" ] = "Время в игре",

	-- en: Your speed
	[ "menu.preset.speed" ] = "Ваша скорость",

	-- en: Your position
	[ "menu.preset.pos" ] = "Ваше положение",

	-- en: Compass
	[ "menu.preset.heading" ] = "Компас",

	-- en: Health and armor
	[ "menu.preset.health_armor" ] = "Здоровье и броня",

	-- en: FPS and ping
	[ "menu.preset.perf" ] = "FPS и пинг",

	-- en: Prop count
	[ "menu.preset.props" ] = "Число объектов",

	-- en: Map
	[ "menu.preset.map" ] = "Карта",

	-- en: Players
	[ "menu.preset.players" ] = "Игроки",

	-- en: Empty (hide the line)
	[ "menu.preset.empty" ] = "Пусто (скрыть строку)",

	-- en: Clock and units
	[ "menu.clock.title" ] = "Часы и единицы",

	-- en: Clock
	[ "menu.clock.style" ] = "Часы",

	-- {language} is the name of the active language
	-- en: As usual in {language}
	[ "menu.clock.auto" ] = "Как принято: {language}",

	-- en: 12 hour
	[ "menu.clock.12h" ] = "12-часовые",

	-- en: 24 hour
	[ "menu.clock.24h" ] = "24-часовые",

	-- en: Show seconds
	[ "menu.clock.seconds" ] = "Показывать секунды",

	-- en: Show AM / PM (12 hour clock)
	[ "menu.clock.ampm" ] = "Показывать AM / PM (12-часовые часы)",

	-- en: Blink the colon
	[ "menu.clock.blink" ] = "Мигающее двоеточие",

	-- en: Units
	[ "menu.units.label" ] = "Единицы",

	-- en: Metric (m, km/h)
	[ "menu.units.m" ] = "Метрические (м, км/ч)",

	-- en: Imperial (ft, mph)
	[ "menu.units.ft" ] = "Имперские (фт, миль/ч)",

	-- en: Hammer units
	[ "menu.units.hu" ] = "Единицы Hammer",

	-- en: Distance decimals
	[ "menu.units.decimals" ] = "Знаков после запятой у расстояний",

	-- en: Icons and effects
	[ "menu.fx.title" ] = "Значки и эффекты",

	-- en: Speaker icon (volume, voice chat)
	[ "menu.fx.speaker" ] = "Значок динамика (громкость, голосовой чат)",

	-- en: Signal icon (connection)
	[ "menu.fx.signal" ] = "Значок сигнала (соединение)",

	-- en: Battery icon (your device's battery)
	[ "menu.fx.battery" ] = "Значок батареи (батарея вашего устройства)",

	-- en: Boot animation when taking out the tool gun
	[ "menu.fx.boot" ] = "Анимация загрузки, когда вы достаёте Инструмент-пушку",

	-- en: Flash when the tool gun fires
	[ "menu.fx.flash" ] = "Вспышка экрана при выстреле Инструмент-пушки",

	-- en: Show game notifications on the screen
	[ "menu.fx.notify" ] = "Показывать уведомления игры на экране",

	-- en: Notification time
	[ "menu.fx.notify_time" ] = "Время показа уведомлений",

	-- en: Scanlines
	[ "menu.fx.scanlines" ] = "Строки развёртки",

	-- en: Darker edges
	[ "menu.fx.vignette" ] = "Затемнять края",

	-- en: Backlight
	[ "menu.fx.backlight" ] = "Подсветка",

	-- en: HUD mirror
	[ "menu.mirror.title" ] = "Зеркало на HUD",

	-- en: Shows the screen on your HUD while you hold the tool gun, for reading the small print.
	[ "menu.mirror.help" ] = "Показывает экран ещё и на HUD, пока у вас в руках Инструмент-пушка, чтобы удобно читать мелкий текст.",

	-- en: Show the screen on the HUD
	[ "menu.mirror.enable" ] = "Показывать экран на HUD",

	-- en: Corner
	[ "menu.mirror.corner" ] = "Угол",

	-- en: Top right
	[ "menu.corner.tr" ] = "Справа сверху",

	-- en: Bottom right
	[ "menu.corner.br" ] = "Справа снизу",

	-- en: Bottom left
	[ "menu.corner.bl" ] = "Слева снизу",

	-- en: Top left
	[ "menu.corner.tl" ] = "Слева сверху",

	-- en: Size
	[ "menu.mirror.size" ] = "Размер",

	-- en: Opacity
	[ "menu.mirror.alpha" ] = "Непрозрачность",

	-- en: Advanced
	[ "menu.adv.title" ] = "Дополнительно",

	-- en: Keep the own screens of tools that draw one
	[ "menu.adv.respect" ] = "Оставлять собственные экраны инструментов, у которых они есть",

	-- en: e.g. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod tools
	[ "menu.adv.respect_help" ] = "например, Easy Entity Inspector, Ragdoll Puppeteer, инструменты Wiremod",

	-- en: Live value updates per second
	[ "menu.adv.refresh" ] = "Обновлений значений в секунду",

	-- en: Screen redraws per second (0 = every frame)
	[ "menu.adv.fps" ] = "Перерисовок экрана в секунду (0 = каждый кадр)",

	-- en: Resolution
	[ "menu.adv.resolution" ] = "Разрешение",

	-- en: 256 x 256 (original)
	[ "menu.res.256" ] = "256 x 256 (оригинал)",

	-- en: 512 x 512 (sharper, for 1440p and up)
	[ "menu.res.512" ] = "512 x 512 (чётче, для 1440p и выше)",

	-- keep the commands as they are
	-- en: Key binds (bind <key> <command>):\n  dts_tool_back  -  previous tool\n  dts_tool_next / dts_tool_prev  -  cycle the category\n  dts_layout_next, dts_theme_next  -  cycle layouts, themes\n  dts_track / dts_untrack  -  follow an entity
	[ "menu.adv.binds" ] = "Привязки клавиш (bind <клавиша> <команда>):\n  dts_tool_back  -  предыдущий инструмент\n  dts_tool_next / dts_tool_prev  -  листать категорию\n  dts_layout_next, dts_theme_next  -  листать макеты, темы\n  dts_track / dts_untrack  -  отслеживать энтити",

	-- en: Copy my settings to the clipboard
	[ "menu.adv.copy" ] = "Скопировать мои настройки в буфер обмена",

	-- en: Screen settings copied to the clipboard
	[ "menu.adv.copied" ] = "Настройки экрана скопированы в буфер обмена",

	-- en: Import settings...
	[ "menu.adv.import" ] = "Импорт настроек...",

	-- en: Import screen settings
	[ "menu.adv.import_title" ] = "Импорт настроек экрана",

	-- en: Paste a DTS1:... settings string
	[ "menu.adv.import_prompt" ] = "Вставьте строку настроек DTS1:...",

	-- en: Import
	[ "menu.adv.import_ok" ] = "Импортировать",

	-- en: Imported screen settings ({n} changed)
	[ "menu.adv.imported" ] = "Настройки экрана импортированы (изменено: {n})",

	-- en: Reset everything to defaults
	[ "menu.adv.reset" ] = "Сбросить всё по умолчанию",

	-- en: Reset
	[ "menu.adv.reset_title" ] = "Сброс",

	-- en: Reset every Dynamic Toolgun Screen setting?
	[ "menu.adv.reset_question" ] = "Сбросить все настройки динамического экрана Инструмент-пушки?",

	-- en: Reset
	[ "menu.adv.reset_yes" ] = "Сбросить",

	-- en: Cancel
	[ "menu.adv.cancel" ] = "Отмена",

	-- en: Another addon replaced the tool gun screen ({file}). Use the button below to take over.
	[ "menu.adv.diag_conflict" ] = "Другой аддон заменил экран Инструмент-пушки ({file}). Кнопка ниже вернёт управление.",

	-- en: v{version} installed. Each redraw takes {ms} ms.
	[ "menu.adv.diag_ok" ] = "v{version} установлен. Одна перерисовка занимает {ms} мс.",

	-- en: Last error: {error}
	[ "menu.adv.diag_error" ] = "Последняя ошибка: {error}",

	-- en: Waiting for the tool gun to load...
	[ "menu.adv.diag_wait" ] = "Ожидание загрузки Инструмент-пушки...",

	-- en: Take over the tool gun screen
	[ "menu.adv.takeover" ] = "Вернуть управление экраном Инструмент-пушки",

	-- en: Only needed if another addon replaced the tool gun's screen after this one
	[ "menu.adv.takeover_tip" ] = "Нужно, только если другой аддон заменил экран Инструмент-пушки после этого аддона",

	-- en: Dynamic Toolgun Screen installed
	[ "menu.adv.takeover_done" ] = "Управление экраном Инструмент-пушки возвращено",

	-- answers to "Import settings..." when the pasted text is wrong
	-- en: This is not a Dynamic Toolgun Screen settings string.
	[ "import.not_ours" ] = "Это не строка настроек динамического экрана Инструмент-пушки.",

	-- en: The settings string is damaged.
	[ "import.damaged" ] = "Строка настроек повреждена.",

	-- en: Token reference
	[ "menu.tokens.title" ] = "Список переменных",

	-- en: Hover a token for what it does, double-click to copy it.
	[ "menu.tokens.help" ] = "Наведите курсор на переменную, чтобы увидеть, что она делает; двойной клик — скопировать.",

	-- en: Token
	[ "menu.tokens.col_token" ] = "Переменная",

	-- en: Right now
	[ "menu.tokens.col_now" ] = "Сейчас",

	-- en: Copied {token}
	[ "menu.tokens.copied" ] = "Скопировано: {token}",

}
