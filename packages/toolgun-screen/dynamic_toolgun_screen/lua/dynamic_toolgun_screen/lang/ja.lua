--[[
	Dynamic Toolgun Screen - 日本語 (ja)

	Made from lang/en.lua with tools/i18n.py (see TRANSLATING.md). Above each phrase, "-- en:" holds the
	English it translates; "tools/i18n.py check" lists phrases whose English changed since. A phrase
	missing here falls back to English.
]]

return {

	-- name of the language in that language, shown in the language list
	-- en: English
	[ "_name" ] = "日本語",

	-- decimal separator for numbers on the screen
	-- en: .
	[ "_decimal" ] = ".",

	-- 1 if a 24 hour clock is usual in this language, 0 for 12 hour
	-- en: 0
	[ "_clock24" ] = "1",

	-- fonts that have every letter of the language; size factor and weight snapping (1/0) for them
	-- en: Tahoma
	[ "_font.ui" ] = "Meiryo UI",

	-- en: Helvetica
	[ "_font.hero" ] = "Meiryo UI",

	-- en: Consolas
	[ "_font.mono" ] = "Meiryo UI",

	-- en: 1
	[ "_font.scale" ] = "1",

	-- en: 0
	[ "_font.snap" ] = "1",

	-- Shown by the game: the tool list, the tool's help on the HUD, the context menu, the Utilities tab --
	-- en: Dynamic Toolgun Screen
	[ "tool.name" ] = "ダイナミック・ツールガン画面",

	-- en: Customize the tool gun's live screen and track entities on it
	[ "tool.desc" ] = "ツールガンのライブ画面をカスタマイズし、エンティティを追跡します",

	-- en: Track the entity you are aiming at
	[ "tool.left" ] = "狙っているエンティティを追跡",

	-- en: Switch to the next screen layout
	[ "tool.right" ] = "次の画面レイアウトに切り替え",

	-- en: Stop tracking
	[ "tool.reload" ] = "追跡を停止",

	-- context menu entry (right click an entity while holding C)
	-- en: Track on tool gun screen
	[ "prop.track" ] = "ツールガン画面で追跡",

	-- Utilities tab: category and its only entry
	-- en: Dynamic Toolgun Screen
	[ "menu.category" ] = "ダイナミック・ツールガン画面",

	-- en: Settings
	[ "menu.settings_item" ] = "設定",

	-- status line; {name} is an entity name such as "oildrum001" or a player's name
	-- en: Aiming at **{name}**
	[ "target.entity" ] = "照準：**{name}**",

	-- en: Aiming at the **sky**
	[ "target.sky" ] = "照準：**空**",

	-- en: World
	[ "target.world" ] = "ワールド",

	-- {surface} is a material from the mat.* phrases below
	-- en: World - **{surface}**
	[ "target.world_surface" ] = "ワールド - **{surface}**",

	-- en: Nothing in range
	[ "target.nothing" ] = "範囲内に対象なし",

	-- what you aim at, when it is the sky
	-- en: sky
	[ "aim.sky" ] = "空",

	-- multi-click tools (weld, rope...): which click comes next
	-- en: Stage {n}
	[ "tool.progress" ] = "ステップ {n}",

	-- health of the tracked entity, e.g. "HP 40/100"
	-- en: HP {hp}
	[ "track.hp" ] = "HP {hp}",

	-- en: Noclip
	[ "noclip" ] = "ノークリップ",

	-- view angles: P = pitch, Y = yaw
	-- en: P {p}  Y {y}
	[ "eye_ang" ] = "ピッチ {p}  ヨー {y}",

	-- compass heading, e.g. "NE 45°"
	-- en: {dir} {deg}°
	[ "heading" ] = "{dir} {deg}°",

	-- en: N
	[ "compass.n" ] = "北",

	-- en: NE
	[ "compass.ne" ] = "北東",

	-- en: E
	[ "compass.e" ] = "東",

	-- en: SE
	[ "compass.se" ] = "南東",

	-- en: S
	[ "compass.s" ] = "南",

	-- en: SW
	[ "compass.sw" ] = "南西",

	-- en: W
	[ "compass.w" ] = "西",

	-- en: NW
	[ "compass.nw" ] = "北西",

	-- label of the FPS graph in the Terminal layout
	-- en: {n} fps
	[ "term.fps" ] = "{n} FPS",

	-- shown on the screen when it fails to draw
	-- en: Screen error
	[ "error.title" ] = "画面エラー",

	-- en: See the console for details. Change the layout or run dts_reset to recover.
	[ "error.hint" ] = "詳細はコンソールを確認してください。レイアウトを変更するか、dts_reset を実行すると復旧します。",

	-- tabs of the Advanced Toolgun [Hotbar] addon's tool list, for the {atg_tab} token
	-- en: Tools
	[ "atg.tab.tools" ] = "ツール",

	-- en: Wire
	[ "atg.tab.wire" ] = "Wire",

	-- en: Favorites
	[ "atg.tab.favorites" ] = "お気に入り",

	-- the device's battery, next to the battery icon and in {battery}: {n} is the charge in percent;
	-- "Plugged in" is shown while the device runs on mains power instead of its battery
	-- en: {n}%
	[ "battery.percent" ] = "{n}%",

	-- en: Plugged in
	[ "battery.plugged" ] = "AC 電源",

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
	[ "duration.hm" ] = "{h}時間{m}分",

	-- en: {m}m {s}s
	[ "duration.ms" ] = "{m}分{s}秒",

	-- en: {s}s
	[ "duration.s" ] = "{s}秒",

	-- 12 hour clock: AM/PM and where they go around the time
	-- en: AM
	[ "clock.am" ] = "午前",

	-- en: PM
	[ "clock.pm" ] = "午後",

	-- en: {time} {ampm}
	[ "clock.ampm" ] = "{ampm}{time}",

	-- Date: {wday} day of week (short), {day} day number, {month} month (short), {year}
	-- en: {wday} {day} {month}
	[ "date.format" ] = "{month}{day}日({wday})",

	-- en: Sun
	[ "date.wday.1" ] = "日",

	-- en: Mon
	[ "date.wday.2" ] = "月",

	-- en: Tue
	[ "date.wday.3" ] = "火",

	-- en: Wed
	[ "date.wday.4" ] = "水",

	-- en: Thu
	[ "date.wday.5" ] = "木",

	-- en: Fri
	[ "date.wday.6" ] = "金",

	-- en: Sat
	[ "date.wday.7" ] = "土",

	-- en: Sunday
	[ "date.wday_full.1" ] = "日曜日",

	-- en: Monday
	[ "date.wday_full.2" ] = "月曜日",

	-- en: Tuesday
	[ "date.wday_full.3" ] = "火曜日",

	-- en: Wednesday
	[ "date.wday_full.4" ] = "水曜日",

	-- en: Thursday
	[ "date.wday_full.5" ] = "木曜日",

	-- en: Friday
	[ "date.wday_full.6" ] = "金曜日",

	-- en: Saturday
	[ "date.wday_full.7" ] = "土曜日",

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
	[ "date.month_full.1" ] = "1月",

	-- en: February
	[ "date.month_full.2" ] = "2月",

	-- en: March
	[ "date.month_full.3" ] = "3月",

	-- en: April
	[ "date.month_full.4" ] = "4月",

	-- en: May
	[ "date.month_full.5" ] = "5月",

	-- en: June
	[ "date.month_full.6" ] = "6月",

	-- en: July
	[ "date.month_full.7" ] = "7月",

	-- en: August
	[ "date.month_full.8" ] = "8月",

	-- en: September
	[ "date.month_full.9" ] = "9月",

	-- en: October
	[ "date.month_full.10" ] = "10月",

	-- en: November
	[ "date.month_full.11" ] = "11月",

	-- en: December
	[ "date.month_full.12" ] = "12月",

	-- Kinds of surface material (the game's material types), shown as "World - Concrete"
	-- en: Antlion
	[ "mat.antlion" ] = "アントライオン",

	-- en: Bloody flesh
	[ "mat.bloodyflesh" ] = "血肉",

	-- en: Concrete
	[ "mat.concrete" ] = "コンクリート",

	-- en: Dirt
	[ "mat.dirt" ] = "土",

	-- en: Eggshell
	[ "mat.eggshell" ] = "卵の殻",

	-- en: Flesh
	[ "mat.flesh" ] = "肉",

	-- en: Grate
	[ "mat.grate" ] = "格子",

	-- en: Alien flesh
	[ "mat.alienflesh" ] = "エイリアンの肉",

	-- en: Clip
	[ "mat.clip" ] = "透明な壁",

	-- en: Snow
	[ "mat.snow" ] = "雪",

	-- en: Plastic
	[ "mat.plastic" ] = "プラスチック",

	-- en: Metal
	[ "mat.metal" ] = "金属",

	-- en: Sand
	[ "mat.sand" ] = "砂",

	-- en: Foliage
	[ "mat.foliage" ] = "植物",

	-- en: Computer
	[ "mat.computer" ] = "電子機器",

	-- en: Liquid
	[ "mat.slosh" ] = "液体",

	-- en: Tile
	[ "mat.tile" ] = "タイル",

	-- en: Grass
	[ "mat.grass" ] = "草",

	-- en: Vent
	[ "mat.vent" ] = "通気口",

	-- en: Wood
	[ "mat.wood" ] = "木",

	-- en: Generic
	[ "mat.default" ] = "標準",

	-- en: Glass
	[ "mat.glass" ] = "ガラス",

	-- en: Warp shield
	[ "mat.warpshield" ] = "ワープシールド",

	-- Notifications on the screen
	-- en: Tracking {name}
	[ "notify.tracking" ] = "追跡中：{name}",

	-- en: Stopped tracking
	[ "notify.untracked" ] = "追跡を停止しました",

	-- en: Layout: {name}
	[ "notify.layout" ] = "レイアウト：{name}",

	-- en: Theme: {name}
	[ "notify.theme" ] = "テーマ：{name}",

	-- title bar: tool category, or the game's name when there is none (keep "Garry's Mod")
	-- en: {tool_category|Garry's Mod}
	[ "tpl.title" ] = "{tool_category|Garry's Mod}",

	-- left link of the Pocket PC screen: the previous tool
	-- en: Back to {tool_prev}
	[ "tpl.nav_back" ] = "{tool_prev} に戻る",

	-- en: Props {props}/{props_max}
	[ "tpl.props" ] = "プロップ {props}/{props_max}",

	-- en: {fps} fps  {ping} ms
	[ "tpl.perf" ] = "{fps} FPS  {ping} ms",

	-- en: Slope {aim_slope}
	[ "tpl.slope" ] = "傾斜 {aim_slope}",

	-- en: HP {ent_health}
	[ "tpl.hp" ] = "HP {ent_health}",

	-- en: Owner: {ent_owner}
	[ "tpl.owner" ] = "所有者：{ent_owner}",

	-- HP = health, AP = armor
	-- en: HP {health}  AP {armor}
	[ "tpl.health_armor" ] = "HP {health}  アーマー {armor}",

	-- en: {players} players
	[ "tpl.players" ] = "プレイヤー {players}",

	-- Terminal lines: a short upper case label, a tab, then the value
	-- en: TOOL\t**{tool}**
	[ "tpl.term_tool" ] = "ツール\t**{tool}**",

	-- en: AIM\t**{aim_what}**
	[ "tpl.term_aim" ] = "対象\t**{aim_what}**",

	-- en: CLASS\t**{ent_class|-}**
	[ "tpl.term_class" ] = "クラス\t**{ent_class|-}**",

	-- en: POS\t**{aim_pos}**
	[ "tpl.term_pos" ] = "位置\t**{aim_pos}**",

	-- en: DIST\t**{aim_dist}**  {aim_slope}
	[ "tpl.term_dist" ] = "距離\t**{aim_dist}**  {aim_slope}",

	-- en: OWNER\t**{ent_owner|-}**
	[ "tpl.term_owner" ] = "所有者\t**{ent_owner|-}**",

	-- en: HP\t**{ent_health|-}**
	[ "tpl.term_hp" ] = "HP\t**{ent_health|-}**",

	-- en: TRACK\t**{track_name|-}** {track_dist}
	[ "tpl.term_track" ] = "追跡\t**{track_name|-}** {track_dist}",

	-- en: Pocket PC
	[ "layout.pocketpc.name" ] = "Pocket PC",

	-- en: The original screen rebuilt with live data: clock, status icons, tool history links, big tool name, status line, six readouts and a hint bar.
	[ "layout.pocketpc.desc" ] = "元の画面をライブデータで再現：時計、ステータスアイコン、ツール履歴のリンク、大きなツール名、ステータス行、6 つの読み取り値、ヒントバー。",

	-- en: Title bar
	[ "layout.pocketpc.title" ] = "タイトルバー",

	-- en: Clock
	[ "layout.pocketpc.clock" ] = "時計",

	-- en: Left link
	[ "layout.pocketpc.nav_l" ] = "左のリンク",

	-- en: Right link
	[ "layout.pocketpc.nav_r" ] = "右のリンク",

	-- en: Big text
	[ "layout.pocketpc.hero" ] = "大きな文字",

	-- en: Under the big text
	[ "layout.pocketpc.sub" ] = "大きな文字の下",

	-- en: Status line
	[ "layout.pocketpc.status" ] = "ステータス行",

	-- en: Readout, left 1
	[ "layout.pocketpc.l1" ] = "読み取り値 左 1",

	-- en: Readout, left 2
	[ "layout.pocketpc.l2" ] = "読み取り値 左 2",

	-- en: Readout, left 3
	[ "layout.pocketpc.l3" ] = "読み取り値 左 3",

	-- en: Readout, right 1
	[ "layout.pocketpc.r1" ] = "読み取り値 右 1",

	-- en: Readout, right 2
	[ "layout.pocketpc.r2" ] = "読み取り値 右 2",

	-- en: Readout, right 3
	[ "layout.pocketpc.r3" ] = "読み取り値 右 3",

	-- en: Menu bar
	[ "layout.pocketpc.menu" ] = "メニューバー",

	-- en: Terminal
	[ "layout.terminal.name" ] = "ターミナル",

	-- en: Developer readout: eight lines of labels and values, an FPS graph and a prompt line with the tool hints.
	[ "layout.terminal.desc" ] = "開発者向けの表示：ラベルと値の 8 行、FPS グラフ、ツールのヒントを表示するプロンプト行。",

	-- en: Header
	[ "layout.terminal.head" ] = "ヘッダー",

	-- en: Header, right
	[ "layout.terminal.clock" ] = "ヘッダー右側",

	-- en: Line 1
	[ "layout.terminal.l1" ] = "1 行目",

	-- en: Line 2
	[ "layout.terminal.l2" ] = "2 行目",

	-- en: Line 3
	[ "layout.terminal.l3" ] = "3 行目",

	-- en: Line 4
	[ "layout.terminal.l4" ] = "4 行目",

	-- en: Line 5
	[ "layout.terminal.l5" ] = "5 行目",

	-- en: Line 6
	[ "layout.terminal.l6" ] = "6 行目",

	-- en: Line 7
	[ "layout.terminal.l7" ] = "7 行目",

	-- en: Line 8
	[ "layout.terminal.l8" ] = "8 行目",

	-- en: Prompt line
	[ "layout.terminal.foot" ] = "プロンプト行",

	-- en: Minimal
	[ "layout.minimal.name" ] = "ミニマル",

	-- en: Large, glanceable text: clock, compass, the tool name sized to fit, what you aim at and two corner values.
	[ "layout.minimal.desc" ] = "ひと目で読める大きな文字：時計、方位、サイズ調整されたツール名、狙っている対象、2 つの隅の値。",

	-- en: Top left
	[ "layout.minimal.top_l" ] = "左上",

	-- en: Top right
	[ "layout.minimal.top_r" ] = "右上",

	-- en: Big text
	[ "layout.minimal.hero" ] = "大きな文字",

	-- en: Under the big text
	[ "layout.minimal.sub" ] = "大きな文字の下",

	-- en: Bottom left
	[ "layout.minimal.foot_l" ] = "左下",

	-- en: Bottom right
	[ "layout.minimal.foot_r" ] = "右下",

	-- en: Pocket PC (original)
	[ "theme.winmobile" ] = "Pocket PC（オリジナル）",

	-- en: Graphite
	[ "theme.graphite" ] = "グラファイト",

	-- en: Green phosphor
	[ "theme.phosphor" ] = "グリーン蛍光",

	-- en: Amber CRT
	[ "theme.amber" ] = "アンバー CRT",

	-- en: Sakura
	[ "theme.sakura" ] = "桜",

	-- en: Sandbox blue
	[ "theme.sandbox" ] = "サンドボックス ブルー",

	-- parts of the screen whose colour can be changed
	-- en: Title bar
	[ "color.bar" ] = "タイトルバー",

	-- en: Links and highlights
	[ "color.accent" ] = "リンクと強調",

	-- en: Big text
	[ "color.hero" ] = "大きな文字",

	-- en: Status line
	[ "color.strip" ] = "ステータス行",

	-- en: Readout panel
	[ "color.panel" ] = "読み取り値パネル",

	-- en: Menu bar
	[ "color.menu" ] = "メニューバー",

	-- en: Terminal text
	[ "color.term" ] = "ターミナルの文字",

	-- en: Text
	[ "category.text" ] = "テキスト",

	-- en: Time
	[ "category.time" ] = "時間",

	-- en: Tool
	[ "category.tool" ] = "ツール",

	-- en: Aim
	[ "category.aim" ] = "照準",

	-- en: Aimed entity
	[ "category.entity" ] = "狙っているエンティティ",

	-- en: Tracked entity
	[ "category.tracked" ] = "追跡中のエンティティ",

	-- en: You
	[ "category.player" ] = "あなた",

	-- en: Game
	[ "category.game" ] = "ゲーム",

	-- the Advanced Toolgun [Hotbar] addon; keep its name as it is
	-- en: Advanced Toolgun
	[ "category.atg" ] = "Advanced Toolgun",

	-- en: A line in your language from the language files, e.g. {tr:nav_back} or {tr:props}.
	[ "token.tr" ] = "言語ファイルにある、あなたの言語の 1 行。例：{tr:nav_back}、{tr:props}。",

	-- en: Local time, formatted by the clock settings. {time:%H:%M:%S} takes an os.date format.
	[ "token.time" ] = "現地時刻（時計の設定に従って表示）。{time:%H:%M:%S} で os.date の書式を使えます。",

	-- en: Today's date. {date:%Y-%m-%d} takes an os.date format.
	[ "token.date" ] = "今日の日付。{date:%Y-%m-%d} で os.date の書式を使えます。",

	-- en: How long you have been in this game.
	[ "token.session" ] = "このゲームに参加してからの時間。",

	-- en: How long the map has been running.
	[ "token.map_time" ] = "マップが始まってからの時間。",

	-- en: Name of the selected tool.
	[ "token.tool" ] = "選択中のツールの名前。",

	-- en: Internal name of the selected tool.
	[ "token.tool_id" ] = "選択中のツールの内部名。",

	-- en: Description of the selected tool.
	[ "token.tool_desc" ] = "選択中のツールの説明。",

	-- en: Tool menu category of the selected tool.
	[ "token.tool_category" ] = "選択中のツールのツールメニュー内のカテゴリ。",

	-- en: Stage of the selected tool (0 = nothing selected yet).
	[ "token.tool_stage" ] = "選択中のツールの段階（0 = まだ何も選択していない）。",

	-- en: The stage while a multi-click tool is in progress, otherwise empty.
	[ "token.tool_progress" ] = "複数回クリックするツールの作業中はその段階、それ以外は空。",

	-- en: The tool you used before this one (dts_tool_back switches to it).
	[ "token.tool_prev" ] = "前に使っていたツール（dts_tool_back で切り替え）。",

	-- en: The next tool in the same menu category (dts_tool_next switches to it).
	[ "token.tool_next" ] = "同じメニューカテゴリの次のツール（dts_tool_next で切り替え）。",

	-- en: Successful tool gun shots this session.
	[ "token.tool_uses" ] = "このセッションでツールガンを使って成功した回数。",

	-- en: A setting of the selected tool, e.g. {tool_cvar:forcelimit} reads weld_forcelimit.
	[ "token.tool_cvar" ] = "選択中のツールの設定。例：{tool_cvar:forcelimit} は weld_forcelimit を読み取ります。",

	-- en: All settings of the selected tool as name=value pairs.
	[ "token.tool_settings" ] = "選択中のツールのすべての設定（名前=値 の形式）。",

	-- en: The current stage's instructions with mouse and key icons.
	[ "token.hints" ] = "現在の段階の操作説明（マウスとキーのアイコン付き）。",

	-- en: What left click does right now.
	[ "token.hint_left" ] = "今、左クリックで何をするか。",

	-- en: What right click does right now.
	[ "token.hint_right" ] = "今、右クリックで何をするか。",

	-- en: What reload does right now.
	[ "token.hint_reload" ] = "今、リロードキーで何をするか。",

	-- en: What you are aiming at, with the name highlighted.
	[ "token.target" ] = "狙っているもの（名前は強調表示）。",

	-- en: Entity name, or the surface material when aiming at the world.
	[ "token.aim_what" ] = "エンティティの名前、ワールドを狙っているときは表面の材質。",

	-- en: Position you are aiming at.
	[ "token.aim_pos" ] = "狙っている位置。",

	-- en: X of the aim position.
	[ "token.aim_x" ] = "狙っている位置の X。",

	-- en: Y of the aim position.
	[ "token.aim_y" ] = "狙っている位置の Y。",

	-- en: Z of the aim position.
	[ "token.aim_z" ] = "狙っている位置の Z。",

	-- en: Distance to the aim position.
	[ "token.aim_dist" ] = "狙っている位置までの距離。",

	-- en: Surface normal at the aim position.
	[ "token.aim_normal" ] = "狙っている位置の表面の法線。",

	-- en: Steepness of the surface (0 = flat floor, 90 = wall).
	[ "token.aim_slope" ] = "表面の傾斜（0 = 平らな床、90 = 壁）。",

	-- en: Kind of surface material (metal, wood, concrete...).
	[ "token.aim_surface" ] = "表面の材質の種類（金属、木、コンクリートなど）。",

	-- en: Surface property as the engine names it (metal box, wood crate...).
	[ "token.aim_surfaceprop" ] = "エンジンでの表面プロパティ名（metal box、wood crate など）。",

	-- en: World texture you are aiming at.
	[ "token.aim_texture" ] = "狙っているワールドのテクスチャ。",

	-- en: Friendly name of the aimed entity.
	[ "token.ent_name" ] = "狙っているエンティティのわかりやすい名前。",

	-- en: Class of the aimed entity.
	[ "token.ent_class" ] = "狙っているエンティティのクラス。",

	-- en: Model file name of the aimed entity.
	[ "token.ent_model" ] = "狙っているエンティティのモデルファイル名。",

	-- en: Full model path of the aimed entity.
	[ "token.ent_model_path" ] = "狙っているエンティティのモデルのフルパス。",

	-- en: Entity index.
	[ "token.ent_index" ] = "エンティティ番号。",

	-- en: Health of the aimed entity (players, NPCs, breakable props).
	[ "token.ent_health" ] = "狙っているエンティティの体力（プレイヤー、NPC、壊せるプロップ）。",

	-- en: Owner of the aimed entity (in multiplayer this needs a CPPI prop protection addon).
	[ "token.ent_owner" ] = "狙っているエンティティの所有者（マルチプレイでは CPPI 対応のプロップ保護アドオンが必要）。",

	-- en: Material of the aimed entity.
	[ "token.ent_material" ] = "狙っているエンティティのマテリアル。",

	-- en: Colour of the aimed entity.
	[ "token.ent_color" ] = "狙っているエンティティの色。",

	-- en: Skin of the aimed entity.
	[ "token.ent_skin" ] = "狙っているエンティティのスキン。",

	-- en: Speed of the aimed entity.
	[ "token.ent_speed" ] = "狙っているエンティティの速度。",

	-- en: Position of the aimed entity.
	[ "token.ent_pos" ] = "狙っているエンティティの位置。",

	-- en: Angles of the aimed entity.
	[ "token.ent_ang" ] = "狙っているエンティティの角度。",

	-- en: Mass of the aimed entity, when your game knows its physics.
	[ "token.ent_mass" ] = "狙っているエンティティの質量（ゲームが物理情報を持っている場合）。",

	-- en: Tracked entity summary: name, distance, speed, health.
	[ "token.track" ] = "追跡中のエンティティの概要：名前、距離、速度、体力。",

	-- en: Name of the tracked entity.
	[ "token.track_name" ] = "追跡中のエンティティの名前。",

	-- en: Class of the tracked entity.
	[ "token.track_class" ] = "追跡中のエンティティのクラス。",

	-- en: Your distance to the tracked entity.
	[ "token.track_dist" ] = "追跡中のエンティティまでの距離。",

	-- en: Speed of the tracked entity.
	[ "token.track_speed" ] = "追跡中のエンティティの速度。",

	-- en: Health of the tracked entity.
	[ "token.track_health" ] = "追跡中のエンティティの体力。",

	-- en: Position of the tracked entity.
	[ "token.track_pos" ] = "追跡中のエンティティの位置。",

	-- en: Your name.
	[ "token.player" ] = "あなたの名前。",

	-- en: Your health.
	[ "token.health" ] = "あなたの体力。",

	-- en: Your armor.
	[ "token.armor" ] = "あなたのアーマー。",

	-- en: Your speed.
	[ "token.speed" ] = "あなたの速度。",

	-- en: Your position.
	[ "token.pos" ] = "あなたの位置。",

	-- en: Your view pitch and yaw.
	[ "token.eye_ang" ] = "視点のピッチとヨー。",

	-- en: Compass heading (north is +Y on the map).
	[ "token.heading" ] = "方位（マップの +Y が北）。",

	-- en: Shows a word while you are noclipping, otherwise empty.
	[ "token.noclip" ] = "ノークリップ中は単語を表示し、それ以外は空。",

	-- en: Frames per second (smoothed).
	[ "token.fps" ] = "1 秒あたりのフレーム数（平滑化）。",

	-- en: Your ping in milliseconds.
	[ "token.ping" ] = "あなたの ping（ミリ秒）。",

	-- en: Your device's battery charge while it runs on battery, or \"Plugged in\".
	[ "token.battery" ] = "バッテリー駆動中はデバイスのバッテリー残量、電源接続中は「AC 電源」。",

	-- en: Current map.
	[ "token.map" ] = "現在のマップ。",

	-- en: Players on the server and its player limit.
	[ "token.players" ] = "サーバーのプレイヤー数と上限。",

	-- en: Server name.
	[ "token.server" ] = "サーバー名。",

	-- en: Active gamemode.
	[ "token.gamemode" ] = "現在のゲームモード。",

	-- en: Server tick rate.
	[ "token.tickrate" ] = "サーバーのティックレート。",

	-- en: Memory used by Lua in your game.
	[ "token.lua_mem" ] = "ゲーム内で Lua が使っているメモリ。",

	-- en: Entities known to your game.
	[ "token.entities" ] = "あなたのゲームが把握しているエンティティの数。",

	-- en: Props you have spawned.
	[ "token.props" ] = "あなたがスポーンしたプロップの数。",

	-- en: Your prop limit.
	[ "token.props_max" ] = "あなたのプロップの上限。",

	-- en: Spawn count and limit of a type, e.g. {count:ragdolls} or {count:thrusters}.
	[ "token.count" ] = "種類ごとのスポーン数と上限。例：{count:ragdolls}、{count:thrusters}。",

	-- en: Value of any console variable, e.g. {cvar:sv_gravity}.
	[ "token.cvar" ] = "任意のコンソール変数の値。例：{cvar:sv_gravity}。",

	-- en: Advanced Toolgun [Hotbar]: its open tab (Tools, Wire or Favorites).
	[ "token.atg_tab" ] = "Advanced Toolgun [Hotbar]：開いているタブ（ツール、Wire、お気に入り）。",

	-- en: Advanced Toolgun [Hotbar]: the section of its list the selection is in.
	[ "token.atg_section" ] = "Advanced Toolgun [Hotbar]：リストで選択中の項目があるセクション。",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel up.
	[ "token.atg_prev" ] = "Advanced Toolgun [Hotbar]：クイック選択でマウスホイールを上に回したときに切り替わるツール。",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel down.
	[ "token.atg_next" ] = "Advanced Toolgun [Hotbar]：クイック選択でマウスホイールを下に回したときに切り替わるツール。",

	-- en: Turns the tool gun's mini screen into a live display. Changes apply instantly; the preview shows what the screen draws right now.
	[ "menu.intro" ] = "ツールガンの小さな画面をライブディスプレイにします。変更はすぐに反映され、プレビューには画面に今描かれている内容が表示されます。",

	-- en: Dynamic screen is off
	[ "menu.preview_off" ] = "ダイナミック画面はオフです",

	-- en: Enable the dynamic screen
	[ "menu.enable" ] = "ダイナミック画面を有効にする",

	-- en: Language
	[ "menu.language" ] = "言語",

	-- first entry of the language list; {name} is the game's language, e.g. "English"
	-- en: Automatic: {name}
	[ "menu.language.auto" ] = "自動：{name}",

	-- en: Inspect: read the screen up close
	[ "menu.inspect.title" ] = "確認：画面を近くで読む",

	-- en: Hold a key while holding the tool gun to raise its screen to your eyes.
	[ "menu.inspect.help" ] = "ツールガンを持っているときにキーを押し続けると、画面を目の前に持ち上げます。",

	-- en: Inspect key
	[ "menu.inspect.key" ] = "確認キー",

	-- en: Screen size while inspecting
	[ "menu.inspect.size" ] = "確認中の画面の大きさ",

	-- en: Or use the console: bind <key> +dts_inspect (hold) or dts_inspect_toggle.
	[ "menu.inspect.console" ] = "コンソールでも設定できます：bind <キー> +dts_inspect（押している間）または dts_inspect_toggle。",

	-- the tool gun model has a paper note glued on, which overlaps the screen's top right corner
	-- en: Screen in front of the paper note
	[ "menu.inspect.on_top" ] = "画面をメモ用紙より手前に表示",

	-- en: While inspecting, the whole screen stays readable. Untick to let the paper note glued to the tool gun cover the top right corner of the screen, as on the model.
	[ "menu.inspect.on_top_help" ] = "確認中は画面全体を読めます。オフにすると、ツールガンに貼られたメモ用紙が、モデルどおり画面の右上の角を隠します。",

	-- en: Layout and look
	[ "menu.look.title" ] = "レイアウトと見た目",

	-- en: Layout
	[ "menu.look.layout" ] = "レイアウト",

	-- en: Theme
	[ "menu.look.theme" ] = "テーマ",

	-- en: Background
	[ "menu.look.background" ] = "背景",

	-- en: Automatic (layout's choice)
	[ "menu.bg.auto" ] = "自動（レイアウトに合わせる）",

	-- the whole original screen picture without its text
	-- en: Original screen
	[ "menu.bg.original" ] = "オリジナルの画面",

	-- only the blurred photo from the original picture, filling the screen
	-- en: Original photo
	[ "menu.bg.art" ] = "オリジナルの写真",

	-- en: Theme gradient
	[ "menu.bg.gradient" ] = "テーマのグラデーション",

	-- en: Live camera: zoom
	[ "menu.bg.camera" ] = "ライブカメラ：ズーム",

	-- en: Live camera: rear view
	[ "menu.bg.rear" ] = "ライブカメラ：後方",

	-- en: Custom image
	[ "menu.bg.image" ] = "カスタム画像",

	-- en: Black
	[ "menu.bg.black" ] = "黒",

	-- en: Custom image
	[ "menu.look.image" ] = "カスタム画像",

	-- en: A material path, or an image in garrysmod/data written as ../data/name.png
	[ "menu.look.image_help" ] = "マテリアルのパス、または garrysmod/data 内の画像を ../data/ファイル名.png の形で指定します",

	-- en: Darken background
	[ "menu.look.dim" ] = "背景を暗くする",

	-- en: Camera field of view
	[ "menu.look.cam_fov" ] = "カメラの視野角",

	-- en: Camera updates per second
	[ "menu.look.cam_fps" ] = "カメラの 1 秒あたりの更新回数",

	-- en: Text font
	[ "menu.look.font" ] = "文字のフォント",

	-- en: Big text font
	[ "menu.look.font_hero" ] = "大きな文字のフォント",

	-- en: Terminal font
	[ "menu.look.font_mono" ] = "ターミナルのフォント",

	-- first entry of the font lists; {font} is the font your language uses
	-- en: Automatic ({font})
	[ "menu.font.auto" ] = "自動（{font}）",

	-- en: Colours
	[ "menu.colors.title" ] = "色",

	-- en: Override single colours of the theme. Click a swatch to change it.
	[ "menu.colors.help" ] = "テーマの色を個別に上書きします。色見本をクリックして変更します。",

	-- written on a colour swatch that still uses the theme's colour
	-- en: theme
	[ "menu.colors.theme_tag" ] = "テーマ",

	-- en: Click to pick a colour
	[ "menu.colors.pick" ] = "クリックして色を選択",

	-- en: Use the theme's colours everywhere
	[ "menu.colors.reset_all" ] = "すべてテーマの色に戻す",

	-- en: Screen colour: {name}
	[ "menu.colors.picker_title" ] = "画面の色：{name}",

	-- en: Use the theme's colour
	[ "menu.colors.use_theme" ] = "テーマの色を使う",

	-- en: Big text
	[ "menu.hero.title" ] = "大きな文字",

	-- en: Behaviour
	[ "menu.hero.mode" ] = "表示方法",

	-- en: Always scroll (original)
	[ "menu.hero.scroll" ] = "常にスクロール（オリジナル）",

	-- en: Scroll only when too long
	[ "menu.hero.auto" ] = "長すぎるときだけスクロール",

	-- en: Shrink to fit
	[ "menu.hero.fit" ] = "縮小して収める",

	-- en: Scroll speed
	[ "menu.hero.speed" ] = "スクロール速度",

	-- en: Upper case tool names
	[ "menu.hero.upper" ] = "ツール名を大文字にする",

	-- en: Screen content
	[ "menu.content.title" ] = "画面の内容",

	-- keep {tokens}, **stars**, {token|fallback} and {tr:...} as they are: they show the syntax
	-- en: Every line of the {layout} layout is a template. Type text and {tokens}; **stars** highlight text, {token|fallback} gives a default, and a line whose tokens are all empty hides itself. {tr:...} writes a line in your language. See the token reference below.
	[ "menu.content.help" ] = "{layout} レイアウトの各行はテンプレートです。文字と {tokens} を入力できます。**アスタリスク** で囲んだ文字は強調され、{token|fallback} は空のときの代わりの文字を指定し、変数がすべて空の行は自動的に隠れます。{tr:...} はあなたの言語の文を書き出します。変数の一覧は下にあります。",

	-- en: Pick a ready-made line
	[ "menu.content.presets_tip" ] = "用意された行から選ぶ",

	-- en: Back to the default: {value}
	[ "menu.content.reset_tip" ] = "デフォルトに戻す：{value}",

	-- en: (empty)
	[ "menu.content.empty" ] = "（空）",

	-- shown in an empty line's text box
	-- en: (hidden)
	[ "menu.content.placeholder" ] = "（非表示）",

	-- under each line: what it shows right now
	-- en: = {text}
	[ "menu.content.now" ] = "= {text}",

	-- en: (hidden right now)
	[ "menu.content.hidden_now" ] = "（今は非表示）",

	-- en: Reset these lines to the layout's defaults
	[ "menu.content.reset_all" ] = "これらの行をレイアウトのデフォルトに戻す",

	-- ready-made lines in the list next to each line
	-- en: Tool name
	[ "menu.preset.tool" ] = "ツール名",

	-- en: Tool category
	[ "menu.preset.tool_category" ] = "ツールのカテゴリ",

	-- en: Tool instructions
	[ "menu.preset.hints" ] = "ツールの操作説明",

	-- en: Previous tool
	[ "menu.preset.prev_tool" ] = "前のツール",

	-- en: Next tool
	[ "menu.preset.next_tool" ] = "次のツール",

	-- en: Tool progress
	[ "menu.preset.progress" ] = "ツールの進行状況",

	-- en: Tool settings
	[ "menu.preset.tool_settings" ] = "ツールの設定",

	-- en: What you aim at
	[ "menu.preset.target" ] = "狙っているもの",

	-- en: Aim position
	[ "menu.preset.aim_pos" ] = "狙っている位置",

	-- en: Aim distance
	[ "menu.preset.aim_dist" ] = "狙っている位置までの距離",

	-- en: Entity or surface
	[ "menu.preset.aim_what" ] = "エンティティまたは表面",

	-- en: Surface slope
	[ "menu.preset.slope" ] = "表面の傾斜",

	-- en: Entity class
	[ "menu.preset.ent_class" ] = "エンティティのクラス",

	-- en: Entity model
	[ "menu.preset.ent_model" ] = "エンティティのモデル",

	-- en: Entity health
	[ "menu.preset.ent_health" ] = "エンティティの体力",

	-- en: Entity owner
	[ "menu.preset.ent_owner" ] = "エンティティの所有者",

	-- en: Entity speed
	[ "menu.preset.ent_speed" ] = "エンティティの速度",

	-- en: Tracked entity
	[ "menu.preset.track" ] = "追跡中のエンティティ",

	-- en: Clock
	[ "menu.preset.clock" ] = "時計",

	-- en: Clock with seconds
	[ "menu.preset.clock_seconds" ] = "秒付きの時計",

	-- en: Date
	[ "menu.preset.date" ] = "日付",

	-- en: Time in game
	[ "menu.preset.session" ] = "プレイ時間",

	-- en: Your speed
	[ "menu.preset.speed" ] = "あなたの速度",

	-- en: Your position
	[ "menu.preset.pos" ] = "あなたの位置",

	-- en: Compass
	[ "menu.preset.heading" ] = "方位",

	-- en: Health and armor
	[ "menu.preset.health_armor" ] = "体力とアーマー",

	-- en: FPS and ping
	[ "menu.preset.perf" ] = "FPS と ping",

	-- en: Prop count
	[ "menu.preset.props" ] = "プロップの数",

	-- en: Map
	[ "menu.preset.map" ] = "マップ",

	-- en: Players
	[ "menu.preset.players" ] = "プレイヤー",

	-- en: Empty (hide the line)
	[ "menu.preset.empty" ] = "空（行を隠す）",

	-- en: Clock and units
	[ "menu.clock.title" ] = "時計と単位",

	-- en: Clock
	[ "menu.clock.style" ] = "時計",

	-- {language} is the name of the active language
	-- en: As usual in {language}
	[ "menu.clock.auto" ] = "{language} の標準",

	-- en: 12 hour
	[ "menu.clock.12h" ] = "12 時間制",

	-- en: 24 hour
	[ "menu.clock.24h" ] = "24 時間制",

	-- en: Show seconds
	[ "menu.clock.seconds" ] = "秒を表示",

	-- en: Show AM / PM (12 hour clock)
	[ "menu.clock.ampm" ] = "午前/午後を表示（12 時間制）",

	-- en: Blink the colon
	[ "menu.clock.blink" ] = "コロンを点滅させる",

	-- en: Units
	[ "menu.units.label" ] = "単位",

	-- en: Metric (m, km/h)
	[ "menu.units.m" ] = "メートル法（m、km/h）",

	-- en: Imperial (ft, mph)
	[ "menu.units.ft" ] = "ヤード・ポンド法（ft、mph）",

	-- en: Hammer units
	[ "menu.units.hu" ] = "Hammer 単位",

	-- en: Distance decimals
	[ "menu.units.decimals" ] = "距離の小数点以下の桁数",

	-- en: Icons and effects
	[ "menu.fx.title" ] = "アイコンとエフェクト",

	-- en: Speaker icon (volume, voice chat)
	[ "menu.fx.speaker" ] = "スピーカーアイコン（音量、ボイスチャット）",

	-- en: Signal icon (connection)
	[ "menu.fx.signal" ] = "電波アイコン（接続状態）",

	-- en: Battery icon (your device's battery)
	[ "menu.fx.battery" ] = "バッテリーアイコン（デバイスのバッテリー）",

	-- en: Boot animation when taking out the tool gun
	[ "menu.fx.boot" ] = "ツールガンを取り出したときに起動アニメーション",

	-- en: Flash when the tool gun fires
	[ "menu.fx.flash" ] = "ツールガンを撃ったときに画面を光らせる",

	-- en: Show game notifications on the screen
	[ "menu.fx.notify" ] = "ゲームの通知を画面に表示する",

	-- en: Notification time
	[ "menu.fx.notify_time" ] = "通知の表示時間",

	-- en: Scanlines
	[ "menu.fx.scanlines" ] = "走査線",

	-- en: Darker edges
	[ "menu.fx.vignette" ] = "周辺を暗くする",

	-- en: Backlight
	[ "menu.fx.backlight" ] = "バックライト",

	-- en: HUD mirror
	[ "menu.mirror.title" ] = "HUD ミラー",

	-- en: Shows the screen on your HUD while you hold the tool gun, for reading the small print.
	[ "menu.mirror.help" ] = "ツールガンを持っている間、画面を HUD にも表示します。細かい文字を読むのに便利です。",

	-- en: Show the screen on the HUD
	[ "menu.mirror.enable" ] = "画面を HUD に表示する",

	-- en: Corner
	[ "menu.mirror.corner" ] = "位置",

	-- en: Top right
	[ "menu.corner.tr" ] = "右上",

	-- en: Bottom right
	[ "menu.corner.br" ] = "右下",

	-- en: Bottom left
	[ "menu.corner.bl" ] = "左下",

	-- en: Top left
	[ "menu.corner.tl" ] = "左上",

	-- en: Size
	[ "menu.mirror.size" ] = "サイズ",

	-- en: Opacity
	[ "menu.mirror.alpha" ] = "不透明度",

	-- en: Advanced
	[ "menu.adv.title" ] = "詳細設定",

	-- en: Keep the own screens of tools that draw one
	[ "menu.adv.respect" ] = "独自の画面を持つツールはその画面を使う",

	-- en: e.g. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod tools
	[ "menu.adv.respect_help" ] = "例：Easy Entity Inspector、Ragdoll Puppeteer、Wiremod のツール",

	-- en: Live value updates per second
	[ "menu.adv.refresh" ] = "ライブ値の 1 秒あたりの更新回数",

	-- en: Screen redraws per second (0 = every frame)
	[ "menu.adv.fps" ] = "画面の 1 秒あたりの再描画回数（0 = 毎フレーム）",

	-- en: Resolution
	[ "menu.adv.resolution" ] = "解像度",

	-- en: 256 x 256 (original)
	[ "menu.res.256" ] = "256 x 256（オリジナル）",

	-- en: 512 x 512 (sharper, for 1440p and up)
	[ "menu.res.512" ] = "512 x 512（より鮮明、1440p 以上向け）",

	-- keep the commands as they are
	-- en: Key binds (bind <key> <command>):\n  dts_tool_back  -  previous tool\n  dts_tool_next / dts_tool_prev  -  cycle the category\n  dts_layout_next, dts_theme_next  -  cycle layouts, themes\n  dts_track / dts_untrack  -  follow an entity
	[ "menu.adv.binds" ] = "キー割り当て（bind <キー> <コマンド>）：\n  dts_tool_back  -  前のツール\n  dts_tool_next / dts_tool_prev  -  カテゴリ内で切り替え\n  dts_layout_next, dts_theme_next  -  レイアウト、テーマを切り替え\n  dts_track / dts_untrack  -  エンティティを追跡",

	-- en: Copy my settings to the clipboard
	[ "menu.adv.copy" ] = "自分の設定をクリップボードにコピー",

	-- en: Screen settings copied to the clipboard
	[ "menu.adv.copied" ] = "画面の設定をクリップボードにコピーしました",

	-- en: Import settings...
	[ "menu.adv.import" ] = "設定をインポート...",

	-- en: Import screen settings
	[ "menu.adv.import_title" ] = "画面の設定をインポート",

	-- en: Paste a DTS1:... settings string
	[ "menu.adv.import_prompt" ] = "DTS1:... の設定文字列を貼り付けてください",

	-- en: Import
	[ "menu.adv.import_ok" ] = "インポート",

	-- en: Imported screen settings ({n} changed)
	[ "menu.adv.imported" ] = "画面の設定をインポートしました（{n} 件変更）",

	-- en: Reset everything to defaults
	[ "menu.adv.reset" ] = "すべてデフォルトに戻す",

	-- en: Reset
	[ "menu.adv.reset_title" ] = "リセット",

	-- en: Reset every Dynamic Toolgun Screen setting?
	[ "menu.adv.reset_question" ] = "ダイナミック・ツールガン画面の設定をすべてリセットしますか？",

	-- en: Reset
	[ "menu.adv.reset_yes" ] = "リセット",

	-- en: Cancel
	[ "menu.adv.cancel" ] = "キャンセル",

	-- en: Another addon replaced the tool gun screen ({file}). Use the button below to take over.
	[ "menu.adv.diag_conflict" ] = "別のアドオンがツールガンの画面を置き換えています（{file}）。下のボタンで引き継げます。",

	-- en: v{version} installed. Each redraw takes {ms} ms.
	[ "menu.adv.diag_ok" ] = "v{version} 導入済み。1 回の再描画に {ms} ms かかっています。",

	-- en: Last error: {error}
	[ "menu.adv.diag_error" ] = "最後のエラー：{error}",

	-- en: Waiting for the tool gun to load...
	[ "menu.adv.diag_wait" ] = "ツールガンの読み込みを待っています...",

	-- en: Take over the tool gun screen
	[ "menu.adv.takeover" ] = "ツールガンの画面を引き継ぐ",

	-- en: Only needed if another addon replaced the tool gun's screen after this one
	[ "menu.adv.takeover_tip" ] = "このアドオンの後で別のアドオンがツールガンの画面を置き換えた場合にだけ必要です",

	-- en: Dynamic Toolgun Screen installed
	[ "menu.adv.takeover_done" ] = "ツールガンの画面を引き継ぎました",

	-- answers to "Import settings..." when the pasted text is wrong
	-- en: This is not a Dynamic Toolgun Screen settings string.
	[ "import.not_ours" ] = "これはダイナミック・ツールガン画面の設定文字列ではありません。",

	-- en: The settings string is damaged.
	[ "import.damaged" ] = "設定文字列が壊れています。",

	-- en: Token reference
	[ "menu.tokens.title" ] = "変数一覧",

	-- en: Hover a token for what it does, double-click to copy it.
	[ "menu.tokens.help" ] = "変数にカーソルを合わせると説明が表示され、ダブルクリックでコピーできます。",

	-- en: Token
	[ "menu.tokens.col_token" ] = "変数",

	-- en: Right now
	[ "menu.tokens.col_now" ] = "現在の値",

	-- en: Copied {token}
	[ "menu.tokens.copied" ] = "{token} をコピーしました",

}
