--[[
	Dynamic Toolgun Screen - 简体中文 (zh-cn)

	Made from lang/en.lua with tools/i18n.py (see TRANSLATING.md). Above each phrase, "-- en:" holds the
	English it translates; "tools/i18n.py check" lists phrases whose English changed since. A phrase
	missing here falls back to English.
]]

return {

	-- name of the language in that language, shown in the language list
	-- en: English
	[ "_name" ] = "简体中文",

	-- decimal separator for numbers on the screen
	-- en: .
	[ "_decimal" ] = ".",

	-- 1 if a 24 hour clock is usual in this language, 0 for 12 hour
	-- en: 0
	[ "_clock24" ] = "1",

	-- fonts that have every letter of the language; size factor and weight snapping (1/0) for them
	-- en: Tahoma
	[ "_font.ui" ] = "Microsoft YaHei UI",

	-- en: Helvetica
	[ "_font.hero" ] = "Microsoft YaHei UI",

	-- en: Consolas
	[ "_font.mono" ] = "Microsoft YaHei UI",

	-- en: 1
	[ "_font.scale" ] = "1.2",

	-- en: 0
	[ "_font.snap" ] = "1",

	-- Shown by the game: the tool list, the tool's help on the HUD, the context menu, the Utilities tab --
	-- en: Dynamic Toolgun Screen
	[ "tool.name" ] = "动态工具枪屏幕",

	-- en: Customize the tool gun's live screen and track entities on it
	[ "tool.desc" ] = "自定义工具枪的实时屏幕，并用它跟踪实体",

	-- en: Track the entity you are aiming at
	[ "tool.left" ] = "跟踪你瞄准的实体",

	-- en: Switch to the next screen layout
	[ "tool.right" ] = "切换到下一个屏幕布局",

	-- en: Stop tracking
	[ "tool.reload" ] = "停止跟踪",

	-- context menu entry (right click an entity while holding C)
	-- en: Track on tool gun screen
	[ "prop.track" ] = "在工具枪屏幕上跟踪",

	-- Utilities tab: category and its only entry
	-- en: Dynamic Toolgun Screen
	[ "menu.category" ] = "动态工具枪屏幕",

	-- en: Settings
	[ "menu.settings_item" ] = "设置",

	-- status line; {name} is an entity name such as "oildrum001" or a player's name
	-- en: Aiming at **{name}**
	[ "target.entity" ] = "瞄准：**{name}**",

	-- en: Aiming at the **sky**
	[ "target.sky" ] = "瞄准：**天空**",

	-- en: World
	[ "target.world" ] = "地图",

	-- {surface} is a material from the mat.* phrases below
	-- en: World - **{surface}**
	[ "target.world_surface" ] = "地图 - **{surface}**",

	-- en: Nothing in range
	[ "target.nothing" ] = "范围内没有目标",

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
	[ "noclip" ] = "穿墙",

	-- view angles: P = pitch, Y = yaw
	-- en: P {p}  Y {y}
	[ "eye_ang" ] = "俯仰 {p}  偏航 {y}",

	-- compass heading, e.g. "NE 45°"
	-- en: {dir} {deg}°
	[ "heading" ] = "{dir} {deg}°",

	-- en: N
	[ "compass.n" ] = "北",

	-- en: NE
	[ "compass.ne" ] = "东北",

	-- en: E
	[ "compass.e" ] = "东",

	-- en: SE
	[ "compass.se" ] = "东南",

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
	[ "error.title" ] = "屏幕出错",

	-- en: See the console for details. Change the layout or run dts_reset to recover.
	[ "error.hint" ] = "详情请查看控制台。更换布局或运行 dts_reset 即可恢复。",

	-- tabs of the Advanced Toolgun [Hotbar] addon's tool list, for the {atg_tab} token
	-- en: Tools
	[ "atg.tab.tools" ] = "工具",

	-- en: Wire
	[ "atg.tab.wire" ] = "Wire",

	-- en: Favorites
	[ "atg.tab.favorites" ] = "收藏夹",

	-- the device's battery, next to the battery icon and in {battery}: {n} is the charge in percent;
	-- "Plugged in" is shown while the device runs on mains power instead of its battery
	-- en: {n}%
	[ "battery.percent" ] = "{n}%",

	-- en: Plugged in
	[ "battery.plugged" ] = "已接通电源",

	-- Units: {v} is the number, already written with the decimal separator above
	-- en: {v} m
	[ "unit.m" ] = "{v} 米",

	-- en: {v} km
	[ "unit.km" ] = "{v} 公里",

	-- en: {v} ft
	[ "unit.ft" ] = "{v} 英尺",

	-- en: {v} mi
	[ "unit.mi" ] = "{v} 英里",

	-- Hammer units, the game's own distance unit
	-- en: {v} u
	[ "unit.hu" ] = "{v} 单位",

	-- en: {v} km/h
	[ "unit.kmh" ] = "{v} km/h",

	-- en: {v} mph
	[ "unit.mph" ] = "{v} 英里/时",

	-- en: {v} u/s
	[ "unit.ups" ] = "{v} 单位/秒",

	-- en: {v} kg
	[ "unit.kg" ] = "{v} 千克",

	-- en: {v} MB
	[ "unit.mb" ] = "{v} MB",

	-- Durations: {h} hours, {m} minutes, {s} seconds (minutes and seconds come with two digits)
	-- en: {h}h {m}m
	[ "duration.hm" ] = "{h}小时{m}分",

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
	[ "date.wday.1" ] = "周日",

	-- en: Mon
	[ "date.wday.2" ] = "周一",

	-- en: Tue
	[ "date.wday.3" ] = "周二",

	-- en: Wed
	[ "date.wday.4" ] = "周三",

	-- en: Thu
	[ "date.wday.5" ] = "周四",

	-- en: Fri
	[ "date.wday.6" ] = "周五",

	-- en: Sat
	[ "date.wday.7" ] = "周六",

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
	[ "mat.antlion" ] = "蚁狮",

	-- en: Bloody flesh
	[ "mat.bloodyflesh" ] = "血肉",

	-- en: Concrete
	[ "mat.concrete" ] = "混凝土",

	-- en: Dirt
	[ "mat.dirt" ] = "泥土",

	-- en: Eggshell
	[ "mat.eggshell" ] = "蛋壳",

	-- en: Flesh
	[ "mat.flesh" ] = "肉体",

	-- en: Grate
	[ "mat.grate" ] = "格栅",

	-- en: Alien flesh
	[ "mat.alienflesh" ] = "外星血肉",

	-- en: Clip
	[ "mat.clip" ] = "隐形墙",

	-- en: Snow
	[ "mat.snow" ] = "雪",

	-- en: Plastic
	[ "mat.plastic" ] = "塑料",

	-- en: Metal
	[ "mat.metal" ] = "金属",

	-- en: Sand
	[ "mat.sand" ] = "沙子",

	-- en: Foliage
	[ "mat.foliage" ] = "植被",

	-- en: Computer
	[ "mat.computer" ] = "电子设备",

	-- en: Liquid
	[ "mat.slosh" ] = "液体",

	-- en: Tile
	[ "mat.tile" ] = "瓷砖",

	-- en: Grass
	[ "mat.grass" ] = "草地",

	-- en: Vent
	[ "mat.vent" ] = "通风口",

	-- en: Wood
	[ "mat.wood" ] = "木头",

	-- en: Generic
	[ "mat.default" ] = "普通",

	-- en: Glass
	[ "mat.glass" ] = "玻璃",

	-- en: Warp shield
	[ "mat.warpshield" ] = "跃迁护盾",

	-- Notifications on the screen
	-- en: Tracking {name}
	[ "notify.tracking" ] = "正在跟踪 {name}",

	-- en: Stopped tracking
	[ "notify.untracked" ] = "已停止跟踪",

	-- en: Layout: {name}
	[ "notify.layout" ] = "布局：{name}",

	-- en: Theme: {name}
	[ "notify.theme" ] = "主题：{name}",

	-- title bar: tool category, or the game's name when there is none (keep "Garry's Mod")
	-- en: {tool_category|Garry's Mod}
	[ "tpl.title" ] = "{tool_category|Garry's Mod}",

	-- left link of the Pocket PC screen: the previous tool
	-- en: Back to {tool_prev}
	[ "tpl.nav_back" ] = "返回 {tool_prev}",

	-- en: Props {props}/{props_max}
	[ "tpl.props" ] = "道具 {props}/{props_max}",

	-- en: {fps} fps  {ping} ms
	[ "tpl.perf" ] = "{fps} FPS  延迟 {ping}ms",

	-- en: Slope {aim_slope}
	[ "tpl.slope" ] = "坡度 {aim_slope}",

	-- en: HP {ent_health}
	[ "tpl.hp" ] = "生命 {ent_health}",

	-- en: Owner: {ent_owner}
	[ "tpl.owner" ] = "所有者：{ent_owner}",

	-- HP = health, AP = armor
	-- en: HP {health}  AP {armor}
	[ "tpl.health_armor" ] = "生命 {health}  护甲 {armor}",

	-- en: {players} players
	[ "tpl.players" ] = "{players} 名玩家",

	-- Terminal lines: a short upper case label, a tab, then the value
	-- en: TOOL\t**{tool}**
	[ "tpl.term_tool" ] = "工具\t**{tool}**",

	-- en: AIM\t**{aim_what}**
	[ "tpl.term_aim" ] = "目标\t**{aim_what}**",

	-- en: CLASS\t**{ent_class|-}**
	[ "tpl.term_class" ] = "类名\t**{ent_class|-}**",

	-- en: POS\t**{aim_pos}**
	[ "tpl.term_pos" ] = "位置\t**{aim_pos}**",

	-- en: DIST\t**{aim_dist}**  {aim_slope}
	[ "tpl.term_dist" ] = "距离\t**{aim_dist}**  {aim_slope}",

	-- en: OWNER\t**{ent_owner|-}**
	[ "tpl.term_owner" ] = "所有者\t**{ent_owner|-}**",

	-- en: HP\t**{ent_health|-}**
	[ "tpl.term_hp" ] = "生命\t**{ent_health|-}**",

	-- en: TRACK\t**{track_name|-}** {track_dist}
	[ "tpl.term_track" ] = "跟踪\t**{track_name|-}** {track_dist}",

	-- en: Pocket PC
	[ "layout.pocketpc.name" ] = "Pocket PC",

	-- en: The original screen rebuilt with live data: clock, status icons, tool history links, big tool name, status line, six readouts and a hint bar.
	[ "layout.pocketpc.desc" ] = "用实时数据重建的原版屏幕：时钟、状态图标、工具历史链接、大号工具名、状态栏、六项读数和提示栏。",

	-- en: Title bar
	[ "layout.pocketpc.title" ] = "标题栏",

	-- en: Clock
	[ "layout.pocketpc.clock" ] = "时钟",

	-- en: Left link
	[ "layout.pocketpc.nav_l" ] = "左侧链接",

	-- en: Right link
	[ "layout.pocketpc.nav_r" ] = "右侧链接",

	-- en: Big text
	[ "layout.pocketpc.hero" ] = "大字",

	-- en: Under the big text
	[ "layout.pocketpc.sub" ] = "大字下方",

	-- en: Status line
	[ "layout.pocketpc.status" ] = "状态栏",

	-- en: Readout, left 1
	[ "layout.pocketpc.l1" ] = "左侧读数 1",

	-- en: Readout, left 2
	[ "layout.pocketpc.l2" ] = "左侧读数 2",

	-- en: Readout, left 3
	[ "layout.pocketpc.l3" ] = "左侧读数 3",

	-- en: Readout, right 1
	[ "layout.pocketpc.r1" ] = "右侧读数 1",

	-- en: Readout, right 2
	[ "layout.pocketpc.r2" ] = "右侧读数 2",

	-- en: Readout, right 3
	[ "layout.pocketpc.r3" ] = "右侧读数 3",

	-- en: Menu bar
	[ "layout.pocketpc.menu" ] = "菜单栏",

	-- en: Terminal
	[ "layout.terminal.name" ] = "终端",

	-- en: Developer readout: eight lines of labels and values, an FPS graph and a prompt line with the tool hints.
	[ "layout.terminal.desc" ] = "开发者读数：八行标签与数值、FPS 曲线图，以及显示工具提示的命令行。",

	-- en: Header
	[ "layout.terminal.head" ] = "标题",

	-- en: Header, right
	[ "layout.terminal.clock" ] = "标题右侧",

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
	[ "layout.terminal.foot" ] = "命令行",

	-- en: Minimal
	[ "layout.minimal.name" ] = "极简",

	-- en: Large, glanceable text: clock, compass, the tool name sized to fit, what you aim at and two corner values.
	[ "layout.minimal.desc" ] = "一眼就能看清的大字：时钟、指南针、自动缩放的工具名、瞄准的目标，以及两个角落的数值。",

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
	[ "theme.phosphor" ] = "绿色荧光",

	-- en: Amber CRT
	[ "theme.amber" ] = "琥珀色 CRT",

	-- en: Sakura
	[ "theme.sakura" ] = "樱花",

	-- en: Sandbox blue
	[ "theme.sandbox" ] = "沙盒蓝",

	-- parts of the screen whose colour can be changed
	-- en: Title bar
	[ "color.bar" ] = "标题栏",

	-- en: Links and highlights
	[ "color.accent" ] = "链接与高亮",

	-- en: Big text
	[ "color.hero" ] = "大字",

	-- en: Status line
	[ "color.strip" ] = "状态栏",

	-- en: Readout panel
	[ "color.panel" ] = "读数面板",

	-- en: Menu bar
	[ "color.menu" ] = "菜单栏",

	-- en: Terminal text
	[ "color.term" ] = "终端文字",

	-- en: Text
	[ "category.text" ] = "文字",

	-- en: Time
	[ "category.time" ] = "时间",

	-- en: Tool
	[ "category.tool" ] = "工具",

	-- en: Aim
	[ "category.aim" ] = "瞄准",

	-- en: Aimed entity
	[ "category.entity" ] = "瞄准的实体",

	-- en: Tracked entity
	[ "category.tracked" ] = "跟踪的实体",

	-- en: You
	[ "category.player" ] = "你",

	-- en: Game
	[ "category.game" ] = "游戏",

	-- the Advanced Toolgun [Hotbar] addon; keep its name as it is
	-- en: Advanced Toolgun
	[ "category.atg" ] = "Advanced Toolgun",

	-- en: A line in your language from the language files, e.g. {tr:nav_back} or {tr:props}.
	[ "token.tr" ] = "语言文件中的一行本地化文字，例如 {tr:nav_back} 或 {tr:props}。",

	-- en: Local time, formatted by the clock settings. {time:%H:%M:%S} takes an os.date format.
	[ "token.time" ] = "本地时间，按时钟设置显示。{time:%H:%M:%S} 可使用 os.date 格式。",

	-- en: Today's date. {date:%Y-%m-%d} takes an os.date format.
	[ "token.date" ] = "今天的日期。{date:%Y-%m-%d} 可使用 os.date 格式。",

	-- en: How long you have been in this game.
	[ "token.session" ] = "你在本局游戏中已待了多久。",

	-- en: How long the map has been running.
	[ "token.map_time" ] = "当前地图已运行的时间。",

	-- en: Name of the selected tool.
	[ "token.tool" ] = "当前工具的名称。",

	-- en: Internal name of the selected tool.
	[ "token.tool_id" ] = "当前工具的内部名称。",

	-- en: Description of the selected tool.
	[ "token.tool_desc" ] = "当前工具的说明。",

	-- en: Tool menu category of the selected tool.
	[ "token.tool_category" ] = "当前工具在工具菜单中的分类。",

	-- en: Stage of the selected tool (0 = nothing selected yet).
	[ "token.tool_stage" ] = "当前工具的阶段（0 = 尚未选中任何物体）。",

	-- en: The stage while a multi-click tool is in progress, otherwise empty.
	[ "token.tool_progress" ] = "多次点击的工具进行中时显示当前阶段，否则为空。",

	-- en: The tool you used before this one (dts_tool_back switches to it).
	[ "token.tool_prev" ] = "你上一个使用的工具（dts_tool_back 可切换回去）。",

	-- en: The next tool in the same menu category (dts_tool_next switches to it).
	[ "token.tool_next" ] = "同一菜单分类中的下一个工具（dts_tool_next 可切换过去）。",

	-- en: Successful tool gun shots this session.
	[ "token.tool_uses" ] = "本局中工具枪成功射击的次数。",

	-- en: A setting of the selected tool, e.g. {tool_cvar:forcelimit} reads weld_forcelimit.
	[ "token.tool_cvar" ] = "当前工具的某项设置，例如 {tool_cvar:forcelimit} 读取 weld_forcelimit。",

	-- en: All settings of the selected tool as name=value pairs.
	[ "token.tool_settings" ] = "当前工具的全部设置，以“名称=数值”的形式列出。",

	-- en: The current stage's instructions with mouse and key icons.
	[ "token.hints" ] = "当前阶段的操作说明，带鼠标和按键图标。",

	-- en: What left click does right now.
	[ "token.hint_left" ] = "左键现在的作用。",

	-- en: What right click does right now.
	[ "token.hint_right" ] = "右键现在的作用。",

	-- en: What reload does right now.
	[ "token.hint_reload" ] = "换弹键（R）现在的作用。",

	-- en: What you are aiming at, with the name highlighted.
	[ "token.target" ] = "你瞄准的目标，名称高亮显示。",

	-- en: Entity name, or the surface material when aiming at the world.
	[ "token.aim_what" ] = "实体名称；瞄准地图时为表面材质。",

	-- en: Position you are aiming at.
	[ "token.aim_pos" ] = "你瞄准的位置。",

	-- en: X of the aim position.
	[ "token.aim_x" ] = "瞄准位置的 X 坐标。",

	-- en: Y of the aim position.
	[ "token.aim_y" ] = "瞄准位置的 Y 坐标。",

	-- en: Z of the aim position.
	[ "token.aim_z" ] = "瞄准位置的 Z 坐标。",

	-- en: Distance to the aim position.
	[ "token.aim_dist" ] = "到瞄准位置的距离。",

	-- en: Surface normal at the aim position.
	[ "token.aim_normal" ] = "瞄准位置的表面法线。",

	-- en: Steepness of the surface (0 = flat floor, 90 = wall).
	[ "token.aim_slope" ] = "表面的坡度（0 = 平地，90 = 墙面）。",

	-- en: Kind of surface material (metal, wood, concrete...).
	[ "token.aim_surface" ] = "表面材质的种类（金属、木头、混凝土……）。",

	-- en: Surface property as the engine names it (metal box, wood crate...).
	[ "token.aim_surfaceprop" ] = "引擎内部的表面属性名（metal box、wood crate……）。",

	-- en: World texture you are aiming at.
	[ "token.aim_texture" ] = "你瞄准的地图贴图。",

	-- en: Friendly name of the aimed entity.
	[ "token.ent_name" ] = "瞄准实体的易读名称。",

	-- en: Class of the aimed entity.
	[ "token.ent_class" ] = "瞄准实体的类名。",

	-- en: Model file name of the aimed entity.
	[ "token.ent_model" ] = "瞄准实体的模型文件名。",

	-- en: Full model path of the aimed entity.
	[ "token.ent_model_path" ] = "瞄准实体的完整模型路径。",

	-- en: Entity index.
	[ "token.ent_index" ] = "实体编号。",

	-- en: Health of the aimed entity (players, NPCs, breakable props).
	[ "token.ent_health" ] = "瞄准实体的生命值（玩家、NPC、可破坏的道具）。",

	-- en: Owner of the aimed entity (in multiplayer this needs a CPPI prop protection addon).
	[ "token.ent_owner" ] = "瞄准实体的所有者（多人游戏中需要支持 CPPI 的道具保护插件）。",

	-- en: Material of the aimed entity.
	[ "token.ent_material" ] = "瞄准实体的材质。",

	-- en: Colour of the aimed entity.
	[ "token.ent_color" ] = "瞄准实体的颜色。",

	-- en: Skin of the aimed entity.
	[ "token.ent_skin" ] = "瞄准实体的皮肤。",

	-- en: Speed of the aimed entity.
	[ "token.ent_speed" ] = "瞄准实体的速度。",

	-- en: Position of the aimed entity.
	[ "token.ent_pos" ] = "瞄准实体的位置。",

	-- en: Angles of the aimed entity.
	[ "token.ent_ang" ] = "瞄准实体的角度。",

	-- en: Mass of the aimed entity, when your game knows its physics.
	[ "token.ent_mass" ] = "瞄准实体的质量（游戏能获取其物理数据时）。",

	-- en: Tracked entity summary: name, distance, speed, health.
	[ "token.track" ] = "跟踪实体的概况：名称、距离、速度、生命值。",

	-- en: Name of the tracked entity.
	[ "token.track_name" ] = "跟踪实体的名称。",

	-- en: Class of the tracked entity.
	[ "token.track_class" ] = "跟踪实体的类名。",

	-- en: Your distance to the tracked entity.
	[ "token.track_dist" ] = "你与跟踪实体的距离。",

	-- en: Speed of the tracked entity.
	[ "token.track_speed" ] = "跟踪实体的速度。",

	-- en: Health of the tracked entity.
	[ "token.track_health" ] = "跟踪实体的生命值。",

	-- en: Position of the tracked entity.
	[ "token.track_pos" ] = "跟踪实体的位置。",

	-- en: Your name.
	[ "token.player" ] = "你的名字。",

	-- en: Your health.
	[ "token.health" ] = "你的生命值。",

	-- en: Your armor.
	[ "token.armor" ] = "你的护甲值。",

	-- en: Your speed.
	[ "token.speed" ] = "你的速度。",

	-- en: Your position.
	[ "token.pos" ] = "你的位置。",

	-- en: Your view pitch and yaw.
	[ "token.eye_ang" ] = "你视角的俯仰角和偏航角。",

	-- en: Compass heading (north is +Y on the map).
	[ "token.heading" ] = "指南针方向（地图上的 +Y 为北）。",

	-- en: Shows a word while you are noclipping, otherwise empty.
	[ "token.noclip" ] = "穿墙时显示一个词，否则为空。",

	-- en: Frames per second (smoothed).
	[ "token.fps" ] = "每秒帧数（平滑后）。",

	-- en: Your ping in milliseconds.
	[ "token.ping" ] = "你的延迟，单位为毫秒。",

	-- en: Your device's battery charge while it runs on battery, or \"Plugged in\".
	[ "token.battery" ] = "设备使用电池供电时为电池电量，接通电源时显示“已接通电源”。",

	-- en: Current map.
	[ "token.map" ] = "当前地图。",

	-- en: Players on the server and its player limit.
	[ "token.players" ] = "服务器上的玩家数和人数上限。",

	-- en: Server name.
	[ "token.server" ] = "服务器名称。",

	-- en: Active gamemode.
	[ "token.gamemode" ] = "当前游戏模式。",

	-- en: Server tick rate.
	[ "token.tickrate" ] = "服务器的 Tick 率。",

	-- en: Memory used by Lua in your game.
	[ "token.lua_mem" ] = "游戏中 Lua 占用的内存。",

	-- en: Entities known to your game.
	[ "token.entities" ] = "你的游戏已知的实体数量。",

	-- en: Props you have spawned.
	[ "token.props" ] = "你生成的道具数量。",

	-- en: Your prop limit.
	[ "token.props_max" ] = "你的道具上限。",

	-- en: Spawn count and limit of a type, e.g. {count:ragdolls} or {count:thrusters}.
	[ "token.count" ] = "某类物品的生成数量和上限，例如 {count:ragdolls} 或 {count:thrusters}。",

	-- en: Value of any console variable, e.g. {cvar:sv_gravity}.
	[ "token.cvar" ] = "任意控制台变量的值，例如 {cvar:sv_gravity}。",

	-- en: Advanced Toolgun [Hotbar]: its open tab (Tools, Wire or Favorites).
	[ "token.atg_tab" ] = "Advanced Toolgun [Hotbar]：当前打开的标签页（工具、Wire 或收藏夹）。",

	-- en: Advanced Toolgun [Hotbar]: the section of its list the selection is in.
	[ "token.atg_section" ] = "Advanced Toolgun [Hotbar]：列表中当前选中项所在的分区。",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel up.
	[ "token.atg_prev" ] = "Advanced Toolgun [Hotbar]：快速选择时向上滚动鼠标滚轮会切换到的工具。",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel down.
	[ "token.atg_next" ] = "Advanced Toolgun [Hotbar]：快速选择时向下滚动鼠标滚轮会切换到的工具。",

	-- en: Turns the tool gun's mini screen into a live display. Changes apply instantly; the preview shows what the screen draws right now.
	[ "menu.intro" ] = "把工具枪的小屏幕变成实时显示屏。修改会立即生效；预览显示屏幕此刻绘制的内容。",

	-- en: Dynamic screen is off
	[ "menu.preview_off" ] = "动态屏幕已关闭",

	-- en: Enable the dynamic screen
	[ "menu.enable" ] = "启用动态屏幕",

	-- en: Language
	[ "menu.language" ] = "语言",

	-- first entry of the language list; {name} is the game's language, e.g. "English"
	-- en: Automatic: {name}
	[ "menu.language.auto" ] = "自动：{name}",

	-- en: Inspect: read the screen up close
	[ "menu.inspect.title" ] = "查看：凑近阅读屏幕",

	-- en: Hold a key while holding the tool gun to raise its screen to your eyes.
	[ "menu.inspect.help" ] = "手持工具枪时按住一个键，屏幕就会举到你眼前。",

	-- en: Inspect key
	[ "menu.inspect.key" ] = "查看键",

	-- en: Screen size while inspecting
	[ "menu.inspect.size" ] = "查看时的屏幕大小",

	-- en: Or use the console: bind <key> +dts_inspect (hold) or dts_inspect_toggle.
	[ "menu.inspect.console" ] = "也可以用控制台：bind <按键> +dts_inspect（按住）或 dts_inspect_toggle。",

	-- the tool gun model has a paper note glued on, which overlaps the screen's top right corner
	-- en: Screen in front of the paper note
	[ "menu.inspect.on_top" ] = "屏幕显示在便条前面",

	-- en: While inspecting, the whole screen stays readable. Untick to let the paper note glued to the tool gun cover the top right corner of the screen, as on the model.
	[ "menu.inspect.on_top_help" ] = "查看时整个屏幕都清晰可读。取消勾选后，粘在工具枪上的便条会像模型上一样挡住屏幕的右上角。",

	-- en: Layout and look
	[ "menu.look.title" ] = "布局与外观",

	-- en: Layout
	[ "menu.look.layout" ] = "布局",

	-- en: Theme
	[ "menu.look.theme" ] = "主题",

	-- en: Background
	[ "menu.look.background" ] = "背景",

	-- en: Automatic (layout's choice)
	[ "menu.bg.auto" ] = "自动（由布局决定）",

	-- the whole original screen picture without its text
	-- en: Original screen
	[ "menu.bg.original" ] = "原版屏幕",

	-- only the blurred photo from the original picture, filling the screen
	-- en: Original photo
	[ "menu.bg.art" ] = "原版照片",

	-- en: Theme gradient
	[ "menu.bg.gradient" ] = "主题渐变",

	-- en: Live camera: zoom
	[ "menu.bg.camera" ] = "实时镜头：放大",

	-- en: Live camera: rear view
	[ "menu.bg.rear" ] = "实时镜头：后视",

	-- en: Custom image
	[ "menu.bg.image" ] = "自定义图片",

	-- en: Black
	[ "menu.bg.black" ] = "黑色",

	-- en: Custom image
	[ "menu.look.image" ] = "自定义图片",

	-- en: A material path, or an image in garrysmod/data written as ../data/name.png
	[ "menu.look.image_help" ] = "填写材质路径，或 garrysmod/data 中的图片，写作 ../data/文件名.png",

	-- en: Darken background
	[ "menu.look.dim" ] = "背景变暗",

	-- en: Camera field of view
	[ "menu.look.cam_fov" ] = "镜头视野",

	-- en: Camera updates per second
	[ "menu.look.cam_fps" ] = "镜头每秒刷新次数",

	-- en: Text font
	[ "menu.look.font" ] = "文字字体",

	-- en: Big text font
	[ "menu.look.font_hero" ] = "大字字体",

	-- en: Terminal font
	[ "menu.look.font_mono" ] = "终端字体",

	-- first entry of the font lists; {font} is the font your language uses
	-- en: Automatic ({font})
	[ "menu.font.auto" ] = "自动（{font}）",

	-- en: Colours
	[ "menu.colors.title" ] = "颜色",

	-- en: Override single colours of the theme. Click a swatch to change it.
	[ "menu.colors.help" ] = "单独覆盖主题中的某些颜色。点击色块即可修改。",

	-- written on a colour swatch that still uses the theme's colour
	-- en: theme
	[ "menu.colors.theme_tag" ] = "主题",

	-- en: Click to pick a colour
	[ "menu.colors.pick" ] = "点击选择颜色",

	-- en: Use the theme's colours everywhere
	[ "menu.colors.reset_all" ] = "全部使用主题颜色",

	-- en: Screen colour: {name}
	[ "menu.colors.picker_title" ] = "屏幕颜色：{name}",

	-- en: Use the theme's colour
	[ "menu.colors.use_theme" ] = "使用主题颜色",

	-- en: Big text
	[ "menu.hero.title" ] = "大字",

	-- en: Behaviour
	[ "menu.hero.mode" ] = "显示方式",

	-- en: Always scroll (original)
	[ "menu.hero.scroll" ] = "始终滚动（原版）",

	-- en: Scroll only when too long
	[ "menu.hero.auto" ] = "过长时才滚动",

	-- en: Shrink to fit
	[ "menu.hero.fit" ] = "缩小以适应",

	-- en: Scroll speed
	[ "menu.hero.speed" ] = "滚动速度",

	-- en: Upper case tool names
	[ "menu.hero.upper" ] = "工具名使用大写字母",

	-- en: Screen content
	[ "menu.content.title" ] = "屏幕内容",

	-- keep {tokens}, **stars**, {token|fallback} and {tr:...} as they are: they show the syntax
	-- en: Every line of the {layout} layout is a template. Type text and {tokens}; **stars** highlight text, {token|fallback} gives a default, and a line whose tokens are all empty hides itself. {tr:...} writes a line in your language. See the token reference below.
	[ "menu.content.help" ] = "{layout} 布局的每一行都是模板。可以输入文字和 {tokens}；用 **星号** 包住的文字会高亮，{token|fallback} 在变量为空时显示默认文字，所有变量都为空的行会自动隐藏。{tr:...} 会写出你所用语言的文字。变量列表见下方。",

	-- en: Pick a ready-made line
	[ "menu.content.presets_tip" ] = "选择现成的行",

	-- en: Back to the default: {value}
	[ "menu.content.reset_tip" ] = "恢复默认：{value}",

	-- en: (empty)
	[ "menu.content.empty" ] = "（空）",

	-- shown in an empty line's text box
	-- en: (hidden)
	[ "menu.content.placeholder" ] = "（隐藏）",

	-- under each line: what it shows right now
	-- en: = {text}
	[ "menu.content.now" ] = "= {text}",

	-- en: (hidden right now)
	[ "menu.content.hidden_now" ] = "（当前隐藏）",

	-- en: Reset these lines to the layout's defaults
	[ "menu.content.reset_all" ] = "将这些行恢复为布局默认值",

	-- ready-made lines in the list next to each line
	-- en: Tool name
	[ "menu.preset.tool" ] = "工具名称",

	-- en: Tool category
	[ "menu.preset.tool_category" ] = "工具分类",

	-- en: Tool instructions
	[ "menu.preset.hints" ] = "工具操作说明",

	-- en: Previous tool
	[ "menu.preset.prev_tool" ] = "上一个工具",

	-- en: Next tool
	[ "menu.preset.next_tool" ] = "下一个工具",

	-- en: Tool progress
	[ "menu.preset.progress" ] = "工具进度",

	-- en: Tool settings
	[ "menu.preset.tool_settings" ] = "工具设置",

	-- en: What you aim at
	[ "menu.preset.target" ] = "瞄准的目标",

	-- en: Aim position
	[ "menu.preset.aim_pos" ] = "瞄准位置",

	-- en: Aim distance
	[ "menu.preset.aim_dist" ] = "瞄准距离",

	-- en: Entity or surface
	[ "menu.preset.aim_what" ] = "实体或表面",

	-- en: Surface slope
	[ "menu.preset.slope" ] = "表面坡度",

	-- en: Entity class
	[ "menu.preset.ent_class" ] = "实体类名",

	-- en: Entity model
	[ "menu.preset.ent_model" ] = "实体模型",

	-- en: Entity health
	[ "menu.preset.ent_health" ] = "实体生命值",

	-- en: Entity owner
	[ "menu.preset.ent_owner" ] = "实体所有者",

	-- en: Entity speed
	[ "menu.preset.ent_speed" ] = "实体速度",

	-- en: Tracked entity
	[ "menu.preset.track" ] = "跟踪的实体",

	-- en: Clock
	[ "menu.preset.clock" ] = "时钟",

	-- en: Clock with seconds
	[ "menu.preset.clock_seconds" ] = "带秒的时钟",

	-- en: Date
	[ "menu.preset.date" ] = "日期",

	-- en: Time in game
	[ "menu.preset.session" ] = "游戏时长",

	-- en: Your speed
	[ "menu.preset.speed" ] = "你的速度",

	-- en: Your position
	[ "menu.preset.pos" ] = "你的位置",

	-- en: Compass
	[ "menu.preset.heading" ] = "指南针",

	-- en: Health and armor
	[ "menu.preset.health_armor" ] = "生命和护甲",

	-- en: FPS and ping
	[ "menu.preset.perf" ] = "FPS 和延迟",

	-- en: Prop count
	[ "menu.preset.props" ] = "道具数量",

	-- en: Map
	[ "menu.preset.map" ] = "地图",

	-- en: Players
	[ "menu.preset.players" ] = "玩家",

	-- en: Empty (hide the line)
	[ "menu.preset.empty" ] = "空（隐藏该行）",

	-- en: Clock and units
	[ "menu.clock.title" ] = "时钟与单位",

	-- en: Clock
	[ "menu.clock.style" ] = "时钟",

	-- {language} is the name of the active language
	-- en: As usual in {language}
	[ "menu.clock.auto" ] = "按{language}的习惯",

	-- en: 12 hour
	[ "menu.clock.12h" ] = "12 小时制",

	-- en: 24 hour
	[ "menu.clock.24h" ] = "24 小时制",

	-- en: Show seconds
	[ "menu.clock.seconds" ] = "显示秒",

	-- en: Show AM / PM (12 hour clock)
	[ "menu.clock.ampm" ] = "显示上午/下午（12 小时制）",

	-- en: Blink the colon
	[ "menu.clock.blink" ] = "冒号闪烁",

	-- en: Units
	[ "menu.units.label" ] = "单位",

	-- en: Metric (m, km/h)
	[ "menu.units.m" ] = "公制（米、km/h）",

	-- en: Imperial (ft, mph)
	[ "menu.units.ft" ] = "英制（英尺、英里/时）",

	-- en: Hammer units
	[ "menu.units.hu" ] = "Hammer 单位",

	-- en: Distance decimals
	[ "menu.units.decimals" ] = "距离的小数位数",

	-- en: Icons and effects
	[ "menu.fx.title" ] = "图标与效果",

	-- en: Speaker icon (volume, voice chat)
	[ "menu.fx.speaker" ] = "扬声器图标（音量、语音聊天）",

	-- en: Signal icon (connection)
	[ "menu.fx.signal" ] = "信号图标（网络连接）",

	-- en: Battery icon (your device's battery)
	[ "menu.fx.battery" ] = "电池图标（设备的电池）",

	-- en: Boot animation when taking out the tool gun
	[ "menu.fx.boot" ] = "拿出工具枪时播放开机动画",

	-- en: Flash when the tool gun fires
	[ "menu.fx.flash" ] = "工具枪开火时屏幕闪烁",

	-- en: Show game notifications on the screen
	[ "menu.fx.notify" ] = "在屏幕上显示游戏通知",

	-- en: Notification time
	[ "menu.fx.notify_time" ] = "通知显示时长",

	-- en: Scanlines
	[ "menu.fx.scanlines" ] = "扫描线",

	-- en: Darker edges
	[ "menu.fx.vignette" ] = "边缘变暗",

	-- en: Backlight
	[ "menu.fx.backlight" ] = "背光亮度",

	-- en: HUD mirror
	[ "menu.mirror.title" ] = "HUD 镜像",

	-- en: Shows the screen on your HUD while you hold the tool gun, for reading the small print.
	[ "menu.mirror.help" ] = "手持工具枪时把屏幕同时显示在 HUD 上，方便阅读小字。",

	-- en: Show the screen on the HUD
	[ "menu.mirror.enable" ] = "在 HUD 上显示屏幕",

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
	[ "menu.adv.title" ] = "高级",

	-- en: Keep the own screens of tools that draw one
	[ "menu.adv.respect" ] = "保留自带屏幕的工具的原有屏幕",

	-- en: e.g. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod tools
	[ "menu.adv.respect_help" ] = "例如 Easy Entity Inspector、Ragdoll Puppeteer、Wiremod 工具",

	-- en: Live value updates per second
	[ "menu.adv.refresh" ] = "实时数值每秒更新次数",

	-- en: Screen redraws per second (0 = every frame)
	[ "menu.adv.fps" ] = "屏幕每秒重绘次数（0 = 每帧）",

	-- en: Resolution
	[ "menu.adv.resolution" ] = "分辨率",

	-- en: 256 x 256 (original)
	[ "menu.res.256" ] = "256 x 256（原版）",

	-- en: 512 x 512 (sharper, for 1440p and up)
	[ "menu.res.512" ] = "512 x 512（更清晰，适合 1440p 及以上）",

	-- keep the commands as they are
	-- en: Key binds (bind <key> <command>):\n  dts_tool_back  -  previous tool\n  dts_tool_next / dts_tool_prev  -  cycle the category\n  dts_layout_next, dts_theme_next  -  cycle layouts, themes\n  dts_track / dts_untrack  -  follow an entity
	[ "menu.adv.binds" ] = "按键绑定（bind <按键> <命令>）：\n  dts_tool_back  -  上一个工具\n  dts_tool_next / dts_tool_prev  -  在分类中切换工具\n  dts_layout_next, dts_theme_next  -  切换布局、主题\n  dts_track / dts_untrack  -  跟踪实体",

	-- en: Copy my settings to the clipboard
	[ "menu.adv.copy" ] = "把我的设置复制到剪贴板",

	-- en: Screen settings copied to the clipboard
	[ "menu.adv.copied" ] = "屏幕设置已复制到剪贴板",

	-- en: Import settings...
	[ "menu.adv.import" ] = "导入设置……",

	-- en: Import screen settings
	[ "menu.adv.import_title" ] = "导入屏幕设置",

	-- en: Paste a DTS1:... settings string
	[ "menu.adv.import_prompt" ] = "粘贴 DTS1:... 格式的设置字符串",

	-- en: Import
	[ "menu.adv.import_ok" ] = "导入",

	-- en: Imported screen settings ({n} changed)
	[ "menu.adv.imported" ] = "已导入屏幕设置（更改了 {n} 项）",

	-- en: Reset everything to defaults
	[ "menu.adv.reset" ] = "全部恢复默认",

	-- en: Reset
	[ "menu.adv.reset_title" ] = "恢复默认",

	-- en: Reset every Dynamic Toolgun Screen setting?
	[ "menu.adv.reset_question" ] = "要把动态工具枪屏幕的所有设置恢复默认吗？",

	-- en: Reset
	[ "menu.adv.reset_yes" ] = "恢复默认",

	-- en: Cancel
	[ "menu.adv.cancel" ] = "取消",

	-- en: Another addon replaced the tool gun screen ({file}). Use the button below to take over.
	[ "menu.adv.diag_conflict" ] = "另一个插件替换了工具枪屏幕（{file}）。可用下面的按钮接管。",

	-- en: v{version} installed. Each redraw takes {ms} ms.
	[ "menu.adv.diag_ok" ] = "v{version} 已安装。每次重绘耗时 {ms} 毫秒。",

	-- en: Last error: {error}
	[ "menu.adv.diag_error" ] = "上次错误：{error}",

	-- en: Waiting for the tool gun to load...
	[ "menu.adv.diag_wait" ] = "正在等待工具枪加载……",

	-- en: Take over the tool gun screen
	[ "menu.adv.takeover" ] = "接管工具枪屏幕",

	-- en: Only needed if another addon replaced the tool gun's screen after this one
	[ "menu.adv.takeover_tip" ] = "仅当其他插件在本插件之后替换了工具枪屏幕时才需要",

	-- en: Dynamic Toolgun Screen installed
	[ "menu.adv.takeover_done" ] = "动态工具枪屏幕已接管",

	-- answers to "Import settings..." when the pasted text is wrong
	-- en: This is not a Dynamic Toolgun Screen settings string.
	[ "import.not_ours" ] = "这不是动态工具枪屏幕的设置字符串。",

	-- en: The settings string is damaged.
	[ "import.damaged" ] = "设置字符串已损坏。",

	-- en: Token reference
	[ "menu.tokens.title" ] = "变量列表",

	-- en: Hover a token for what it does, double-click to copy it.
	[ "menu.tokens.help" ] = "鼠标悬停可查看变量的作用，双击即可复制。",

	-- en: Token
	[ "menu.tokens.col_token" ] = "变量",

	-- en: Right now
	[ "menu.tokens.col_now" ] = "当前值",

	-- en: Copied {token}
	[ "menu.tokens.copied" ] = "已复制 {token}",

}
