--[[
	Dynamic Toolgun Screen - 한국어 (ko)

	Made from lang/en.lua with tools/i18n.py (see TRANSLATING.md). Above each phrase, "-- en:" holds the
	English it translates; "tools/i18n.py check" lists phrases whose English changed since. A phrase
	missing here falls back to English.
]]

return {

	-- name of the language in that language, shown in the language list
	-- en: English
	[ "_name" ] = "한국어",

	-- decimal separator for numbers on the screen
	-- en: .
	[ "_decimal" ] = ".",

	-- 1 if a 24 hour clock is usual in this language, 0 for 12 hour
	-- en: 0
	[ "_clock24" ] = "0",

	-- fonts that have every letter of the language; size factor and weight snapping (1/0) for them
	-- en: Tahoma
	[ "_font.ui" ] = "Malgun Gothic",

	-- en: Helvetica
	[ "_font.hero" ] = "Malgun Gothic",

	-- en: Consolas
	[ "_font.mono" ] = "Malgun Gothic",

	-- en: 1
	[ "_font.scale" ] = "1.05",

	-- en: 0
	[ "_font.snap" ] = "1",

	-- Shown by the game: the tool list, the tool's help on the HUD, the context menu, the Utilities tab --
	-- en: Dynamic Toolgun Screen
	[ "tool.name" ] = "다이나믹 툴 건 화면",

	-- en: Customize the tool gun's live screen and track entities on it
	[ "tool.desc" ] = "툴 건의 실시간 화면을 꾸미고 엔티티를 추적합니다",

	-- en: Track the entity you are aiming at
	[ "tool.left" ] = "조준한 엔티티 추적",

	-- en: Switch to the next screen layout
	[ "tool.right" ] = "다음 화면 레이아웃으로 전환",

	-- en: Stop tracking
	[ "tool.reload" ] = "추적 중지",

	-- context menu entry (right click an entity while holding C)
	-- en: Track on tool gun screen
	[ "prop.track" ] = "툴 건 화면에서 추적",

	-- Utilities tab: category and its only entry
	-- en: Dynamic Toolgun Screen
	[ "menu.category" ] = "다이나믹 툴 건 화면",

	-- en: Settings
	[ "menu.settings_item" ] = "설정",

	-- status line; {name} is an entity name such as "oildrum001" or a player's name
	-- en: Aiming at **{name}**
	[ "target.entity" ] = "조준: **{name}**",

	-- en: Aiming at the **sky**
	[ "target.sky" ] = "조준: **하늘**",

	-- en: World
	[ "target.world" ] = "월드",

	-- {surface} is a material from the mat.* phrases below
	-- en: World - **{surface}**
	[ "target.world_surface" ] = "월드 - **{surface}**",

	-- en: Nothing in range
	[ "target.nothing" ] = "범위 안에 대상 없음",

	-- what you aim at, when it is the sky
	-- en: sky
	[ "aim.sky" ] = "하늘",

	-- multi-click tools (weld, rope...): which click comes next
	-- en: Stage {n}
	[ "tool.progress" ] = "{n}단계",

	-- health of the tracked entity, e.g. "HP 40/100"
	-- en: HP {hp}
	[ "track.hp" ] = "체력 {hp}",

	-- en: Noclip
	[ "noclip" ] = "노클립",

	-- view angles: P = pitch, Y = yaw
	-- en: P {p}  Y {y}
	[ "eye_ang" ] = "피치 {p}  요 {y}",

	-- compass heading, e.g. "NE 45°"
	-- en: {dir} {deg}°
	[ "heading" ] = "{dir} {deg}°",

	-- en: N
	[ "compass.n" ] = "북",

	-- en: NE
	[ "compass.ne" ] = "북동",

	-- en: E
	[ "compass.e" ] = "동",

	-- en: SE
	[ "compass.se" ] = "남동",

	-- en: S
	[ "compass.s" ] = "남",

	-- en: SW
	[ "compass.sw" ] = "남서",

	-- en: W
	[ "compass.w" ] = "서",

	-- en: NW
	[ "compass.nw" ] = "북서",

	-- label of the FPS graph in the Terminal layout
	-- en: {n} fps
	[ "term.fps" ] = "{n} FPS",

	-- shown on the screen when it fails to draw
	-- en: Screen error
	[ "error.title" ] = "화면 오류",

	-- en: See the console for details. Change the layout or run dts_reset to recover.
	[ "error.hint" ] = "자세한 내용은 콘솔을 확인하세요. 레이아웃을 바꾸거나 dts_reset을 실행하면 복구됩니다.",

	-- tabs of the Advanced Toolgun [Hotbar] addon's tool list, for the {atg_tab} token
	-- en: Tools
	[ "atg.tab.tools" ] = "도구",

	-- en: Wire
	[ "atg.tab.wire" ] = "Wire",

	-- en: Favorites
	[ "atg.tab.favorites" ] = "즐겨찾기",

	-- the device's battery, next to the battery icon and in {battery}: {n} is the charge in percent;
	-- "Plugged in" is shown while the device runs on mains power instead of its battery
	-- en: {n}%
	[ "battery.percent" ] = "{n}%",

	-- en: Plugged in
	[ "battery.plugged" ] = "전원 연결됨",

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
	[ "duration.hm" ] = "{h}시간 {m}분",

	-- en: {m}m {s}s
	[ "duration.ms" ] = "{m}분 {s}초",

	-- en: {s}s
	[ "duration.s" ] = "{s}초",

	-- 12 hour clock: AM/PM and where they go around the time
	-- en: AM
	[ "clock.am" ] = "오전",

	-- en: PM
	[ "clock.pm" ] = "오후",

	-- en: {time} {ampm}
	[ "clock.ampm" ] = "{ampm} {time}",

	-- Date: {wday} day of week (short), {day} day number, {month} month (short), {year}
	-- en: {wday} {day} {month}
	[ "date.format" ] = "{month} {day}일 ({wday})",

	-- en: Sun
	[ "date.wday.1" ] = "일",

	-- en: Mon
	[ "date.wday.2" ] = "월",

	-- en: Tue
	[ "date.wday.3" ] = "화",

	-- en: Wed
	[ "date.wday.4" ] = "수",

	-- en: Thu
	[ "date.wday.5" ] = "목",

	-- en: Fri
	[ "date.wday.6" ] = "금",

	-- en: Sat
	[ "date.wday.7" ] = "토",

	-- en: Sunday
	[ "date.wday_full.1" ] = "일요일",

	-- en: Monday
	[ "date.wday_full.2" ] = "월요일",

	-- en: Tuesday
	[ "date.wday_full.3" ] = "화요일",

	-- en: Wednesday
	[ "date.wday_full.4" ] = "수요일",

	-- en: Thursday
	[ "date.wday_full.5" ] = "목요일",

	-- en: Friday
	[ "date.wday_full.6" ] = "금요일",

	-- en: Saturday
	[ "date.wday_full.7" ] = "토요일",

	-- short month names, used in dates ({month} above and %b): use the form your dates need
	-- en: Jan
	[ "date.month.1" ] = "1월",

	-- en: Feb
	[ "date.month.2" ] = "2월",

	-- en: Mar
	[ "date.month.3" ] = "3월",

	-- en: Apr
	[ "date.month.4" ] = "4월",

	-- en: May
	[ "date.month.5" ] = "5월",

	-- en: Jun
	[ "date.month.6" ] = "6월",

	-- en: Jul
	[ "date.month.7" ] = "7월",

	-- en: Aug
	[ "date.month.8" ] = "8월",

	-- en: Sep
	[ "date.month.9" ] = "9월",

	-- en: Oct
	[ "date.month.10" ] = "10월",

	-- en: Nov
	[ "date.month.11" ] = "11월",

	-- en: Dec
	[ "date.month.12" ] = "12월",

	-- full month names (%B), usually written right after a day number
	-- en: January
	[ "date.month_full.1" ] = "1월",

	-- en: February
	[ "date.month_full.2" ] = "2월",

	-- en: March
	[ "date.month_full.3" ] = "3월",

	-- en: April
	[ "date.month_full.4" ] = "4월",

	-- en: May
	[ "date.month_full.5" ] = "5월",

	-- en: June
	[ "date.month_full.6" ] = "6월",

	-- en: July
	[ "date.month_full.7" ] = "7월",

	-- en: August
	[ "date.month_full.8" ] = "8월",

	-- en: September
	[ "date.month_full.9" ] = "9월",

	-- en: October
	[ "date.month_full.10" ] = "10월",

	-- en: November
	[ "date.month_full.11" ] = "11월",

	-- en: December
	[ "date.month_full.12" ] = "12월",

	-- Kinds of surface material (the game's material types), shown as "World - Concrete"
	-- en: Antlion
	[ "mat.antlion" ] = "앤트라이온",

	-- en: Bloody flesh
	[ "mat.bloodyflesh" ] = "피 묻은 살",

	-- en: Concrete
	[ "mat.concrete" ] = "콘크리트",

	-- en: Dirt
	[ "mat.dirt" ] = "흙",

	-- en: Eggshell
	[ "mat.eggshell" ] = "알껍데기",

	-- en: Flesh
	[ "mat.flesh" ] = "살",

	-- en: Grate
	[ "mat.grate" ] = "격자",

	-- en: Alien flesh
	[ "mat.alienflesh" ] = "외계 생물의 살",

	-- en: Clip
	[ "mat.clip" ] = "투명 벽",

	-- en: Snow
	[ "mat.snow" ] = "눈",

	-- en: Plastic
	[ "mat.plastic" ] = "플라스틱",

	-- en: Metal
	[ "mat.metal" ] = "금속",

	-- en: Sand
	[ "mat.sand" ] = "모래",

	-- en: Foliage
	[ "mat.foliage" ] = "식물",

	-- en: Computer
	[ "mat.computer" ] = "전자 기기",

	-- en: Liquid
	[ "mat.slosh" ] = "액체",

	-- en: Tile
	[ "mat.tile" ] = "타일",

	-- en: Grass
	[ "mat.grass" ] = "잔디",

	-- en: Vent
	[ "mat.vent" ] = "환풍구",

	-- en: Wood
	[ "mat.wood" ] = "나무",

	-- en: Generic
	[ "mat.default" ] = "일반",

	-- en: Glass
	[ "mat.glass" ] = "유리",

	-- en: Warp shield
	[ "mat.warpshield" ] = "워프 실드",

	-- Notifications on the screen
	-- en: Tracking {name}
	[ "notify.tracking" ] = "추적 중: {name}",

	-- en: Stopped tracking
	[ "notify.untracked" ] = "추적을 멈췄습니다",

	-- en: Layout: {name}
	[ "notify.layout" ] = "레이아웃: {name}",

	-- en: Theme: {name}
	[ "notify.theme" ] = "테마: {name}",

	-- title bar: tool category, or the game's name when there is none (keep "Garry's Mod")
	-- en: {tool_category|Garry's Mod}
	[ "tpl.title" ] = "{tool_category|Garry's Mod}",

	-- left link of the Pocket PC screen: the previous tool
	-- en: Back to {tool_prev}
	[ "tpl.nav_back" ] = "이전: {tool_prev}",

	-- en: Props {props}/{props_max}
	[ "tpl.props" ] = "프롭 {props}/{props_max}",

	-- en: {fps} fps  {ping} ms
	[ "tpl.perf" ] = "{fps} FPS  {ping} ms",

	-- en: Slope {aim_slope}
	[ "tpl.slope" ] = "경사 {aim_slope}",

	-- en: HP {ent_health}
	[ "tpl.hp" ] = "체력 {ent_health}",

	-- en: Owner: {ent_owner}
	[ "tpl.owner" ] = "소유자: {ent_owner}",

	-- HP = health, AP = armor
	-- en: HP {health}  AP {armor}
	[ "tpl.health_armor" ] = "체력 {health}  방어구 {armor}",

	-- en: {players} players
	[ "tpl.players" ] = "플레이어 {players}",

	-- Terminal lines: a short upper case label, a tab, then the value
	-- en: TOOL\t**{tool}**
	[ "tpl.term_tool" ] = "도구\t**{tool}**",

	-- en: AIM\t**{aim_what}**
	[ "tpl.term_aim" ] = "대상\t**{aim_what}**",

	-- en: CLASS\t**{ent_class|-}**
	[ "tpl.term_class" ] = "클래스\t**{ent_class|-}**",

	-- en: POS\t**{aim_pos}**
	[ "tpl.term_pos" ] = "위치\t**{aim_pos}**",

	-- en: DIST\t**{aim_dist}**  {aim_slope}
	[ "tpl.term_dist" ] = "거리\t**{aim_dist}**  {aim_slope}",

	-- en: OWNER\t**{ent_owner|-}**
	[ "tpl.term_owner" ] = "소유자\t**{ent_owner|-}**",

	-- en: HP\t**{ent_health|-}**
	[ "tpl.term_hp" ] = "체력\t**{ent_health|-}**",

	-- en: TRACK\t**{track_name|-}** {track_dist}
	[ "tpl.term_track" ] = "추적\t**{track_name|-}** {track_dist}",

	-- en: Pocket PC
	[ "layout.pocketpc.name" ] = "Pocket PC",

	-- en: The original screen rebuilt with live data: clock, status icons, tool history links, big tool name, status line, six readouts and a hint bar.
	[ "layout.pocketpc.desc" ] = "원래 화면을 실시간 데이터로 재현합니다: 시계, 상태 아이콘, 도구 기록 링크, 큰 도구 이름, 상태 줄, 6개의 판독값, 힌트 바.",

	-- en: Title bar
	[ "layout.pocketpc.title" ] = "제목 표시줄",

	-- en: Clock
	[ "layout.pocketpc.clock" ] = "시계",

	-- en: Left link
	[ "layout.pocketpc.nav_l" ] = "왼쪽 링크",

	-- en: Right link
	[ "layout.pocketpc.nav_r" ] = "오른쪽 링크",

	-- en: Big text
	[ "layout.pocketpc.hero" ] = "큰 글자",

	-- en: Under the big text
	[ "layout.pocketpc.sub" ] = "큰 글자 아래",

	-- en: Status line
	[ "layout.pocketpc.status" ] = "상태 줄",

	-- en: Readout, left 1
	[ "layout.pocketpc.l1" ] = "판독값, 왼쪽 1",

	-- en: Readout, left 2
	[ "layout.pocketpc.l2" ] = "판독값, 왼쪽 2",

	-- en: Readout, left 3
	[ "layout.pocketpc.l3" ] = "판독값, 왼쪽 3",

	-- en: Readout, right 1
	[ "layout.pocketpc.r1" ] = "판독값, 오른쪽 1",

	-- en: Readout, right 2
	[ "layout.pocketpc.r2" ] = "판독값, 오른쪽 2",

	-- en: Readout, right 3
	[ "layout.pocketpc.r3" ] = "판독값, 오른쪽 3",

	-- en: Menu bar
	[ "layout.pocketpc.menu" ] = "메뉴 바",

	-- en: Terminal
	[ "layout.terminal.name" ] = "터미널",

	-- en: Developer readout: eight lines of labels and values, an FPS graph and a prompt line with the tool hints.
	[ "layout.terminal.desc" ] = "개발자용 판독 화면: 라벨과 값 8줄, FPS 그래프, 도구 힌트를 보여 주는 프롬프트 줄.",

	-- en: Header
	[ "layout.terminal.head" ] = "헤더",

	-- en: Header, right
	[ "layout.terminal.clock" ] = "헤더 오른쪽",

	-- en: Line 1
	[ "layout.terminal.l1" ] = "1번째 줄",

	-- en: Line 2
	[ "layout.terminal.l2" ] = "2번째 줄",

	-- en: Line 3
	[ "layout.terminal.l3" ] = "3번째 줄",

	-- en: Line 4
	[ "layout.terminal.l4" ] = "4번째 줄",

	-- en: Line 5
	[ "layout.terminal.l5" ] = "5번째 줄",

	-- en: Line 6
	[ "layout.terminal.l6" ] = "6번째 줄",

	-- en: Line 7
	[ "layout.terminal.l7" ] = "7번째 줄",

	-- en: Line 8
	[ "layout.terminal.l8" ] = "8번째 줄",

	-- en: Prompt line
	[ "layout.terminal.foot" ] = "프롬프트 줄",

	-- en: Minimal
	[ "layout.minimal.name" ] = "미니멀",

	-- en: Large, glanceable text: clock, compass, the tool name sized to fit, what you aim at and two corner values.
	[ "layout.minimal.desc" ] = "한눈에 읽히는 큰 글자: 시계, 나침반, 크기가 맞춰지는 도구 이름, 조준한 대상, 두 모서리의 값.",

	-- en: Top left
	[ "layout.minimal.top_l" ] = "왼쪽 위",

	-- en: Top right
	[ "layout.minimal.top_r" ] = "오른쪽 위",

	-- en: Big text
	[ "layout.minimal.hero" ] = "큰 글자",

	-- en: Under the big text
	[ "layout.minimal.sub" ] = "큰 글자 아래",

	-- en: Bottom left
	[ "layout.minimal.foot_l" ] = "왼쪽 아래",

	-- en: Bottom right
	[ "layout.minimal.foot_r" ] = "오른쪽 아래",

	-- en: Pocket PC (original)
	[ "theme.winmobile" ] = "Pocket PC (원본)",

	-- en: Graphite
	[ "theme.graphite" ] = "그래파이트",

	-- en: Green phosphor
	[ "theme.phosphor" ] = "녹색 형광",

	-- en: Amber CRT
	[ "theme.amber" ] = "앰버 CRT",

	-- en: Sakura
	[ "theme.sakura" ] = "벚꽃",

	-- en: Sandbox blue
	[ "theme.sandbox" ] = "샌드박스 블루",

	-- parts of the screen whose colour can be changed
	-- en: Title bar
	[ "color.bar" ] = "제목 표시줄",

	-- en: Links and highlights
	[ "color.accent" ] = "링크와 강조",

	-- en: Big text
	[ "color.hero" ] = "큰 글자",

	-- en: Status line
	[ "color.strip" ] = "상태 줄",

	-- en: Readout panel
	[ "color.panel" ] = "판독값 패널",

	-- en: Menu bar
	[ "color.menu" ] = "메뉴 바",

	-- en: Terminal text
	[ "color.term" ] = "터미널 글자",

	-- en: Text
	[ "category.text" ] = "텍스트",

	-- en: Time
	[ "category.time" ] = "시간",

	-- en: Tool
	[ "category.tool" ] = "도구",

	-- en: Aim
	[ "category.aim" ] = "조준",

	-- en: Aimed entity
	[ "category.entity" ] = "조준한 엔티티",

	-- en: Tracked entity
	[ "category.tracked" ] = "추적 중인 엔티티",

	-- en: You
	[ "category.player" ] = "나",

	-- en: Game
	[ "category.game" ] = "게임",

	-- the Advanced Toolgun [Hotbar] addon; keep its name as it is
	-- en: Advanced Toolgun
	[ "category.atg" ] = "Advanced Toolgun",

	-- en: A line in your language from the language files, e.g. {tr:nav_back} or {tr:props}.
	[ "token.tr" ] = "언어 파일에 있는 내 언어의 한 줄입니다. 예: {tr:nav_back}, {tr:props}.",

	-- en: Local time, formatted by the clock settings. {time:%H:%M:%S} takes an os.date format.
	[ "token.time" ] = "현지 시각으로, 시계 설정에 따라 표시됩니다. {time:%H:%M:%S}처럼 os.date 형식을 쓸 수 있습니다.",

	-- en: Today's date. {date:%Y-%m-%d} takes an os.date format.
	[ "token.date" ] = "오늘 날짜입니다. {date:%Y-%m-%d}처럼 os.date 형식을 쓸 수 있습니다.",

	-- en: How long you have been in this game.
	[ "token.session" ] = "이 게임에 들어온 지 얼마나 되었는지.",

	-- en: How long the map has been running.
	[ "token.map_time" ] = "맵이 시작된 지 얼마나 되었는지.",

	-- en: Name of the selected tool.
	[ "token.tool" ] = "선택한 도구의 이름.",

	-- en: Internal name of the selected tool.
	[ "token.tool_id" ] = "선택한 도구의 내부 이름.",

	-- en: Description of the selected tool.
	[ "token.tool_desc" ] = "선택한 도구의 설명.",

	-- en: Tool menu category of the selected tool.
	[ "token.tool_category" ] = "선택한 도구의 도구 메뉴 분류.",

	-- en: Stage of the selected tool (0 = nothing selected yet).
	[ "token.tool_stage" ] = "선택한 도구의 단계 (0 = 아직 아무것도 선택하지 않음).",

	-- en: The stage while a multi-click tool is in progress, otherwise empty.
	[ "token.tool_progress" ] = "여러 번 클릭하는 도구를 쓰는 중에는 그 단계, 아니면 비어 있음.",

	-- en: The tool you used before this one (dts_tool_back switches to it).
	[ "token.tool_prev" ] = "이 도구 전에 쓰던 도구 (dts_tool_back으로 전환).",

	-- en: The next tool in the same menu category (dts_tool_next switches to it).
	[ "token.tool_next" ] = "같은 메뉴 분류의 다음 도구 (dts_tool_next로 전환).",

	-- en: Successful tool gun shots this session.
	[ "token.tool_uses" ] = "이번 게임에서 툴 건을 성공적으로 쏜 횟수.",

	-- en: A setting of the selected tool, e.g. {tool_cvar:forcelimit} reads weld_forcelimit.
	[ "token.tool_cvar" ] = "선택한 도구의 설정입니다. 예: {tool_cvar:forcelimit}는 weld_forcelimit을 읽습니다.",

	-- en: All settings of the selected tool as name=value pairs.
	[ "token.tool_settings" ] = "선택한 도구의 모든 설정 (이름=값 형식).",

	-- en: The current stage's instructions with mouse and key icons.
	[ "token.hints" ] = "현재 단계의 사용법 (마우스와 키 아이콘 포함).",

	-- en: What left click does right now.
	[ "token.hint_left" ] = "지금 왼쪽 클릭으로 하는 일.",

	-- en: What right click does right now.
	[ "token.hint_right" ] = "지금 오른쪽 클릭으로 하는 일.",

	-- en: What reload does right now.
	[ "token.hint_reload" ] = "지금 재장전 키로 하는 일.",

	-- en: What you are aiming at, with the name highlighted.
	[ "token.target" ] = "조준하고 있는 대상 (이름은 강조 표시).",

	-- en: Entity name, or the surface material when aiming at the world.
	[ "token.aim_what" ] = "엔티티 이름, 월드를 조준할 때는 표면 재질.",

	-- en: Position you are aiming at.
	[ "token.aim_pos" ] = "조준하고 있는 위치.",

	-- en: X of the aim position.
	[ "token.aim_x" ] = "조준 위치의 X.",

	-- en: Y of the aim position.
	[ "token.aim_y" ] = "조준 위치의 Y.",

	-- en: Z of the aim position.
	[ "token.aim_z" ] = "조준 위치의 Z.",

	-- en: Distance to the aim position.
	[ "token.aim_dist" ] = "조준 위치까지의 거리.",

	-- en: Surface normal at the aim position.
	[ "token.aim_normal" ] = "조준 위치의 표면 법선.",

	-- en: Steepness of the surface (0 = flat floor, 90 = wall).
	[ "token.aim_slope" ] = "표면의 경사 (0 = 평평한 바닥, 90 = 벽).",

	-- en: Kind of surface material (metal, wood, concrete...).
	[ "token.aim_surface" ] = "표면 재질의 종류 (금속, 나무, 콘크리트 등).",

	-- en: Surface property as the engine names it (metal box, wood crate...).
	[ "token.aim_surfaceprop" ] = "엔진에서 쓰는 표면 속성 이름 (metal box, wood crate 등).",

	-- en: World texture you are aiming at.
	[ "token.aim_texture" ] = "조준하고 있는 월드 텍스처.",

	-- en: Friendly name of the aimed entity.
	[ "token.ent_name" ] = "조준한 엔티티의 알기 쉬운 이름.",

	-- en: Class of the aimed entity.
	[ "token.ent_class" ] = "조준한 엔티티의 클래스.",

	-- en: Model file name of the aimed entity.
	[ "token.ent_model" ] = "조준한 엔티티의 모델 파일 이름.",

	-- en: Full model path of the aimed entity.
	[ "token.ent_model_path" ] = "조준한 엔티티의 전체 모델 경로.",

	-- en: Entity index.
	[ "token.ent_index" ] = "엔티티 번호.",

	-- en: Health of the aimed entity (players, NPCs, breakable props).
	[ "token.ent_health" ] = "조준한 엔티티의 체력 (플레이어, NPC, 부서지는 프롭).",

	-- en: Owner of the aimed entity (in multiplayer this needs a CPPI prop protection addon).
	[ "token.ent_owner" ] = "조준한 엔티티의 소유자 (멀티플레이에서는 CPPI를 지원하는 프롭 보호 애드온이 필요합니다).",

	-- en: Material of the aimed entity.
	[ "token.ent_material" ] = "조준한 엔티티의 머티리얼.",

	-- en: Colour of the aimed entity.
	[ "token.ent_color" ] = "조준한 엔티티의 색상.",

	-- en: Skin of the aimed entity.
	[ "token.ent_skin" ] = "조준한 엔티티의 스킨.",

	-- en: Speed of the aimed entity.
	[ "token.ent_speed" ] = "조준한 엔티티의 속도.",

	-- en: Position of the aimed entity.
	[ "token.ent_pos" ] = "조준한 엔티티의 위치.",

	-- en: Angles of the aimed entity.
	[ "token.ent_ang" ] = "조준한 엔티티의 각도.",

	-- en: Mass of the aimed entity, when your game knows its physics.
	[ "token.ent_mass" ] = "조준한 엔티티의 질량 (게임이 물리 정보를 알 때).",

	-- en: Tracked entity summary: name, distance, speed, health.
	[ "token.track" ] = "추적 중인 엔티티 요약: 이름, 거리, 속도, 체력.",

	-- en: Name of the tracked entity.
	[ "token.track_name" ] = "추적 중인 엔티티의 이름.",

	-- en: Class of the tracked entity.
	[ "token.track_class" ] = "추적 중인 엔티티의 클래스.",

	-- en: Your distance to the tracked entity.
	[ "token.track_dist" ] = "추적 중인 엔티티까지의 거리.",

	-- en: Speed of the tracked entity.
	[ "token.track_speed" ] = "추적 중인 엔티티의 속도.",

	-- en: Health of the tracked entity.
	[ "token.track_health" ] = "추적 중인 엔티티의 체력.",

	-- en: Position of the tracked entity.
	[ "token.track_pos" ] = "추적 중인 엔티티의 위치.",

	-- en: Your name.
	[ "token.player" ] = "내 이름.",

	-- en: Your health.
	[ "token.health" ] = "내 체력.",

	-- en: Your armor.
	[ "token.armor" ] = "내 방어구.",

	-- en: Your speed.
	[ "token.speed" ] = "내 속도.",

	-- en: Your position.
	[ "token.pos" ] = "내 위치.",

	-- en: Your view pitch and yaw.
	[ "token.eye_ang" ] = "시점의 피치와 요.",

	-- en: Compass heading (north is +Y on the map).
	[ "token.heading" ] = "나침반 방향 (맵의 +Y가 북쪽).",

	-- en: Shows a word while you are noclipping, otherwise empty.
	[ "token.noclip" ] = "노클립 중에는 단어를 표시하고, 아니면 비어 있음.",

	-- en: Frames per second (smoothed).
	[ "token.fps" ] = "초당 프레임 수 (평활화).",

	-- en: Your ping in milliseconds.
	[ "token.ping" ] = "내 핑 (밀리초).",

	-- en: Your device's battery charge while it runs on battery, or \"Plugged in\".
	[ "token.battery" ] = "배터리로 작동할 때는 기기의 배터리 잔량, 전원에 연결되어 있으면 '전원 연결됨'.",

	-- en: Current map.
	[ "token.map" ] = "현재 맵.",

	-- en: Players on the server and its player limit.
	[ "token.players" ] = "서버의 플레이어 수와 최대 인원.",

	-- en: Server name.
	[ "token.server" ] = "서버 이름.",

	-- en: Active gamemode.
	[ "token.gamemode" ] = "현재 게임 모드.",

	-- en: Server tick rate.
	[ "token.tickrate" ] = "서버 틱레이트.",

	-- en: Memory used by Lua in your game.
	[ "token.lua_mem" ] = "게임에서 Lua가 사용하는 메모리.",

	-- en: Entities known to your game.
	[ "token.entities" ] = "내 게임이 알고 있는 엔티티 수.",

	-- en: Props you have spawned.
	[ "token.props" ] = "내가 생성한 프롭 수.",

	-- en: Your prop limit.
	[ "token.props_max" ] = "내 프롭 한도.",

	-- en: Spawn count and limit of a type, e.g. {count:ragdolls} or {count:thrusters}.
	[ "token.count" ] = "종류별 생성 수와 한도입니다. 예: {count:ragdolls}, {count:thrusters}.",

	-- en: Value of any console variable, e.g. {cvar:sv_gravity}.
	[ "token.cvar" ] = "아무 콘솔 변수의 값입니다. 예: {cvar:sv_gravity}.",

	-- en: Advanced Toolgun [Hotbar]: its open tab (Tools, Wire or Favorites).
	[ "token.atg_tab" ] = "Advanced Toolgun [Hotbar]: 열려 있는 탭 (도구, Wire, 즐겨찾기).",

	-- en: Advanced Toolgun [Hotbar]: the section of its list the selection is in.
	[ "token.atg_section" ] = "Advanced Toolgun [Hotbar]: 목록에서 선택 항목이 있는 구역.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel up.
	[ "token.atg_prev" ] = "Advanced Toolgun [Hotbar]: 빠른 선택에서 마우스 휠을 위로 돌리면 바뀌는 도구.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel down.
	[ "token.atg_next" ] = "Advanced Toolgun [Hotbar]: 빠른 선택에서 마우스 휠을 아래로 돌리면 바뀌는 도구.",

	-- en: Turns the tool gun's mini screen into a live display. Changes apply instantly; the preview shows what the screen draws right now.
	[ "menu.intro" ] = "툴 건의 작은 화면을 실시간 디스플레이로 바꿉니다. 변경 사항은 바로 적용되며, 미리 보기에는 지금 화면에 그려지는 내용이 표시됩니다.",

	-- en: Dynamic screen is off
	[ "menu.preview_off" ] = "다이나믹 화면이 꺼져 있습니다",

	-- en: Enable the dynamic screen
	[ "menu.enable" ] = "다이나믹 화면 사용",

	-- en: Language
	[ "menu.language" ] = "언어",

	-- first entry of the language list; {name} is the game's language, e.g. "English"
	-- en: Automatic: {name}
	[ "menu.language.auto" ] = "자동: {name}",

	-- en: Inspect: read the screen up close
	[ "menu.inspect.title" ] = "살펴보기: 화면을 가까이에서 읽기",

	-- en: Hold a key while holding the tool gun to raise its screen to your eyes.
	[ "menu.inspect.help" ] = "툴 건을 든 상태에서 키를 누르고 있으면 화면이 눈앞으로 올라옵니다.",

	-- en: Inspect key
	[ "menu.inspect.key" ] = "살펴보기 키",

	-- en: Screen size while inspecting
	[ "menu.inspect.size" ] = "살펴볼 때 화면 크기",

	-- en: Or use the console: bind <key> +dts_inspect (hold) or dts_inspect_toggle.
	[ "menu.inspect.console" ] = "콘솔에서도 할 수 있습니다: bind <키> +dts_inspect (누르고 있기) 또는 dts_inspect_toggle.",

	-- the tool gun model has a paper note glued on, which overlaps the screen's top right corner
	-- en: Screen in front of the paper note
	[ "menu.inspect.on_top" ] = "화면을 메모지 앞에 표시",

	-- en: While inspecting, the whole screen stays readable. Untick to let the paper note glued to the tool gun cover the top right corner of the screen, as on the model.
	[ "menu.inspect.on_top_help" ] = "살펴볼 때 화면 전체를 읽을 수 있습니다. 끄면 툴 건에 붙은 메모지가 모델 그대로 화면의 오른쪽 위 모서리를 가립니다.",

	-- en: Layout and look
	[ "menu.look.title" ] = "레이아웃과 모양",

	-- en: Layout
	[ "menu.look.layout" ] = "레이아웃",

	-- en: Theme
	[ "menu.look.theme" ] = "테마",

	-- en: Background
	[ "menu.look.background" ] = "배경",

	-- en: Automatic (layout's choice)
	[ "menu.bg.auto" ] = "자동 (레이아웃에 따름)",

	-- the whole original screen picture without its text
	-- en: Original screen
	[ "menu.bg.original" ] = "원본 화면",

	-- only the blurred photo from the original picture, filling the screen
	-- en: Original photo
	[ "menu.bg.art" ] = "원본 사진",

	-- en: Theme gradient
	[ "menu.bg.gradient" ] = "테마 그라데이션",

	-- en: Live camera: zoom
	[ "menu.bg.camera" ] = "실시간 카메라: 확대",

	-- en: Live camera: rear view
	[ "menu.bg.rear" ] = "실시간 카메라: 후방",

	-- en: Custom image
	[ "menu.bg.image" ] = "사용자 이미지",

	-- en: Black
	[ "menu.bg.black" ] = "검은색",

	-- en: Custom image
	[ "menu.look.image" ] = "사용자 이미지",

	-- en: A material path, or an image in garrysmod/data written as ../data/name.png
	[ "menu.look.image_help" ] = "머티리얼 경로, 또는 garrysmod/data에 있는 이미지를 ../data/파일이름.png 형식으로 적으세요",

	-- en: Darken background
	[ "menu.look.dim" ] = "배경 어둡게",

	-- en: Camera field of view
	[ "menu.look.cam_fov" ] = "카메라 시야각",

	-- en: Camera updates per second
	[ "menu.look.cam_fps" ] = "카메라 초당 갱신 횟수",

	-- en: Text font
	[ "menu.look.font" ] = "글꼴",

	-- en: Big text font
	[ "menu.look.font_hero" ] = "큰 글자 글꼴",

	-- en: Terminal font
	[ "menu.look.font_mono" ] = "터미널 글꼴",

	-- first entry of the font lists; {font} is the font your language uses
	-- en: Automatic ({font})
	[ "menu.font.auto" ] = "자동 ({font})",

	-- en: Colours
	[ "menu.colors.title" ] = "색상",

	-- en: Override single colours of the theme. Click a swatch to change it.
	[ "menu.colors.help" ] = "테마의 색을 하나씩 덮어씁니다. 색 견본을 클릭해 바꾸세요.",

	-- written on a colour swatch that still uses the theme's colour
	-- en: theme
	[ "menu.colors.theme_tag" ] = "테마",

	-- en: Click to pick a colour
	[ "menu.colors.pick" ] = "클릭해서 색 선택",

	-- en: Use the theme's colours everywhere
	[ "menu.colors.reset_all" ] = "모두 테마 색상 사용",

	-- en: Screen colour: {name}
	[ "menu.colors.picker_title" ] = "화면 색상: {name}",

	-- en: Use the theme's colour
	[ "menu.colors.use_theme" ] = "테마 색상 사용",

	-- en: Big text
	[ "menu.hero.title" ] = "큰 글자",

	-- en: Behaviour
	[ "menu.hero.mode" ] = "표시 방식",

	-- en: Always scroll (original)
	[ "menu.hero.scroll" ] = "항상 스크롤 (원본)",

	-- en: Scroll only when too long
	[ "menu.hero.auto" ] = "너무 길 때만 스크롤",

	-- en: Shrink to fit
	[ "menu.hero.fit" ] = "줄여서 맞추기",

	-- en: Scroll speed
	[ "menu.hero.speed" ] = "스크롤 속도",

	-- en: Upper case tool names
	[ "menu.hero.upper" ] = "도구 이름을 대문자로",

	-- en: Screen content
	[ "menu.content.title" ] = "화면 내용",

	-- keep {tokens}, **stars**, {token|fallback} and {tr:...} as they are: they show the syntax
	-- en: Every line of the {layout} layout is a template. Type text and {tokens}; **stars** highlight text, {token|fallback} gives a default, and a line whose tokens are all empty hides itself. {tr:...} writes a line in your language. See the token reference below.
	[ "menu.content.help" ] = "{layout} 레이아웃의 각 줄은 템플릿입니다. 글자와 {tokens}를 입력하세요. **별표**로 감싼 글자는 강조되고, {token|fallback}은 값이 비었을 때 대신 쓸 글자를 정하며, 변수가 모두 빈 줄은 자동으로 숨겨집니다. {tr:...}는 내 언어로 된 줄을 씁니다. 변수 목록은 아래에 있습니다.",

	-- en: Pick a ready-made line
	[ "menu.content.presets_tip" ] = "미리 만든 줄 고르기",

	-- en: Back to the default: {value}
	[ "menu.content.reset_tip" ] = "기본값으로: {value}",

	-- en: (empty)
	[ "menu.content.empty" ] = "(비어 있음)",

	-- shown in an empty line's text box
	-- en: (hidden)
	[ "menu.content.placeholder" ] = "(숨김)",

	-- under each line: what it shows right now
	-- en: = {text}
	[ "menu.content.now" ] = "= {text}",

	-- en: (hidden right now)
	[ "menu.content.hidden_now" ] = "(지금은 숨김)",

	-- en: Reset these lines to the layout's defaults
	[ "menu.content.reset_all" ] = "이 줄들을 레이아웃 기본값으로 되돌리기",

	-- ready-made lines in the list next to each line
	-- en: Tool name
	[ "menu.preset.tool" ] = "도구 이름",

	-- en: Tool category
	[ "menu.preset.tool_category" ] = "도구 분류",

	-- en: Tool instructions
	[ "menu.preset.hints" ] = "도구 사용법",

	-- en: Previous tool
	[ "menu.preset.prev_tool" ] = "이전 도구",

	-- en: Next tool
	[ "menu.preset.next_tool" ] = "다음 도구",

	-- en: Tool progress
	[ "menu.preset.progress" ] = "도구 진행 단계",

	-- en: Tool settings
	[ "menu.preset.tool_settings" ] = "도구 설정",

	-- en: What you aim at
	[ "menu.preset.target" ] = "조준한 대상",

	-- en: Aim position
	[ "menu.preset.aim_pos" ] = "조준 위치",

	-- en: Aim distance
	[ "menu.preset.aim_dist" ] = "조준 거리",

	-- en: Entity or surface
	[ "menu.preset.aim_what" ] = "엔티티 또는 표면",

	-- en: Surface slope
	[ "menu.preset.slope" ] = "표면 경사",

	-- en: Entity class
	[ "menu.preset.ent_class" ] = "엔티티 클래스",

	-- en: Entity model
	[ "menu.preset.ent_model" ] = "엔티티 모델",

	-- en: Entity health
	[ "menu.preset.ent_health" ] = "엔티티 체력",

	-- en: Entity owner
	[ "menu.preset.ent_owner" ] = "엔티티 소유자",

	-- en: Entity speed
	[ "menu.preset.ent_speed" ] = "엔티티 속도",

	-- en: Tracked entity
	[ "menu.preset.track" ] = "추적 중인 엔티티",

	-- en: Clock
	[ "menu.preset.clock" ] = "시계",

	-- en: Clock with seconds
	[ "menu.preset.clock_seconds" ] = "초까지 표시하는 시계",

	-- en: Date
	[ "menu.preset.date" ] = "날짜",

	-- en: Time in game
	[ "menu.preset.session" ] = "게임 시간",

	-- en: Your speed
	[ "menu.preset.speed" ] = "내 속도",

	-- en: Your position
	[ "menu.preset.pos" ] = "내 위치",

	-- en: Compass
	[ "menu.preset.heading" ] = "나침반",

	-- en: Health and armor
	[ "menu.preset.health_armor" ] = "체력과 방어구",

	-- en: FPS and ping
	[ "menu.preset.perf" ] = "FPS와 핑",

	-- en: Prop count
	[ "menu.preset.props" ] = "프롭 수",

	-- en: Map
	[ "menu.preset.map" ] = "맵",

	-- en: Players
	[ "menu.preset.players" ] = "플레이어",

	-- en: Empty (hide the line)
	[ "menu.preset.empty" ] = "비우기 (줄 숨기기)",

	-- en: Clock and units
	[ "menu.clock.title" ] = "시계와 단위",

	-- en: Clock
	[ "menu.clock.style" ] = "시계",

	-- {language} is the name of the active language
	-- en: As usual in {language}
	[ "menu.clock.auto" ] = "{language} 기본 방식",

	-- en: 12 hour
	[ "menu.clock.12h" ] = "12시간제",

	-- en: 24 hour
	[ "menu.clock.24h" ] = "24시간제",

	-- en: Show seconds
	[ "menu.clock.seconds" ] = "초 표시",

	-- en: Show AM / PM (12 hour clock)
	[ "menu.clock.ampm" ] = "오전/오후 표시 (12시간제)",

	-- en: Blink the colon
	[ "menu.clock.blink" ] = "콜론 깜박이기",

	-- en: Units
	[ "menu.units.label" ] = "단위",

	-- en: Metric (m, km/h)
	[ "menu.units.m" ] = "미터법 (m, km/h)",

	-- en: Imperial (ft, mph)
	[ "menu.units.ft" ] = "야드파운드법 (ft, mph)",

	-- en: Hammer units
	[ "menu.units.hu" ] = "Hammer 단위",

	-- en: Distance decimals
	[ "menu.units.decimals" ] = "거리 소수점 자릿수",

	-- en: Icons and effects
	[ "menu.fx.title" ] = "아이콘과 효과",

	-- en: Speaker icon (volume, voice chat)
	[ "menu.fx.speaker" ] = "스피커 아이콘 (음량, 음성 채팅)",

	-- en: Signal icon (connection)
	[ "menu.fx.signal" ] = "신호 아이콘 (연결 상태)",

	-- en: Battery icon (your device's battery)
	[ "menu.fx.battery" ] = "배터리 아이콘 (기기 배터리)",

	-- en: Boot animation when taking out the tool gun
	[ "menu.fx.boot" ] = "툴 건을 꺼낼 때 부팅 애니메이션",

	-- en: Flash when the tool gun fires
	[ "menu.fx.flash" ] = "툴 건을 쏠 때 화면 깜박이기",

	-- en: Show game notifications on the screen
	[ "menu.fx.notify" ] = "게임 알림을 화면에 표시",

	-- en: Notification time
	[ "menu.fx.notify_time" ] = "알림 표시 시간",

	-- en: Scanlines
	[ "menu.fx.scanlines" ] = "주사선",

	-- en: Darker edges
	[ "menu.fx.vignette" ] = "가장자리 어둡게",

	-- en: Backlight
	[ "menu.fx.backlight" ] = "백라이트",

	-- en: HUD mirror
	[ "menu.mirror.title" ] = "HUD 미러",

	-- en: Shows the screen on your HUD while you hold the tool gun, for reading the small print.
	[ "menu.mirror.help" ] = "툴 건을 들고 있는 동안 화면을 HUD에도 보여 줍니다. 작은 글자를 읽을 때 좋습니다.",

	-- en: Show the screen on the HUD
	[ "menu.mirror.enable" ] = "HUD에 화면 표시",

	-- en: Corner
	[ "menu.mirror.corner" ] = "위치",

	-- en: Top right
	[ "menu.corner.tr" ] = "오른쪽 위",

	-- en: Bottom right
	[ "menu.corner.br" ] = "오른쪽 아래",

	-- en: Bottom left
	[ "menu.corner.bl" ] = "왼쪽 아래",

	-- en: Top left
	[ "menu.corner.tl" ] = "왼쪽 위",

	-- en: Size
	[ "menu.mirror.size" ] = "크기",

	-- en: Opacity
	[ "menu.mirror.alpha" ] = "불투명도",

	-- en: Advanced
	[ "menu.adv.title" ] = "고급",

	-- en: Keep the own screens of tools that draw one
	[ "menu.adv.respect" ] = "자체 화면이 있는 도구는 그 화면 유지",

	-- en: e.g. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod tools
	[ "menu.adv.respect_help" ] = "예: Easy Entity Inspector, Ragdoll Puppeteer, Wiremod 도구",

	-- en: Live value updates per second
	[ "menu.adv.refresh" ] = "실시간 값의 초당 갱신 횟수",

	-- en: Screen redraws per second (0 = every frame)
	[ "menu.adv.fps" ] = "화면의 초당 다시 그리기 횟수 (0 = 매 프레임)",

	-- en: Resolution
	[ "menu.adv.resolution" ] = "해상도",

	-- en: 256 x 256 (original)
	[ "menu.res.256" ] = "256 x 256 (원본)",

	-- en: 512 x 512 (sharper, for 1440p and up)
	[ "menu.res.512" ] = "512 x 512 (더 선명함, 1440p 이상에 적합)",

	-- keep the commands as they are
	-- en: Key binds (bind <key> <command>):\n  dts_tool_back  -  previous tool\n  dts_tool_next / dts_tool_prev  -  cycle the category\n  dts_layout_next, dts_theme_next  -  cycle layouts, themes\n  dts_track / dts_untrack  -  follow an entity
	[ "menu.adv.binds" ] = "키 설정 (bind <키> <명령어>):\n  dts_tool_back  -  이전 도구\n  dts_tool_next / dts_tool_prev  -  분류 안에서 전환\n  dts_layout_next, dts_theme_next  -  레이아웃, 테마 전환\n  dts_track / dts_untrack  -  엔티티 추적",

	-- en: Copy my settings to the clipboard
	[ "menu.adv.copy" ] = "내 설정을 클립보드에 복사",

	-- en: Screen settings copied to the clipboard
	[ "menu.adv.copied" ] = "화면 설정을 클립보드에 복사했습니다",

	-- en: Import settings...
	[ "menu.adv.import" ] = "설정 가져오기...",

	-- en: Import screen settings
	[ "menu.adv.import_title" ] = "화면 설정 가져오기",

	-- en: Paste a DTS1:... settings string
	[ "menu.adv.import_prompt" ] = "DTS1:... 설정 문자열을 붙여 넣으세요",

	-- en: Import
	[ "menu.adv.import_ok" ] = "가져오기",

	-- en: Imported screen settings ({n} changed)
	[ "menu.adv.imported" ] = "화면 설정을 가져왔습니다 ({n}개 변경)",

	-- en: Reset everything to defaults
	[ "menu.adv.reset" ] = "모두 기본값으로 초기화",

	-- en: Reset
	[ "menu.adv.reset_title" ] = "초기화",

	-- en: Reset every Dynamic Toolgun Screen setting?
	[ "menu.adv.reset_question" ] = "다이나믹 툴 건 화면의 모든 설정을 초기화할까요?",

	-- en: Reset
	[ "menu.adv.reset_yes" ] = "초기화",

	-- en: Cancel
	[ "menu.adv.cancel" ] = "취소",

	-- en: Another addon replaced the tool gun screen ({file}). Use the button below to take over.
	[ "menu.adv.diag_conflict" ] = "다른 애드온이 툴 건 화면을 바꿔 놓았습니다 ({file}). 아래 버튼으로 다시 가져오세요.",

	-- en: v{version} installed. Each redraw takes {ms} ms.
	[ "menu.adv.diag_ok" ] = "v{version} 설치됨. 다시 그릴 때마다 {ms} ms가 걸립니다.",

	-- en: Last error: {error}
	[ "menu.adv.diag_error" ] = "마지막 오류: {error}",

	-- en: Waiting for the tool gun to load...
	[ "menu.adv.diag_wait" ] = "툴 건을 불러오는 중...",

	-- en: Take over the tool gun screen
	[ "menu.adv.takeover" ] = "툴 건 화면 다시 가져오기",

	-- en: Only needed if another addon replaced the tool gun's screen after this one
	[ "menu.adv.takeover_tip" ] = "이 애드온 다음에 다른 애드온이 툴 건 화면을 바꿨을 때만 필요합니다",

	-- en: Dynamic Toolgun Screen installed
	[ "menu.adv.takeover_done" ] = "툴 건 화면을 다시 가져왔습니다",

	-- answers to "Import settings..." when the pasted text is wrong
	-- en: This is not a Dynamic Toolgun Screen settings string.
	[ "import.not_ours" ] = "다이나믹 툴 건 화면의 설정 문자열이 아닙니다.",

	-- en: The settings string is damaged.
	[ "import.damaged" ] = "설정 문자열이 손상되었습니다.",

	-- en: Token reference
	[ "menu.tokens.title" ] = "변수 목록",

	-- en: Hover a token for what it does, double-click to copy it.
	[ "menu.tokens.help" ] = "변수에 마우스를 올리면 설명이 나오고, 두 번 클릭하면 복사됩니다.",

	-- en: Token
	[ "menu.tokens.col_token" ] = "변수",

	-- en: Right now
	[ "menu.tokens.col_now" ] = "현재 값",

	-- en: Copied {token}
	[ "menu.tokens.copied" ] = "{token} 복사됨",

}
