--[[
	Dynamic Toolgun Screen - 繁體中文 (zh-tw)

	Made from lang/en.lua with tools/i18n.py (see TRANSLATING.md). Above each phrase, "-- en:" holds the
	English it translates; "tools/i18n.py check" lists phrases whose English changed since. A phrase
	missing here falls back to English.
]]

return {

	-- name of the language in that language, shown in the language list
	-- en: English
	[ "_name" ] = "繁體中文",

	-- decimal separator for numbers on the screen
	-- en: .
	[ "_decimal" ] = ".",

	-- 1 if a 24 hour clock is usual in this language, 0 for 12 hour
	-- en: 0
	[ "_clock24" ] = "0",

	-- fonts that have every letter of the language; size factor and weight snapping (1/0) for them
	-- en: Tahoma
	[ "_font.ui" ] = "Microsoft JhengHei UI",

	-- en: Helvetica
	[ "_font.hero" ] = "Microsoft JhengHei UI",

	-- en: Consolas
	[ "_font.mono" ] = "Microsoft JhengHei UI",

	-- en: 1
	[ "_font.scale" ] = "1",

	-- en: 0
	[ "_font.snap" ] = "1",

	-- Shown by the game: the tool list, the tool's help on the HUD, the context menu, the Utilities tab --
	-- en: Dynamic Toolgun Screen
	[ "tool.name" ] = "動態工具槍螢幕",

	-- en: Customize the tool gun's live screen and track entities on it
	[ "tool.desc" ] = "自訂工具槍的即時螢幕，並用它追蹤實體",

	-- en: Track the entity you are aiming at
	[ "tool.left" ] = "追蹤你瞄準的實體",

	-- en: Switch to the next screen layout
	[ "tool.right" ] = "切換到下一個螢幕版面配置",

	-- en: Stop tracking
	[ "tool.reload" ] = "停止追蹤",

	-- context menu entry (right click an entity while holding C)
	-- en: Track on tool gun screen
	[ "prop.track" ] = "在工具槍螢幕上追蹤",

	-- Utilities tab: category and its only entry
	-- en: Dynamic Toolgun Screen
	[ "menu.category" ] = "動態工具槍螢幕",

	-- en: Settings
	[ "menu.settings_item" ] = "設定",

	-- status line; {name} is an entity name such as "oildrum001" or a player's name
	-- en: Aiming at **{name}**
	[ "target.entity" ] = "瞄準：**{name}**",

	-- en: Aiming at the **sky**
	[ "target.sky" ] = "瞄準：**天空**",

	-- en: World
	[ "target.world" ] = "地圖",

	-- {surface} is a material from the mat.* phrases below
	-- en: World - **{surface}**
	[ "target.world_surface" ] = "地圖 - **{surface}**",

	-- en: Nothing in range
	[ "target.nothing" ] = "範圍內沒有目標",

	-- what you aim at, when it is the sky
	-- en: sky
	[ "aim.sky" ] = "天空",

	-- multi-click tools (weld, rope...): which click comes next
	-- en: Stage {n}
	[ "tool.progress" ] = "第 {n} 步",

	-- health of the tracked entity, e.g. "HP 40/100"
	-- en: HP {hp}
	[ "track.hp" ] = "生命 {hp}",

	-- en: Noclip
	[ "noclip" ] = "穿牆",

	-- view angles: P = pitch, Y = yaw
	-- en: P {p}  Y {y}
	[ "eye_ang" ] = "俯仰 {p}  偏航 {y}",

	-- compass heading, e.g. "NE 45°"
	-- en: {dir} {deg}°
	[ "heading" ] = "{dir} {deg}°",

	-- en: N
	[ "compass.n" ] = "北",

	-- en: NE
	[ "compass.ne" ] = "東北",

	-- en: E
	[ "compass.e" ] = "東",

	-- en: SE
	[ "compass.se" ] = "東南",

	-- en: S
	[ "compass.s" ] = "南",

	-- en: SW
	[ "compass.sw" ] = "西南",

	-- en: W
	[ "compass.w" ] = "西",

	-- en: NW
	[ "compass.nw" ] = "西北",

	-- label of the FPS graph in the Terminal layout
	-- en: {n} fps
	[ "term.fps" ] = "{n} FPS",

	-- shown on the screen when it fails to draw
	-- en: Screen error
	[ "error.title" ] = "螢幕發生錯誤",

	-- en: See the console for details. Change the layout or run dts_reset to recover.
	[ "error.hint" ] = "詳細資訊請查看主控台。更換版面配置或執行 dts_reset 即可復原。",

	-- tabs of the Advanced Toolgun [Hotbar] addon's tool list, for the {atg_tab} token
	-- en: Tools
	[ "atg.tab.tools" ] = "工具",

	-- en: Wire
	[ "atg.tab.wire" ] = "Wire",

	-- en: Favorites
	[ "atg.tab.favorites" ] = "我的最愛",

	-- the device's battery, next to the battery icon and in {battery}: {n} is the charge in percent;
	-- "Plugged in" is shown while the device runs on mains power instead of its battery
	-- en: {n}%
	[ "battery.percent" ] = "{n}%",

	-- en: Plugged in
	[ "battery.plugged" ] = "已接上電源",

	-- Units: {v} is the number, already written with the decimal separator above
	-- en: {v} m
	[ "unit.m" ] = "{v} 公尺",

	-- en: {v} km
	[ "unit.km" ] = "{v} 公里",

	-- en: {v} ft
	[ "unit.ft" ] = "{v} 英尺",

	-- en: {v} mi
	[ "unit.mi" ] = "{v} 英里",

	-- Hammer units, the game's own distance unit
	-- en: {v} u
	[ "unit.hu" ] = "{v} 單位",

	-- en: {v} km/h
	[ "unit.kmh" ] = "{v} km/h",

	-- en: {v} mph
	[ "unit.mph" ] = "{v} 英里/時",

	-- en: {v} u/s
	[ "unit.ups" ] = "{v} 單位/秒",

	-- en: {v} kg
	[ "unit.kg" ] = "{v} 公斤",

	-- en: {v} MB
	[ "unit.mb" ] = "{v} MB",

	-- Durations: {h} hours, {m} minutes, {s} seconds (minutes and seconds come with two digits)
	-- en: {h}h {m}m
	[ "duration.hm" ] = "{h}小時{m}分",

	-- en: {m}m {s}s
	[ "duration.ms" ] = "{m}分{s}秒",

	-- en: {s}s
	[ "duration.s" ] = "{s}秒",

	-- 12 hour clock: AM/PM and where they go around the time
	-- en: AM
	[ "clock.am" ] = "上午",

	-- en: PM
	[ "clock.pm" ] = "下午",

	-- en: {time} {ampm}
	[ "clock.ampm" ] = "{ampm}{time}",

	-- Date: {wday} day of week (short), {day} day number, {month} month (short), {year}
	-- en: {wday} {day} {month}
	[ "date.format" ] = "{month}{day}日 {wday}",

	-- en: Sun
	[ "date.wday.1" ] = "週日",

	-- en: Mon
	[ "date.wday.2" ] = "週一",

	-- en: Tue
	[ "date.wday.3" ] = "週二",

	-- en: Wed
	[ "date.wday.4" ] = "週三",

	-- en: Thu
	[ "date.wday.5" ] = "週四",

	-- en: Fri
	[ "date.wday.6" ] = "週五",

	-- en: Sat
	[ "date.wday.7" ] = "週六",

	-- en: Sunday
	[ "date.wday_full.1" ] = "星期日",

	-- en: Monday
	[ "date.wday_full.2" ] = "星期一",

	-- en: Tuesday
	[ "date.wday_full.3" ] = "星期二",

	-- en: Wednesday
	[ "date.wday_full.4" ] = "星期三",

	-- en: Thursday
	[ "date.wday_full.5" ] = "星期四",

	-- en: Friday
	[ "date.wday_full.6" ] = "星期五",

	-- en: Saturday
	[ "date.wday_full.7" ] = "星期六",

	-- short month names, used in dates ({month} above and %b): use the form your dates need
	-- en: Jan
	[ "date.month.1" ] = "1月",

	-- en: Feb
	[ "date.month.2" ] = "2月",

	-- en: Mar
	[ "date.month.3" ] = "3月",

	-- en: Apr
	[ "date.month.4" ] = "4月",

	-- en: May
	[ "date.month.5" ] = "5月",

	-- en: Jun
	[ "date.month.6" ] = "6月",

	-- en: Jul
	[ "date.month.7" ] = "7月",

	-- en: Aug
	[ "date.month.8" ] = "8月",

	-- en: Sep
	[ "date.month.9" ] = "9月",

	-- en: Oct
	[ "date.month.10" ] = "10月",

	-- en: Nov
	[ "date.month.11" ] = "11月",

	-- en: Dec
	[ "date.month.12" ] = "12月",

	-- full month names (%B), usually written right after a day number
	-- en: January
	[ "date.month_full.1" ] = "一月",

	-- en: February
	[ "date.month_full.2" ] = "二月",

	-- en: March
	[ "date.month_full.3" ] = "三月",

	-- en: April
	[ "date.month_full.4" ] = "四月",

	-- en: May
	[ "date.month_full.5" ] = "五月",

	-- en: June
	[ "date.month_full.6" ] = "六月",

	-- en: July
	[ "date.month_full.7" ] = "七月",

	-- en: August
	[ "date.month_full.8" ] = "八月",

	-- en: September
	[ "date.month_full.9" ] = "九月",

	-- en: October
	[ "date.month_full.10" ] = "十月",

	-- en: November
	[ "date.month_full.11" ] = "十一月",

	-- en: December
	[ "date.month_full.12" ] = "十二月",

	-- Kinds of surface material (the game's material types), shown as "World - Concrete"
	-- en: Antlion
	[ "mat.antlion" ] = "蟻獅",

	-- en: Bloody flesh
	[ "mat.bloodyflesh" ] = "血肉",

	-- en: Concrete
	[ "mat.concrete" ] = "混凝土",

	-- en: Dirt
	[ "mat.dirt" ] = "泥土",

	-- en: Eggshell
	[ "mat.eggshell" ] = "蛋殼",

	-- en: Flesh
	[ "mat.flesh" ] = "肉體",

	-- en: Grate
	[ "mat.grate" ] = "格柵",

	-- en: Alien flesh
	[ "mat.alienflesh" ] = "外星血肉",

	-- en: Clip
	[ "mat.clip" ] = "隱形牆",

	-- en: Snow
	[ "mat.snow" ] = "雪",

	-- en: Plastic
	[ "mat.plastic" ] = "塑膠",

	-- en: Metal
	[ "mat.metal" ] = "金屬",

	-- en: Sand
	[ "mat.sand" ] = "沙子",

	-- en: Foliage
	[ "mat.foliage" ] = "植被",

	-- en: Computer
	[ "mat.computer" ] = "電子設備",

	-- en: Liquid
	[ "mat.slosh" ] = "液體",

	-- en: Tile
	[ "mat.tile" ] = "磁磚",

	-- en: Grass
	[ "mat.grass" ] = "草地",

	-- en: Vent
	[ "mat.vent" ] = "通風口",

	-- en: Wood
	[ "mat.wood" ] = "木頭",

	-- en: Generic
	[ "mat.default" ] = "一般",

	-- en: Glass
	[ "mat.glass" ] = "玻璃",

	-- en: Warp shield
	[ "mat.warpshield" ] = "躍遷護盾",

	-- Notifications on the screen
	-- en: Tracking {name}
	[ "notify.tracking" ] = "正在追蹤 {name}",

	-- en: Stopped tracking
	[ "notify.untracked" ] = "已停止追蹤",

	-- en: Layout: {name}
	[ "notify.layout" ] = "版面配置：{name}",

	-- en: Theme: {name}
	[ "notify.theme" ] = "主題：{name}",

	-- title bar: tool category, or the game's name when there is none (keep "Garry's Mod")
	-- en: {tool_category|Garry's Mod}
	[ "tpl.title" ] = "{tool_category|Garry's Mod}",

	-- left link of the Pocket PC screen: the previous tool
	-- en: Back to {tool_prev}
	[ "tpl.nav_back" ] = "返回 {tool_prev}",

	-- en: Props {props}/{props_max}
	[ "tpl.props" ] = "物件 {props}/{props_max}",

	-- en: {fps} fps  {ping} ms
	[ "tpl.perf" ] = "{fps} FPS  延遲 {ping}ms",

	-- en: Slope {aim_slope}
	[ "tpl.slope" ] = "坡度 {aim_slope}",

	-- en: HP {ent_health}
	[ "tpl.hp" ] = "生命 {ent_health}",

	-- en: Owner: {ent_owner}
	[ "tpl.owner" ] = "擁有者：{ent_owner}",

	-- HP = health, AP = armor
	-- en: HP {health}  AP {armor}
	[ "tpl.health_armor" ] = "生命 {health}  護甲 {armor}",

	-- en: {players} players
	[ "tpl.players" ] = "{players} 位玩家",

	-- Terminal lines: a short upper case label, a tab, then the value
	-- en: TOOL\t**{tool}**
	[ "tpl.term_tool" ] = "工具\t**{tool}**",

	-- en: AIM\t**{aim_what}**
	[ "tpl.term_aim" ] = "目標\t**{aim_what}**",

	-- en: CLASS\t**{ent_class|-}**
	[ "tpl.term_class" ] = "類別\t**{ent_class|-}**",

	-- en: POS\t**{aim_pos}**
	[ "tpl.term_pos" ] = "位置\t**{aim_pos}**",

	-- en: DIST\t**{aim_dist}**  {aim_slope}
	[ "tpl.term_dist" ] = "距離\t**{aim_dist}**  {aim_slope}",

	-- en: OWNER\t**{ent_owner|-}**
	[ "tpl.term_owner" ] = "擁有者\t**{ent_owner|-}**",

	-- en: HP\t**{ent_health|-}**
	[ "tpl.term_hp" ] = "生命\t**{ent_health|-}**",

	-- en: TRACK\t**{track_name|-}** {track_dist}
	[ "tpl.term_track" ] = "追蹤\t**{track_name|-}** {track_dist}",

	-- en: Pocket PC
	[ "layout.pocketpc.name" ] = "Pocket PC",

	-- en: The original screen rebuilt with live data: clock, status icons, tool history links, big tool name, status line, six readouts and a hint bar.
	[ "layout.pocketpc.desc" ] = "以即時資料重建的原版螢幕：時鐘、狀態圖示、工具歷史連結、大型工具名稱、狀態列、六項讀數與提示列。",

	-- en: Title bar
	[ "layout.pocketpc.title" ] = "標題列",

	-- en: Clock
	[ "layout.pocketpc.clock" ] = "時鐘",

	-- en: Left link
	[ "layout.pocketpc.nav_l" ] = "左側連結",

	-- en: Right link
	[ "layout.pocketpc.nav_r" ] = "右側連結",

	-- en: Big text
	[ "layout.pocketpc.hero" ] = "大字",

	-- en: Under the big text
	[ "layout.pocketpc.sub" ] = "大字下方",

	-- en: Status line
	[ "layout.pocketpc.status" ] = "狀態列",

	-- en: Readout, left 1
	[ "layout.pocketpc.l1" ] = "左側讀數 1",

	-- en: Readout, left 2
	[ "layout.pocketpc.l2" ] = "左側讀數 2",

	-- en: Readout, left 3
	[ "layout.pocketpc.l3" ] = "左側讀數 3",

	-- en: Readout, right 1
	[ "layout.pocketpc.r1" ] = "右側讀數 1",

	-- en: Readout, right 2
	[ "layout.pocketpc.r2" ] = "右側讀數 2",

	-- en: Readout, right 3
	[ "layout.pocketpc.r3" ] = "右側讀數 3",

	-- en: Menu bar
	[ "layout.pocketpc.menu" ] = "選單列",

	-- en: Terminal
	[ "layout.terminal.name" ] = "終端機",

	-- en: Developer readout: eight lines of labels and values, an FPS graph and a prompt line with the tool hints.
	[ "layout.terminal.desc" ] = "開發者讀數：八行標籤與數值、FPS 圖表，以及顯示工具提示的命令列。",

	-- en: Header
	[ "layout.terminal.head" ] = "標題",

	-- en: Header, right
	[ "layout.terminal.clock" ] = "標題右側",

	-- en: Line 1
	[ "layout.terminal.l1" ] = "第 1 行",

	-- en: Line 2
	[ "layout.terminal.l2" ] = "第 2 行",

	-- en: Line 3
	[ "layout.terminal.l3" ] = "第 3 行",

	-- en: Line 4
	[ "layout.terminal.l4" ] = "第 4 行",

	-- en: Line 5
	[ "layout.terminal.l5" ] = "第 5 行",

	-- en: Line 6
	[ "layout.terminal.l6" ] = "第 6 行",

	-- en: Line 7
	[ "layout.terminal.l7" ] = "第 7 行",

	-- en: Line 8
	[ "layout.terminal.l8" ] = "第 8 行",

	-- en: Prompt line
	[ "layout.terminal.foot" ] = "命令列",

	-- en: Minimal
	[ "layout.minimal.name" ] = "極簡",

	-- en: Large, glanceable text: clock, compass, the tool name sized to fit, what you aim at and two corner values.
	[ "layout.minimal.desc" ] = "一眼就能看清楚的大字：時鐘、指南針、自動縮放的工具名稱、瞄準的目標，以及兩個角落的數值。",

	-- en: Top left
	[ "layout.minimal.top_l" ] = "左上",

	-- en: Top right
	[ "layout.minimal.top_r" ] = "右上",

	-- en: Big text
	[ "layout.minimal.hero" ] = "大字",

	-- en: Under the big text
	[ "layout.minimal.sub" ] = "大字下方",

	-- en: Bottom left
	[ "layout.minimal.foot_l" ] = "左下",

	-- en: Bottom right
	[ "layout.minimal.foot_r" ] = "右下",

	-- en: Pocket PC (original)
	[ "theme.winmobile" ] = "Pocket PC（原版）",

	-- en: Graphite
	[ "theme.graphite" ] = "石墨",

	-- en: Green phosphor
	[ "theme.phosphor" ] = "綠色螢光",

	-- en: Amber CRT
	[ "theme.amber" ] = "琥珀色 CRT",

	-- en: Sakura
	[ "theme.sakura" ] = "櫻花",

	-- en: Sandbox blue
	[ "theme.sandbox" ] = "沙盒藍",

	-- parts of the screen whose colour can be changed
	-- en: Title bar
	[ "color.bar" ] = "標題列",

	-- en: Links and highlights
	[ "color.accent" ] = "連結與強調色",

	-- en: Big text
	[ "color.hero" ] = "大字",

	-- en: Status line
	[ "color.strip" ] = "狀態列",

	-- en: Readout panel
	[ "color.panel" ] = "讀數面板",

	-- en: Menu bar
	[ "color.menu" ] = "選單列",

	-- en: Terminal text
	[ "color.term" ] = "終端機文字",

	-- en: Text
	[ "category.text" ] = "文字",

	-- en: Time
	[ "category.time" ] = "時間",

	-- en: Tool
	[ "category.tool" ] = "工具",

	-- en: Aim
	[ "category.aim" ] = "瞄準",

	-- en: Aimed entity
	[ "category.entity" ] = "瞄準的實體",

	-- en: Tracked entity
	[ "category.tracked" ] = "追蹤的實體",

	-- en: You
	[ "category.player" ] = "你",

	-- en: Game
	[ "category.game" ] = "遊戲",

	-- the Advanced Toolgun [Hotbar] addon; keep its name as it is
	-- en: Advanced Toolgun
	[ "category.atg" ] = "Advanced Toolgun",

	-- en: A line in your language from the language files, e.g. {tr:nav_back} or {tr:props}.
	[ "token.tr" ] = "語言檔中的一行在地化文字，例如 {tr:nav_back} 或 {tr:props}。",

	-- en: Local time, formatted by the clock settings. {time:%H:%M:%S} takes an os.date format.
	[ "token.time" ] = "本地時間，依時鐘設定顯示。{time:%H:%M:%S} 可使用 os.date 格式。",

	-- en: Today's date. {date:%Y-%m-%d} takes an os.date format.
	[ "token.date" ] = "今天的日期。{date:%Y-%m-%d} 可使用 os.date 格式。",

	-- en: How long you have been in this game.
	[ "token.session" ] = "你在這場遊戲中已待了多久。",

	-- en: How long the map has been running.
	[ "token.map_time" ] = "目前地圖已執行的時間。",

	-- en: Name of the selected tool.
	[ "token.tool" ] = "目前工具的名稱。",

	-- en: Internal name of the selected tool.
	[ "token.tool_id" ] = "目前工具的內部名稱。",

	-- en: Description of the selected tool.
	[ "token.tool_desc" ] = "目前工具的說明。",

	-- en: Tool menu category of the selected tool.
	[ "token.tool_category" ] = "目前工具在工具選單中的分類。",

	-- en: Stage of the selected tool (0 = nothing selected yet).
	[ "token.tool_stage" ] = "目前工具的階段（0 = 尚未選取任何物件）。",

	-- en: The stage while a multi-click tool is in progress, otherwise empty.
	[ "token.tool_progress" ] = "需要多次點擊的工具進行中時顯示目前階段，否則為空。",

	-- en: The tool you used before this one (dts_tool_back switches to it).
	[ "token.tool_prev" ] = "你上一個使用的工具（dts_tool_back 可切換回去）。",

	-- en: The next tool in the same menu category (dts_tool_next switches to it).
	[ "token.tool_next" ] = "同一選單分類中的下一個工具（dts_tool_next 可切換過去）。",

	-- en: Successful tool gun shots this session.
	[ "token.tool_uses" ] = "這場遊戲中工具槍成功射擊的次數。",

	-- en: A setting of the selected tool, e.g. {tool_cvar:forcelimit} reads weld_forcelimit.
	[ "token.tool_cvar" ] = "目前工具的某項設定，例如 {tool_cvar:forcelimit} 會讀取 weld_forcelimit。",

	-- en: All settings of the selected tool as name=value pairs.
	[ "token.tool_settings" ] = "目前工具的所有設定，以「名稱=數值」的形式列出。",

	-- en: The current stage's instructions with mouse and key icons.
	[ "token.hints" ] = "目前階段的操作說明，附滑鼠與按鍵圖示。",

	-- en: What left click does right now.
	[ "token.hint_left" ] = "左鍵目前的作用。",

	-- en: What right click does right now.
	[ "token.hint_right" ] = "右鍵目前的作用。",

	-- en: What reload does right now.
	[ "token.hint_reload" ] = "換彈鍵（R）目前的作用。",

	-- en: What you are aiming at, with the name highlighted.
	[ "token.target" ] = "你瞄準的目標，名稱會醒目顯示。",

	-- en: Entity name, or the surface material when aiming at the world.
	[ "token.aim_what" ] = "實體名稱；瞄準地圖時為表面材質。",

	-- en: Position you are aiming at.
	[ "token.aim_pos" ] = "你瞄準的位置。",

	-- en: X of the aim position.
	[ "token.aim_x" ] = "瞄準位置的 X 座標。",

	-- en: Y of the aim position.
	[ "token.aim_y" ] = "瞄準位置的 Y 座標。",

	-- en: Z of the aim position.
	[ "token.aim_z" ] = "瞄準位置的 Z 座標。",

	-- en: Distance to the aim position.
	[ "token.aim_dist" ] = "到瞄準位置的距離。",

	-- en: Surface normal at the aim position.
	[ "token.aim_normal" ] = "瞄準位置的表面法線。",

	-- en: Steepness of the surface (0 = flat floor, 90 = wall).
	[ "token.aim_slope" ] = "表面的坡度（0 = 平地，90 = 牆面）。",

	-- en: Kind of surface material (metal, wood, concrete...).
	[ "token.aim_surface" ] = "表面材質的種類（金屬、木頭、混凝土……）。",

	-- en: Surface property as the engine names it (metal box, wood crate...).
	[ "token.aim_surfaceprop" ] = "引擎內部的表面屬性名稱（metal box、wood crate……）。",

	-- en: World texture you are aiming at.
	[ "token.aim_texture" ] = "你瞄準的地圖貼圖。",

	-- en: Friendly name of the aimed entity.
	[ "token.ent_name" ] = "瞄準實體的易讀名稱。",

	-- en: Class of the aimed entity.
	[ "token.ent_class" ] = "瞄準實體的類別。",

	-- en: Model file name of the aimed entity.
	[ "token.ent_model" ] = "瞄準實體的模型檔名。",

	-- en: Full model path of the aimed entity.
	[ "token.ent_model_path" ] = "瞄準實體的完整模型路徑。",

	-- en: Entity index.
	[ "token.ent_index" ] = "實體編號。",

	-- en: Health of the aimed entity (players, NPCs, breakable props).
	[ "token.ent_health" ] = "瞄準實體的生命值（玩家、NPC、可破壞的物件）。",

	-- en: Owner of the aimed entity (in multiplayer this needs a CPPI prop protection addon).
	[ "token.ent_owner" ] = "瞄準實體的擁有者（多人遊戲中需要支援 CPPI 的物件保護插件）。",

	-- en: Material of the aimed entity.
	[ "token.ent_material" ] = "瞄準實體的材質。",

	-- en: Colour of the aimed entity.
	[ "token.ent_color" ] = "瞄準實體的顏色。",

	-- en: Skin of the aimed entity.
	[ "token.ent_skin" ] = "瞄準實體的皮膚。",

	-- en: Speed of the aimed entity.
	[ "token.ent_speed" ] = "瞄準實體的速度。",

	-- en: Position of the aimed entity.
	[ "token.ent_pos" ] = "瞄準實體的位置。",

	-- en: Angles of the aimed entity.
	[ "token.ent_ang" ] = "瞄準實體的角度。",

	-- en: Mass of the aimed entity, when your game knows its physics.
	[ "token.ent_mass" ] = "瞄準實體的質量（遊戲能取得其物理資料時）。",

	-- en: Tracked entity summary: name, distance, speed, health.
	[ "token.track" ] = "追蹤實體的概況：名稱、距離、速度、生命值。",

	-- en: Name of the tracked entity.
	[ "token.track_name" ] = "追蹤實體的名稱。",

	-- en: Class of the tracked entity.
	[ "token.track_class" ] = "追蹤實體的類別。",

	-- en: Your distance to the tracked entity.
	[ "token.track_dist" ] = "你與追蹤實體的距離。",

	-- en: Speed of the tracked entity.
	[ "token.track_speed" ] = "追蹤實體的速度。",

	-- en: Health of the tracked entity.
	[ "token.track_health" ] = "追蹤實體的生命值。",

	-- en: Position of the tracked entity.
	[ "token.track_pos" ] = "追蹤實體的位置。",

	-- en: Your name.
	[ "token.player" ] = "你的名字。",

	-- en: Your health.
	[ "token.health" ] = "你的生命值。",

	-- en: Your armor.
	[ "token.armor" ] = "你的護甲值。",

	-- en: Your speed.
	[ "token.speed" ] = "你的速度。",

	-- en: Your position.
	[ "token.pos" ] = "你的位置。",

	-- en: Your view pitch and yaw.
	[ "token.eye_ang" ] = "你視角的俯仰角與偏航角。",

	-- en: Compass heading (north is +Y on the map).
	[ "token.heading" ] = "指南針方位（地圖上的 +Y 為北）。",

	-- en: Shows a word while you are noclipping, otherwise empty.
	[ "token.noclip" ] = "穿牆時顯示一個詞，否則為空。",

	-- en: Frames per second (smoothed).
	[ "token.fps" ] = "每秒影格數（平滑後）。",

	-- en: Your ping in milliseconds.
	[ "token.ping" ] = "你的延遲，單位為毫秒。",

	-- en: Your device's battery charge while it runs on battery, or \"Plugged in\".
	[ "token.battery" ] = "裝置使用電池供電時為電池電量，接上電源時顯示「已接上電源」。",

	-- en: Current map.
	[ "token.map" ] = "目前的地圖。",

	-- en: Players on the server and its player limit.
	[ "token.players" ] = "伺服器上的玩家數與人數上限。",

	-- en: Server name.
	[ "token.server" ] = "伺服器名稱。",

	-- en: Active gamemode.
	[ "token.gamemode" ] = "目前的遊戲模式。",

	-- en: Server tick rate.
	[ "token.tickrate" ] = "伺服器的 Tick 率。",

	-- en: Memory used by Lua in your game.
	[ "token.lua_mem" ] = "遊戲中 Lua 使用的記憶體。",

	-- en: Entities known to your game.
	[ "token.entities" ] = "你的遊戲已知的實體數量。",

	-- en: Props you have spawned.
	[ "token.props" ] = "你生成的物件數量。",

	-- en: Your prop limit.
	[ "token.props_max" ] = "你的物件上限。",

	-- en: Spawn count and limit of a type, e.g. {count:ragdolls} or {count:thrusters}.
	[ "token.count" ] = "某類物品的生成數量與上限，例如 {count:ragdolls} 或 {count:thrusters}。",

	-- en: Value of any console variable, e.g. {cvar:sv_gravity}.
	[ "token.cvar" ] = "任意主控台變數的值，例如 {cvar:sv_gravity}。",

	-- en: Advanced Toolgun [Hotbar]: its open tab (Tools, Wire or Favorites).
	[ "token.atg_tab" ] = "Advanced Toolgun [Hotbar]：目前開啟的分頁（工具、Wire 或我的最愛）。",

	-- en: Advanced Toolgun [Hotbar]: the section of its list the selection is in.
	[ "token.atg_section" ] = "Advanced Toolgun [Hotbar]：清單中目前選取項目所在的區段。",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel up.
	[ "token.atg_prev" ] = "Advanced Toolgun [Hotbar]：快速選擇時向上捲動滑鼠滾輪會切換到的工具。",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel down.
	[ "token.atg_next" ] = "Advanced Toolgun [Hotbar]：快速選擇時向下捲動滑鼠滾輪會切換到的工具。",

	-- en: Turns the tool gun's mini screen into a live display. Changes apply instantly; the preview shows what the screen draws right now.
	[ "menu.intro" ] = "把工具槍的小螢幕變成即時顯示器。變更會立即生效；預覽會顯示螢幕此刻繪製的內容。",

	-- en: Dynamic screen is off
	[ "menu.preview_off" ] = "動態螢幕已關閉",

	-- en: Enable the dynamic screen
	[ "menu.enable" ] = "啟用動態螢幕",

	-- en: Language
	[ "menu.language" ] = "語言",

	-- first entry of the language list; {name} is the game's language, e.g. "English"
	-- en: Automatic: {name}
	[ "menu.language.auto" ] = "自動：{name}",

	-- en: Inspect: read the screen up close
	[ "menu.inspect.title" ] = "檢視：湊近閱讀螢幕",

	-- en: Hold a key while holding the tool gun to raise its screen to your eyes.
	[ "menu.inspect.help" ] = "手持工具槍時按住一個鍵，螢幕就會舉到你眼前。",

	-- en: Inspect key
	[ "menu.inspect.key" ] = "檢視鍵",

	-- en: Screen size while inspecting
	[ "menu.inspect.size" ] = "檢視時的螢幕大小",

	-- en: Or use the console: bind <key> +dts_inspect (hold) or dts_inspect_toggle.
	[ "menu.inspect.console" ] = "也可以使用主控台：bind <按鍵> +dts_inspect（按住）或 dts_inspect_toggle。",

	-- the tool gun model has a paper note glued on, which overlaps the screen's top right corner
	-- en: Screen in front of the paper note
	[ "menu.inspect.on_top" ] = "螢幕顯示在便條前面",

	-- en: While inspecting, the whole screen stays readable. Untick to let the paper note glued to the tool gun cover the top right corner of the screen, as on the model.
	[ "menu.inspect.on_top_help" ] = "檢視時整個螢幕都清晰可讀。取消勾選後，黏在工具槍上的便條會像模型上一樣擋住螢幕的右上角。",

	-- en: Layout and look
	[ "menu.look.title" ] = "版面配置與外觀",

	-- en: Layout
	[ "menu.look.layout" ] = "版面配置",

	-- en: Theme
	[ "menu.look.theme" ] = "主題",

	-- en: Background
	[ "menu.look.background" ] = "背景",

	-- en: Automatic (layout's choice)
	[ "menu.bg.auto" ] = "自動（由版面配置決定）",

	-- the whole original screen picture without its text
	-- en: Original screen
	[ "menu.bg.original" ] = "原版螢幕",

	-- only the blurred photo from the original picture, filling the screen
	-- en: Original photo
	[ "menu.bg.art" ] = "原版照片",

	-- en: Theme gradient
	[ "menu.bg.gradient" ] = "主題漸層",

	-- en: Live camera: zoom
	[ "menu.bg.camera" ] = "即時鏡頭：放大",

	-- en: Live camera: rear view
	[ "menu.bg.rear" ] = "即時鏡頭：後視",

	-- en: Custom image
	[ "menu.bg.image" ] = "自訂圖片",

	-- en: Black
	[ "menu.bg.black" ] = "黑色",

	-- en: Custom image
	[ "menu.look.image" ] = "自訂圖片",

	-- en: A material path, or an image in garrysmod/data written as ../data/name.png
	[ "menu.look.image_help" ] = "填入材質路徑，或 garrysmod/data 中的圖片，寫成 ../data/檔名.png",

	-- en: Darken background
	[ "menu.look.dim" ] = "背景變暗",

	-- en: Camera field of view
	[ "menu.look.cam_fov" ] = "鏡頭視野",

	-- en: Camera updates per second
	[ "menu.look.cam_fps" ] = "鏡頭每秒更新次數",

	-- en: Text font
	[ "menu.look.font" ] = "文字字型",

	-- en: Big text font
	[ "menu.look.font_hero" ] = "大字字型",

	-- en: Terminal font
	[ "menu.look.font_mono" ] = "終端機字型",

	-- first entry of the font lists; {font} is the font your language uses
	-- en: Automatic ({font})
	[ "menu.font.auto" ] = "自動（{font}）",

	-- en: Colours
	[ "menu.colors.title" ] = "顏色",

	-- en: Override single colours of the theme. Click a swatch to change it.
	[ "menu.colors.help" ] = "個別覆寫主題中的某些顏色。點擊色塊即可變更。",

	-- written on a colour swatch that still uses the theme's colour
	-- en: theme
	[ "menu.colors.theme_tag" ] = "主題",

	-- en: Click to pick a colour
	[ "menu.colors.pick" ] = "點擊以選擇顏色",

	-- en: Use the theme's colours everywhere
	[ "menu.colors.reset_all" ] = "全部使用主題顏色",

	-- en: Screen colour: {name}
	[ "menu.colors.picker_title" ] = "螢幕顏色：{name}",

	-- en: Use the theme's colour
	[ "menu.colors.use_theme" ] = "使用主題顏色",

	-- en: Big text
	[ "menu.hero.title" ] = "大字",

	-- en: Behaviour
	[ "menu.hero.mode" ] = "顯示方式",

	-- en: Always scroll (original)
	[ "menu.hero.scroll" ] = "持續捲動（原版）",

	-- en: Scroll only when too long
	[ "menu.hero.auto" ] = "過長時才捲動",

	-- en: Shrink to fit
	[ "menu.hero.fit" ] = "縮小以符合",

	-- en: Scroll speed
	[ "menu.hero.speed" ] = "捲動速度",

	-- en: Upper case tool names
	[ "menu.hero.upper" ] = "工具名稱使用大寫字母",

	-- en: Screen content
	[ "menu.content.title" ] = "螢幕內容",

	-- keep {tokens}, **stars**, {token|fallback} and {tr:...} as they are: they show the syntax
	-- en: Every line of the {layout} layout is a template. Type text and {tokens}; **stars** highlight text, {token|fallback} gives a default, and a line whose tokens are all empty hides itself. {tr:...} writes a line in your language. See the token reference below.
	[ "menu.content.help" ] = "{layout} 版面配置的每一行都是範本。可以輸入文字和 {tokens}；用 **星號** 包住的文字會醒目顯示，{token|fallback} 會在變數為空時顯示預設文字，所有變數皆為空的行會自動隱藏。{tr:...} 會寫出你所用語言的文字。變數清單請見下方。",

	-- en: Pick a ready-made line
	[ "menu.content.presets_tip" ] = "選擇現成的行",

	-- en: Back to the default: {value}
	[ "menu.content.reset_tip" ] = "還原為預設值：{value}",

	-- en: (empty)
	[ "menu.content.empty" ] = "（空白）",

	-- shown in an empty line's text box
	-- en: (hidden)
	[ "menu.content.placeholder" ] = "（隱藏）",

	-- under each line: what it shows right now
	-- en: = {text}
	[ "menu.content.now" ] = "= {text}",

	-- en: (hidden right now)
	[ "menu.content.hidden_now" ] = "（目前隱藏）",

	-- en: Reset these lines to the layout's defaults
	[ "menu.content.reset_all" ] = "將這些行還原為版面配置的預設值",

	-- ready-made lines in the list next to each line
	-- en: Tool name
	[ "menu.preset.tool" ] = "工具名稱",

	-- en: Tool category
	[ "menu.preset.tool_category" ] = "工具分類",

	-- en: Tool instructions
	[ "menu.preset.hints" ] = "工具操作說明",

	-- en: Previous tool
	[ "menu.preset.prev_tool" ] = "上一個工具",

	-- en: Next tool
	[ "menu.preset.next_tool" ] = "下一個工具",

	-- en: Tool progress
	[ "menu.preset.progress" ] = "工具進度",

	-- en: Tool settings
	[ "menu.preset.tool_settings" ] = "工具設定",

	-- en: What you aim at
	[ "menu.preset.target" ] = "瞄準的目標",

	-- en: Aim position
	[ "menu.preset.aim_pos" ] = "瞄準位置",

	-- en: Aim distance
	[ "menu.preset.aim_dist" ] = "瞄準距離",

	-- en: Entity or surface
	[ "menu.preset.aim_what" ] = "實體或表面",

	-- en: Surface slope
	[ "menu.preset.slope" ] = "表面坡度",

	-- en: Entity class
	[ "menu.preset.ent_class" ] = "實體類別",

	-- en: Entity model
	[ "menu.preset.ent_model" ] = "實體模型",

	-- en: Entity health
	[ "menu.preset.ent_health" ] = "實體生命值",

	-- en: Entity owner
	[ "menu.preset.ent_owner" ] = "實體擁有者",

	-- en: Entity speed
	[ "menu.preset.ent_speed" ] = "實體速度",

	-- en: Tracked entity
	[ "menu.preset.track" ] = "追蹤的實體",

	-- en: Clock
	[ "menu.preset.clock" ] = "時鐘",

	-- en: Clock with seconds
	[ "menu.preset.clock_seconds" ] = "含秒數的時鐘",

	-- en: Date
	[ "menu.preset.date" ] = "日期",

	-- en: Time in game
	[ "menu.preset.session" ] = "遊戲時間",

	-- en: Your speed
	[ "menu.preset.speed" ] = "你的速度",

	-- en: Your position
	[ "menu.preset.pos" ] = "你的位置",

	-- en: Compass
	[ "menu.preset.heading" ] = "指南針",

	-- en: Health and armor
	[ "menu.preset.health_armor" ] = "生命與護甲",

	-- en: FPS and ping
	[ "menu.preset.perf" ] = "FPS 與延遲",

	-- en: Prop count
	[ "menu.preset.props" ] = "物件數量",

	-- en: Map
	[ "menu.preset.map" ] = "地圖",

	-- en: Players
	[ "menu.preset.players" ] = "玩家",

	-- en: Empty (hide the line)
	[ "menu.preset.empty" ] = "空白（隱藏此行）",

	-- en: Clock and units
	[ "menu.clock.title" ] = "時鐘與單位",

	-- en: Clock
	[ "menu.clock.style" ] = "時鐘",

	-- {language} is the name of the active language
	-- en: As usual in {language}
	[ "menu.clock.auto" ] = "依{language}的習慣",

	-- en: 12 hour
	[ "menu.clock.12h" ] = "12 小時制",

	-- en: 24 hour
	[ "menu.clock.24h" ] = "24 小時制",

	-- en: Show seconds
	[ "menu.clock.seconds" ] = "顯示秒數",

	-- en: Show AM / PM (12 hour clock)
	[ "menu.clock.ampm" ] = "顯示上午/下午（12 小時制）",

	-- en: Blink the colon
	[ "menu.clock.blink" ] = "冒號閃爍",

	-- en: Units
	[ "menu.units.label" ] = "單位",

	-- en: Metric (m, km/h)
	[ "menu.units.m" ] = "公制（公尺、km/h）",

	-- en: Imperial (ft, mph)
	[ "menu.units.ft" ] = "英制（英尺、英里/時）",

	-- en: Hammer units
	[ "menu.units.hu" ] = "Hammer 單位",

	-- en: Distance decimals
	[ "menu.units.decimals" ] = "距離的小數位數",

	-- en: Icons and effects
	[ "menu.fx.title" ] = "圖示與效果",

	-- en: Speaker icon (volume, voice chat)
	[ "menu.fx.speaker" ] = "喇叭圖示（音量、語音聊天）",

	-- en: Signal icon (connection)
	[ "menu.fx.signal" ] = "訊號圖示（網路連線）",

	-- en: Battery icon (your device's battery)
	[ "menu.fx.battery" ] = "電池圖示（裝置的電池）",

	-- en: Boot animation when taking out the tool gun
	[ "menu.fx.boot" ] = "拿出工具槍時播放開機動畫",

	-- en: Flash when the tool gun fires
	[ "menu.fx.flash" ] = "工具槍開火時螢幕閃爍",

	-- en: Show game notifications on the screen
	[ "menu.fx.notify" ] = "在螢幕上顯示遊戲通知",

	-- en: Notification time
	[ "menu.fx.notify_time" ] = "通知顯示時間",

	-- en: Scanlines
	[ "menu.fx.scanlines" ] = "掃描線",

	-- en: Darker edges
	[ "menu.fx.vignette" ] = "邊緣變暗",

	-- en: Backlight
	[ "menu.fx.backlight" ] = "背光亮度",

	-- en: HUD mirror
	[ "menu.mirror.title" ] = "HUD 鏡像",

	-- en: Shows the screen on your HUD while you hold the tool gun, for reading the small print.
	[ "menu.mirror.help" ] = "手持工具槍時把螢幕同時顯示在 HUD 上，方便閱讀小字。",

	-- en: Show the screen on the HUD
	[ "menu.mirror.enable" ] = "在 HUD 上顯示螢幕",

	-- en: Corner
	[ "menu.mirror.corner" ] = "位置",

	-- en: Top right
	[ "menu.corner.tr" ] = "右上角",

	-- en: Bottom right
	[ "menu.corner.br" ] = "右下角",

	-- en: Bottom left
	[ "menu.corner.bl" ] = "左下角",

	-- en: Top left
	[ "menu.corner.tl" ] = "左上角",

	-- en: Size
	[ "menu.mirror.size" ] = "大小",

	-- en: Opacity
	[ "menu.mirror.alpha" ] = "不透明度",

	-- en: Advanced
	[ "menu.adv.title" ] = "進階",

	-- en: Keep the own screens of tools that draw one
	[ "menu.adv.respect" ] = "保留自帶螢幕之工具的原有螢幕",

	-- en: e.g. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod tools
	[ "menu.adv.respect_help" ] = "例如 Easy Entity Inspector、Ragdoll Puppeteer、Wiremod 工具",

	-- en: Live value updates per second
	[ "menu.adv.refresh" ] = "即時數值每秒更新次數",

	-- en: Screen redraws per second (0 = every frame)
	[ "menu.adv.fps" ] = "螢幕每秒重繪次數（0 = 每一影格）",

	-- en: Resolution
	[ "menu.adv.resolution" ] = "解析度",

	-- en: 256 x 256 (original)
	[ "menu.res.256" ] = "256 x 256（原版）",

	-- en: 512 x 512 (sharper, for 1440p and up)
	[ "menu.res.512" ] = "512 x 512（更清晰，適合 1440p 以上）",

	-- keep the commands as they are
	-- en: Key binds (bind <key> <command>):\n  dts_tool_back  -  previous tool\n  dts_tool_next / dts_tool_prev  -  cycle the category\n  dts_layout_next, dts_theme_next  -  cycle layouts, themes\n  dts_track / dts_untrack  -  follow an entity
	[ "menu.adv.binds" ] = "按鍵綁定（bind <按鍵> <指令>）：\n  dts_tool_back  -  上一個工具\n  dts_tool_next / dts_tool_prev  -  在分類中切換工具\n  dts_layout_next, dts_theme_next  -  切換版面配置、主題\n  dts_track / dts_untrack  -  追蹤實體",

	-- en: Copy my settings to the clipboard
	[ "menu.adv.copy" ] = "把我的設定複製到剪貼簿",

	-- en: Screen settings copied to the clipboard
	[ "menu.adv.copied" ] = "螢幕設定已複製到剪貼簿",

	-- en: Import settings...
	[ "menu.adv.import" ] = "匯入設定……",

	-- en: Import screen settings
	[ "menu.adv.import_title" ] = "匯入螢幕設定",

	-- en: Paste a DTS1:... settings string
	[ "menu.adv.import_prompt" ] = "貼上 DTS1:... 格式的設定字串",

	-- en: Import
	[ "menu.adv.import_ok" ] = "匯入",

	-- en: Imported screen settings ({n} changed)
	[ "menu.adv.imported" ] = "已匯入螢幕設定（變更了 {n} 項）",

	-- en: Reset everything to defaults
	[ "menu.adv.reset" ] = "全部還原為預設值",

	-- en: Reset
	[ "menu.adv.reset_title" ] = "還原預設值",

	-- en: Reset every Dynamic Toolgun Screen setting?
	[ "menu.adv.reset_question" ] = "要把動態工具槍螢幕的所有設定還原為預設值嗎？",

	-- en: Reset
	[ "menu.adv.reset_yes" ] = "還原",

	-- en: Cancel
	[ "menu.adv.cancel" ] = "取消",

	-- en: Another addon replaced the tool gun screen ({file}). Use the button below to take over.
	[ "menu.adv.diag_conflict" ] = "另一個插件取代了工具槍螢幕（{file}）。可用下方按鈕接管。",

	-- en: v{version} installed. Each redraw takes {ms} ms.
	[ "menu.adv.diag_ok" ] = "v{version} 已安裝。每次重繪耗時 {ms} 毫秒。",

	-- en: Last error: {error}
	[ "menu.adv.diag_error" ] = "上次錯誤：{error}",

	-- en: Waiting for the tool gun to load...
	[ "menu.adv.diag_wait" ] = "正在等待工具槍載入……",

	-- en: Take over the tool gun screen
	[ "menu.adv.takeover" ] = "接管工具槍螢幕",

	-- en: Only needed if another addon replaced the tool gun's screen after this one
	[ "menu.adv.takeover_tip" ] = "只有在其他插件於本插件之後取代了工具槍螢幕時才需要",

	-- en: Dynamic Toolgun Screen installed
	[ "menu.adv.takeover_done" ] = "已接管工具槍螢幕",

	-- answers to "Import settings..." when the pasted text is wrong
	-- en: This is not a Dynamic Toolgun Screen settings string.
	[ "import.not_ours" ] = "這不是動態工具槍螢幕的設定字串。",

	-- en: The settings string is damaged.
	[ "import.damaged" ] = "設定字串已損毀。",

	-- en: Token reference
	[ "menu.tokens.title" ] = "變數清單",

	-- en: Hover a token for what it does, double-click to copy it.
	[ "menu.tokens.help" ] = "將滑鼠停在變數上可查看說明，按兩下即可複製。",

	-- en: Token
	[ "menu.tokens.col_token" ] = "變數",

	-- en: Right now
	[ "menu.tokens.col_now" ] = "目前值",

	-- en: Copied {token}
	[ "menu.tokens.copied" ] = "已複製 {token}",

}
