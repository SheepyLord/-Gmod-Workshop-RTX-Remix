--[[
	Dynamic Toolgun Screen - Türkçe (tr)

	Made from lang/en.lua with tools/i18n.py (see TRANSLATING.md). Above each phrase, "-- en:" holds the
	English it translates; "tools/i18n.py check" lists phrases whose English changed since. A phrase
	missing here falls back to English.
]]

return {

	-- name of the language in that language, shown in the language list
	-- en: English
	[ "_name" ] = "Türkçe",

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
	[ "tool.name" ] = "Dinamik Alet Silahı Ekranı",

	-- en: Customize the tool gun's live screen and track entities on it
	[ "tool.desc" ] = "Alet Silahı'nın canlı ekranını özelleştir ve üzerinde varlıkları takip et",

	-- en: Track the entity you are aiming at
	[ "tool.left" ] = "Nişan aldığın varlığı takip et",

	-- en: Switch to the next screen layout
	[ "tool.right" ] = "Sonraki ekran düzenine geç",

	-- en: Stop tracking
	[ "tool.reload" ] = "Takibi bırak",

	-- context menu entry (right click an entity while holding C)
	-- en: Track on tool gun screen
	[ "prop.track" ] = "Alet Silahı ekranında takip et",

	-- Utilities tab: category and its only entry
	-- en: Dynamic Toolgun Screen
	[ "menu.category" ] = "Dinamik Alet Silahı Ekranı",

	-- en: Settings
	[ "menu.settings_item" ] = "Ayarlar",

	-- status line; {name} is an entity name such as "oildrum001" or a player's name
	-- en: Aiming at **{name}**
	[ "target.entity" ] = "Hedef: **{name}**",

	-- en: Aiming at the **sky**
	[ "target.sky" ] = "Hedef: **gökyüzü**",

	-- en: World
	[ "target.world" ] = "Dünya",

	-- {surface} is a material from the mat.* phrases below
	-- en: World - **{surface}**
	[ "target.world_surface" ] = "Dünya - **{surface}**",

	-- en: Nothing in range
	[ "target.nothing" ] = "Menzilde bir şey yok",

	-- what you aim at, when it is the sky
	-- en: sky
	[ "aim.sky" ] = "gökyüzü",

	-- multi-click tools (weld, rope...): which click comes next
	-- en: Stage {n}
	[ "tool.progress" ] = "Aşama {n}",

	-- health of the tracked entity, e.g. "HP 40/100"
	-- en: HP {hp}
	[ "track.hp" ] = "Can {hp}",

	-- en: Noclip
	[ "noclip" ] = "Noclip",

	-- view angles: P = pitch, Y = yaw
	-- en: P {p}  Y {y}
	[ "eye_ang" ] = "Yunuslama {p}  Sapma {y}",

	-- compass heading, e.g. "NE 45°"
	-- en: {dir} {deg}°
	[ "heading" ] = "{dir} {deg}°",

	-- en: N
	[ "compass.n" ] = "K",

	-- en: NE
	[ "compass.ne" ] = "KD",

	-- en: E
	[ "compass.e" ] = "D",

	-- en: SE
	[ "compass.se" ] = "GD",

	-- en: S
	[ "compass.s" ] = "G",

	-- en: SW
	[ "compass.sw" ] = "GB",

	-- en: W
	[ "compass.w" ] = "B",

	-- en: NW
	[ "compass.nw" ] = "KB",

	-- label of the FPS graph in the Terminal layout
	-- en: {n} fps
	[ "term.fps" ] = "{n} FPS",

	-- shown on the screen when it fails to draw
	-- en: Screen error
	[ "error.title" ] = "Ekran hatası",

	-- en: See the console for details. Change the layout or run dts_reset to recover.
	[ "error.hint" ] = "Ayrıntılar konsolda. Düzeni değiştir ya da düzeltmek için dts_reset komutunu çalıştır.",

	-- tabs of the Advanced Toolgun [Hotbar] addon's tool list, for the {atg_tab} token
	-- en: Tools
	[ "atg.tab.tools" ] = "Aletler",

	-- en: Wire
	[ "atg.tab.wire" ] = "Wire",

	-- en: Favorites
	[ "atg.tab.favorites" ] = "Favoriler",

	-- the device's battery, next to the battery icon and in {battery}: {n} is the charge in percent;
	-- "Plugged in" is shown while the device runs on mains power instead of its battery
	-- en: {n}%
	[ "battery.percent" ] = "%{n}",

	-- en: Plugged in
	[ "battery.plugged" ] = "Prize takılı",

	-- Units: {v} is the number, already written with the decimal separator above
	-- en: {v} m
	[ "unit.m" ] = "{v} m",

	-- en: {v} km
	[ "unit.km" ] = "{v} km",

	-- en: {v} ft
	[ "unit.ft" ] = "{v} ft",

	-- en: {v} mi
	[ "unit.mi" ] = "{v} mil",

	-- Hammer units, the game's own distance unit
	-- en: {v} u
	[ "unit.hu" ] = "{v} br",

	-- en: {v} km/h
	[ "unit.kmh" ] = "{v} km/sa",

	-- en: {v} mph
	[ "unit.mph" ] = "{v} mil/sa",

	-- en: {v} u/s
	[ "unit.ups" ] = "{v} br/sn",

	-- en: {v} kg
	[ "unit.kg" ] = "{v} kg",

	-- en: {v} MB
	[ "unit.mb" ] = "{v} MB",

	-- Durations: {h} hours, {m} minutes, {s} seconds (minutes and seconds come with two digits)
	-- en: {h}h {m}m
	[ "duration.hm" ] = "{h} sa {m} dk",

	-- en: {m}m {s}s
	[ "duration.ms" ] = "{m} dk {s} sn",

	-- en: {s}s
	[ "duration.s" ] = "{s} sn",

	-- 12 hour clock: AM/PM and where they go around the time
	-- en: AM
	[ "clock.am" ] = "ÖÖ",

	-- en: PM
	[ "clock.pm" ] = "ÖS",

	-- en: {time} {ampm}
	[ "clock.ampm" ] = "{ampm} {time}",

	-- Date: {wday} day of week (short), {day} day number, {month} month (short), {year}
	-- en: {wday} {day} {month}
	[ "date.format" ] = "{day} {month} {wday}",

	-- en: Sun
	[ "date.wday.1" ] = "Paz",

	-- en: Mon
	[ "date.wday.2" ] = "Pzt",

	-- en: Tue
	[ "date.wday.3" ] = "Sal",

	-- en: Wed
	[ "date.wday.4" ] = "Çar",

	-- en: Thu
	[ "date.wday.5" ] = "Per",

	-- en: Fri
	[ "date.wday.6" ] = "Cum",

	-- en: Sat
	[ "date.wday.7" ] = "Cmt",

	-- en: Sunday
	[ "date.wday_full.1" ] = "Pazar",

	-- en: Monday
	[ "date.wday_full.2" ] = "Pazartesi",

	-- en: Tuesday
	[ "date.wday_full.3" ] = "Salı",

	-- en: Wednesday
	[ "date.wday_full.4" ] = "Çarşamba",

	-- en: Thursday
	[ "date.wday_full.5" ] = "Perşembe",

	-- en: Friday
	[ "date.wday_full.6" ] = "Cuma",

	-- en: Saturday
	[ "date.wday_full.7" ] = "Cumartesi",

	-- short month names, used in dates ({month} above and %b): use the form your dates need
	-- en: Jan
	[ "date.month.1" ] = "Oca",

	-- en: Feb
	[ "date.month.2" ] = "Şub",

	-- en: Mar
	[ "date.month.3" ] = "Mar",

	-- en: Apr
	[ "date.month.4" ] = "Nis",

	-- en: May
	[ "date.month.5" ] = "May",

	-- en: Jun
	[ "date.month.6" ] = "Haz",

	-- en: Jul
	[ "date.month.7" ] = "Tem",

	-- en: Aug
	[ "date.month.8" ] = "Ağu",

	-- en: Sep
	[ "date.month.9" ] = "Eyl",

	-- en: Oct
	[ "date.month.10" ] = "Eki",

	-- en: Nov
	[ "date.month.11" ] = "Kas",

	-- en: Dec
	[ "date.month.12" ] = "Ara",

	-- full month names (%B), usually written right after a day number
	-- en: January
	[ "date.month_full.1" ] = "Ocak",

	-- en: February
	[ "date.month_full.2" ] = "Şubat",

	-- en: March
	[ "date.month_full.3" ] = "Mart",

	-- en: April
	[ "date.month_full.4" ] = "Nisan",

	-- en: May
	[ "date.month_full.5" ] = "Mayıs",

	-- en: June
	[ "date.month_full.6" ] = "Haziran",

	-- en: July
	[ "date.month_full.7" ] = "Temmuz",

	-- en: August
	[ "date.month_full.8" ] = "Ağustos",

	-- en: September
	[ "date.month_full.9" ] = "Eylül",

	-- en: October
	[ "date.month_full.10" ] = "Ekim",

	-- en: November
	[ "date.month_full.11" ] = "Kasım",

	-- en: December
	[ "date.month_full.12" ] = "Aralık",

	-- Kinds of surface material (the game's material types), shown as "World - Concrete"
	-- en: Antlion
	[ "mat.antlion" ] = "Kum Böceği",

	-- en: Bloody flesh
	[ "mat.bloodyflesh" ] = "Kanlı et",

	-- en: Concrete
	[ "mat.concrete" ] = "Beton",

	-- en: Dirt
	[ "mat.dirt" ] = "Toprak",

	-- en: Eggshell
	[ "mat.eggshell" ] = "Yumurta kabuğu",

	-- en: Flesh
	[ "mat.flesh" ] = "Et",

	-- en: Grate
	[ "mat.grate" ] = "Izgara",

	-- en: Alien flesh
	[ "mat.alienflesh" ] = "Uzaylı eti",

	-- en: Clip
	[ "mat.clip" ] = "Görünmez duvar",

	-- en: Snow
	[ "mat.snow" ] = "Kar",

	-- en: Plastic
	[ "mat.plastic" ] = "Plastik",

	-- en: Metal
	[ "mat.metal" ] = "Metal",

	-- en: Sand
	[ "mat.sand" ] = "Kum",

	-- en: Foliage
	[ "mat.foliage" ] = "Yeşillik",

	-- en: Computer
	[ "mat.computer" ] = "Elektronik",

	-- en: Liquid
	[ "mat.slosh" ] = "Sıvı",

	-- en: Tile
	[ "mat.tile" ] = "Fayans",

	-- en: Grass
	[ "mat.grass" ] = "Çimen",

	-- en: Vent
	[ "mat.vent" ] = "Havalandırma",

	-- en: Wood
	[ "mat.wood" ] = "Ahşap",

	-- en: Generic
	[ "mat.default" ] = "Genel",

	-- en: Glass
	[ "mat.glass" ] = "Cam",

	-- en: Warp shield
	[ "mat.warpshield" ] = "Bükülme kalkanı",

	-- Notifications on the screen
	-- en: Tracking {name}
	[ "notify.tracking" ] = "Takip ediliyor: {name}",

	-- en: Stopped tracking
	[ "notify.untracked" ] = "Takip bırakıldı",

	-- en: Layout: {name}
	[ "notify.layout" ] = "Düzen: {name}",

	-- en: Theme: {name}
	[ "notify.theme" ] = "Tema: {name}",

	-- title bar: tool category, or the game's name when there is none (keep "Garry's Mod")
	-- en: {tool_category|Garry's Mod}
	[ "tpl.title" ] = "{tool_category|Garry's Mod}",

	-- left link of the Pocket PC screen: the previous tool
	-- en: Back to {tool_prev}
	[ "tpl.nav_back" ] = "Geri: {tool_prev}",

	-- en: Props {props}/{props_max}
	[ "tpl.props" ] = "Nesne {props}/{props_max}",

	-- en: {fps} fps  {ping} ms
	[ "tpl.perf" ] = "{fps} FPS  {ping} ms",

	-- en: Slope {aim_slope}
	[ "tpl.slope" ] = "Eğim {aim_slope}",

	-- en: HP {ent_health}
	[ "tpl.hp" ] = "Can {ent_health}",

	-- en: Owner: {ent_owner}
	[ "tpl.owner" ] = "Sahibi: {ent_owner}",

	-- HP = health, AP = armor
	-- en: HP {health}  AP {armor}
	[ "tpl.health_armor" ] = "Can {health}  Zırh {armor}",

	-- en: {players} players
	[ "tpl.players" ] = "{players} oyuncu",

	-- Terminal lines: a short upper case label, a tab, then the value
	-- en: TOOL\t**{tool}**
	[ "tpl.term_tool" ] = "ALET\t**{tool}**",

	-- en: AIM\t**{aim_what}**
	[ "tpl.term_aim" ] = "HEDEF\t**{aim_what}**",

	-- en: CLASS\t**{ent_class|-}**
	[ "tpl.term_class" ] = "SINIF\t**{ent_class|-}**",

	-- en: POS\t**{aim_pos}**
	[ "tpl.term_pos" ] = "KONUM\t**{aim_pos}**",

	-- en: DIST\t**{aim_dist}**  {aim_slope}
	[ "tpl.term_dist" ] = "MESAFE\t**{aim_dist}**  {aim_slope}",

	-- en: OWNER\t**{ent_owner|-}**
	[ "tpl.term_owner" ] = "SAHİBİ\t**{ent_owner|-}**",

	-- en: HP\t**{ent_health|-}**
	[ "tpl.term_hp" ] = "CAN\t**{ent_health|-}**",

	-- en: TRACK\t**{track_name|-}** {track_dist}
	[ "tpl.term_track" ] = "TAKİP\t**{track_name|-}** {track_dist}",

	-- en: Pocket PC
	[ "layout.pocketpc.name" ] = "Pocket PC",

	-- en: The original screen rebuilt with live data: clock, status icons, tool history links, big tool name, status line, six readouts and a hint bar.
	[ "layout.pocketpc.desc" ] = "Canlı verilerle yeniden kurulan orijinal ekran: saat, durum simgeleri, alet geçmişi bağlantıları, büyük alet adı, durum satırı, altı gösterge ve bir ipucu çubuğu.",

	-- en: Title bar
	[ "layout.pocketpc.title" ] = "Başlık çubuğu",

	-- en: Clock
	[ "layout.pocketpc.clock" ] = "Saat",

	-- en: Left link
	[ "layout.pocketpc.nav_l" ] = "Sol bağlantı",

	-- en: Right link
	[ "layout.pocketpc.nav_r" ] = "Sağ bağlantı",

	-- en: Big text
	[ "layout.pocketpc.hero" ] = "Büyük metin",

	-- en: Under the big text
	[ "layout.pocketpc.sub" ] = "Büyük metnin altı",

	-- en: Status line
	[ "layout.pocketpc.status" ] = "Durum satırı",

	-- en: Readout, left 1
	[ "layout.pocketpc.l1" ] = "Gösterge, sol 1",

	-- en: Readout, left 2
	[ "layout.pocketpc.l2" ] = "Gösterge, sol 2",

	-- en: Readout, left 3
	[ "layout.pocketpc.l3" ] = "Gösterge, sol 3",

	-- en: Readout, right 1
	[ "layout.pocketpc.r1" ] = "Gösterge, sağ 1",

	-- en: Readout, right 2
	[ "layout.pocketpc.r2" ] = "Gösterge, sağ 2",

	-- en: Readout, right 3
	[ "layout.pocketpc.r3" ] = "Gösterge, sağ 3",

	-- en: Menu bar
	[ "layout.pocketpc.menu" ] = "Menü çubuğu",

	-- en: Terminal
	[ "layout.terminal.name" ] = "Terminal",

	-- en: Developer readout: eight lines of labels and values, an FPS graph and a prompt line with the tool hints.
	[ "layout.terminal.desc" ] = "Geliştirici görünümü: sekiz satır etiket ve değer, bir FPS grafiği ve alet ipuçlarını gösteren bir komut satırı.",

	-- en: Header
	[ "layout.terminal.head" ] = "Başlık",

	-- en: Header, right
	[ "layout.terminal.clock" ] = "Başlık, sağ",

	-- en: Line 1
	[ "layout.terminal.l1" ] = "Satır 1",

	-- en: Line 2
	[ "layout.terminal.l2" ] = "Satır 2",

	-- en: Line 3
	[ "layout.terminal.l3" ] = "Satır 3",

	-- en: Line 4
	[ "layout.terminal.l4" ] = "Satır 4",

	-- en: Line 5
	[ "layout.terminal.l5" ] = "Satır 5",

	-- en: Line 6
	[ "layout.terminal.l6" ] = "Satır 6",

	-- en: Line 7
	[ "layout.terminal.l7" ] = "Satır 7",

	-- en: Line 8
	[ "layout.terminal.l8" ] = "Satır 8",

	-- en: Prompt line
	[ "layout.terminal.foot" ] = "Komut satırı",

	-- en: Minimal
	[ "layout.minimal.name" ] = "Sade",

	-- en: Large, glanceable text: clock, compass, the tool name sized to fit, what you aim at and two corner values.
	[ "layout.minimal.desc" ] = "Bir bakışta okunan büyük metin: saat, pusula, sığacak boyutta alet adı, nişan aldığın şey ve iki köşe değeri.",

	-- en: Top left
	[ "layout.minimal.top_l" ] = "Sol üst",

	-- en: Top right
	[ "layout.minimal.top_r" ] = "Sağ üst",

	-- en: Big text
	[ "layout.minimal.hero" ] = "Büyük metin",

	-- en: Under the big text
	[ "layout.minimal.sub" ] = "Büyük metnin altı",

	-- en: Bottom left
	[ "layout.minimal.foot_l" ] = "Sol alt",

	-- en: Bottom right
	[ "layout.minimal.foot_r" ] = "Sağ alt",

	-- en: Pocket PC (original)
	[ "theme.winmobile" ] = "Pocket PC (orijinal)",

	-- en: Graphite
	[ "theme.graphite" ] = "Grafit",

	-- en: Green phosphor
	[ "theme.phosphor" ] = "Yeşil fosfor",

	-- en: Amber CRT
	[ "theme.amber" ] = "Kehribar CRT",

	-- en: Sakura
	[ "theme.sakura" ] = "Sakura",

	-- en: Sandbox blue
	[ "theme.sandbox" ] = "Sandbox mavisi",

	-- parts of the screen whose colour can be changed
	-- en: Title bar
	[ "color.bar" ] = "Başlık çubuğu",

	-- en: Links and highlights
	[ "color.accent" ] = "Bağlantılar ve vurgular",

	-- en: Big text
	[ "color.hero" ] = "Büyük metin",

	-- en: Status line
	[ "color.strip" ] = "Durum satırı",

	-- en: Readout panel
	[ "color.panel" ] = "Gösterge paneli",

	-- en: Menu bar
	[ "color.menu" ] = "Menü çubuğu",

	-- en: Terminal text
	[ "color.term" ] = "Terminal metni",

	-- en: Text
	[ "category.text" ] = "Metin",

	-- en: Time
	[ "category.time" ] = "Zaman",

	-- en: Tool
	[ "category.tool" ] = "Alet",

	-- en: Aim
	[ "category.aim" ] = "Nişan",

	-- en: Aimed entity
	[ "category.entity" ] = "Nişan alınan varlık",

	-- en: Tracked entity
	[ "category.tracked" ] = "Takip edilen varlık",

	-- en: You
	[ "category.player" ] = "Sen",

	-- en: Game
	[ "category.game" ] = "Oyun",

	-- the Advanced Toolgun [Hotbar] addon; keep its name as it is
	-- en: Advanced Toolgun
	[ "category.atg" ] = "Advanced Toolgun",

	-- en: A line in your language from the language files, e.g. {tr:nav_back} or {tr:props}.
	[ "token.tr" ] = "Dil dosyalarından senin dilinde bir satır, örn. {tr:nav_back} veya {tr:props}.",

	-- en: Local time, formatted by the clock settings. {time:%H:%M:%S} takes an os.date format.
	[ "token.time" ] = "Saat ayarlarına göre biçimlenen yerel saat. {time:%H:%M:%S} bir os.date biçimi alır.",

	-- en: Today's date. {date:%Y-%m-%d} takes an os.date format.
	[ "token.date" ] = "Bugünün tarihi. {date:%Y-%m-%d} bir os.date biçimi alır.",

	-- en: How long you have been in this game.
	[ "token.session" ] = "Bu oyunda ne kadar süredir bulunduğun.",

	-- en: How long the map has been running.
	[ "token.map_time" ] = "Haritanın ne kadar süredir açık olduğu.",

	-- en: Name of the selected tool.
	[ "token.tool" ] = "Seçili aletin adı.",

	-- en: Internal name of the selected tool.
	[ "token.tool_id" ] = "Seçili aletin iç adı.",

	-- en: Description of the selected tool.
	[ "token.tool_desc" ] = "Seçili aletin açıklaması.",

	-- en: Tool menu category of the selected tool.
	[ "token.tool_category" ] = "Seçili aletin alet menüsündeki kategorisi.",

	-- en: Stage of the selected tool (0 = nothing selected yet).
	[ "token.tool_stage" ] = "Seçili aletin aşaması (0 = henüz bir şey seçilmedi).",

	-- en: The stage while a multi-click tool is in progress, otherwise empty.
	[ "token.tool_progress" ] = "Çok tıklamalı bir alet kullanılırken aşama, aksi halde boş.",

	-- en: The tool you used before this one (dts_tool_back switches to it).
	[ "token.tool_prev" ] = "Bundan önce kullandığın alet (dts_tool_back ona geçer).",

	-- en: The next tool in the same menu category (dts_tool_next switches to it).
	[ "token.tool_next" ] = "Aynı menü kategorisindeki sonraki alet (dts_tool_next ona geçer).",

	-- en: Successful tool gun shots this session.
	[ "token.tool_uses" ] = "Bu oturumdaki başarılı Alet Silahı atışları.",

	-- en: A setting of the selected tool, e.g. {tool_cvar:forcelimit} reads weld_forcelimit.
	[ "token.tool_cvar" ] = "Seçili aletin bir ayarı, örn. {tool_cvar:forcelimit} weld_forcelimit değerini okur.",

	-- en: All settings of the selected tool as name=value pairs.
	[ "token.tool_settings" ] = "Seçili aletin tüm ayarları, ad=değer çiftleri olarak.",

	-- en: The current stage's instructions with mouse and key icons.
	[ "token.hints" ] = "Geçerli aşamanın talimatları, fare ve tuş simgeleriyle.",

	-- en: What left click does right now.
	[ "token.hint_left" ] = "Sol tıklamanın şu an ne yaptığı.",

	-- en: What right click does right now.
	[ "token.hint_right" ] = "Sağ tıklamanın şu an ne yaptığı.",

	-- en: What reload does right now.
	[ "token.hint_reload" ] = "Yeniden doldurma tuşunun şu an ne yaptığı.",

	-- en: What you are aiming at, with the name highlighted.
	[ "token.target" ] = "Nişan aldığın şey, adı vurgulanmış olarak.",

	-- en: Entity name, or the surface material when aiming at the world.
	[ "token.aim_what" ] = "Varlığın adı ya da dünyaya nişan alırken yüzey malzemesi.",

	-- en: Position you are aiming at.
	[ "token.aim_pos" ] = "Nişan aldığın konum.",

	-- en: X of the aim position.
	[ "token.aim_x" ] = "Nişan konumunun X değeri.",

	-- en: Y of the aim position.
	[ "token.aim_y" ] = "Nişan konumunun Y değeri.",

	-- en: Z of the aim position.
	[ "token.aim_z" ] = "Nişan konumunun Z değeri.",

	-- en: Distance to the aim position.
	[ "token.aim_dist" ] = "Nişan konumuna olan mesafe.",

	-- en: Surface normal at the aim position.
	[ "token.aim_normal" ] = "Nişan konumundaki yüzey normali.",

	-- en: Steepness of the surface (0 = flat floor, 90 = wall).
	[ "token.aim_slope" ] = "Yüzeyin eğimi (0 = düz zemin, 90 = duvar).",

	-- en: Kind of surface material (metal, wood, concrete...).
	[ "token.aim_surface" ] = "Yüzey malzemesinin türü (metal, ahşap, beton...).",

	-- en: Surface property as the engine names it (metal box, wood crate...).
	[ "token.aim_surfaceprop" ] = "Motorun verdiği adla yüzey özelliği (metal box, wood crate...).",

	-- en: World texture you are aiming at.
	[ "token.aim_texture" ] = "Nişan aldığın dünya dokusu.",

	-- en: Friendly name of the aimed entity.
	[ "token.ent_name" ] = "Nişan alınan varlığın okunabilir adı.",

	-- en: Class of the aimed entity.
	[ "token.ent_class" ] = "Nişan alınan varlığın sınıfı.",

	-- en: Model file name of the aimed entity.
	[ "token.ent_model" ] = "Nişan alınan varlığın model dosyası adı.",

	-- en: Full model path of the aimed entity.
	[ "token.ent_model_path" ] = "Nişan alınan varlığın tam model yolu.",

	-- en: Entity index.
	[ "token.ent_index" ] = "Varlık numarası.",

	-- en: Health of the aimed entity (players, NPCs, breakable props).
	[ "token.ent_health" ] = "Nişan alınan varlığın canı (oyuncular, NPC'ler, kırılabilir nesneler).",

	-- en: Owner of the aimed entity (in multiplayer this needs a CPPI prop protection addon).
	[ "token.ent_owner" ] = "Nişan alınan varlığın sahibi (çok oyunculu modda CPPI destekli bir nesne koruma eklentisi gerekir).",

	-- en: Material of the aimed entity.
	[ "token.ent_material" ] = "Nişan alınan varlığın malzemesi.",

	-- en: Colour of the aimed entity.
	[ "token.ent_color" ] = "Nişan alınan varlığın rengi.",

	-- en: Skin of the aimed entity.
	[ "token.ent_skin" ] = "Nişan alınan varlığın görünümü (skin).",

	-- en: Speed of the aimed entity.
	[ "token.ent_speed" ] = "Nişan alınan varlığın hızı.",

	-- en: Position of the aimed entity.
	[ "token.ent_pos" ] = "Nişan alınan varlığın konumu.",

	-- en: Angles of the aimed entity.
	[ "token.ent_ang" ] = "Nişan alınan varlığın açıları.",

	-- en: Mass of the aimed entity, when your game knows its physics.
	[ "token.ent_mass" ] = "Nişan alınan varlığın kütlesi (oyunun fiziğini bildiği durumlarda).",

	-- en: Tracked entity summary: name, distance, speed, health.
	[ "token.track" ] = "Takip edilen varlığın özeti: ad, mesafe, hız, can.",

	-- en: Name of the tracked entity.
	[ "token.track_name" ] = "Takip edilen varlığın adı.",

	-- en: Class of the tracked entity.
	[ "token.track_class" ] = "Takip edilen varlığın sınıfı.",

	-- en: Your distance to the tracked entity.
	[ "token.track_dist" ] = "Takip edilen varlığa olan mesafen.",

	-- en: Speed of the tracked entity.
	[ "token.track_speed" ] = "Takip edilen varlığın hızı.",

	-- en: Health of the tracked entity.
	[ "token.track_health" ] = "Takip edilen varlığın canı.",

	-- en: Position of the tracked entity.
	[ "token.track_pos" ] = "Takip edilen varlığın konumu.",

	-- en: Your name.
	[ "token.player" ] = "Adın.",

	-- en: Your health.
	[ "token.health" ] = "Canın.",

	-- en: Your armor.
	[ "token.armor" ] = "Zırhın.",

	-- en: Your speed.
	[ "token.speed" ] = "Hızın.",

	-- en: Your position.
	[ "token.pos" ] = "Konumun.",

	-- en: Your view pitch and yaw.
	[ "token.eye_ang" ] = "Bakışının yunuslama ve sapma açıları.",

	-- en: Compass heading (north is +Y on the map).
	[ "token.heading" ] = "Pusula yönü (kuzey haritada +Y'dir).",

	-- en: Shows a word while you are noclipping, otherwise empty.
	[ "token.noclip" ] = "Noclip açıkken bir kelime gösterir, aksi halde boş.",

	-- en: Frames per second (smoothed).
	[ "token.fps" ] = "Saniyedeki kare sayısı (yumuşatılmış).",

	-- en: Your ping in milliseconds.
	[ "token.ping" ] = "Milisaniye cinsinden gecikmen (ping).",

	-- en: Your device's battery charge while it runs on battery, or \"Plugged in\".
	[ "token.battery" ] = "Pille çalışırken cihazının pil seviyesi, aksi halde “Prize takılı”.",

	-- en: Current map.
	[ "token.map" ] = "Geçerli harita.",

	-- en: Players on the server and its player limit.
	[ "token.players" ] = "Sunucudaki oyuncular ve oyuncu sınırı.",

	-- en: Server name.
	[ "token.server" ] = "Sunucu adı.",

	-- en: Active gamemode.
	[ "token.gamemode" ] = "Etkin oyun modu.",

	-- en: Server tick rate.
	[ "token.tickrate" ] = "Sunucunun tick hızı.",

	-- en: Memory used by Lua in your game.
	[ "token.lua_mem" ] = "Oyununda Lua'nın kullandığı bellek.",

	-- en: Entities known to your game.
	[ "token.entities" ] = "Oyununun bildiği varlıklar.",

	-- en: Props you have spawned.
	[ "token.props" ] = "Oluşturduğun nesneler.",

	-- en: Your prop limit.
	[ "token.props_max" ] = "Nesne sınırın.",

	-- en: Spawn count and limit of a type, e.g. {count:ragdolls} or {count:thrusters}.
	[ "token.count" ] = "Bir türün sayısı ve sınırı, örn. {count:ragdolls} veya {count:thrusters}.",

	-- en: Value of any console variable, e.g. {cvar:sv_gravity}.
	[ "token.cvar" ] = "Herhangi bir konsol değişkeninin değeri, örn. {cvar:sv_gravity}.",

	-- en: Advanced Toolgun [Hotbar]: its open tab (Tools, Wire or Favorites).
	[ "token.atg_tab" ] = "Advanced Toolgun [Hotbar]: açık olan sekmesi (Aletler, Wire veya Favoriler).",

	-- en: Advanced Toolgun [Hotbar]: the section of its list the selection is in.
	[ "token.atg_section" ] = "Advanced Toolgun [Hotbar]: listesinde seçimin bulunduğu bölüm.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel up.
	[ "token.atg_prev" ] = "Advanced Toolgun [Hotbar]: hızlı seçiminin fare tekerleği yukarı çevrilince geçtiği alet.",

	-- en: Advanced Toolgun [Hotbar]: the tool its quick select goes to on wheel down.
	[ "token.atg_next" ] = "Advanced Toolgun [Hotbar]: hızlı seçiminin fare tekerleği aşağı çevrilince geçtiği alet.",

	-- en: Turns the tool gun's mini screen into a live display. Changes apply instantly; the preview shows what the screen draws right now.
	[ "menu.intro" ] = "Alet Silahı'nın küçük ekranını canlı bir göstergeye dönüştürür. Değişiklikler anında uygulanır; önizleme, ekranın şu anda ne çizdiğini gösterir.",

	-- en: Dynamic screen is off
	[ "menu.preview_off" ] = "Dinamik ekran kapalı",

	-- en: Enable the dynamic screen
	[ "menu.enable" ] = "Dinamik ekranı etkinleştir",

	-- en: Language
	[ "menu.language" ] = "Dil",

	-- first entry of the language list; {name} is the game's language, e.g. "English"
	-- en: Automatic: {name}
	[ "menu.language.auto" ] = "Otomatik: {name}",

	-- en: Inspect: read the screen up close
	[ "menu.inspect.title" ] = "İncele: ekranı yakından oku",

	-- en: Hold a key while holding the tool gun to raise its screen to your eyes.
	[ "menu.inspect.help" ] = "Alet Silahı elindeyken bir tuşu basılı tutarak ekranını gözlerine yaklaştır.",

	-- en: Inspect key
	[ "menu.inspect.key" ] = "İnceleme tuşu",

	-- en: Screen size while inspecting
	[ "menu.inspect.size" ] = "İnceleme sırasında ekran boyutu",

	-- en: Or use the console: bind <key> +dts_inspect (hold) or dts_inspect_toggle.
	[ "menu.inspect.console" ] = "Ya da konsoldan: bind <tuş> +dts_inspect (basılı tut) veya dts_inspect_toggle.",

	-- the tool gun model has a paper note glued on, which overlaps the screen's top right corner
	-- en: Screen in front of the paper note
	[ "menu.inspect.on_top" ] = "Ekran kâğıt notun önünde",

	-- en: While inspecting, the whole screen stays readable. Untick to let the paper note glued to the tool gun cover the top right corner of the screen, as on the model.
	[ "menu.inspect.on_top_help" ] = "İnceleme sırasında ekranın tamamı okunabilir kalır. Alet Silahı'na yapıştırılmış kâğıt notun, modeldeki gibi ekranın sağ üst köşesini kapatması için işareti kaldır.",

	-- en: Layout and look
	[ "menu.look.title" ] = "Düzen ve görünüm",

	-- en: Layout
	[ "menu.look.layout" ] = "Düzen",

	-- en: Theme
	[ "menu.look.theme" ] = "Tema",

	-- en: Background
	[ "menu.look.background" ] = "Arka plan",

	-- en: Automatic (layout's choice)
	[ "menu.bg.auto" ] = "Otomatik (düzenin seçimi)",

	-- the whole original screen picture without its text
	-- en: Original screen
	[ "menu.bg.original" ] = "Orijinal ekran",

	-- only the blurred photo from the original picture, filling the screen
	-- en: Original photo
	[ "menu.bg.art" ] = "Orijinal fotoğraf",

	-- en: Theme gradient
	[ "menu.bg.gradient" ] = "Tema gradyanı",

	-- en: Live camera: zoom
	[ "menu.bg.camera" ] = "Canlı kamera: yakınlaştırma",

	-- en: Live camera: rear view
	[ "menu.bg.rear" ] = "Canlı kamera: arka görünüm",

	-- en: Custom image
	[ "menu.bg.image" ] = "Özel görsel",

	-- en: Black
	[ "menu.bg.black" ] = "Siyah",

	-- en: Custom image
	[ "menu.look.image" ] = "Özel görsel",

	-- en: A material path, or an image in garrysmod/data written as ../data/name.png
	[ "menu.look.image_help" ] = "Bir malzeme yolu ya da garrysmod/data içindeki bir görsel; ../data/ad.png şeklinde yazılır",

	-- en: Darken background
	[ "menu.look.dim" ] = "Arka planı karart",

	-- en: Camera field of view
	[ "menu.look.cam_fov" ] = "Kamera görüş alanı",

	-- en: Camera updates per second
	[ "menu.look.cam_fps" ] = "Saniyede kamera güncellemesi",

	-- en: Text font
	[ "menu.look.font" ] = "Metin yazı tipi",

	-- en: Big text font
	[ "menu.look.font_hero" ] = "Büyük metin yazı tipi",

	-- en: Terminal font
	[ "menu.look.font_mono" ] = "Terminal yazı tipi",

	-- first entry of the font lists; {font} is the font your language uses
	-- en: Automatic ({font})
	[ "menu.font.auto" ] = "Otomatik ({font})",

	-- en: Colours
	[ "menu.colors.title" ] = "Renkler",

	-- en: Override single colours of the theme. Click a swatch to change it.
	[ "menu.colors.help" ] = "Temanın tek tek renklerini değiştir. Değiştirmek için bir renk örneğine tıkla.",

	-- written on a colour swatch that still uses the theme's colour
	-- en: theme
	[ "menu.colors.theme_tag" ] = "tema",

	-- en: Click to pick a colour
	[ "menu.colors.pick" ] = "Renk seçmek için tıkla",

	-- en: Use the theme's colours everywhere
	[ "menu.colors.reset_all" ] = "Her yerde temanın renklerini kullan",

	-- en: Screen colour: {name}
	[ "menu.colors.picker_title" ] = "Ekran rengi: {name}",

	-- en: Use the theme's colour
	[ "menu.colors.use_theme" ] = "Temanın rengini kullan",

	-- en: Big text
	[ "menu.hero.title" ] = "Büyük metin",

	-- en: Behaviour
	[ "menu.hero.mode" ] = "Davranış",

	-- en: Always scroll (original)
	[ "menu.hero.scroll" ] = "Her zaman kaydır (orijinal)",

	-- en: Scroll only when too long
	[ "menu.hero.auto" ] = "Yalnızca sığmadığında kaydır",

	-- en: Shrink to fit
	[ "menu.hero.fit" ] = "Sığacak şekilde küçült",

	-- en: Scroll speed
	[ "menu.hero.speed" ] = "Kaydırma hızı",

	-- en: Upper case tool names
	[ "menu.hero.upper" ] = "Alet adlarını büyük harfle yaz",

	-- en: Screen content
	[ "menu.content.title" ] = "Ekran içeriği",

	-- keep {tokens}, **stars**, {token|fallback} and {tr:...} as they are: they show the syntax
	-- en: Every line of the {layout} layout is a template. Type text and {tokens}; **stars** highlight text, {token|fallback} gives a default, and a line whose tokens are all empty hides itself. {tr:...} writes a line in your language. See the token reference below.
	[ "menu.content.help" ] = "{layout} düzeninin her satırı bir şablondur. Metin ve {tokens} yaz; **yıldızlar** metni vurgular, {token|fallback} varsayılan bir değer verir ve tüm token'ları boş olan bir satır kendini gizler. {tr:...} senin dilinde bir satır yazar. Token listesi aşağıda.",

	-- en: Pick a ready-made line
	[ "menu.content.presets_tip" ] = "Hazır bir satır seç",

	-- en: Back to the default: {value}
	[ "menu.content.reset_tip" ] = "Varsayılana dön: {value}",

	-- en: (empty)
	[ "menu.content.empty" ] = "(boş)",

	-- shown in an empty line's text box
	-- en: (hidden)
	[ "menu.content.placeholder" ] = "(gizli)",

	-- under each line: what it shows right now
	-- en: = {text}
	[ "menu.content.now" ] = "= {text}",

	-- en: (hidden right now)
	[ "menu.content.hidden_now" ] = "(şu an gizli)",

	-- en: Reset these lines to the layout's defaults
	[ "menu.content.reset_all" ] = "Bu satırları düzenin varsayılanlarına sıfırla",

	-- ready-made lines in the list next to each line
	-- en: Tool name
	[ "menu.preset.tool" ] = "Alet adı",

	-- en: Tool category
	[ "menu.preset.tool_category" ] = "Alet kategorisi",

	-- en: Tool instructions
	[ "menu.preset.hints" ] = "Alet talimatları",

	-- en: Previous tool
	[ "menu.preset.prev_tool" ] = "Önceki alet",

	-- en: Next tool
	[ "menu.preset.next_tool" ] = "Sonraki alet",

	-- en: Tool progress
	[ "menu.preset.progress" ] = "Alet ilerlemesi",

	-- en: Tool settings
	[ "menu.preset.tool_settings" ] = "Alet ayarları",

	-- en: What you aim at
	[ "menu.preset.target" ] = "Nişan aldığın şey",

	-- en: Aim position
	[ "menu.preset.aim_pos" ] = "Nişan konumu",

	-- en: Aim distance
	[ "menu.preset.aim_dist" ] = "Nişan mesafesi",

	-- en: Entity or surface
	[ "menu.preset.aim_what" ] = "Varlık veya yüzey",

	-- en: Surface slope
	[ "menu.preset.slope" ] = "Yüzey eğimi",

	-- en: Entity class
	[ "menu.preset.ent_class" ] = "Varlık sınıfı",

	-- en: Entity model
	[ "menu.preset.ent_model" ] = "Varlık modeli",

	-- en: Entity health
	[ "menu.preset.ent_health" ] = "Varlığın canı",

	-- en: Entity owner
	[ "menu.preset.ent_owner" ] = "Varlığın sahibi",

	-- en: Entity speed
	[ "menu.preset.ent_speed" ] = "Varlığın hızı",

	-- en: Tracked entity
	[ "menu.preset.track" ] = "Takip edilen varlık",

	-- en: Clock
	[ "menu.preset.clock" ] = "Saat",

	-- en: Clock with seconds
	[ "menu.preset.clock_seconds" ] = "Saniyeli saat",

	-- en: Date
	[ "menu.preset.date" ] = "Tarih",

	-- en: Time in game
	[ "menu.preset.session" ] = "Oyundaki süre",

	-- en: Your speed
	[ "menu.preset.speed" ] = "Hızın",

	-- en: Your position
	[ "menu.preset.pos" ] = "Konumun",

	-- en: Compass
	[ "menu.preset.heading" ] = "Pusula",

	-- en: Health and armor
	[ "menu.preset.health_armor" ] = "Can ve zırh",

	-- en: FPS and ping
	[ "menu.preset.perf" ] = "FPS ve ping",

	-- en: Prop count
	[ "menu.preset.props" ] = "Nesne sayısı",

	-- en: Map
	[ "menu.preset.map" ] = "Harita",

	-- en: Players
	[ "menu.preset.players" ] = "Oyuncular",

	-- en: Empty (hide the line)
	[ "menu.preset.empty" ] = "Boş (satırı gizle)",

	-- en: Clock and units
	[ "menu.clock.title" ] = "Saat ve birimler",

	-- en: Clock
	[ "menu.clock.style" ] = "Saat",

	-- {language} is the name of the active language
	-- en: As usual in {language}
	[ "menu.clock.auto" ] = "Dile göre ({language})",

	-- en: 12 hour
	[ "menu.clock.12h" ] = "12 saat",

	-- en: 24 hour
	[ "menu.clock.24h" ] = "24 saat",

	-- en: Show seconds
	[ "menu.clock.seconds" ] = "Saniyeleri göster",

	-- en: Show AM / PM (12 hour clock)
	[ "menu.clock.ampm" ] = "ÖÖ / ÖS göster (12 saatlik düzen)",

	-- en: Blink the colon
	[ "menu.clock.blink" ] = "İki noktayı yanıp söndür",

	-- en: Units
	[ "menu.units.label" ] = "Birimler",

	-- en: Metric (m, km/h)
	[ "menu.units.m" ] = "Metrik (m, km/sa)",

	-- en: Imperial (ft, mph)
	[ "menu.units.ft" ] = "İngiliz (ft, mil/sa)",

	-- en: Hammer units
	[ "menu.units.hu" ] = "Hammer birimleri",

	-- en: Distance decimals
	[ "menu.units.decimals" ] = "Mesafelerde ondalık basamak",

	-- en: Icons and effects
	[ "menu.fx.title" ] = "Simgeler ve efektler",

	-- en: Speaker icon (volume, voice chat)
	[ "menu.fx.speaker" ] = "Hoparlör simgesi (ses düzeyi, sesli sohbet)",

	-- en: Signal icon (connection)
	[ "menu.fx.signal" ] = "Sinyal simgesi (bağlantı)",

	-- en: Battery icon (your device's battery)
	[ "menu.fx.battery" ] = "Pil simgesi (cihazının pili)",

	-- en: Boot animation when taking out the tool gun
	[ "menu.fx.boot" ] = "Alet Silahı'nı çıkarınca açılış animasyonu",

	-- en: Flash when the tool gun fires
	[ "menu.fx.flash" ] = "Alet Silahı ateşlenince ekran parlaması",

	-- en: Show game notifications on the screen
	[ "menu.fx.notify" ] = "Oyun bildirimlerini ekranda göster",

	-- en: Notification time
	[ "menu.fx.notify_time" ] = "Bildirim süresi",

	-- en: Scanlines
	[ "menu.fx.scanlines" ] = "Tarama çizgileri",

	-- en: Darker edges
	[ "menu.fx.vignette" ] = "Daha koyu kenarlar",

	-- en: Backlight
	[ "menu.fx.backlight" ] = "Arka ışık",

	-- en: HUD mirror
	[ "menu.mirror.title" ] = "HUD aynası",

	-- en: Shows the screen on your HUD while you hold the tool gun, for reading the small print.
	[ "menu.mirror.help" ] = "Alet Silahı elindeyken ekranı HUD'da da gösterir; küçük yazıları okumak için.",

	-- en: Show the screen on the HUD
	[ "menu.mirror.enable" ] = "Ekranı HUD'da göster",

	-- en: Corner
	[ "menu.mirror.corner" ] = "Köşe",

	-- en: Top right
	[ "menu.corner.tr" ] = "Sağ üst",

	-- en: Bottom right
	[ "menu.corner.br" ] = "Sağ alt",

	-- en: Bottom left
	[ "menu.corner.bl" ] = "Sol alt",

	-- en: Top left
	[ "menu.corner.tl" ] = "Sol üst",

	-- en: Size
	[ "menu.mirror.size" ] = "Boyut",

	-- en: Opacity
	[ "menu.mirror.alpha" ] = "Opaklık",

	-- en: Advanced
	[ "menu.adv.title" ] = "Gelişmiş",

	-- en: Keep the own screens of tools that draw one
	[ "menu.adv.respect" ] = "Kendi ekranını çizen aletlerin ekranını koru",

	-- en: e.g. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod tools
	[ "menu.adv.respect_help" ] = "örn. Easy Entity Inspector, Ragdoll Puppeteer, Wiremod aletleri",

	-- en: Live value updates per second
	[ "menu.adv.refresh" ] = "Saniyede canlı değer güncellemesi",

	-- en: Screen redraws per second (0 = every frame)
	[ "menu.adv.fps" ] = "Saniyede ekran yeniden çizimi (0 = her kare)",

	-- en: Resolution
	[ "menu.adv.resolution" ] = "Çözünürlük",

	-- en: 256 x 256 (original)
	[ "menu.res.256" ] = "256 x 256 (orijinal)",

	-- en: 512 x 512 (sharper, for 1440p and up)
	[ "menu.res.512" ] = "512 x 512 (daha keskin, 1440p ve üstü için)",

	-- keep the commands as they are
	-- en: Key binds (bind <key> <command>):\n  dts_tool_back  -  previous tool\n  dts_tool_next / dts_tool_prev  -  cycle the category\n  dts_layout_next, dts_theme_next  -  cycle layouts, themes\n  dts_track / dts_untrack  -  follow an entity
	[ "menu.adv.binds" ] = "Tuş atamaları (bind <tuş> <komut>):\n  dts_tool_back  -  önceki alet\n  dts_tool_next / dts_tool_prev  -  kategoride gezin\n  dts_layout_next, dts_theme_next  -  düzenler, temalar arasında geçiş\n  dts_track / dts_untrack  -  bir varlığı takip et",

	-- en: Copy my settings to the clipboard
	[ "menu.adv.copy" ] = "Ayarlarımı panoya kopyala",

	-- en: Screen settings copied to the clipboard
	[ "menu.adv.copied" ] = "Ekran ayarları panoya kopyalandı",

	-- en: Import settings...
	[ "menu.adv.import" ] = "Ayarları içe aktar...",

	-- en: Import screen settings
	[ "menu.adv.import_title" ] = "Ekran ayarlarını içe aktar",

	-- en: Paste a DTS1:... settings string
	[ "menu.adv.import_prompt" ] = "Bir DTS1:... ayar metni yapıştır",

	-- en: Import
	[ "menu.adv.import_ok" ] = "İçe aktar",

	-- en: Imported screen settings ({n} changed)
	[ "menu.adv.imported" ] = "Ekran ayarları içe aktarıldı ({n} değişiklik)",

	-- en: Reset everything to defaults
	[ "menu.adv.reset" ] = "Her şeyi varsayılana sıfırla",

	-- en: Reset
	[ "menu.adv.reset_title" ] = "Sıfırla",

	-- en: Reset every Dynamic Toolgun Screen setting?
	[ "menu.adv.reset_question" ] = "Dinamik Alet Silahı Ekranı'nın tüm ayarları sıfırlansın mı?",

	-- en: Reset
	[ "menu.adv.reset_yes" ] = "Sıfırla",

	-- en: Cancel
	[ "menu.adv.cancel" ] = "İptal Et",

	-- en: Another addon replaced the tool gun screen ({file}). Use the button below to take over.
	[ "menu.adv.diag_conflict" ] = "Başka bir eklenti Alet Silahı ekranını değiştirdi ({file}). Geri almak için aşağıdaki düğmeyi kullan.",

	-- en: v{version} installed. Each redraw takes {ms} ms.
	[ "menu.adv.diag_ok" ] = "v{version} yüklü. Her yeniden çizim {ms} ms sürüyor.",

	-- en: Last error: {error}
	[ "menu.adv.diag_error" ] = "Son hata: {error}",

	-- en: Waiting for the tool gun to load...
	[ "menu.adv.diag_wait" ] = "Alet Silahı'nın yüklenmesi bekleniyor...",

	-- en: Take over the tool gun screen
	[ "menu.adv.takeover" ] = "Alet Silahı ekranını devral",

	-- en: Only needed if another addon replaced the tool gun's screen after this one
	[ "menu.adv.takeover_tip" ] = "Yalnızca başka bir eklenti bu eklentiden sonra Alet Silahı ekranını değiştirdiyse gerekir",

	-- en: Dynamic Toolgun Screen installed
	[ "menu.adv.takeover_done" ] = "Dinamik Alet Silahı Ekranı yüklendi",

	-- answers to "Import settings..." when the pasted text is wrong
	-- en: This is not a Dynamic Toolgun Screen settings string.
	[ "import.not_ours" ] = "Bu bir Dinamik Alet Silahı Ekranı ayar metni değil.",

	-- en: The settings string is damaged.
	[ "import.damaged" ] = "Ayar metni bozuk.",

	-- en: Token reference
	[ "menu.tokens.title" ] = "Token listesi",

	-- en: Hover a token for what it does, double-click to copy it.
	[ "menu.tokens.help" ] = "Ne yaptığını görmek için imleci bir token'ın üzerine getir; kopyalamak için çift tıkla.",

	-- en: Token
	[ "menu.tokens.col_token" ] = "Token",

	-- en: Right now
	[ "menu.tokens.col_now" ] = "Şu an",

	-- en: Copied {token}
	[ "menu.tokens.copied" ] = "{token} kopyalandı",

}
