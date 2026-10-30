-- Client-side menu localization. "auto" follows Garry's Mod/Steam language.

BBS = BBS or {}
BBS.I18N = BBS.I18N or {}

local I = BBS.I18N
local DEFAULT_LANGUAGE = "en"
local SUPPORTED = { en = true, zh = true, ja = true, fr = true, ru = true }

CreateClientConVar( "bbs_language", "auto", true, false,
	"Procedural Bodygroup Destruction menu language; auto follows gmod_language." )

local EN = {
	[ "tab.title" ] = "Procedural Bodygroup Destruction",
	[ "category.damage" ] = "Damage",
	[ "category.developer" ] = "Developer",
	[ "menu.damage_filters" ] = "Damage & Filters",
	[ "menu.damage" ] = "Damage & Appearance",
	[ "menu.filters" ] = "Models & Bodygroups",
	[ "menu.debug" ] = "Debug Tools",
	[ "language.title" ] = "Interface language",
	[ "language.auto" ] = "Automatic (Garry's Mod language)",
	[ "language.en" ] = "English",
	[ "language.zh" ] = "简体中文",
	[ "language.ja" ] = "日本語",
	[ "language.fr" ] = "Français",
	[ "language.ru" ] = "Русский",
	[ "common.add" ] = "Add",
	[ "common.remove_selected" ] = "Remove selected",
	[ "common.reset_defaults" ] = "Reset defaults",
	[ "common.clear" ] = "Clear",
	[ "common.cancel" ] = "Cancel",
	[ "permission.admin" ] = "Admin access is required to change this server setting.",

	[ "filter.model_behavior" ] = "Model list behavior",
	[ "filter.blacklist" ] = "Blacklist — damage every model except listed",
	[ "filter.whitelist" ] = "Whitelist — damage only listed models",
	[ "filter.models_column" ] = "Models in this list",
	[ "filter.model_placeholder" ] = "models/example/model.mdl",
	[ "filter.add_aimed" ] = "Add aimed model",
	[ "filter.clear_models" ] = "Clear model list",
	[ "filter.aim_help" ] = "Aim at an entity to inspect its model decision.",
	[ "filter.whitelist_empty" ] = "The whitelist is empty, so texture damage is currently disabled for every model.",
	[ "filter.whitelist_help" ] = "Only exact model paths below can receive texture damage.",
	[ "filter.blacklist_help" ] = "Exact model paths below are excluded; an empty blacklist allows every model.",
	[ "filter.clear_confirm" ] = "Remove every model path from the active list?",
	[ "filter.bodygroups_column" ] = "Excluded bodygroup names",
	[ "filter.bodygroup_placeholder" ] = "Exact bodygroup name",
	[ "filter.aimed_status" ] = "Aimed: {{model}}\n{{decision}} — {{reason}}",
	[ "filter.allowed" ] = "ALLOWED",
	[ "filter.blocked" ] = "BLOCKED",
	[ "filter.no_model" ] = "<no model>",
	[ "filter.select_model_first" ] = "Select a model first.",
	[ "filter.aim_entity_first" ] = "Aim at an entity first.",
	[ "filter.select_bodygroup_first" ] = "Select a bodygroup name first.",
	[ "filter.override_model_column" ] = "Model",
	[ "filter.override_bodygroup_column" ] = "Forced hideable bodygroup",
	[ "filter.override_id_column" ] = "ID",
	[ "filter.override_aim_help" ] = "Aim at an entity, then choose one of its bodygroups below.",
	[ "filter.override_select_bodygroup" ] = "Select a bodygroup from the aimed model",
	[ "filter.override_add_selected" ] = "Force selected hideable",
	[ "filter.override_aim_missing" ] = "Aim at an entity and select a bodygroup first.",
	[ "filter.override_remove_first" ] = "Select a hideable override first.",
	[ "filter.override_clear" ] = "Clear hideable overrides",
	[ "filter.override_clear_confirm" ] = "Remove every per-model hideable bodygroup override?",
	[ "filter.page_intro" ] = "Choose which models and bodygroups can receive procedural texture damage. Specific per-model overrides take priority over the broader exclusion rules below.",
	[ "reason.invalid_model_path" ] = "invalid model path",
	[ "reason.model_whitelisted" ] = "model is whitelisted",
	[ "reason.model_not_whitelisted" ] = "model is not whitelisted",
	[ "reason.model_blacklisted" ] = "model is blacklisted",
	[ "reason.model_not_blacklisted" ] = "model is not blacklisted",

	[ "main.intro" ] = "Bullet-driven cloth and equipment damage for ragdolls, with optional living-player and NPC support.",
	[ "main.realtime_preset" ] = "Apply recommended realtime settings",
	[ "main.damage" ] = "Damage",
	[ "main.enable_addon" ] = "Enable Procedural Bodygroup Destruction",
	[ "main.living_players" ] = "Apply effects to living players",
	[ "main.living_npcs" ] = "Apply effects to living NPCs",
	[ "main.server_help" ] = "Living-player and NPC effects are controlled by the server. Disabling a target type clears its existing damage.",
	[ "main.texture_removal" ] = "Enable texture removal",
	[ "main.apply_materials" ] = "Apply generated damage materials",
	[ "main.base_radius" ] = "Base hole radius",
	[ "main.depth_inside" ] = "Depth into surface",
	[ "main.reach_outside" ] = "Reach outside surface",
	[ "main.layer_limit" ] = "Maximum affected layers (0 = unlimited)",
	[ "main.layer_help" ] = "Each intersected mesh surface is one layer, ordered from the bullet-facing outside inward. Non-damageable mesh surfaces still consume a layer; existing holes do not.",
	[ "main.appearance" ] = "Damage appearance",
	[ "main.scale_damage" ] = "Scale hole by bullet damage",
	[ "main.reference_damage" ] = "Reference damage (base size)",
	[ "main.max_multiplier" ] = "Maximum size multiplier",
	[ "main.base_irregularity" ] = "Base edge irregularity",
	[ "main.extra_irregularity" ] = "Extra irregularity from damage",
	[ "main.max_irregularity" ] = "Maximum edge irregularity",
	[ "main.damage_shape_help" ] = "Radius grows with the square root of damage. The maximum multiplier caps the outermost tear; higher damage also creates a less regular deterministic edge.",
	[ "main.edge_expansion" ] = "Edge expansion (pixels)",
	[ "main.edge_softness" ] = "Edge softness (pixels)",
	[ "main.smoothing_passes" ] = "Smoothing passes",
	[ "main.repair_seams" ] = "Repair UV seams",
	[ "main.force_nocull" ] = "Show reverse faces around holes ($nocull)",
	[ "main.nocull_help" ] = "Forces $nocull 1 on generated damage materials so torn openings do not look like an empty one-sided shell.",
	[ "main.aspect_help" ] = "Textures and bullet masks always keep the full original resolution. A 4096×2048 source uses 4096×2048 targets. Unsupported sizes keep the source material and report an error.",
	[ "main.model_scope" ] = "Model scope",
	[ "main.model_scope_help" ] = "Choose whether the exact model paths below are denied or are the only models allowed. Filtered models skip mesh analysis entirely.",
	[ "main.excluded_bodygroups" ] = "Excluded bodygroups",
	[ "main.bodygroup_help" ] = "Blank-capable bodygroups with an exact matching name are never damaged. Matching ignores case but does not use partial words.",
	[ "main.hideable_overrides" ] = "Hideable bodygroup overrides",
	[ "main.hideable_override_help" ] = "Force a bodygroup on one exact model to be damageable. This has the highest priority, bypasses the bodygroup-name blacklist, and uses the compiled MDL bodypart layout even when the group has only one submodel and no blank option.",
	[ "main.filters_saved" ] = "Filters are saved in {{path}}.",
	[ "main.filters_future" ] = "Filter changes affect future hits. Use Repair on the Damage & Appearance page to remove damage that was already applied.",
	[ "main.repair" ] = "Repair",
	[ "main.clear_damage" ] = "Clear all transparent damage",

	[ "debug.intro" ] = "Developer instrumentation. These controls are not required for normal use.",
	[ "debug.preset" ] = "Apply lightweight debug preset",
	[ "debug.ragdoll_scope" ] = "Ragdoll scope and cold-cache control",
	[ "debug.death_only" ] = "Only damage ragdolls created from NPCs or players",
	[ "debug.prewarm" ] = "Enable background model prewarming",
	[ "debug.prewarm_living" ] = "Start prewarming from living NPCs and players",
	[ "debug.disk_cache" ] = "Persist processed mesh caches across restarts",
	[ "debug.io_budget" ] = "Persistent cache I/O budget (ms/frame)",
	[ "debug.build_budget" ] = "Cold mesh packing budget (ms/frame)",
	[ "debug.prepare_target" ] = "Cold model preparation target (seconds)",
	[ "debug.catchup_budget" ] = "Cold-cache hard slice cap (ms/frame)",
	[ "debug.clear_disk_cache" ] = "Clear persistent model cache",
	[ "debug.disk_cache_status" ] = "Print persistent cache status",
	[ "debug.burst" ] = "Shotgun and burst control",
	[ "debug.coalesce" ] = "Coalesce simultaneous pellet impacts",
	[ "debug.burst_window" ] = "Burst collection window (seconds)",
	[ "debug.merge_radius" ] = "Pellet merge radius",
	[ "debug.max_clusters" ] = "Maximum spatial clusters per burst",
	[ "debug.clusters_frame" ] = "Clusters dispatched per frame",
	[ "debug.queue_limit" ] = "Queue coalescing watermark",
	[ "debug.overlay" ] = "Hit overlay",
	[ "debug.draw_overlay" ] = "Draw 3D overlay",
	[ "debug.draw_labels" ] = "Draw labels",
	[ "debug.through_walls" ] = "Draw through walls",
	[ "debug.last_hit_hud" ] = "Show last-hit HUD",
	[ "debug.console" ] = "Print console diagnostics",
	[ "debug.marker_duration" ] = "Marker duration (0 = persistent)",
	[ "debug.marker_size" ] = "Marker size",
	[ "debug.retrace_length" ] = "Retrace half-length",
	[ "debug.max_hits" ] = "Maximum retained hits",
	[ "debug.hull_visual" ] = "Removal-hull visualization",
	[ "debug.draw_hull" ] = "Draw irregular removal hull",
	[ "debug.hull_segments" ] = "Hull render segments",
	[ "debug.hull_alpha" ] = "Hull fill alpha",
	[ "debug.hull_help" ] = "Green cap = outside; red cap = inside. The axis follows bullet travel.",
	[ "debug.mesh_internals" ] = "Mesh-query internals",
	[ "debug.analysis_budget" ] = "Analysis budget (ms/frame)",
	[ "debug.bone_padding" ] = "Bone candidate padding",
	[ "debug.removable_only" ] = "Query only removable meshes",
	[ "debug.local_bounds" ] = "Cylinder-local interval broad phase",
	[ "debug.full_scan" ] = "Force full-model scan (slow diagnostic)",
	[ "debug.projection" ] = "Irregular hull-to-UV projection internals",
	[ "debug.polar_samples" ] = "Polar boundary samples",
	[ "debug.subdivision" ] = "Adaptive subdivision depth",
	[ "debug.boundary_tolerance" ] = "Boundary tolerance (world units)",
	[ "debug.max_uv_triangles" ] = "Maximum projected UV triangles",
	[ "debug.angle_bounds" ] = "Angle-aware local projection bounds",
	[ "debug.batch_raster" ] = "Experimental batched mask rasterization",
	[ "debug.projection_help" ] = "The finite world-space tear volume is adaptively clipped against posed surface triangles, then mapped into each triangle's UV island. Large hits automatically reduce subdivision depth to remain inside the triangle budget.",
	[ "debug.material" ] = "Material diagnostics",
	[ "debug.rtx" ] = "RTX Remix direct material binding",
	[ "debug.rtx_help" ] = "On detected RTX-Remix clients, bind each damaged material directly during every ragdoll draw pass, including shadow/depth passes. SetSubMaterial remains active as the normal renderer fallback.",
	[ "debug.texture_inspector" ] = "Show top-right texture inspector (expensive)",
	[ "debug.texture_help" ] = "The texture inspector is off by default and is not enabled by the debug preset. It may redraw thousands of UV triangles every frame.",
	[ "debug.dump" ] = "Dump debug bundles to data/bbs_debug",
	[ "debug.validate_copy" ] = "Validate source copy with GPU readback (slow)",
	[ "debug.print_vmt" ] = "Print complete generated VMT (slow)",
	[ "debug.print_uv" ] = "Print individual UV coordinates",
	[ "debug.uv_limit" ] = "UVs printed per mesh",
	[ "debug.performance" ] = "Performance profiler",
	[ "debug.perf_enable" ] = "Enable performance tracking",
	[ "debug.perf_hud" ] = "Show ranked performance HUD",
	[ "debug.perf_console" ] = "Print report after each hit",
	[ "debug.perf_history" ] = "Completed hits retained",
	[ "debug.perf_stages" ] = "Stages shown in HUD",
	[ "debug.perf_help" ] = "Reports rank measured client CPU time for each hit and track continuous overlay/inspector frame costs separately. Render timings show client-thread submission or blocking, not asynchronous GPU execution.",
	[ "debug.print_perf" ] = "Print performance report",
	[ "debug.clear_perf" ] = "Clear performance history",
	[ "debug.actions" ] = "Debug actions",
	[ "debug.probe_target" ] = "Probe aimed enabled target (no bullet)",
	[ "debug.print_last_hit" ] = "Print last hit to console",
	[ "debug.print_status" ] = "Print addon status",
	[ "debug.print_filters" ] = "Print filter status",
	[ "debug.reload_filters" ] = "Reload filters from data JSON",
	[ "debug.clear_markers" ] = "Clear markers",
	[ "debug.mesh_cache_status" ] = "Print mesh cache status",
	[ "debug.probe_mesh" ] = "Probe last hit mesh structures",
	[ "debug.clear_mesh_cache" ] = "Clear mesh cache",
	[ "debug.print_uv_result" ] = "Print last UV damage result",
	[ "debug.probe_vmt" ] = "Probe cloned VMT parameters",
	[ "debug.uv_status" ] = "Print UV damage status",
	[ "debug.probe_bodygroups" ] = "Probe blank/bodygroup filters",
	[ "debug.clear_transparent" ] = "Clear transparent damage",
}

local ZH = {
	[ "tab.title" ] = "Procedural Bodygroup Destruction", [ "category.damage" ] = "破损", [ "category.developer" ] = "开发者",
	[ "menu.damage_filters" ] = "破损与筛选", [ "menu.debug" ] = "调试与诊断",
	[ "language.title" ] = "界面语言", [ "language.auto" ] = "自动（跟随 Garry's Mod 语言）",
	[ "common.add" ] = "添加", [ "common.remove_selected" ] = "移除所选", [ "common.reset_defaults" ] = "恢复默认",
	[ "common.clear" ] = "清空", [ "common.cancel" ] = "取消", [ "permission.admin" ] = "需要管理员权限才能更改此服务器设置。",
	[ "filter.model_behavior" ] = "模型列表模式", [ "filter.blacklist" ] = "黑名单 — 除列表中的模型外均可破损",
	[ "filter.whitelist" ] = "白名单 — 仅列表中的模型可破损", [ "filter.models_column" ] = "列表中的模型",
	[ "filter.add_aimed" ] = "添加瞄准的模型", [ "filter.clear_models" ] = "清空模型列表",
	[ "filter.aim_help" ] = "瞄准一个实体以查看其模型判定。", [ "filter.whitelist_empty" ] = "白名单为空，因此当前所有模型都不会产生纹理破损。",
	[ "filter.whitelist_help" ] = "仅下方完全匹配的模型路径可产生纹理破损。", [ "filter.blacklist_help" ] = "下方完全匹配的模型路径会被排除；空黑名单允许所有模型。",
	[ "filter.clear_confirm" ] = "从当前列表中移除所有模型路径？", [ "filter.bodygroups_column" ] = "排除的身体组名称",
	[ "filter.bodygroup_placeholder" ] = "准确的身体组名称", [ "filter.aimed_status" ] = "瞄准：{{model}}\n{{decision}} — {{reason}}",
	[ "filter.allowed" ] = "允许", [ "filter.blocked" ] = "阻止", [ "filter.no_model" ] = "<无模型>",
	[ "filter.select_model_first" ] = "请先选择一个模型。", [ "filter.aim_entity_first" ] = "请先瞄准一个实体。",
	[ "filter.select_bodygroup_first" ] = "请先选择一个身体组名称。", [ "reason.invalid_model_path" ] = "模型路径无效",
	[ "reason.model_whitelisted" ] = "模型在白名单中", [ "reason.model_not_whitelisted" ] = "模型不在白名单中",
	[ "reason.model_blacklisted" ] = "模型在黑名单中", [ "reason.model_not_blacklisted" ] = "模型不在黑名单中",
	[ "main.intro" ] = "由子弹驱动的布料与装备破损效果，适用于布娃娃，也可用于存活的玩家和 NPC。",
	[ "main.realtime_preset" ] = "应用推荐的实时设置", [ "main.damage" ] = "破损",
	[ "main.enable_addon" ] = "启用 Procedural Bodygroup Destruction", [ "main.living_players" ] = "对存活玩家应用效果",
	[ "main.living_npcs" ] = "对存活 NPC 应用效果", [ "main.server_help" ] = "存活玩家和 NPC 的效果由服务器控制。禁用目标类型会清除其已有破损。",
	[ "main.texture_removal" ] = "启用纹理移除", [ "main.apply_materials" ] = "应用生成的破损材质",
	[ "main.base_radius" ] = "基础破洞半径", [ "main.depth_inside" ] = "向表面内部深度", [ "main.reach_outside" ] = "向表面外部距离",
	[ "main.appearance" ] = "破损外观", [ "main.scale_damage" ] = "按子弹伤害缩放破洞",
	[ "main.reference_damage" ] = "参考伤害（基础尺寸）", [ "main.max_multiplier" ] = "最大尺寸倍率",
	[ "main.base_irregularity" ] = "基础边缘不规则度", [ "main.extra_irregularity" ] = "伤害附加不规则度",
	[ "main.max_irregularity" ] = "最大边缘不规则度", [ "main.damage_shape_help" ] = "半径随伤害的平方根增长。最大倍率限制最外层撕裂范围；更高伤害也会产生更不规则且可重复的边缘。",
	[ "main.edge_expansion" ] = "边缘扩张（像素）",
	[ "main.edge_softness" ] = "边缘柔化（像素）", [ "main.smoothing_passes" ] = "平滑次数", [ "main.repair_seams" ] = "修复 UV 接缝",
	[ "main.aspect_help" ] = "纹理和弹孔遮罩始终保持完整原始分辨率。4096×2048 原图使用 4096×2048 目标。不支持的尺寸会保留原始材质并报告错误。",
	[ "main.model_scope" ] = "模型范围", [ "main.model_scope_help" ] = "选择下方精确模型路径是禁止列表，还是唯一允许列表。被筛选的模型会完全跳过网格分析。",
	[ "main.excluded_bodygroups" ] = "排除的身体组", [ "main.bodygroup_help" ] = "名称完全匹配的可隐藏身体组永远不会受损。匹配忽略大小写，但不匹配部分词。",
	[ "main.filters_saved" ] = "筛选设置保存在 {{path}}。", [ "main.filters_future" ] = "筛选更改仅影响后续命中。使用下方“修复”移除已应用的破损。",
	[ "main.repair" ] = "修复", [ "main.clear_damage" ] = "清除全部透明破损",
	[ "debug.intro" ] = "开发者诊断工具。正常使用不需要这些选项。", [ "debug.preset" ] = "应用轻量调试预设",
	[ "debug.ragdoll_scope" ] = "布娃娃范围与冷缓存控制", [ "debug.death_only" ] = "仅破损由 NPC 或玩家生成的布娃娃",
	[ "debug.prewarm" ] = "启用后台模型预热", [ "debug.prewarm_living" ] = "从存活 NPC 和玩家开始预热",
	[ "debug.disk_cache" ] = "跨游戏重启保留已处理网格缓存", [ "debug.io_budget" ] = "持久缓存 I/O 预算（毫秒/帧）",
	[ "debug.build_budget" ] = "冷网格打包预算（毫秒/帧）",
	[ "debug.prepare_target" ] = "冷模型准备目标（秒）",
	[ "debug.catchup_budget" ] = "冷缓存单帧硬上限（毫秒/帧）",
	[ "debug.clear_disk_cache" ] = "清除持久模型缓存", [ "debug.disk_cache_status" ] = "打印持久缓存状态",
	[ "debug.burst" ] = "霰弹与连发控制", [ "debug.coalesce" ] = "合并同时发生的弹丸命中", [ "debug.burst_window" ] = "连发收集窗口（秒）",
	[ "debug.merge_radius" ] = "弹丸合并半径", [ "debug.max_clusters" ] = "每次连发的最大空间簇数", [ "debug.clusters_frame" ] = "每帧派发的簇数", [ "debug.queue_limit" ] = "队列合并软阈值",
	[ "debug.overlay" ] = "命中叠加层", [ "debug.draw_overlay" ] = "绘制 3D 叠加层", [ "debug.draw_labels" ] = "绘制标签",
	[ "debug.through_walls" ] = "穿墙绘制", [ "debug.last_hit_hud" ] = "显示最后命中 HUD", [ "debug.console" ] = "打印控制台诊断",
	[ "debug.marker_duration" ] = "标记持续时间（0 = 永久）", [ "debug.marker_size" ] = "标记尺寸", [ "debug.retrace_length" ] = "反向追踪半长", [ "debug.max_hits" ] = "最多保留命中数",
	[ "debug.hull_visual" ] = "移除体可视化", [ "debug.draw_hull" ] = "绘制不规则移除体", [ "debug.hull_segments" ] = "移除体绘制分段", [ "debug.hull_alpha" ] = "移除体填充透明度",
	[ "debug.hull_help" ] = "绿色端面 = 外侧；红色端面 = 内侧。轴线沿子弹飞行方向。",
	[ "debug.mesh_internals" ] = "网格查询内部设置", [ "debug.analysis_budget" ] = "分析预算（毫秒/帧）", [ "debug.bone_padding" ] = "骨骼候选扩展",
	[ "debug.removable_only" ] = "仅查询可移除网格", [ "debug.local_bounds" ] = "圆柱局部区间宽阶段", [ "debug.full_scan" ] = "强制全模型扫描（慢速诊断）",
	[ "debug.projection" ] = "不规则移除体到 UV 投影内部设置", [ "debug.polar_samples" ] = "极坐标边界采样", [ "debug.subdivision" ] = "自适应细分深度",
	[ "debug.boundary_tolerance" ] = "边界容差（世界单位）", [ "debug.max_uv_triangles" ] = "最大投影 UV 三角形数", [ "debug.angle_bounds" ] = "角度感知局部投影边界",
	[ "debug.batch_raster" ] = "实验性批量遮罩光栅化", [ "debug.projection_help" ] = "有限的世界空间撕裂体会自适应裁剪姿态表面三角形，再映射到各三角形的 UV 岛。大型命中会自动降低细分深度以保持在三角形预算内。",
	[ "debug.material" ] = "材质诊断", [ "debug.rtx" ] = "RTX Remix 直接材质绑定",
	[ "debug.rtx_help" ] = "检测到 RTX Remix 时，在布娃娃的每次绘制（包括阴影/深度通道）中直接绑定受损材质。SetSubMaterial 仍作为普通渲染器的后备方案。",
	[ "debug.texture_inspector" ] = "显示右上角纹理检查器（高开销）", [ "debug.texture_help" ] = "纹理检查器默认关闭，调试预设也不会启用。它可能每帧重绘数千个 UV 三角形。",
	[ "debug.dump" ] = "转储调试包到 data/bbs_debug", [ "debug.validate_copy" ] = "用 GPU 回读验证源复制（慢）", [ "debug.print_vmt" ] = "打印完整生成 VMT（慢）",
	[ "debug.print_uv" ] = "打印单个 UV 坐标", [ "debug.uv_limit" ] = "每个网格打印的 UV 数",
	[ "debug.performance" ] = "性能分析器", [ "debug.perf_enable" ] = "启用性能跟踪", [ "debug.perf_hud" ] = "显示性能排名 HUD",
	[ "debug.perf_console" ] = "每次命中后打印报告", [ "debug.perf_history" ] = "保留的已完成命中数", [ "debug.perf_stages" ] = "HUD 显示的阶段数",
	[ "debug.perf_help" ] = "报告按每次命中的客户端 CPU 实测时间排序，并分别跟踪持续叠加层/检查器帧开销。渲染计时表示客户端线程提交或阻塞，而非异步 GPU 执行。",
	[ "debug.print_perf" ] = "打印性能报告", [ "debug.clear_perf" ] = "清除性能历史", [ "debug.actions" ] = "调试操作",
	[ "debug.probe_target" ] = "探测瞄准的已启用目标（无子弹）", [ "debug.print_last_hit" ] = "将最后命中打印到控制台", [ "debug.print_status" ] = "打印插件状态",
	[ "debug.print_filters" ] = "打印筛选状态", [ "debug.reload_filters" ] = "从 data JSON 重新加载筛选", [ "debug.clear_markers" ] = "清除标记",
	[ "debug.mesh_cache_status" ] = "打印网格缓存状态", [ "debug.probe_mesh" ] = "探测最后命中的网格结构", [ "debug.clear_mesh_cache" ] = "清除网格缓存",
	[ "debug.print_uv_result" ] = "打印最后 UV 破损结果", [ "debug.probe_vmt" ] = "探测克隆 VMT 参数", [ "debug.uv_status" ] = "打印 UV 破损状态",
	[ "debug.probe_bodygroups" ] = "探测空白/身体组筛选", [ "debug.clear_transparent" ] = "清除透明破损",
}

local JA = {
	[ "tab.title" ] = "Procedural Bodygroup Destruction", [ "category.damage" ] = "ダメージ", [ "category.developer" ] = "開発者",
	[ "menu.damage_filters" ] = "ダメージとフィルター", [ "menu.debug" ] = "デバッグと診断", [ "language.title" ] = "表示言語",
	[ "language.auto" ] = "自動（Garry's Mod の言語）", [ "common.add" ] = "追加", [ "common.remove_selected" ] = "選択項目を削除",
	[ "common.reset_defaults" ] = "初期値に戻す", [ "common.clear" ] = "クリア", [ "common.cancel" ] = "キャンセル",
	[ "permission.admin" ] = "このサーバー設定を変更するには管理者権限が必要です。",
	[ "filter.model_behavior" ] = "モデルリストの動作", [ "filter.blacklist" ] = "ブラックリスト — 登録モデル以外を破損",
	[ "filter.whitelist" ] = "ホワイトリスト — 登録モデルのみ破損", [ "filter.models_column" ] = "リスト内のモデル",
	[ "filter.add_aimed" ] = "照準先モデルを追加", [ "filter.clear_models" ] = "モデルリストをクリア", [ "filter.aim_help" ] = "エンティティを狙うとモデル判定を確認できます。",
	[ "filter.whitelist_empty" ] = "ホワイトリストが空のため、現在すべてのモデルでテクスチャ破損が無効です。", [ "filter.whitelist_help" ] = "下記と完全一致するモデルパスのみ破損できます。",
	[ "filter.blacklist_help" ] = "下記と完全一致するモデルパスを除外します。空ならすべて許可します。", [ "filter.clear_confirm" ] = "現在のリストから全モデルパスを削除しますか？",
	[ "filter.bodygroups_column" ] = "除外するボディグループ名", [ "filter.bodygroup_placeholder" ] = "正確なボディグループ名",
	[ "filter.aimed_status" ] = "照準先: {{model}}\n{{decision}} — {{reason}}", [ "filter.allowed" ] = "許可", [ "filter.blocked" ] = "ブロック", [ "filter.no_model" ] = "<モデルなし>",
	[ "filter.select_model_first" ] = "先にモデルを選択してください。", [ "filter.aim_entity_first" ] = "先にエンティティを狙ってください。", [ "filter.select_bodygroup_first" ] = "先にボディグループ名を選択してください。",
	[ "reason.invalid_model_path" ] = "無効なモデルパス", [ "reason.model_whitelisted" ] = "モデルはホワイトリスト内です", [ "reason.model_not_whitelisted" ] = "モデルはホワイトリスト外です",
	[ "reason.model_blacklisted" ] = "モデルはブラックリスト内です", [ "reason.model_not_blacklisted" ] = "モデルはブラックリスト外です",
	[ "main.intro" ] = "弾丸による布や装備の破損をラグドールに適用し、生存中のプレイヤーと NPC にも任意で対応します。", [ "main.realtime_preset" ] = "推奨リアルタイム設定を適用",
	[ "main.damage" ] = "ダメージ", [ "main.enable_addon" ] = "Procedural Bodygroup Destruction を有効化", [ "main.living_players" ] = "生存プレイヤーに効果を適用",
	[ "main.living_npcs" ] = "生存 NPC に効果を適用", [ "main.server_help" ] = "生存プレイヤーと NPC の効果はサーバー側で制御されます。対象を無効にすると既存の破損も消去されます。",
	[ "main.texture_removal" ] = "テクスチャ除去を有効化", [ "main.apply_materials" ] = "生成した破損マテリアルを適用",
	[ "main.base_radius" ] = "基本穴半径", [ "main.depth_inside" ] = "表面内への深さ", [ "main.reach_outside" ] = "表面外への距離", [ "main.appearance" ] = "破損の外観",
	[ "main.scale_damage" ] = "弾丸ダメージで穴を拡大", [ "main.reference_damage" ] = "基準ダメージ（基本サイズ）", [ "main.max_multiplier" ] = "最大サイズ倍率",
	[ "main.base_irregularity" ] = "基本エッジ不規則度", [ "main.extra_irregularity" ] = "ダメージによる追加不規則度", [ "main.max_irregularity" ] = "最大エッジ不規則度",
	[ "main.damage_shape_help" ] = "半径はダメージの平方根に応じて増加します。最大倍率が裂け目の外端を制限し、高ダメージほど不規則で再現可能な輪郭になります。",
	[ "main.edge_expansion" ] = "エッジ拡張（ピクセル）", [ "main.edge_softness" ] = "エッジの柔らかさ（ピクセル）",
	[ "main.smoothing_passes" ] = "平滑化回数", [ "main.repair_seams" ] = "UV シームを修復", [ "main.aspect_help" ] = "テクスチャと弾痕マスクは常に元の解像度を維持します。4096×2048 の画像には 4096×2048 のターゲットを使用します。非対応のサイズでは元のマテリアルを保持し、エラーを報告します。",
	[ "main.model_scope" ] = "モデル範囲", [ "main.model_scope_help" ] = "下記の完全一致モデルパスを拒否リストにするか、唯一の許可リストにするかを選択します。除外モデルはメッシュ解析を完全に省略します。",
	[ "main.excluded_bodygroups" ] = "除外ボディグループ", [ "main.bodygroup_help" ] = "名前が完全一致する非表示可能ボディグループは破損しません。大文字小文字は無視しますが部分一致はしません。",
	[ "main.filters_saved" ] = "フィルターは {{path}} に保存されます。", [ "main.filters_future" ] = "変更は今後のヒットに適用されます。既存の破損は下の修復で除去してください。",
	[ "main.repair" ] = "修復", [ "main.clear_damage" ] = "すべての透明破損をクリア",
}

local FR = {
	[ "tab.title" ] = "Procedural Bodygroup Destruction", [ "category.damage" ] = "Dégâts", [ "category.developer" ] = "Développeur",
	[ "menu.damage_filters" ] = "Dégâts et filtres", [ "menu.debug" ] = "Débogage et diagnostic", [ "language.title" ] = "Langue de l’interface",
	[ "language.auto" ] = "Automatique (langue de Garry's Mod)", [ "common.add" ] = "Ajouter", [ "common.remove_selected" ] = "Supprimer la sélection",
	[ "common.reset_defaults" ] = "Valeurs par défaut", [ "common.clear" ] = "Effacer", [ "common.cancel" ] = "Annuler",
	[ "permission.admin" ] = "Les droits d’administrateur sont requis pour modifier ce réglage serveur.",
	[ "filter.model_behavior" ] = "Comportement de la liste de modèles", [ "filter.blacklist" ] = "Liste noire — endommager tous les modèles sauf ceux listés",
	[ "filter.whitelist" ] = "Liste blanche — endommager uniquement les modèles listés", [ "filter.models_column" ] = "Modèles de cette liste",
	[ "filter.add_aimed" ] = "Ajouter le modèle visé", [ "filter.clear_models" ] = "Effacer la liste de modèles", [ "filter.aim_help" ] = "Visez une entité pour connaître la décision appliquée à son modèle.",
	[ "filter.whitelist_empty" ] = "La liste blanche est vide : les dégâts de texture sont désactivés pour tous les modèles.", [ "filter.whitelist_help" ] = "Seuls les chemins de modèles exacts ci-dessous peuvent recevoir des dégâts de texture.",
	[ "filter.blacklist_help" ] = "Les chemins exacts ci-dessous sont exclus ; une liste noire vide autorise tous les modèles.", [ "filter.clear_confirm" ] = "Supprimer tous les chemins de modèles de la liste active ?",
	[ "filter.bodygroups_column" ] = "Noms de bodygroups exclus", [ "filter.bodygroup_placeholder" ] = "Nom exact du bodygroup",
	[ "filter.aimed_status" ] = "Visé : {{model}}\n{{decision}} — {{reason}}", [ "filter.allowed" ] = "AUTORISÉ", [ "filter.blocked" ] = "BLOQUÉ", [ "filter.no_model" ] = "<aucun modèle>",
	[ "filter.select_model_first" ] = "Sélectionnez d’abord un modèle.", [ "filter.aim_entity_first" ] = "Visez d’abord une entité.", [ "filter.select_bodygroup_first" ] = "Sélectionnez d’abord un nom de bodygroup.",
	[ "reason.invalid_model_path" ] = "chemin de modèle non valide", [ "reason.model_whitelisted" ] = "le modèle est sur liste blanche", [ "reason.model_not_whitelisted" ] = "le modèle n’est pas sur liste blanche",
	[ "reason.model_blacklisted" ] = "le modèle est sur liste noire", [ "reason.model_not_blacklisted" ] = "le modèle n’est pas sur liste noire",
	[ "main.intro" ] = "Dégâts de vêtements et d’équipements causés par les balles pour les ragdolls, avec prise en charge facultative des joueurs vivants et des PNJ.", [ "main.realtime_preset" ] = "Appliquer les réglages temps réel recommandés",
	[ "main.damage" ] = "Dégâts", [ "main.enable_addon" ] = "Activer Procedural Bodygroup Destruction", [ "main.living_players" ] = "Appliquer aux joueurs vivants", [ "main.living_npcs" ] = "Appliquer aux PNJ vivants",
	[ "main.server_help" ] = "Les effets sur les joueurs vivants et les PNJ sont contrôlés par le serveur. Désactiver un type de cible efface ses dégâts existants.",
	[ "main.texture_removal" ] = "Activer la suppression de texture", [ "main.apply_materials" ] = "Appliquer les matériaux de dégâts générés",
	[ "main.base_radius" ] = "Rayon de base du trou", [ "main.depth_inside" ] = "Profondeur dans la surface", [ "main.reach_outside" ] = "Portée hors de la surface", [ "main.appearance" ] = "Apparence des dégâts",
	[ "main.scale_damage" ] = "Adapter le trou aux dégâts de la balle", [ "main.reference_damage" ] = "Dégâts de référence (taille de base)", [ "main.max_multiplier" ] = "Multiplicateur de taille maximal",
	[ "main.base_irregularity" ] = "Irrégularité de base du bord", [ "main.extra_irregularity" ] = "Irrégularité supplémentaire selon les dégâts", [ "main.max_irregularity" ] = "Irrégularité maximale du bord",
	[ "main.damage_shape_help" ] = "Le rayon augmente avec la racine carrée des dégâts. Le multiplicateur maximal limite la déchirure ; des dégâts élevés produisent aussi un bord déterministe plus irrégulier.",
	[ "main.edge_expansion" ] = "Expansion du bord (pixels)", [ "main.edge_softness" ] = "Adoucissement du bord (pixels)",
	[ "main.smoothing_passes" ] = "Passes de lissage", [ "main.repair_seams" ] = "Réparer les coutures UV", [ "main.aspect_help" ] = "Les textures et masques d’impact conservent toujours la résolution d’origine. Une source 4096×2048 utilise des cibles 4096×2048. Les tailles non prises en charge conservent le matériau source et signalent une erreur.",
	[ "main.model_scope" ] = "Portée des modèles", [ "main.model_scope_help" ] = "Choisissez si les chemins exacts ci-dessous sont refusés ou s’ils sont les seuls autorisés. Les modèles filtrés ignorent entièrement l’analyse du maillage.",
	[ "main.excluded_bodygroups" ] = "Bodygroups exclus", [ "main.bodygroup_help" ] = "Les bodygroups masquables dont le nom correspond exactement ne sont jamais endommagés. La casse est ignorée, sans correspondance partielle.",
	[ "main.filters_saved" ] = "Les filtres sont enregistrés dans {{path}}.", [ "main.filters_future" ] = "Les changements concernent les futurs impacts. Utilisez Réparer ci-dessous pour retirer les dégâts déjà appliqués.",
	[ "main.repair" ] = "Réparer", [ "main.clear_damage" ] = "Effacer tous les dégâts transparents",
}

local RU = {
	[ "tab.title" ] = "Procedural Bodygroup Destruction", [ "category.damage" ] = "Повреждения", [ "category.developer" ] = "Разработчик",
	[ "menu.damage_filters" ] = "Повреждения и фильтры", [ "menu.debug" ] = "Отладка и диагностика", [ "language.title" ] = "Язык интерфейса",
	[ "language.auto" ] = "Автоматически (язык Garry's Mod)", [ "common.add" ] = "Добавить", [ "common.remove_selected" ] = "Удалить выбранное",
	[ "common.reset_defaults" ] = "Сбросить настройки", [ "common.clear" ] = "Очистить", [ "common.cancel" ] = "Отмена",
	[ "permission.admin" ] = "Для изменения этой серверной настройки требуются права администратора.",
	[ "filter.model_behavior" ] = "Режим списка моделей", [ "filter.blacklist" ] = "Чёрный список — повреждать все модели, кроме указанных",
	[ "filter.whitelist" ] = "Белый список — повреждать только указанные модели", [ "filter.models_column" ] = "Модели в списке",
	[ "filter.add_aimed" ] = "Добавить модель под прицелом", [ "filter.clear_models" ] = "Очистить список моделей", [ "filter.aim_help" ] = "Наведитесь на сущность, чтобы проверить решение для её модели.",
	[ "filter.whitelist_empty" ] = "Белый список пуст, поэтому повреждение текстур сейчас отключено для всех моделей.", [ "filter.whitelist_help" ] = "Повреждения разрешены только для точных путей моделей ниже.",
	[ "filter.blacklist_help" ] = "Точные пути ниже исключены; пустой чёрный список разрешает все модели.", [ "filter.clear_confirm" ] = "Удалить все пути моделей из активного списка?",
	[ "filter.bodygroups_column" ] = "Исключённые названия бодигрупп", [ "filter.bodygroup_placeholder" ] = "Точное название бодигруппы",
	[ "filter.aimed_status" ] = "Под прицелом: {{model}}\n{{decision}} — {{reason}}", [ "filter.allowed" ] = "РАЗРЕШЕНО", [ "filter.blocked" ] = "ЗАБЛОКИРОВАНО", [ "filter.no_model" ] = "<нет модели>",
	[ "filter.select_model_first" ] = "Сначала выберите модель.", [ "filter.aim_entity_first" ] = "Сначала наведитесь на сущность.", [ "filter.select_bodygroup_first" ] = "Сначала выберите название бодигруппы.",
	[ "reason.invalid_model_path" ] = "неверный путь модели", [ "reason.model_whitelisted" ] = "модель в белом списке", [ "reason.model_not_whitelisted" ] = "модель не в белом списке",
	[ "reason.model_blacklisted" ] = "модель в чёрном списке", [ "reason.model_not_blacklisted" ] = "модель не в чёрном списке",
	[ "main.intro" ] = "Пулевые повреждения одежды и снаряжения на рэгдоллах с дополнительной поддержкой живых игроков и NPC.", [ "main.realtime_preset" ] = "Применить рекомендуемые настройки реального времени",
	[ "main.damage" ] = "Повреждения", [ "main.enable_addon" ] = "Включить Procedural Bodygroup Destruction", [ "main.living_players" ] = "Применять к живым игрокам", [ "main.living_npcs" ] = "Применять к живым NPC",
	[ "main.server_help" ] = "Эффекты для живых игроков и NPC управляются сервером. Отключение типа цели удаляет существующие повреждения.",
	[ "main.texture_removal" ] = "Включить удаление текстуры", [ "main.apply_materials" ] = "Применять созданные материалы повреждений",
	[ "main.base_radius" ] = "Базовый радиус отверстия", [ "main.depth_inside" ] = "Глубина внутрь поверхности", [ "main.reach_outside" ] = "Дальность снаружи поверхности", [ "main.appearance" ] = "Вид повреждений",
	[ "main.scale_damage" ] = "Масштабировать отверстие по урону", [ "main.reference_damage" ] = "Опорный урон (базовый размер)", [ "main.max_multiplier" ] = "Максимальный множитель размера",
	[ "main.base_irregularity" ] = "Базовая неровность края", [ "main.extra_irregularity" ] = "Дополнительная неровность от урона", [ "main.max_irregularity" ] = "Максимальная неровность края",
	[ "main.damage_shape_help" ] = "Радиус растёт с квадратным корнем урона. Максимальный множитель ограничивает разрыв; высокий урон также создаёт более неровный детерминированный край.",
	[ "main.edge_expansion" ] = "Расширение края (пиксели)", [ "main.edge_softness" ] = "Мягкость края (пиксели)",
	[ "main.smoothing_passes" ] = "Проходы сглаживания", [ "main.repair_seams" ] = "Исправлять UV-швы", [ "main.aspect_help" ] = "Текстуры и маски попаданий всегда сохраняют исходное разрешение. Источник 4096×2048 использует цели 4096×2048. Если размер не поддерживается, исходный материал сохраняется и выводится ошибка.",
	[ "main.model_scope" ] = "Область моделей", [ "main.model_scope_help" ] = "Выберите: запрещать точные пути ниже или разрешать только их. Отфильтрованные модели полностью пропускают анализ сетки.",
	[ "main.excluded_bodygroups" ] = "Исключённые бодигруппы", [ "main.bodygroup_help" ] = "Скрываемые бодигруппы с точно совпадающим названием не повреждаются. Регистр игнорируется, частичные совпадения не используются.",
	[ "main.filters_saved" ] = "Фильтры сохранены в {{path}}.", [ "main.filters_future" ] = "Изменения действуют на будущие попадания. Используйте восстановление ниже, чтобы убрать уже нанесённые повреждения.",
	[ "main.repair" ] = "Восстановление", [ "main.clear_damage" ] = "Очистить все прозрачные повреждения",
}

-- Technical/debug labels shared by Japanese, French and Russian are filled
-- below. Keeping them in one explicit map also makes missing translations easy
-- to audit against the complete English key set.
local DEBUG_TRANSLATIONS = {
	ja = {
		"開発者向け計測機能です。通常使用では不要です。", "軽量デバッグプリセットを適用", "ラグドール範囲とコールドキャッシュ制御", "NPC またはプレイヤー由来のラグドールのみ破損", "バックグラウンドでモデルを事前処理", "生存 NPC とプレイヤーから事前処理を開始", "処理済みメッシュキャッシュを再起動後も保持", "永続キャッシュ I/O 予算（ms/フレーム）", "永続モデルキャッシュを消去", "永続キャッシュ状態を表示", "ショットガンとバースト制御", "同時ペレット着弾を統合", "バースト収集時間（秒）", "ペレット統合半径", "バーストごとの最大空間クラスタ数", "フレームごとの送信クラスタ数", "最大待機クラスタ数", "ヒットオーバーレイ", "3D オーバーレイを描画", "ラベルを描画", "壁越しに描画", "最終ヒット HUD を表示", "コンソール診断を出力", "マーカー時間（0 = 永続）", "マーカーサイズ", "再トレース半長", "保持する最大ヒット数", "除去ハル表示", "不規則な除去ハルを描画", "ハル描画セグメント", "ハル塗りつぶしアルファ", "緑の面 = 外側、赤の面 = 内側。軸は弾道方向に沿います。", "メッシュクエリ内部設定", "解析予算（ms/フレーム）", "ボーン候補余白", "除去可能メッシュのみ検索", "円柱ローカル区間広域判定", "全モデル走査を強制（低速診断）", "不規則ハルから UV への投影内部設定", "極座標境界サンプル", "適応細分化深度", "境界許容値（ワールド単位）", "最大投影 UV 三角形数", "角度対応ローカル投影境界", "実験的バッチマスクラスタライズ", "有限のワールド空間裂け領域をポーズ済み表面三角形に適応的にクリップし、各 UV アイランドへ写像します。大きなヒットでは三角形予算内に収めるため細分化深度を自動調整します。", "マテリアル診断", "RTX Remix 直接マテリアル割り当て", "RTX Remix 検出時は影・深度パスを含む各描画で破損マテリアルを直接割り当てます。通常レンダラーでは SetSubMaterial がフォールバックです。", "右上のテクスチャ検査を表示（高負荷）", "テクスチャ検査は既定で無効で、デバッグプリセットでも有効になりません。毎フレーム数千の UV 三角形を再描画する場合があります。", "デバッグ一式を data/bbs_debug に保存", "GPU 読み戻しで元コピーを検証（低速）", "生成 VMT 全体を出力（低速）", "個別 UV 座標を出力", "メッシュごとの UV 出力数", "パフォーマンスプロファイラー", "パフォーマンス追跡を有効化", "順位付きパフォーマンス HUD を表示", "各ヒット後にレポートを出力", "保持する完了ヒット数", "HUD に表示する段階数", "各ヒットのクライアント CPU 実測時間を順位付けし、継続的なオーバーレイ/検査フレームコストを別に追跡します。レンダー時間は非同期 GPU 実行ではなくクライアントスレッドの送信または待機です。", "パフォーマンスレポートを出力", "パフォーマンス履歴を消去", "デバッグ操作", "照準先の有効対象を調査（弾丸なし）", "最終ヒットをコンソールに出力", "アドオン状態を出力", "フィルター状態を出力", "data JSON からフィルターを再読み込み", "マーカーを消去", "メッシュキャッシュ状態を出力", "最終ヒットのメッシュ構造を調査", "メッシュキャッシュを消去", "最終 UV 破損結果を出力", "複製 VMT パラメータを調査", "UV 破損状態を出力", "空/ボディグループフィルターを調査", "透明破損を消去",
	},
	fr = {
		"Instrumentation pour développeurs. Ces réglages ne sont pas nécessaires à l’utilisation normale.", "Appliquer le préréglage de débogage léger", "Portée des ragdolls et contrôle du cache froid", "Endommager uniquement les ragdolls créés par des PNJ ou joueurs", "Activer le préchauffage des modèles en arrière-plan", "Préchauffer à partir des PNJ et joueurs vivants", "Conserver les caches de maillage après redémarrage", "Budget E/S du cache persistant (ms/image)", "Effacer le cache persistant des modèles", "Afficher l’état du cache persistant", "Contrôle des fusils à pompe et rafales", "Regrouper les impacts simultanés", "Fenêtre de collecte de rafale (secondes)", "Rayon de fusion des projectiles", "Nombre maximal de groupes spatiaux par rafale", "Groupes traités par image", "Nombre maximal de groupes en attente", "Superposition des impacts", "Afficher la superposition 3D", "Afficher les étiquettes", "Afficher à travers les murs", "Afficher le HUD du dernier impact", "Afficher les diagnostics dans la console", "Durée des marqueurs (0 = permanent)", "Taille des marqueurs", "Demi-longueur du retraçage", "Nombre maximal d’impacts conservés", "Visualisation du volume de suppression", "Afficher le volume irrégulier", "Segments de rendu du volume", "Opacité du remplissage", "Face verte = extérieur ; face rouge = intérieur. L’axe suit la trajectoire de la balle.", "Fonctionnement interne de la recherche de maillage", "Budget d’analyse (ms/image)", "Marge des os candidats", "Rechercher uniquement les maillages supprimables", "Phase large locale à l’intervalle du cylindre", "Forcer l’analyse du modèle complet (diagnostic lent)", "Projection interne du volume irrégulier vers les UV", "Échantillons de bord polaire", "Profondeur de subdivision adaptative", "Tolérance de bord (unités du monde)", "Nombre maximal de triangles UV projetés", "Limites locales sensibles à l’angle", "Rastérisation groupée expérimentale", "Le volume de déchirure est découpé adaptativement sur les triangles posés puis projeté dans chaque îlot UV. Les grands impacts réduisent automatiquement la subdivision pour respecter le budget.", "Diagnostic des matériaux", "Liaison directe des matériaux RTX Remix", "Avec RTX Remix, chaque matériau endommagé est lié durant toutes les passes du ragdoll, y compris ombres et profondeur. SetSubMaterial reste la solution de repli du moteur normal.", "Afficher l’inspecteur de texture en haut à droite (coûteux)", "L’inspecteur est désactivé par défaut et par le préréglage. Il peut redessiner des milliers de triangles UV par image.", "Exporter les diagnostics dans data/bbs_debug", "Valider la copie source par lecture GPU (lent)", "Afficher le VMT généré complet (lent)", "Afficher les coordonnées UV individuelles", "UV affichés par maillage", "Profileur de performances", "Activer le suivi des performances", "Afficher le HUD de performances classées", "Afficher un rapport après chaque impact", "Impacts terminés conservés", "Étapes affichées dans le HUD", "Les rapports classent le temps CPU client mesuré et suivent séparément le coût continu de la superposition et de l’inspecteur. Les temps de rendu mesurent la soumission ou le blocage du thread client, pas l’exécution GPU asynchrone.", "Afficher le rapport de performances", "Effacer l’historique des performances", "Actions de débogage", "Analyser la cible visée activée (sans balle)", "Afficher le dernier impact dans la console", "Afficher l’état de l’addon", "Afficher l’état des filtres", "Recharger les filtres depuis le JSON de données", "Effacer les marqueurs", "Afficher l’état du cache de maillage", "Analyser les structures du dernier maillage touché", "Effacer le cache de maillage", "Afficher le dernier résultat de dégâts UV", "Analyser les paramètres du VMT cloné", "Afficher l’état des dégâts UV", "Analyser les filtres vide/bodygroup", "Effacer les dégâts transparents",
	},
	ru = {
		"Инструменты разработчика. Для обычного использования эти настройки не нужны.", "Применить облегчённый профиль отладки", "Область рэгдоллов и управление холодным кэшем", "Повреждать только рэгдоллы, созданные NPC или игроками", "Включить фоновый прогрев моделей", "Начинать прогрев с живых NPC и игроков", "Сохранять обработанный кэш сеток после перезапуска", "Бюджет ввода-вывода кэша (мс/кадр)", "Очистить постоянный кэш моделей", "Показать состояние постоянного кэша", "Управление дробовиком и очередями", "Объединять одновременные попадания дроби", "Окно сбора очереди (секунды)", "Радиус объединения дроби", "Максимум пространственных групп в очереди", "Групп за кадр", "Максимум групп в очереди обработки", "Оверлей попаданий", "Рисовать 3D-оверлей", "Рисовать подписи", "Рисовать сквозь стены", "Показывать HUD последнего попадания", "Печатать диагностику в консоль", "Длительность маркера (0 = постоянно)", "Размер маркера", "Половина длины повторной трассировки", "Максимум сохранённых попаданий", "Визуализация объёма удаления", "Рисовать неровный объём удаления", "Сегменты отображения объёма", "Прозрачность заполнения", "Зелёная крышка = снаружи; красная = внутри. Ось следует направлению пули.", "Внутренние параметры поиска сетки", "Бюджет анализа (мс/кадр)", "Запас кандидатов костей", "Искать только удаляемые сетки", "Локальная интервальная широкая фаза цилиндра", "Принудительно сканировать всю модель (медленно)", "Внутренние параметры проекции объёма в UV", "Полярные выборки границы", "Глубина адаптивного подразделения", "Допуск границы (мировые единицы)", "Максимум проецируемых UV-треугольников", "Локальные границы проекции с учётом угла", "Экспериментальная пакетная растеризация маски", "Конечный объём разрыва адаптивно обрезается по треугольникам поверхности и отображается в UV-острова. Для больших попаданий глубина подразделения автоматически уменьшается до бюджета треугольников.", "Диагностика материалов", "Прямая привязка материалов RTX Remix", "При RTX Remix повреждённый материал привязывается во всех проходах отрисовки рэгдолла, включая тени и глубину. SetSubMaterial остаётся запасным вариантом обычного рендера.", "Показывать инспектор текстуры справа сверху (затратно)", "Инспектор по умолчанию выключен и не включается отладочным профилем. Он может перерисовывать тысячи UV-треугольников каждый кадр.", "Сохранять отладочные пакеты в data/bbs_debug", "Проверять исходную копию чтением GPU (медленно)", "Печатать полный созданный VMT (медленно)", "Печатать отдельные UV-координаты", "UV на сетку в консоли", "Профилировщик производительности", "Включить отслеживание производительности", "Показывать ранжированный HUD производительности", "Печатать отчёт после каждого попадания", "Сохранённых завершённых попаданий", "Этапов в HUD", "Отчёты ранжируют измеренное время CPU клиента и отдельно отслеживают постоянную стоимость оверлея/инспектора. Время рендера показывает отправку или блокировку клиентского потока, а не асинхронную работу GPU.", "Печатать отчёт производительности", "Очистить историю производительности", "Отладочные действия", "Проверить цель под прицелом (без пули)", "Печатать последнее попадание в консоль", "Печатать состояние аддона", "Печатать состояние фильтров", "Перезагрузить фильтры из JSON данных", "Очистить маркеры", "Печатать состояние кэша сеток", "Проверить структуры сетки последнего попадания", "Очистить кэш сеток", "Печатать последний результат UV-повреждения", "Проверить параметры клонированного VMT", "Печатать состояние UV-повреждений", "Проверить фильтры пустых бодигрупп", "Очистить прозрачные повреждения",
	},
}

local DEBUG_KEYS = {
	"debug.intro", "debug.preset", "debug.ragdoll_scope", "debug.death_only", "debug.prewarm", "debug.prewarm_living", "debug.disk_cache", "debug.io_budget", "debug.clear_disk_cache", "debug.disk_cache_status", "debug.burst", "debug.coalesce", "debug.burst_window", "debug.merge_radius", "debug.max_clusters", "debug.clusters_frame", "debug.queue_limit", "debug.overlay", "debug.draw_overlay", "debug.draw_labels", "debug.through_walls", "debug.last_hit_hud", "debug.console", "debug.marker_duration", "debug.marker_size", "debug.retrace_length", "debug.max_hits", "debug.hull_visual", "debug.draw_hull", "debug.hull_segments", "debug.hull_alpha", "debug.hull_help", "debug.mesh_internals", "debug.analysis_budget", "debug.bone_padding", "debug.removable_only", "debug.local_bounds", "debug.full_scan", "debug.projection", "debug.polar_samples", "debug.subdivision", "debug.boundary_tolerance", "debug.max_uv_triangles", "debug.angle_bounds", "debug.batch_raster", "debug.projection_help", "debug.material", "debug.rtx", "debug.rtx_help", "debug.texture_inspector", "debug.texture_help", "debug.dump", "debug.validate_copy", "debug.print_vmt", "debug.print_uv", "debug.uv_limit", "debug.performance", "debug.perf_enable", "debug.perf_hud", "debug.perf_console", "debug.perf_history", "debug.perf_stages", "debug.perf_help", "debug.print_perf", "debug.clear_perf", "debug.actions", "debug.probe_target", "debug.print_last_hit", "debug.print_status", "debug.print_filters", "debug.reload_filters", "debug.clear_markers", "debug.mesh_cache_status", "debug.probe_mesh", "debug.clear_mesh_cache", "debug.print_uv_result", "debug.probe_vmt", "debug.uv_status", "debug.probe_bodygroups", "debug.clear_transparent",
}

for code, values in pairs( DEBUG_TRANSLATIONS ) do
	local locale = code == "ja" and JA or code == "fr" and FR or RU
	for index, key in ipairs( DEBUG_KEYS ) do locale[ key ] = values[ index ] end
end

JA[ "debug.build_budget" ] = "コールドメッシュ構築予算（ミリ秒/フレーム）"
FR[ "debug.build_budget" ] = "Budget d’assemblage du maillage froid (ms/image)"
RU[ "debug.build_budget" ] = "Бюджет сборки холодной сетки (мс/кадр)"
JA[ "debug.prepare_target" ] = "コールドモデル準備目標（秒）"
FR[ "debug.prepare_target" ] = "Objectif de préparation du modèle froid (secondes)"
RU[ "debug.prepare_target" ] = "Целевое время подготовки холодной модели (секунды)"
JA[ "debug.catchup_budget" ] = "コールドキャッシュ処理のハード上限（ミリ秒/フレーム）"
FR[ "debug.catchup_budget" ] = "Limite stricte du cache froid (ms/image)"
RU[ "debug.catchup_budget" ] = "Жёсткий лимит холодного кэша (мс/кадр)"
JA[ "debug.queue_limit" ] = "キュー結合ソフト上限"
FR[ "debug.queue_limit" ] = "Seuil souple de fusion de file"
RU[ "debug.queue_limit" ] = "Мягкий порог объединения очереди"

local OVERRIDE_TRANSLATIONS = {
	zh = {
		[ "filter.override_model_column" ] = "模型",
		[ "filter.override_bodygroup_column" ] = "强制可隐藏身体组",
		[ "filter.override_id_column" ] = "ID",
		[ "filter.override_aim_help" ] = "瞄准一个实体，然后在下方选择其身体组。",
		[ "filter.override_select_bodygroup" ] = "从瞄准的模型选择身体组",
		[ "filter.override_add_selected" ] = "强制所选为可隐藏",
		[ "filter.override_aim_missing" ] = "请先瞄准实体并选择一个身体组。",
		[ "filter.override_remove_first" ] = "请先选择一个可隐藏覆盖。",
		[ "filter.override_clear" ] = "清空可隐藏覆盖",
		[ "filter.override_clear_confirm" ] = "移除全部按模型设置的可隐藏身体组覆盖？",
		[ "main.hideable_overrides" ] = "可隐藏身体组覆盖",
		[ "main.hideable_override_help" ] = "强制指定模型上的身体组可以受损。此设置具有最高优先级，会绕过身体组名称黑名单；即使该组只有一个子模型且没有空白选项，也会通过编译后的 MDL 身体部件布局识别其网格。",
		[ "menu.damage" ] = "破损与外观",
		[ "menu.filters" ] = "模型与身体组",
		[ "menu.debug" ] = "调试工具",
		[ "filter.page_intro" ] = "选择哪些模型和身体组可以产生程序化纹理破损。按模型设置的明确覆盖优先于下方更广泛的排除规则。",
		[ "main.filters_future" ] = "筛选更改仅影响后续命中。要移除已应用的破损，请使用“破损与外观”页面中的“修复”。",
		[ "main.layer_limit" ] = "最大受影响层数（0 = 无限）",
		[ "main.layer_help" ] = "每个相交的网格表面独立计为一层，并从子弹朝向的外侧向内部排序。不可破损的网格表面仍会占用一层；已有破洞不会。",
		[ "main.force_nocull" ] = "在破洞周围显示背面（$nocull）",
		[ "main.nocull_help" ] = "对生成的破损材质强制设置 $nocull 1，使撕裂开口不会呈现空洞的单面外壳。",
	},
	ja = {
		[ "filter.override_model_column" ] = "モデル",
		[ "filter.override_bodygroup_column" ] = "強制非表示ボディグループ",
		[ "filter.override_id_column" ] = "ID",
		[ "filter.override_aim_help" ] = "エンティティを照準し、下からボディグループを選択します。",
		[ "filter.override_select_bodygroup" ] = "照準中モデルのボディグループを選択",
		[ "filter.override_add_selected" ] = "選択項目を破損対象にする",
		[ "filter.override_aim_missing" ] = "先にエンティティを照準してボディグループを選択してください。",
		[ "filter.override_remove_first" ] = "先に非表示オーバーライドを選択してください。",
		[ "filter.override_clear" ] = "非表示オーバーライドを消去",
		[ "filter.override_clear_confirm" ] = "モデル別の非表示ボディグループ設定をすべて削除しますか？",
		[ "main.hideable_overrides" ] = "非表示ボディグループのオーバーライド",
		[ "main.hideable_override_help" ] = "特定モデルのボディグループを強制的に破損対象にします。最優先で名前ブラックリストを無視し、サブモデルが1つだけで空オプションがない場合も、コンパイル済みMDLのボディパーツ構成からメッシュを識別します。",
		[ "menu.damage" ] = "ダメージと外観",
		[ "menu.filters" ] = "モデルとボディグループ",
		[ "menu.debug" ] = "デバッグツール",
		[ "filter.page_intro" ] = "プロシージャルなテクスチャ破損を許可するモデルとボディグループを選びます。モデル別の明示的なオーバーライドは、下の一般的な除外ルールより優先されます。",
		[ "main.filters_future" ] = "変更は今後のヒットに適用されます。既存の破損を消すには「ダメージと外観」ページの修復を使用してください。",
		[ "main.layer_limit" ] = "最大破損レイヤー数（0 = 無制限）",
		[ "main.layer_help" ] = "交差する各メッシュ面を1レイヤーとして、弾丸側の外から内へ並べます。破損対象外のメッシュ面も数えますが、既存の穴は数えません。",
		[ "main.force_nocull" ] = "穴の周囲で裏面を表示（$nocull）",
		[ "main.nocull_help" ] = "生成する破損マテリアルに $nocull 1 を強制し、裂け目が空の片面シェルに見えないようにします。",
	},
	fr = {
		[ "filter.override_model_column" ] = "Modèle",
		[ "filter.override_bodygroup_column" ] = "Bodygroup masquable forcé",
		[ "filter.override_id_column" ] = "ID",
		[ "filter.override_aim_help" ] = "Visez une entité, puis choisissez l’un de ses bodygroups ci-dessous.",
		[ "filter.override_select_bodygroup" ] = "Choisir un bodygroup du modèle visé",
		[ "filter.override_add_selected" ] = "Forcer comme masquable",
		[ "filter.override_aim_missing" ] = "Visez une entité et choisissez d’abord un bodygroup.",
		[ "filter.override_remove_first" ] = "Sélectionnez d’abord un remplacement masquable.",
		[ "filter.override_clear" ] = "Effacer les remplacements masquables",
		[ "filter.override_clear_confirm" ] = "Supprimer tous les remplacements de bodygroups masquables par modèle ?",
		[ "main.hideable_overrides" ] = "Remplacements de bodygroups masquables",
		[ "main.hideable_override_help" ] = "Force un bodygroup d’un modèle précis à devenir endommageable. Cette règle est prioritaire, ignore la liste noire des noms et utilise la structure compilée du MDL même si le groupe n’a qu’un sous-modèle et aucune option vide.",
		[ "menu.damage" ] = "Dégâts et apparence",
		[ "menu.filters" ] = "Modèles et bodygroups",
		[ "menu.debug" ] = "Outils de débogage",
		[ "filter.page_intro" ] = "Choisissez les modèles et bodygroups pouvant recevoir des dégâts de texture procéduraux. Les remplacements propres à un modèle ont priorité sur les exclusions générales ci-dessous.",
		[ "main.filters_future" ] = "Les changements concernent les futurs impacts. Utilisez Réparer dans la page Dégâts et apparence pour retirer les dégâts déjà appliqués.",
		[ "main.layer_limit" ] = "Nombre maximal de couches touchées (0 = illimité)",
		[ "main.layer_help" ] = "Chaque surface de maillage traversée forme une couche, de l’extérieur vers l’intérieur. Les surfaces non endommageables comptent aussi, mais pas les trous existants.",
		[ "main.force_nocull" ] = "Afficher les faces arrière autour des trous ($nocull)",
		[ "main.nocull_help" ] = "Force $nocull 1 sur les matériaux endommagés générés afin que les ouvertures ne ressemblent pas à une coque vide à face unique.",
	},
	ru = {
		[ "filter.override_model_column" ] = "Модель",
		[ "filter.override_bodygroup_column" ] = "Принудительно скрываемая бодигруппа",
		[ "filter.override_id_column" ] = "ID",
		[ "filter.override_aim_help" ] = "Наведитесь на объект и выберите его бодигруппу ниже.",
		[ "filter.override_select_bodygroup" ] = "Выберите бодигруппу наведённой модели",
		[ "filter.override_add_selected" ] = "Сделать выбранную скрываемой",
		[ "filter.override_aim_missing" ] = "Сначала наведитесь на объект и выберите бодигруппу.",
		[ "filter.override_remove_first" ] = "Сначала выберите переопределение.",
		[ "filter.override_clear" ] = "Очистить переопределения",
		[ "filter.override_clear_confirm" ] = "Удалить все переопределения скрываемых бодигрупп моделей?",
		[ "main.hideable_overrides" ] = "Переопределения скрываемых бодигрупп",
		[ "main.hideable_override_help" ] = "Принудительно разрешает повреждение бодигруппы конкретной модели. Имеет высший приоритет, игнорирует чёрный список имён и использует структуру скомпилированного MDL, даже если у группы одна подмодель и нет пустого варианта.",
		[ "menu.damage" ] = "Повреждения и вид",
		[ "menu.filters" ] = "Модели и бодигруппы",
		[ "menu.debug" ] = "Инструменты отладки",
		[ "filter.page_intro" ] = "Выберите модели и бодигруппы, которые могут получать процедурные повреждения текстуры. Явные переопределения для модели имеют приоритет над общими исключениями ниже.",
		[ "main.filters_future" ] = "Изменения действуют на будущие попадания. Используйте восстановление на странице «Повреждения и вид», чтобы убрать уже нанесённые повреждения.",
		[ "main.layer_limit" ] = "Максимум затрагиваемых слоёв (0 = без ограничения)",
		[ "main.layer_help" ] = "Каждая пересечённая поверхность меша считается отдельным слоем от внешней стороны внутрь. Неповреждаемые поверхности тоже считаются, а существующие отверстия — нет.",
		[ "main.force_nocull" ] = "Показывать обратные стороны вокруг отверстий ($nocull)",
		[ "main.nocull_help" ] = "Принудительно задаёт $nocull 1 созданным материалам повреждений, чтобы разрывы не выглядели пустой односторонней оболочкой.",
	},
}

for code, values in pairs( OVERRIDE_TRANSLATIONS ) do
	local locale = code == "zh" and ZH or code == "ja" and JA
		or code == "fr" and FR or RU
	for key, value in pairs( values ) do locale[ key ] = value end
end

-- Keep the performance page keyed instead of extending DEBUG_TRANSLATIONS'
-- positional arrays. This makes future labels safe to insert or reorder.
local PERFORMANCE_TRANSLATIONS = {
	en = {
		[ "menu.performance" ] = "Performance",
		[ "performance.intro" ] = "Control how much client CPU time the addon may use per real rendered frame. Higher budgets finish work sooner but can cause larger frame-time spikes.",
		[ "performance.presets" ] = "Performance presets",
		[ "performance.gentle" ] = "Smooth gameplay (low budget)",
		[ "performance.balanced" ] = "Balanced (recommended)",
		[ "performance.fast" ] = "Fast processing (higher frame cost)",
		[ "performance.aggressive" ] = "Aggressive (may stutter)",
		[ "performance.preset_help" ] = "Balanced is the install/update default and equals 1.25× the former Aggressive profile. Fast is 2× Balanced, Aggressive is 4×, and manual sliders reach 8×. Presets change only processing budgets; choose Smooth if higher values cause frame spikes. Damage appearance, filters, and debug options are unchanged.",
		[ "performance.background" ] = "Background model preparation",
		[ "performance.io_budget" ] = "Persistent cache I/O budget (ms/frame)",
		[ "performance.build_budget" ] = "Cold mesh packing budget (ms/frame)",
		[ "performance.catchup_budget" ] = "Urgent cold-cache limit (ms/frame)",
		[ "performance.per_hit" ] = "Per-hit processing",
		[ "performance.query_budget" ] = "Impact mesh-query budget (ms/frame)",
		[ "performance.projection_budget" ] = "Damage projection and painting budget (ms/frame)",
		[ "performance.rtx" ] = "RTX Remix",
		[ "performance.rtx_background" ] = "Background preparation limit (ms/frame)",
		[ "performance.rtx_catchup" ] = "Urgent preparation limit (ms/frame)",
		[ "performance.rtx_help" ] = "These two limits are used only by detected RTX Remix clients. Vanilla Garry's Mod uses the normal cold-cache budgets above.",
		[ "performance.live_help" ] = "Changes apply immediately. Milliseconds are CPU time per real Source frame; DLSS-generated frames do not run addon processing.",
		[ "performance.runtime" ] = "Detected runtime: {{runtime}}",
		[ "performance.runtime_vanilla" ] = "Vanilla Garry's Mod",
		[ "performance.runtime_rtx" ] = "RTX Remix",
	},
	zh = {
		[ "menu.performance" ] = "性能",
		[ "performance.intro" ] = "控制插件在每个实际渲染帧中可使用的客户端 CPU 时间。预算越高，处理完成越快，但可能产生更明显的帧时间峰值。",
		[ "performance.presets" ] = "性能预设",
		[ "performance.gentle" ] = "流畅游戏（低预算）",
		[ "performance.balanced" ] = "平衡（推荐）",
		[ "performance.fast" ] = "快速处理（较高帧负载）",
		[ "performance.aggressive" ] = "极限处理（可能卡顿）",
		[ "performance.preset_help" ] = "“平衡”是安装或更新后的默认值，相当于旧“极限”预设的 1.25 倍。“快速”为“平衡”的 2 倍，“极限”为 4 倍，手动滑块最高为 8 倍。预设仅修改处理预算；如果较高数值导致帧时间峰值，请选择“流畅游戏”。不会更改破损外观、筛选或调试选项。",
		[ "performance.background" ] = "后台模型准备",
		[ "performance.io_budget" ] = "持久缓存 I/O 预算（毫秒/帧）",
		[ "performance.build_budget" ] = "冷网格打包预算（毫秒/帧）",
		[ "performance.catchup_budget" ] = "紧急冷缓存上限（毫秒/帧）",
		[ "performance.per_hit" ] = "每次命中处理",
		[ "performance.query_budget" ] = "命中网格查询预算（毫秒/帧）",
		[ "performance.projection_budget" ] = "破损投影与绘制预算（毫秒/帧）",
		[ "performance.rtx" ] = "RTX Remix",
		[ "performance.rtx_background" ] = "后台准备上限（毫秒/帧）",
		[ "performance.rtx_catchup" ] = "紧急准备上限（毫秒/帧）",
		[ "performance.rtx_help" ] = "只有检测到 RTX Remix 的客户端才使用这两个上限。原版 Garry's Mod 使用上方普通冷缓存预算。",
		[ "performance.live_help" ] = "更改会立即生效。毫秒值表示每个实际 Source 帧的 CPU 时间；DLSS 生成帧不会运行插件处理。",
		[ "performance.runtime" ] = "检测到的运行环境：{{runtime}}",
		[ "performance.runtime_vanilla" ] = "原版 Garry's Mod",
		[ "performance.runtime_rtx" ] = "RTX Remix",
	},
	ja = {
		[ "menu.performance" ] = "パフォーマンス",
		[ "performance.intro" ] = "実際に描画される各フレームでアドオンが使用できるクライアント CPU 時間を調整します。予算を増やすと処理は早く完了しますが、フレーム時間のスパイクが大きくなる場合があります。",
		[ "performance.presets" ] = "パフォーマンスプリセット",
		[ "performance.gentle" ] = "滑らかなゲームプレイ（低予算）",
		[ "performance.balanced" ] = "バランス（推奨）",
		[ "performance.fast" ] = "高速処理（フレーム負荷増）",
		[ "performance.aggressive" ] = "高負荷（カクつく場合あり）",
		[ "performance.preset_help" ] = "「バランス」は新規インストールおよび更新後の既定値で、旧「高負荷」プリセットの1.25倍です。「高速処理」はバランスの2倍、「高負荷」は4倍、手動スライダーは最大8倍です。プリセットは処理予算のみ変更します。高い値でフレーム時間が跳ねる場合は「滑らかなゲームプレイ」を選んでください。破損の外観、フィルター、デバッグ設定は変更しません。",
		[ "performance.background" ] = "バックグラウンドモデル準備",
		[ "performance.io_budget" ] = "永続キャッシュ I/O 予算（ms/フレーム）",
		[ "performance.build_budget" ] = "コールドメッシュ構築予算（ms/フレーム）",
		[ "performance.catchup_budget" ] = "緊急コールドキャッシュ上限（ms/フレーム）",
		[ "performance.per_hit" ] = "ヒットごとの処理",
		[ "performance.query_budget" ] = "着弾メッシュ検索予算（ms/フレーム）",
		[ "performance.projection_budget" ] = "破損投影・描画予算（ms/フレーム）",
		[ "performance.rtx" ] = "RTX Remix",
		[ "performance.rtx_background" ] = "バックグラウンド準備上限（ms/フレーム）",
		[ "performance.rtx_catchup" ] = "緊急準備上限（ms/フレーム）",
		[ "performance.rtx_help" ] = "この2つの上限は RTX Remix を検出したクライアントだけで使用します。通常版 Garry's Mod は上の通常コールドキャッシュ予算を使用します。",
		[ "performance.live_help" ] = "変更は直ちに反映されます。ミリ秒は実際の Source フレームごとの CPU 時間です。DLSS の生成フレームではアドオン処理は実行されません。",
		[ "performance.runtime" ] = "検出された環境：{{runtime}}",
		[ "performance.runtime_vanilla" ] = "通常版 Garry's Mod",
		[ "performance.runtime_rtx" ] = "RTX Remix",
	},
	fr = {
		[ "menu.performance" ] = "Performances",
		[ "performance.intro" ] = "Contrôlez le temps CPU client que l’addon peut utiliser par image réellement rendue. Des budgets plus élevés terminent le traitement plus vite, mais peuvent augmenter les pics de temps d’image.",
		[ "performance.presets" ] = "Préréglages de performances",
		[ "performance.gentle" ] = "Jeu fluide (budget réduit)",
		[ "performance.balanced" ] = "Équilibré (recommandé)",
		[ "performance.fast" ] = "Traitement rapide (coût par image accru)",
		[ "performance.aggressive" ] = "Agressif (risque de saccades)",
		[ "performance.preset_help" ] = "Équilibré est le réglage par défaut après installation ou mise à jour et vaut 1,25× l’ancien profil Agressif. Rapide vaut 2× Équilibré, Agressif 4× et les curseurs manuels atteignent 8×. Les préréglages modifient uniquement les budgets ; choisissez Jeu fluide si les valeurs élevées provoquent des pics de temps d’image. L’apparence des dégâts, les filtres et le débogage restent inchangés.",
		[ "performance.background" ] = "Préparation des modèles en arrière-plan",
		[ "performance.io_budget" ] = "Budget E/S du cache persistant (ms/image)",
		[ "performance.build_budget" ] = "Budget d’assemblage du maillage froid (ms/image)",
		[ "performance.catchup_budget" ] = "Limite urgente du cache froid (ms/image)",
		[ "performance.per_hit" ] = "Traitement de chaque impact",
		[ "performance.query_budget" ] = "Budget de recherche du maillage touché (ms/image)",
		[ "performance.projection_budget" ] = "Budget de projection et de peinture (ms/image)",
		[ "performance.rtx" ] = "RTX Remix",
		[ "performance.rtx_background" ] = "Limite de préparation en arrière-plan (ms/image)",
		[ "performance.rtx_catchup" ] = "Limite de préparation urgente (ms/image)",
		[ "performance.rtx_help" ] = "Ces deux limites sont utilisées uniquement lorsqu’un client RTX Remix est détecté. Garry's Mod standard utilise les budgets normaux du cache froid ci-dessus.",
		[ "performance.live_help" ] = "Les changements s’appliquent immédiatement. Les millisecondes représentent le temps CPU par image Source réelle ; les images générées par DLSS n’exécutent pas le traitement de l’addon.",
		[ "performance.runtime" ] = "Environnement détecté : {{runtime}}",
		[ "performance.runtime_vanilla" ] = "Garry's Mod standard",
		[ "performance.runtime_rtx" ] = "RTX Remix",
	},
	ru = {
		[ "menu.performance" ] = "Производительность",
		[ "performance.intro" ] = "Настройте время CPU клиента, которое аддон может использовать за один реально отрисованный кадр. Больший бюджет ускоряет обработку, но может усилить скачки времени кадра.",
		[ "performance.presets" ] = "Профили производительности",
		[ "performance.gentle" ] = "Плавная игра (малый бюджет)",
		[ "performance.balanced" ] = "Сбалансированный (рекомендуется)",
		[ "performance.fast" ] = "Быстрая обработка (выше нагрузка на кадр)",
		[ "performance.aggressive" ] = "Агрессивный (возможны подтормаживания)",
		[ "performance.preset_help" ] = "«Сбалансированный» — значение по умолчанию после установки или обновления; это 1,25× прежнего профиля «Агрессивный». «Быстрый» равен 2× сбалансированного, «Агрессивный» — 4×, а ручные ползунки доходят до 8×. Профили меняют только бюджеты обработки; выберите «Плавная игра», если высокие значения вызывают скачки времени кадра. Вид повреждений, фильтры и отладка не меняются.",
		[ "performance.background" ] = "Фоновая подготовка моделей",
		[ "performance.io_budget" ] = "Бюджет ввода-вывода постоянного кэша (мс/кадр)",
		[ "performance.build_budget" ] = "Бюджет сборки холодной сетки (мс/кадр)",
		[ "performance.catchup_budget" ] = "Срочный предел холодного кэша (мс/кадр)",
		[ "performance.per_hit" ] = "Обработка каждого попадания",
		[ "performance.query_budget" ] = "Бюджет поиска сетки попадания (мс/кадр)",
		[ "performance.projection_budget" ] = "Бюджет проекции и рисования повреждения (мс/кадр)",
		[ "performance.rtx" ] = "RTX Remix",
		[ "performance.rtx_background" ] = "Предел фоновой подготовки (мс/кадр)",
		[ "performance.rtx_catchup" ] = "Предел срочной подготовки (мс/кадр)",
		[ "performance.rtx_help" ] = "Эти два предела используются только при обнаружении клиента RTX Remix. Обычный Garry's Mod использует стандартные бюджеты холодного кэша выше.",
		[ "performance.live_help" ] = "Изменения применяются сразу. Миллисекунды означают время CPU на реальный кадр Source; кадры, созданные DLSS, не запускают обработку аддона.",
		[ "performance.runtime" ] = "Обнаруженная среда: {{runtime}}",
		[ "performance.runtime_vanilla" ] = "Обычный Garry's Mod",
		[ "performance.runtime_rtx" ] = "RTX Remix",
	},
}

local PERFORMANCE_LOCALES = { en = EN, zh = ZH, ja = JA, fr = FR, ru = RU }
for code, values in pairs( PERFORMANCE_TRANSLATIONS ) do
	local locale = PERFORMANCE_LOCALES[ code ]
	for key, value in pairs( values ) do locale[ key ] = value end
end

I.locales = { en = EN, zh = ZH, ja = JA, fr = FR, ru = RU }

function I.DetectLanguage()
	local convar = GetConVar( "gmod_language" )
	local value = string.lower( convar and convar:GetString() or "en" )
	value = string.gsub( value, "[%s%-]+", "_" )
	local function begins( prefix ) return string.sub( value, 1, #prefix ) == prefix end
	local function contains( part ) return string.find( value, part, 1, true ) ~= nil end
	if begins( "zh" ) or value == "schinese" or value == "tchinese"
	or value == "chs" or value == "cht" or contains( "chinese" )
	or contains( "hans" ) or contains( "hant" ) then return "zh" end
	if begins( "ja" ) or begins( "jp" ) or contains( "japanese" ) then return "ja" end
	if begins( "fr" ) or contains( "french" ) or contains( "francais" ) then return "fr" end
	if begins( "ru" ) or contains( "russian" ) then return "ru" end
	return DEFAULT_LANGUAGE
end

function I.Reload()
	local convar = GetConVar( "bbs_language" )
	local selected = string.lower( convar and convar:GetString() or "auto" )
	if selected == "" or selected == "auto" then selected = I.DetectLanguage() end
	I.language = SUPPORTED[ selected ] and selected or DEFAULT_LANGUAGE
end

function I.GetLanguageOptions()
	return { "auto", "en", "zh", "ja", "fr", "ru" }
end

function BBS.L( key, variables )
	local selected = I.locales[ I.language or DEFAULT_LANGUAGE ] or EN
	local text = selected[ key ] or EN[ key ] or tostring( key )
	if variables then
		text = string.gsub( text, "{{%s*([%w_]+)%s*}}", function( name )
			local value = variables[ name ]
			return value == nil and "{{" .. name .. "}}" or tostring( value )
		end )
	end
	return text
end

I.Reload()

local function ReloadLanguage( rebuildSpawnMenu )
	I.Reload()
	if rebuildSpawnMenu then
		timer.Simple( 0, function() RunConsoleCommand( "spawnmenu_reload" ) end )
	end
end

cvars.AddChangeCallback( "bbs_language", function()
	ReloadLanguage( true )
end, "BBS.LanguageOverrideChanged" )

cvars.AddChangeCallback( "gmod_language", function()
	local convar = GetConVar( "bbs_language" )
	if convar and ( convar:GetString() == "auto" or convar:GetString() == "" ) then
		-- Sandbox also rebuilds for this convar, but callback order is undefined.
		-- Queue our own rebuild so translated labels always use the new locale.
		ReloadLanguage( true )
	end
end, "BBS.GModLanguageChanged" )

hook.Add( "InitPostEntity", "BBS.DetectLanguageAfterInit", function()
	local before = I.language
	I.Reload()
	if before ~= I.language then RunConsoleCommand( "spawnmenu_reload" ) end
end )
