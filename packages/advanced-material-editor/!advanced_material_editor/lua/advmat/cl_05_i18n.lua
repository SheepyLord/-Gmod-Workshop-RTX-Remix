--[[---------------------------------------------------------------------------
	Advanced Material Editor - client-side localisation

	"auto" follows gmod_language.  English is also the stable source language:
	AdvMat.LText can translate existing labels without making every VGUI call
	carry a localisation key.  New text should still use AdvMat.L directly.
-----------------------------------------------------------------------------]]

if not CLIENT then return end

AdvMat = AdvMat or {}
AdvMat.I18N = AdvMat.I18N or {}

local I = AdvMat.I18N
local DEFAULT = "en"
local SUPPORTED = { en = true, zh = true, ja = true, ko = true, fr = true, ru = true }
local ORDER = { "en", "zh", "ja", "ko", "fr", "ru" }

CreateClientConVar( "advmat_language", "auto", true, false,
	"Advanced Material Editor language; auto follows gmod_language." )

I.locales = { en = {}, zh = {}, ja = {}, ko = {}, fr = {}, ru = {} }
I.reverse = {}

local function SameTranslationVector( left, right )
	for _, lang in ipairs( ORDER ) do
		if I.locales[ lang ][ left ] ~= I.locales[ lang ][ right ] then return false end
	end
	return true
end

local function IndexReverse( text, key )
	if text == "" then return end
	local previous = I.reverse[ text ]
	if previous == nil then
		I.reverse[ text ] = key
	elseif previous ~= false and previous ~= key
	and not SameTranslationVector( previous, key ) then
		-- The same visible phrase can mean different controls in different
		-- locales (for example French "Ajuster" is both Fit and Adjust).  There
		-- is no key metadata on legacy VGUI labels, so leaving an ambiguous phrase
		-- unchanged is safer than silently translating it to the wrong action.
		I.reverse[ text ] = false
	end
end

local function ConVarString( name, fallback )
	local convar = GetConVar( name )
	return convar and convar.GetString and convar:GetString() or fallback
end

-- Keeping all six forms on one row makes omissions visible in review and
-- impossible at runtime.  Product and engine names deliberately stay native.
local function R( key, en, zh, ja, ko, fr, ru )
	local values = { en, zh, ja, ko, fr, ru }
	for n, lang in ipairs( ORDER ) do I.locales[ lang ][ key ] = values[ n ] end
	for _, text in ipairs( values ) do IndexReverse( text, key ) end
end

R( "language.title", "Interface language", "界面语言", "表示言語", "인터페이스 언어", "Langue de l’interface", "Язык интерфейса" )
R( "language.auto", "Automatic (Garry's Mod language)", "自动（跟随 Garry's Mod 语言）", "自動（Garry's Mod の言語に従う）", "자동(Garry's Mod 언어 따름)", "Automatique (langue de Garry's Mod)", "Автоматически (язык Garry's Mod)" )
R( "language.en", "English", "English", "English", "English", "English", "English" )
R( "language.zh", "简体中文", "简体中文", "简体中文", "简体中文", "简体中文", "简体中文" )
R( "language.ja", "日本語", "日本語", "日本語", "日本語", "日本語", "日本語" )
R( "language.ko", "한국어", "한국어", "한국어", "한국어", "한국어", "한국어" )
R( "language.fr", "Français", "Français", "Français", "Français", "Français", "Français" )
R( "language.ru", "Русский", "Русский", "Русский", "Русский", "Русский", "Русский" )

R( "tool.name", "Advanced Material Editor", "高级材质编辑器", "高機能マテリアルエディター", "고급 재질 편집기", "Éditeur de matériaux avancé", "Расширенный редактор материалов" )
R( "tool.desc", "Edit any VMT parameter of a model's sub-materials, live.", "实时编辑模型子材质的任意 VMT 参数。", "モデルのサブマテリアルにある任意の VMT パラメーターをリアルタイムで編集します。", "모델 하위 재질의 모든 VMT 매개변수를 실시간으로 편집합니다.", "Modifiez en direct tout paramètre VMT des sous-matériaux d’un modèle.", "Редактируйте любые параметры VMT подматериалов модели в реальном времени." )
R( "tool.left", "Open the material editor", "打开材质编辑器", "マテリアルエディターを開く", "재질 편집기 열기", "Ouvrir l’éditeur de matériaux", "Открыть редактор материалов" )
R( "tool.left_world", "Edit the map surface you are aiming at", "编辑瞄准的地图表面", "照準中のマップ表面を編集", "조준 중인 맵 표면 편집", "Modifier la surface de la carte visée", "Редактировать поверхность карты под прицелом" )
R( "tool.right", "Copy this entity's material overrides", "复制此实体的材质覆盖", "このエンティティのマテリアル上書きをコピー", "이 엔티티의 재질 재정의 복사", "Copier les remplacements de matériau de cette entité", "Копировать переопределения материалов объекта" )
R( "tool.right_paste", "Paste the copied material overrides", "粘贴已复制的材质覆盖", "コピーしたマテリアル上書きを貼り付け", "복사한 재질 재정의 붙여넣기", "Coller les remplacements de matériau copiés", "Вставить скопированные переопределения материалов" )
R( "tool.reload", "Edit your own player model", "编辑自己的玩家模型", "自分のプレイヤーモデルを編集", "내 플레이어 모델 편집", "Modifier votre propre modèle de joueur", "Редактировать свою модель игрока" )
R( "tool.reload_strip", "Remove every override from this entity", "移除此实体的所有覆盖", "このエンティティの上書きをすべて削除", "이 엔티티의 모든 재정의 제거", "Supprimer tous les remplacements de cette entité", "Удалить все переопределения с объекта" )
R( "tool.help_left", "Left click a prop, ragdoll or player to open the material editor.", "左键点击物件、布娃娃或玩家以打开材质编辑器。", "プロップ、ラグドール、プレイヤーを左クリックしてマテリアルエディターを開きます。", "프롭, 래그돌 또는 플레이어를 왼쪽 클릭해 재질 편집기를 엽니다.", "Cliquez gauche sur un prop, un ragdoll ou un joueur pour ouvrir l’éditeur de matériaux.", "Щёлкните левой кнопкой по объекту, рэгдоллу или игроку, чтобы открыть редактор материалов." )
R( "tool.help_reload", "Reload (R) opens it on your own player model.", "按重新装填键（R）可为自己的玩家模型打开编辑器。", "リロード（R）で自分のプレイヤーモデルを開きます。", "재장전(R)을 누르면 내 플레이어 모델에서 엽니다.", "Recharger (R) l’ouvre sur votre propre modèle de joueur.", "Перезарядка (R) открывает редактор для вашей модели игрока." )
R( "tool.help_world", "Shift + left click edits the map surface you are aiming at.", "Shift + 左键可编辑瞄准的地图表面。", "Shift + 左クリックで照準中のマップ表面を編集します。", "Shift + 왼쪽 클릭으로 조준 중인 맵 표면을 편집합니다.", "Maj + clic gauche modifie la surface de la carte que vous visez.", "Shift + левая кнопка редактирует поверхность карты под прицелом." )
R( "tool.help_strip", "Shift + reload strips every override from the entity you are aiming at.", "Shift + 重新装填可移除瞄准实体的所有覆盖。", "Shift + リロードで照準中のエンティティから全上書きを削除します。", "Shift + 재장전으로 조준 중인 엔티티의 모든 재정의를 제거합니다.", "Maj + recharger supprime tous les remplacements de l’entité visée.", "Shift + перезарядка удаляет все переопределения с объекта под прицелом." )
R( "tool.save_to", "Save edits to", "将编辑保存到", "編集の保存先", "편집 저장 대상", "Enregistrer les modifications dans", "Область сохранения изменений" )
R( "tool.scope_model_recommended", "Every prop with this model (recommended)", "使用此模型的所有物件（推荐）", "このモデルを使う全プロップ（推奨）", "이 모델을 사용하는 모든 프롭(권장)", "Tous les props utilisant ce modèle (recommandé)", "Все объекты с этой моделью (рекомендуется)" )
R( "tool.live_drag", "Live preview while dragging", "拖动时实时预览", "ドラッグ中にライブプレビュー", "드래그 중 실시간 미리보기", "Aperçu en direct pendant le glissement", "Предпросмотр во время перетаскивания" )
R( "tool.live_help", "Shows changes on your screen immediately. Others only see them once you press Save.", "立即在你的屏幕上显示更改；其他玩家仅在你按下“保存”后才能看到。", "変更は自分の画面にすぐ表示され、他のプレイヤーには「保存」後に表示されます。", "변경 사항이 내 화면에 즉시 표시됩니다. 다른 플레이어는 ‘저장’을 누른 뒤에 볼 수 있습니다.", "Affiche immédiatement les changements sur votre écran. Les autres ne les voient qu’après l’enregistrement.", "Сразу показывает изменения на вашем экране. Остальные увидят их только после сохранения." )
R( "tool.list_all", "List every parameter the shader supports", "列出着色器支持的所有参数", "シェーダーが対応する全パラメーターを表示", "셰이더가 지원하는 모든 매개변수 표시", "Lister tous les paramètres pris en charge par le shader", "Показать все параметры, поддерживаемые шейдером" )
R( "tool.list_help", "Off: only show parameters the material already defines.", "关闭时：仅显示材质已定义的参数。", "オフでは、マテリアルに既に定義されたパラメーターだけを表示します。", "끄면 재질에 이미 정의된 매개변수만 표시합니다.", "Désactivé : n’affiche que les paramètres déjà définis par le matériau.", "Если выключено, показываются только уже заданные в материале параметры." )
R( "tool.browser", "Open the saved-overrides browser", "打开已保存覆盖浏览器", "保存済み上書きブラウザーを開く", "저장된 재정의 브라우저 열기", "Ouvrir le navigateur des remplacements enregistrés", "Открыть список сохранённых переопределений" )
R( "tool.reapply", "Re-apply every override now", "立即重新应用所有覆盖", "全上書きを今すぐ再適用", "지금 모든 재정의 다시 적용", "Réappliquer tous les remplacements maintenant", "Повторно применить все переопределения" )
R( "tool.resync", "Re-download overrides from the server", "从服务器重新下载覆盖", "サーバーから上書きを再取得", "서버에서 재정의 다시 다운로드", "Retélécharger les remplacements depuis le serveur", "Повторно загрузить переопределения с сервера" )
R( "tool.rebuild", "Rebuild every generated texture", "重新生成所有已生成纹理", "生成テクスチャをすべて再構築", "생성된 모든 텍스처 다시 빌드", "Reconstruire toutes les textures générées", "Пересоздать все сгенерированные текстуры" )
R( "tool.make_help", "Every texture parameter has Make for generating a normal, Phong exponent or reflection map from the material colours, and Edit for painting, recolouring or cutting holes by selecting directly on the model.", "每个纹理参数都有“生成”按钮，可根据材质颜色生成法线、Phong 指数或反射贴图；“编辑”按钮可直接在模型上选择区域进行绘制、重新着色或挖出透明区域。", "各テクスチャパラメーターの「作成」は色から法線・Phong 指数・反射マップを生成し、「編集」はモデル上で直接選択して描画、色変更、穴開けを行います。", "각 텍스처 매개변수의 ‘만들기’는 재질 색상으로 노멀, Phong 지수 또는 반사 맵을 만들고, ‘편집’은 모델에서 직접 선택해 그리기, 색상 변경 또는 구멍 내기를 수행합니다.", "Chaque paramètre de texture propose Créer pour générer une normal map, une map d’exposant Phong ou un masque de réflexion depuis les couleurs, et Modifier pour peindre, recolorer ou découper directement via le modèle.", "У каждого параметра текстуры есть «Создать» для генерации карты нормалей, экспоненты Phong или отражений по цветам материала и «Изменить» для рисования, перекраски и вырезания областей прямо на модели." )
R( "tool.storage_help", "Overrides are stored on the server in garrysmod/data/advmat/overrides.json and reapplied when the map loads. Generated textures remain editable recipes. Painted textures also relay a verified PNG through the server for clients that cannot rebuild them at full resolution.", "覆盖保存在服务器的 garrysmod/data/advmat/overrides.json 中，并会在地图载入时重新应用。生成纹理仍以可编辑的配方保存；绘制纹理还会通过服务器传送经过验证的 PNG，供无法以完整分辨率重建纹理的客户端使用。", "上書きはサーバーの garrysmod/data/advmat/overrides.json に保存され、マップ読み込み時に再適用されます。生成テクスチャは編集可能なレシピとして保持されます。手描きテクスチャは、フル解像度で再構築できないクライアント向けに、検証済みの PNG もサーバー経由で転送します。", "재정의는 서버의 garrysmod/data/advmat/overrides.json에 저장되고 맵을 불러올 때 다시 적용됩니다. 생성된 텍스처는 편집 가능한 설정으로 유지됩니다. 페인팅한 텍스처는 전체 해상도로 다시 만들 수 없는 클라이언트를 위해 검증된 PNG도 서버를 통해 전송합니다.", "Les remplacements sont stockés sur le serveur dans garrysmod/data/advmat/overrides.json et réappliqués au chargement de la carte. Les textures générées restent des recettes modifiables. Pour les clients incapables de les reconstruire en pleine résolution, les textures peintes transmettent également un PNG vérifié par le serveur.", "Переопределения хранятся на сервере в garrysmod/data/advmat/overrides.json и применяются при загрузке карты. Созданные текстуры остаются редактируемыми рецептами. Для клиентов, которые не могут восстановить нарисованную текстуру в полном разрешении, сервер также передаёт проверенный PNG." )

-- RTX Remix uses a separate PBR profile, renderer bridge and interface.  These
-- labels deliberately describe Remix's actual hash-wide replacement scope and
-- distinguish live native writing from the export-only fallback.
R( "rtx.backend", "Material editor mode", "材质编辑器模式", "マテリアルエディターのモード", "재질 편집기 모드", "Mode de l’éditeur de matériaux", "Режим редактора материалов" )
R( "rtx.backend_auto", "Automatic detection", "自动检测", "自動検出", "자동 감지", "Détection automatique", "Автоопределение" )
R( "rtx.backend_vanilla", "Vanilla Source", "原版 Source", "標準 Source", "기본 Source", "Source d’origine", "Обычный Source" )
R( "rtx.backend_rtx", "RTX Remix", "RTX Remix", "RTX Remix", "RTX Remix", "RTX Remix", "RTX Remix" )
R( "rtx.backend_help", "Automatic detection opens the RTX Remix editor only when the required client APIs are available. Vanilla and RTX profiles are stored and applied separately.", "仅当所需的客户端 API 可用时，自动检测才会打开 RTX Remix 编辑器。原版材质覆盖与 RTX 配置会分开保存和应用。", "自動検出では、必要なクライアント API が利用できる場合にのみ RTX Remix エディターを開きます。標準版の上書きと RTX プロファイルは別々に保存・適用されます。", "자동 감지는 필요한 클라이언트 API를 사용할 수 있을 때만 RTX Remix 편집기를 엽니다. 기본 재질 재정의와 RTX 프로필은 서로 별도로 저장되고 적용됩니다.", "La détection automatique n’ouvre l’éditeur RTX Remix que si les API clientes requises sont disponibles. Les remplacements d’origine et les profils RTX sont enregistrés et appliqués séparément.", "При автоопределении редактор RTX Remix открывается только при наличии необходимых клиентских API. Обычные переопределения и профили RTX хранятся и применяются раздельно." )

R( "rtx.title", "Advanced Material Editor — RTX Remix", "高级材质编辑器 — RTX Remix", "高機能マテリアルエディター — RTX Remix", "고급 재질 편집기 — RTX Remix", "Éditeur de matériaux avancé — RTX Remix", "Расширенный редактор материалов — RTX Remix" )
R( "rtx.scope_hash", "Scope: every occurrence of the captured texture hash", "作用范围：捕获到的纹理哈希的每一处使用位置", "適用範囲：キャプチャしたテクスチャハッシュのすべての使用箇所", "적용 범위: 캡처된 텍스처 해시가 사용된 모든 곳", "Portée : chaque utilisation du hachage de texture capturé", "Область: все места использования захваченного хеша текстуры" )
R( "rtx.live_world", "Live RTX world preview", "在世界中实时预览 RTX 效果", "ワールド内で RTX をライブプレビュー", "월드에서 RTX 실시간 미리보기", "Aperçu RTX en direct dans le monde", "Предпросмотр RTX в игровом мире" )
R( "rtx.remove", "Remove override", "移除覆盖", "上書きを削除", "재정의 제거", "Supprimer le remplacement", "Удалить переопределение" )
R( "rtx.surface", "Material", "材质", "マテリアル", "재질", "Matériau", "Материал" )
R( "rtx.graph", "Shader graph", "着色器节点图", "シェーダーグラフ", "셰이더 그래프", "Graphe de shader", "Граф шейдера" )
R( "rtx.diagnostics", "Diagnostics", "诊断", "診断", "진단", "Diagnostic", "Диагностика" )
R( "rtx.source.tab", "Source / VMT", "Source / VMT", "Source / VMT", "Source / VMT", "Source / VMT", "Source / VMT" )
R( "rtx.source.intro", "Edit the original Source VMT parameters. Source overrides are saved separately from RTX Remix profiles; many Source shading parameters do not affect Remix.", "编辑原始 Source VMT 参数。Source 覆盖与 RTX Remix 配置分开保存；许多 Source 着色参数不会影响 Remix。", "元の Source VMT パラメーターを編集します。Source の上書きは RTX Remix プロファイルとは別に保存されます。Source のシェーディング設定の多くは Remix には影響しません。", "원본 Source VMT 매개변수를 편집합니다. Source 재정의는 RTX Remix 프로필과 별도로 저장되며, 많은 Source 셰이딩 매개변수는 Remix에 영향을 주지 않습니다.", "Modifiez les paramètres VMT Source d’origine. Les remplacements Source sont enregistrés séparément des profils RTX Remix ; de nombreux paramètres d’ombrage Source n’affectent pas Remix.", "Редактирование исходных параметров Source VMT. Переопределения Source сохраняются отдельно от профилей RTX Remix; многие параметры шейдинга Source не влияют на Remix." )
R( "rtx.source.slot", "Source slot {{slot}}: {{material}}", "Source 槽位 {{slot}}：{{material}}", "Source スロット {{slot}}：{{material}}", "Source 슬롯 {{slot}}: {{material}}", "Emplacement Source {{slot}} : {{material}}", "Слот Source {{slot}}: {{material}}" )
R( "rtx.source.save_target", "Source save target", "Source 保存目标", "Source の保存先", "Source 저장 대상", "Cible d’enregistrement Source", "Область сохранения Source" )
R( "rtx.source.live_preview", "Live Source world preview", "在世界中实时预览 Source 效果", "ワールド内で Source をライブプレビュー", "월드에서 Source 실시간 미리보기", "Aperçu Source en direct dans le monde", "Предпросмотр Source в игровом мире" )
R( "rtx.source.saved", "Source material overrides saved.", "Source 材质覆盖已保存。", "Source マテリアルの上書きを保存しました。", "Source 재질 재정의를 저장했습니다.", "Remplacements de matériau Source enregistrés.", "Переопределения материала Source сохранены." )
R( "rtx.source.saving", "Saving Source material overrides…", "正在保存 Source 材质覆盖…", "Source マテリアルの上書きを保存しています…", "Source 재질 재정의를 저장하는 중…", "Enregistrement des remplacements de matériau Source…", "Сохранение переопределений материала Source…" )
R( "rtx.source.removing", "Removing Source override…", "正在移除 Source 覆盖…", "Source の上書きを削除しています…", "Source 재정의를 제거하는 중…", "Suppression du remplacement Source…", "Удаление переопределения Source…" )
R( "rtx.source.removed", "Source override removed.", "Source 覆盖已移除。", "Source の上書きを削除しました。", "Source 재정의를 제거했습니다.", "Remplacement Source supprimé.", "Переопределение Source удалено." )
R( "rtx.source.save_timeout", "The server did not confirm every Source change. Unconfirmed edits remain unsaved; retry.", "服务器未确认所有 Source 更改。未确认的编辑仍未保存；请重试。", "サーバーがすべての Source 変更を確認できませんでした。未確認の編集は未保存のままです。もう一度お試しください。", "서버가 모든 Source 변경 사항을 확인하지 못했습니다. 확인되지 않은 편집 내용은 저장되지 않았으므로 다시 시도하세요.", "Le serveur n’a pas confirmé toutes les modifications Source. Les modifications non confirmées restent non enregistrées ; réessayez.", "Сервер подтвердил не все изменения Source. Неподтверждённые правки остались несохранёнными; повторите попытку." )
R( "rtx.source.saving_disk", "Source material overrides applied; the server is writing them to disk…", "Source 材质覆盖已应用；服务器正在将其写入磁盘…", "Source マテリアルの上書きを適用しました。サーバーがディスクに書き込んでいます…", "Source 재질 재정의를 적용했습니다. 서버가 디스크에 기록하는 중입니다…", "Remplacements de matériau Source appliqués ; le serveur les écrit sur le disque…", "Переопределения материала Source применены; сервер записывает их на диск…" )
R( "rtx.source.conflict", "Not saved: somebody else changed this Source material after you loaded it. Save again to replace their change, or reopen the editor to load it.", "未保存：在你加载后，其他人修改了此 Source 材质。再次保存将覆盖对方的更改，或重新打开编辑器以加载对方的版本。", "保存されませんでした：読み込んだ後に他の人がこの Source マテリアルを変更しました。もう一度保存すると相手の変更を置き換え、エディターを開き直すと相手の版を読み込みます。", "저장되지 않았습니다: 불러온 뒤 다른 사람이 이 Source 재질을 변경했습니다. 다시 저장하면 상대의 변경을 덮어쓰고, 편집기를 다시 열면 상대의 버전을 불러옵니다.", "Non enregistré : quelqu’un d’autre a modifié ce matériau Source après son chargement. Enregistrez à nouveau pour remplacer sa modification, ou rouvrez l’éditeur pour la charger.", "Не сохранено: кто-то другой изменил этот материал Source после загрузки. Сохраните ещё раз, чтобы заменить его изменение, или откройте редактор заново, чтобы загрузить его." )
R( "rtx.source.rejected", "The server refused the Source change: {{reason}}", "服务器拒绝了 Source 更改：{{reason}}", "サーバーが Source の変更を拒否しました：{{reason}}", "서버가 Source 변경을 거부했습니다: {{reason}}", "Le serveur a refusé la modification Source : {{reason}}", "Сервер отклонил изменение Source: {{reason}}" )
R( "rtx.source.material_conflict", "Different Source slot edits share this material path. Make them match, or save with the entity/model target.", "不同 Source 槽位的编辑共用同一材质路径。请使它们保持一致，或改用实体/模型目标保存。", "異なる Source スロットの編集が同じマテリアルパスを共有しています。内容を一致させるか、エンティティ／モデルを保存先にしてください。", "서로 다른 Source 슬롯 편집이 같은 재질 경로를 공유합니다. 내용을 같게 만들거나 엔티티/모델 대상으로 저장하세요.", "Des modifications de différents emplacements Source partagent ce chemin de matériau. Rendez-les identiques ou enregistrez-les avec la cible entité/modèle.", "Изменения разных слотов Source используют один путь материала. Сделайте их одинаковыми либо сохраните для объекта/модели." )
R( "rtx.source.target_lost", "The Source save target is no longer available. Select a valid target or reopen the editor.", "Source 保存目标已不可用。请选择有效目标或重新打开编辑器。", "Source の保存先が利用できなくなりました。有効な保存先を選択するか、エディターを開き直してください。", "Source 저장 대상을 더 이상 사용할 수 없습니다. 유효한 대상을 선택하거나 편집기를 다시 여세요.", "La cible d’enregistrement Source n’est plus disponible. Sélectionnez une cible valide ou rouvrez l’éditeur.", "Цель сохранения Source больше недоступна. Выберите допустимую цель или заново откройте редактор." )
R( "rtx.source.finish_dialog", "Finish or cancel the open texture/map dialog before saving Source changes.", "请先完成或取消已打开的纹理/贴图对话框，再保存 Source 更改。", "Source の変更を保存する前に、開いているテクスチャ／マップのダイアログを完了するかキャンセルしてください。", "Source 변경 사항을 저장하기 전에 열린 텍스처/맵 대화 상자를 완료하거나 취소하세요.", "Terminez ou annulez la boîte de dialogue de texture/carte ouverte avant d’enregistrer les modifications Source.", "Перед сохранением изменений Source завершите или отмените работу в открытом окне текстуры/карты." )
R( "rtx.source.wait_close", "Please wait for the Source material save to finish before closing the editor.", "请等待 Source 材质保存完成后再关闭编辑器。", "Source マテリアルの保存が完了してからエディターを閉じてください。", "Source 재질 저장이 완료될 때까지 기다린 후 편집기를 닫으세요.", "Attendez la fin de l’enregistrement du matériau Source avant de fermer l’éditeur.", "Дождитесь завершения сохранения материала Source, прежде чем закрывать редактор." )
R( "rtx.source.unsaved", "Unsaved Source material changes", "Source 材质有未保存的更改", "Source マテリアルに未保存の変更があります", "Source 재질에 저장하지 않은 변경 사항이 있습니다", "Modifications du matériau Source non enregistrées", "Есть несохранённые изменения материала Source" )
R( "rtx.source.nothing_save", "No Source material changes to save.", "没有需要保存的 Source 材质更改。", "保存する Source マテリアルの変更はありません。", "저장할 Source 재질 변경 사항이 없습니다.", "Aucune modification du matériau Source à enregistrer.", "Нет изменений материала Source для сохранения." )
R( "rtx.source.save_denied", "Only administrators can save Source material overrides on this server.", "此服务器仅允许管理员保存 Source 材质覆盖。", "このサーバーでは管理者だけが Source マテリアルの上書きを保存できます。", "이 서버에서는 관리자만 Source 재질 재정의를 저장할 수 있습니다.", "Seuls les administrateurs peuvent enregistrer les remplacements de matériau Source sur ce serveur.", "На этом сервере сохранять переопределения материала Source могут только администраторы." )
R( "rtx.source.revert", "Revert Source changes", "还原 Source 更改", "Source の変更を元に戻す", "Source 변경 사항 되돌리기", "Annuler les modifications Source", "Отменить изменения Source" )
R( "rtx.source.remove", "Remove Source override", "移除 Source 覆盖", "Source の上書きを削除", "Source 재정의 제거", "Supprimer le remplacement Source", "Удалить переопределение Source" )
R( "rtx.source.empty", "No Source parameters are available for this material.", "此材质没有可用的 Source 参数。", "このマテリアルには使用可能な Source パラメーターがありません。", "이 재질에는 사용할 수 있는 Source 매개변수가 없습니다.", "Aucun paramètre Source n’est disponible pour ce matériau.", "Для этого материала нет доступных параметров Source." )
R( "rtx.source.select_material", "Select a sub-material on the left to edit its Source parameters.", "请在左侧选择一个子材质以编辑其 Source 参数。", "左側でサブマテリアルを選択し、Source パラメーターを編集してください。", "왼쪽에서 하위 재질을 선택하여 Source 매개변수를 편집하세요.", "Sélectionnez un sous-matériau à gauche pour modifier ses paramètres Source.", "Выберите подматериал слева, чтобы изменить его параметры Source." )
R( "rtx.source.scope_entity_hint", "Save the Source/VMT override only on this entity. The RTX profile still uses its captured texture-hash scope.", "仅将 Source / VMT 覆盖保存到此实体。RTX 配置仍使用捕获到的纹理哈希范围。", "Source / VMT の上書きをこのエンティティだけに保存します。RTX プロファイルには引き続きキャプチャしたテクスチャハッシュの範囲が適用されます。", "Source/VMT 재정의를 이 엔티티에만 저장합니다. RTX 프로필은 계속 캡처된 텍스처 해시 범위를 사용합니다.", "Enregistre le remplacement Source/VMT uniquement sur cette entité. Le profil RTX conserve sa portée fondée sur le hachage de texture capturé.", "Сохраняет переопределение Source/VMT только для этого объекта. Профиль RTX по-прежнему использует область захваченного хеша текстуры." )
R( "rtx.source.scope_model_hint", "Save the Source/VMT override for every prop using this model. The RTX profile still uses its captured texture-hash scope.", "将 Source / VMT 覆盖保存到使用此模型的所有物件。RTX 配置仍使用捕获到的纹理哈希范围。", "Source / VMT の上書きをこのモデルを使うすべてのプロップに保存します。RTX プロファイルには引き続きキャプチャしたテクスチャハッシュの範囲が適用されます。", "Source/VMT 재정의를 이 모델을 사용하는 모든 프롭에 저장합니다. RTX 프로필은 계속 캡처된 텍스처 해시 범위를 사용합니다.", "Enregistre le remplacement Source/VMT pour tous les props utilisant ce modèle. Le profil RTX conserve sa portée fondée sur le hachage de texture capturé.", "Сохраняет переопределение Source/VMT для всех объектов с этой моделью. Профиль RTX по-прежнему использует область захваченного хеша текстуры." )
R( "rtx.source.scope_material_hint", "Save the Source/VMT override for every material with this path. The RTX profile still uses its captured texture-hash scope.", "将 Source / VMT 覆盖保存到使用此路径的所有材质。RTX 配置仍使用捕获到的纹理哈希范围。", "Source / VMT の上書きをこのパスを使うすべてのマテリアルに保存します。RTX プロファイルには引き続きキャプチャしたテクスチャハッシュの範囲が適用されます。", "Source/VMT 재정의를 이 경로를 사용하는 모든 재질에 저장합니다. RTX 프로필은 계속 캡처된 텍스처 해시 범위를 사용합니다.", "Enregistre le remplacement Source/VMT pour tous les matériaux ayant ce chemin. Le profil RTX conserve sa portée fondée sur le hachage de texture capturé.", "Сохраняет переопределение Source/VMT для всех материалов с этим путём. Профиль RTX по-прежнему использует область захваченного хеша текстуры." )
R( "rtx.source.scope_surface_hint", "Save the Source/VMT override for this map surface material. The RTX profile still uses its captured texture-hash scope.", "将 Source / VMT 覆盖保存到此地图表面材质。RTX 配置仍使用捕获到的纹理哈希范围。", "Source / VMT の上書きをこのマップ表面のマテリアルに保存します。RTX プロファイルには引き続きキャプチャしたテクスチャハッシュの範囲が適用されます。", "Source/VMT 재정의를 이 맵 표면 재질에 저장합니다. RTX 프로필은 계속 캡처된 텍스처 해시 범위를 사용합니다.", "Enregistre le remplacement Source/VMT pour ce matériau de surface de la carte. Le profil RTX conserve sa portée fondée sur le hachage de texture capturé.", "Сохраняет переопределение Source/VMT для этого материала поверхности карты. Профиль RTX по-прежнему использует область захваченного хеша текстуры." )
R( "rtx.writer_live", "Native writer • live preview", "原生写入模块 • 实时预览", "ネイティブ書き込み • ライブプレビュー", "네이티브 쓰기 모듈 • 실시간 미리보기", "Module d’écriture natif • aperçu en direct", "Нативный модуль записи • предпросмотр" )
R( "rtx.writer_save", "Native writer • save/reload", "原生写入模块 • 保存后重新载入", "ネイティブ書き込み • 保存後に再読み込み", "네이티브 쓰기 모듈 • 저장 후 다시 불러오기", "Module d’écriture natif • enregistrement/rechargement", "Нативный модуль записи • сохранение/перезагрузка" )
R( "rtx.writer_export", "Export-only • native writer not installed", "仅可导出 • 未安装原生写入模块", "エクスポートのみ • ネイティブ書き込みが未導入", "내보내기 전용 • 네이티브 쓰기 모듈이 설치되지 않음", "Exportation uniquement • module d’écriture natif absent", "Только экспорт • нативный модуль записи не установлен" )
R( "rtx.writer_blocked", "Native writer blocked • reset required", "原生写入模块已阻止 • 需要重置", "ネイティブ書き込みをブロック中 • リセットが必要", "네이티브 쓰기 모듈 차단됨 • 초기화 필요", "Module d’écriture natif bloqué • réinitialisation requise", "Нативный модуль записи заблокирован • требуется сброс" )
R( "rtx.unsaved", "Unsaved RTX material changes", "RTX 材质有未保存的更改", "RTX マテリアルに未保存の変更があります", "RTX 재질에 저장하지 않은 변경 사항이 있습니다", "Modifications du matériau RTX non enregistrées", "Есть несохранённые изменения материала RTX" )

R( "rtx.map.albedo", "Base colour", "基础色", "ベースカラー", "기본 색상", "Couleur de base", "Базовый цвет" )
R( "rtx.map.normal", "Normal", "法线", "法線", "노멀", "Normale", "Нормаль" )
R( "rtx.map.roughness", "Roughness", "粗糙度", "粗さ", "거칠기", "Rugosité", "Шероховатость" )
R( "rtx.map.metallic", "Metallic", "金属度", "メタリック", "금속성", "Métallique", "Металличность" )
R( "rtx.map.height", "Height", "高度", "高さ", "높이", "Hauteur", "Высота" )
R( "rtx.map.emissive", "Emission", "自发光", "発光", "발광", "Émission", "Эмиссия" )
R( "rtx.map.anisotropy", "Anisotropy", "各向异性", "異方性", "비등방성", "Anisotropie", "Анизотропия" )
R( "rtx.map.subsurface_transmittance", "Transmittance", "透射", "透過", "투과", "Transmission", "Пропускание" )
R( "rtx.map.subsurface_thickness", "Measurement distance", "测量距离", "測定距離", "측정 거리", "Distance de mesure", "Расстояние измерения" )
R( "rtx.map.subsurface_scattering", "Single scattering", "单次散射", "単一散乱", "단일 산란", "Diffusion simple", "Однократное рассеяние" )
R( "rtx.map.subsurface_radius", "Subsurface radius", "次表面散射半径", "サブサーフェス散乱半径", "서브서피스 산란 반경", "Rayon de diffusion sous-surface", "Радиус подповерхностного рассеяния" )
R( "rtx.map.empty", "DDS/image path, or use Edit for a Source VTF", "DDS / 图像路径；如需使用 Source VTF，请点击“编辑”", "DDS / 画像のパス。Source VTF には「編集」を使用", "DDS/이미지 경로. Source VTF는 ‘편집’을 사용하세요", "Chemin DDS/image ; pour un VTF Source, utilisez Modifier", "Путь к DDS/изображению; для Source VTF используйте «Изменить»" )
R( "rtx.map.generated", "Generated / edited map", "已生成 / 已编辑的贴图", "生成済み / 編集済みマップ", "생성/편집된 맵", "Map générée / modifiée", "Созданная / изменённая карта" )
R( "rtx.surface_intro", "Physically based controls. Maps override their matching constants; the Shader graph remains authoritative.", "基于物理的材质控制。贴图会覆盖对应的常量；着色器节点图始终为最终依据。", "物理ベースのマテリアル設定です。マップは対応する定数より優先され、シェーダーグラフが最終的な設定となります。", "물리 기반 재질 설정입니다. 맵은 해당 상숫값보다 우선하며 셰이더 그래프가 최종 설정입니다.", "Réglages de matériau physiquement réalistes. Les maps remplacent les constantes correspondantes ; le graphe de shader reste la référence.", "Физически корректные параметры материала. Карты заменяют соответствующие константы; окончательные значения задаёт граф шейдера." )
R( "rtx.maps", "PBR texture maps", "PBR 纹理贴图", "PBR テクスチャマップ", "PBR 텍스처 맵", "Maps de texture PBR", "Текстурные карты PBR" )
R( "rtx.base_colour", "Base colour multiplier", "基础色乘数", "ベースカラーの乗数", "기본 색상 배율", "Multiplicateur de couleur de base", "Множитель базового цвета" )
R( "rtx.surface_values", "Surface response", "表面响应", "サーフェス応答", "표면 반응", "Réponse de la surface", "Параметры поверхности" )
R( "rtx.roughness", "Roughness", "粗糙度", "粗さ", "거칠기", "Rugosité", "Шероховатость" )
R( "rtx.metallic", "Metallic", "金属度", "メタリック", "금속성", "Métallique", "Металличность" )
R( "rtx.opacity", "Opacity", "不透明度", "不透明度", "불투명도", "Opacité", "Непрозрачность" )
R( "rtx.anisotropy", "Anisotropy", "各向异性", "異方性", "비등방성", "Anisotropie", "Анизотропия" )
R( "rtx.thin_film", "Thin-film thickness (nm)", "薄膜厚度（纳米）", "薄膜の厚さ（nm）", "박막 두께(nm)", "Épaisseur de couche mince (nm)", "Толщина тонкой плёнки (нм)" )
R( "rtx.displace_in", "Displacement inward", "向内位移", "内向きのディスプレイスメント", "안쪽 변위", "Déplacement vers l’intérieur", "Смещение внутрь" )
R( "rtx.displace_out", "Displacement outward", "向外位移", "外向きのディスプレイスメント", "바깥쪽 변위", "Déplacement vers l’extérieur", "Смещение наружу" )
R( "rtx.emission_colour", "Emission colour", "自发光颜色", "発光色", "발광 색상", "Couleur d’émission", "Цвет эмиссии" )
R( "rtx.emission_strength", "Emission intensity", "自发光强度", "発光強度", "발광 강도", "Intensité d’émission", "Интенсивность эмиссии" )
R( "rtx.base_material", "Base material", "基础材质", "ベースマテリアル", "기본 재질", "Matériau de base", "Базовый материал" )
R( "rtx.iridescence", "Iridescence", "虹彩", "虹彩", "이리데슨스", "Iridescence", "Иридесценция" )
R( "rtx.emission", "Emission", "自发光", "発光", "발광", "Émission", "Эмиссия" )
R( "rtx.preview_restore_failed", "Could not restore the saved RTX material after preview: {{error}}", "预览后无法恢复已保存的 RTX 材质：{{error}}", "プレビュー後に保存済みの RTX マテリアルを復元できませんでした：{{error}}", "미리보기 후 저장된 RTX 머티리얼을 복원하지 못했습니다: {{error}}", "Impossible de restaurer le matériau RTX enregistré après l’aperçu : {{error}}", "Не удалось восстановить сохранённый материал RTX после предпросмотра: {{error}}" )
R( "rtx.live_world_tip", "Preview edits in your world only. Save to keep and share them; closing or turning preview off restores saved materials. Affects every use of the captured texture hash.", "仅在本地世界中预览修改。保存后才能保留并同步；关闭窗口或预览会恢复已保存的材质。所有使用同一捕获纹理哈希的对象都会受到影响。", "変更をローカルのワールドだけでプレビューします。保存すると変更が保持・共有されます。閉じるかプレビューをオフにすると保存済みのマテリアルに戻ります。同じキャプチャ済みテクスチャハッシュを使うすべての箇所に適用されます。", "변경 사항을 로컬 월드에서만 미리 봅니다. 저장하면 유지 및 공유되며, 창을 닫거나 미리보기를 끄면 저장된 머티리얼로 돌아갑니다. 같은 캡처 텍스처 해시를 사용하는 모든 곳에 적용됩니다.", "Prévisualise les modifications uniquement dans votre monde local. Enregistrez pour les conserver et les partager ; fermer ou désactiver l’aperçu restaure les matériaux enregistrés. Affecte toutes les utilisations du même hachage de texture capturée.", "Предпросмотр изменений только в вашем локальном мире. Сохраните, чтобы оставить и передать их другим; закрытие окна или отключение предпросмотра возвращает сохранённые материалы. Влияет на все объекты с тем же хешем захваченной текстуры." )
R( "rtx.live_world_unavailable", "Live preview requires an updated native RTX bridge with reversible preview support. Update the bridge and restart the game.", "实时预览需要支持可撤销预览的新版原生 RTX 桥接模块。请更新模块并重启游戏。", "ライブプレビューには、元に戻せるプレビューに対応した新しいネイティブ RTX ブリッジが必要です。ブリッジを更新してゲームを再起動してください。", "실시간 미리보기에는 원상 복원이 가능한 최신 네이티브 RTX 브리지가 필요합니다. 브리지를 업데이트하고 게임을 다시 시작하세요.", "L’aperçu en direct nécessite un pont RTX natif à jour prenant en charge la restauration. Mettez le pont à jour et redémarrez le jeu.", "Для предпросмотра нужен обновлённый нативный мост RTX с поддержкой восстановления материалов. Обновите мост и перезапустите игру." )
R( "rtx.animation", "Animation", "动画", "アニメーション", "애니메이션", "Animation", "Анимация" )
R( "rtx.remix_flags", "Remix flags", "Remix 标志", "Remix フラグ", "Remix 플래그", "Indicateurs Remix", "Флаги Remix" )
R( "rtx.alpha_blending", "Alpha blending", "Alpha 混合", "アルファブレンディング", "알파 블렌딩", "Fusion alpha", "Альфа-смешивание" )
R( "rtx.filtering", "Filtering", "纹理过滤", "フィルタリング", "필터링", "Filtrage", "Фильтрация" )
R( "rtx.displacement", "Displacement", "位移", "ディスプレイスメント", "변위", "Déplacement", "Смещение" )
R( "rtx.subsurface", "Subsurface", "次表面散射", "サブサーフェス", "서브서피스", "Diffusion sous-surface", "Подповерхностное рассеяние" )
R( "rtx.enable_thin_film", "Enable thin film", "启用薄膜效果", "薄膜効果を有効化", "박막 효과 사용", "Activer la couche mince", "Включить эффект тонкой плёнки" )
R( "rtx.enable_emission", "Enable emission", "启用自发光", "発光を有効化", "발광 사용", "Activer l’émission", "Включить эмиссию" )
R( "rtx.emission_disabled_hint", "Emission is off. Enable it above to use the map, colour and intensity below.", "自发光已关闭。请在上方启用，以使下方的贴图、颜色和强度设置生效。", "発光は無効です。下のマップ・色・強度の設定を使うには、上で発光を有効にしてください。", "발광이 꺼져 있습니다. 아래 맵, 색상 및 강도 설정을 적용하려면 위에서 발광을 켜세요.", "L’émission est désactivée. Activez-la ci-dessus pour utiliser la texture, la couleur et l’intensité ci-dessous.", "Эмиссия выключена. Включите её выше, чтобы использовать карту, цвет и интенсивность ниже." )
R( "rtx.emission_enabled_hint", "Emission is on. Turning it off keeps the settings below.", "自发光已启用。关闭后仍会保留下方的设置。", "発光は有効です。無効にしても、下の設定は保持されます。", "발광이 켜져 있습니다. 꺼도 아래 설정은 유지됩니다.", "L’émission est activée. La désactiver conserve les réglages ci-dessous.", "Эмиссия включена. При отключении настройки ниже сохранятся." )
R( "rtx.preload_textures", "Preload textures", "预加载纹理", "テクスチャをプリロード", "텍스처 미리 불러오기", "Précharger les textures", "Предзагружать текстуры" )
R( "rtx.ignore_material", "Ignore material", "忽略材质", "マテリアルを無視", "재질 무시", "Ignorer le matériau", "Игнорировать материал" )
R( "rtx.blend_enabled", "Enable alpha blending", "启用 Alpha 混合", "アルファブレンディングを有効化", "알파 블렌딩 사용", "Activer la fusion alpha", "Включить альфа-смешивание" )
R( "rtx.normal_encoding", "Normal-map encoding", "法线贴图编码", "法線マップのエンコード", "노멀 맵 인코딩", "Encodage de la normal map", "Кодирование карты нормалей" )
R( "rtx.normal_encoding_tip", "How the normal map picture is drawn. RTX Remix reads only octahedral normal maps, so a DirectX or OpenGL picture is converted when it is applied. AME's own normal maps, like Source's, are DirectX.", "法线贴图图片的编码方式。RTX Remix 只读取八面体编码的法线贴图，因此 DirectX 或 OpenGL 图片会在应用时被转换。AME 自己生成的法线贴图与 Source 的一样，都是 DirectX 格式。", "法線マップ画像の描かれ方です。RTX Remix はオクタヘドラル形式の法線マップしか読まないため、DirectX や OpenGL 形式の画像は適用時に変換されます。AME が作る法線マップは Source と同じく DirectX 形式です。", "노멀 맵 이미지가 그려진 방식입니다. RTX Remix는 옥타헤드럴 노멀 맵만 읽으므로 DirectX 또는 OpenGL 이미지는 적용할 때 변환됩니다. AME가 만드는 노멀 맵은 Source와 마찬가지로 DirectX 방식입니다.", "La façon dont l’image de la normal map est dessinée. RTX Remix ne lit que des normal maps octaédriques : une image DirectX ou OpenGL est donc convertie lors de l’application. Les normal maps d’AME, comme celles de Source, sont au format DirectX.", "Как нарисована карта нормалей. RTX Remix читает только октаэдрические карты нормалей, поэтому изображение DirectX или OpenGL преобразуется при применении. Карты нормалей AME, как и карты Source, — в формате DirectX." )
R( "rtx.subsurface_diffusion_profile", "Enable diffusion profile", "启用次表面散射扩散轮廓", "拡散プロファイルを有効化", "확산 프로파일 사용", "Activer le profil de diffusion", "Включить профиль диффузии" )
R( "rtx.subsurface_transmittance_color", "Transmittance colour", "透射颜色", "透過色", "투과 색상", "Couleur de transmission", "Цвет пропускания" )
R( "rtx.subsurface_measurement_distance", "Measurement distance", "测量距离", "測定距離", "측정 거리", "Distance de mesure", "Расстояние измерения" )
R( "rtx.subsurface_single_scattering_albedo", "Single-scattering albedo", "单次散射反照率", "単一散乱アルベド", "단일 산란 알베도", "Albédo de diffusion simple", "Альбедо однократного рассеяния" )
R( "rtx.subsurface_volumetric_anisotropy", "Volumetric anisotropy", "体积各向异性", "体積異方性", "체적 비등방성", "Anisotropie volumétrique", "Объёмная анизотропия" )
R( "rtx.subsurface_radius", "Subsurface-scattering radius", "次表面散射半径", "サブサーフェス散乱半径", "서브서피스 산란 반경", "Rayon de diffusion sous-surface", "Радиус подповерхностного рассеяния" )
R( "rtx.subsurface_radius_scale", "Subsurface radius scale", "次表面散射半径缩放", "サブサーフェス散乱半径のスケール", "서브서피스 산란 반경 배율", "Échelle du rayon sous-surface", "Масштаб радиуса подповерхностного рассеяния" )
R( "rtx.subsurface_max_sample_radius", "Maximum sample radius", "最大采样半径", "最大サンプル半径", "최대 샘플 반경", "Rayon d’échantillonnage maximal", "Максимальный радиус выборки" )
R( "rtx.sampling_alpha", "Sampling and alpha", "采样与 Alpha", "サンプリングとアルファ", "샘플링 및 알파", "Échantillonnage et alpha", "Сэмплирование и альфа-канал" )
R( "rtx.filter", "Texture filtering", "纹理过滤", "テクスチャフィルタリング", "텍스처 필터링", "Filtrage des textures", "Фильтрация текстур" )
R( "rtx.wrap_u", "Horizontal wrapping", "水平寻址模式", "水平方向のラップ", "수평 래핑", "Répétition horizontale", "Горизонтальный режим адресации" )
R( "rtx.wrap_v", "Vertical wrapping", "垂直寻址模式", "垂直方向のラップ", "수직 래핑", "Répétition verticale", "Вертикальный режим адресации" )
R( "rtx.sprite_sheet_rows", "Sprite-sheet rows", "精灵图行数", "スプライトシートの行数", "스프라이트 시트 행 수", "Lignes de la planche de sprites", "Число строк атласа спрайтов" )
R( "rtx.sprite_sheet_columns", "Sprite-sheet columns", "精灵图列数", "スプライトシートの列数", "스프라이트 시트 열 수", "Colonnes de la planche de sprites", "Число столбцов атласа спрайтов" )
R( "rtx.sprite_sheet_fps", "Sprite-sheet frames per second", "精灵图每秒帧数", "スプライトシートのフレームレート（FPS）", "스프라이트 시트 초당 프레임 수", "Images par seconde de la planche de sprites", "Частота кадров атласа спрайтов" )
R( "rtx.blend", "Blend mode", "混合模式", "ブレンドモード", "블렌드 모드", "Mode de fusion", "Режим смешивания" )
R( "rtx.alpha_test", "Alpha test", "Alpha 测试", "アルファテスト", "알파 테스트", "Test alpha", "Альфа-тест" )
R( "rtx.alpha_reference", "Alpha reference", "Alpha 参考值", "アルファ参照値", "알파 기준값", "Seuil alpha", "Порог альфа-теста" )
R( "rtx.draw_alpha", "Use captured draw-call alpha state", "使用捕获到的绘制调用 Alpha 状态", "キャプチャした描画コールのアルファ状態を使用", "캡처된 드로우 콜의 알파 상태 사용", "Utiliser l’état alpha de l’appel de rendu capturé", "Использовать захваченное состояние альфа-канала вызова отрисовки" )
R( "rtx.inverted_blend", "Invert blend", "反转混合", "ブレンドを反転", "블렌드 반전", "Inverser la fusion", "Инвертировать смешивание" )
R( "rtx.alpha_thin_film", "Use alpha as thin-film thickness", "将 Alpha 用作薄膜厚度", "アルファを薄膜の厚さとして使用", "알파를 박막 두께로 사용", "Utiliser l’alpha comme épaisseur de couche mince", "Использовать альфа-канал как толщину тонкой плёнки" )

R( "rtx.target", "Replacement target", "替换目标", "置換対象", "교체 대상", "Cible du remplacement", "Цель замены" )
R( "rtx.scope_explain", "RTX Remix identifies legacy materials by the captured base-texture hash. This edit affects every material and model sharing that hash.", "RTX Remix 通过捕获到的基础纹理哈希识别旧式材质。此编辑会影响共享该哈希的所有材质与模型。", "RTX Remix は、キャプチャしたベーステクスチャのハッシュで従来のマテリアルを識別します。この編集は同じハッシュを共有するすべてのマテリアルとモデルに影響します。", "RTX Remix는 캡처된 기본 텍스처 해시로 기존 재질을 식별합니다. 이 편집은 해당 해시를 공유하는 모든 재질과 모델에 적용됩니다.", "RTX Remix identifie les anciens matériaux grâce au hachage capturé de leur texture de base. Cette modification affecte tous les matériaux et modèles qui partagent ce hachage.", "RTX Remix определяет старые материалы по захваченному хешу базовой текстуры. Изменение затронет все материалы и модели с тем же хешем." )
R( "rtx.hashes", "Captured texture hashes", "捕获到的纹理哈希", "キャプチャしたテクスチャハッシュ", "캡처된 텍스처 해시", "Hachages de texture capturés", "Захваченные хеши текстур" )
R( "rtx.hash_wait", "No hash captured yet. Keep this material visible in the world, then retry.", "尚未捕获到哈希。请让此材质在世界中保持可见，然后重试。", "ハッシュはまだキャプチャされていません。このマテリアルをワールド内に表示したまま再試行してください。", "아직 해시를 캡처하지 못했습니다. 이 재질이 월드에 보이게 한 뒤 다시 시도하세요.", "Aucun hachage n’a encore été capturé. Laissez ce matériau visible dans le monde, puis réessayez.", "Хеш пока не захвачен. Оставьте этот материал видимым в игровом мире и повторите попытку." )
R( "rtx.retry_hash", "Capture hashes again", "重新捕获哈希", "ハッシュを再キャプチャ", "해시 다시 캡처", "Capturer de nouveau les hachages", "Повторно захватить хеши" )
R( "rtx.capabilities", "Client capabilities", "客户端功能", "クライアント機能", "클라이언트 기능", "Fonctionnalités du client", "Возможности клиента" )
R( "rtx.export_explain", "This installed RTX client can inspect materials but cannot write arbitrary legacy USD replacements. Save exports a complete profile under garrysmod/data/advmat/rtx_exports; install the AdvMat RTX native bridge to apply it in-world.", "当前安装的 RTX 客户端可以检查材质，但无法写入任意旧式 USD 替换项。保存操作会将完整配置导出到 garrysmod/data/advmat/rtx_exports；安装 AdvMat RTX 原生桥接模块后即可在世界中应用。", "インストール済みの RTX クライアントはマテリアルを検査できますが、任意の従来型 USD 置換を書き込むことはできません。保存すると完全なプロファイルが garrysmod/data/advmat/rtx_exports にエクスポートされます。ワールド内で適用するには AdvMat RTX ネイティブブリッジを導入してください。", "설치된 RTX 클라이언트는 재질을 검사할 수 있지만 임의의 기존 USD 교체 항목을 쓸 수는 없습니다. 저장하면 전체 프로필을 garrysmod/data/advmat/rtx_exports에 내보냅니다. 월드에 적용하려면 AdvMat RTX 네이티브 브리지를 설치하세요.", "Le client RTX installé peut inspecter les matériaux, mais ne peut pas écrire des remplacements USD arbitraires pour l’ancien pipeline. L’enregistrement exporte un profil complet dans garrysmod/data/advmat/rtx_exports ; installez le pont natif AdvMat RTX pour l’appliquer dans le monde.", "Установленный RTX-клиент умеет анализировать материалы, но не может записывать произвольные USD-замены для старого конвейера. При сохранении полный профиль экспортируется в garrysmod/data/advmat/rtx_exports; установите нативный мост AdvMat RTX, чтобы применить его в игровом мире." )
R( "rtx.native_blocked", "The installed native writer could not reset its owned state, so synchronization and writes are blocked: {{reason}}", "已安装的原生写入模块无法重置其拥有的状态，因此同步和写入已被阻止：{{reason}}", "インストール済みのネイティブ書き込みが所有状態をリセットできなかったため、同期と書き込みをブロックしました: {{reason}}", "설치된 네이티브 쓰기 모듈이 소유 상태를 초기화하지 못해 동기화와 쓰기가 차단되었습니다: {{reason}}", "Le module d’écriture natif installé n’a pas pu réinitialiser l’état qu’il possède ; la synchronisation et les écritures sont donc bloquées : {{reason}}", "Установленный нативный модуль записи не смог сбросить принадлежащее ему состояние, поэтому синхронизация и запись заблокированы: {{reason}}" )
R( "rtx.external_warning", "CreateOpaqueMaterial is available, but it only creates materials for Remix API geometry. It is intentionally not used for this Source model.", "CreateOpaqueMaterial 可用，但它只能为 Remix API 几何体创建材质，因此本工具不会将其用于此 Source 模型。", "CreateOpaqueMaterial は利用できますが、Remix API ジオメトリ用のマテリアルしか作成できません。そのため、この Source モデルには意図的に使用していません。", "CreateOpaqueMaterial을 사용할 수 있지만 Remix API 지오메트리용 재질만 생성합니다. 따라서 이 Source 모델에는 의도적으로 사용하지 않습니다.", "CreateOpaqueMaterial est disponible, mais ne crée des matériaux que pour la géométrie de l’API Remix. Cette fonction n’est donc volontairement pas utilisée pour ce modèle Source.", "CreateOpaqueMaterial доступен, но создаёт материалы только для геометрии Remix API. Поэтому он намеренно не используется для этой модели Source." )
R( "rtx.source_inspection", "Imported Source material", "已导入的 Source 材质", "読み込んだ Source マテリアル", "가져온 Source 재질", "Matériau Source importé", "Импортированный материал Source" )
R( "rtx.no_inspection", "No ToPBR inspection data.", "没有 ToPBR 检查数据。", "ToPBR の検査データがありません。", "ToPBR 검사 데이터가 없습니다.", "Aucune donnée d’inspection ToPBR.", "Нет данных анализа ToPBR." )

R( "rtx.save_denied", "Only administrators can save on this server.", "此服务器仅允许管理员保存。", "このサーバーでは管理者だけが保存できます。", "이 서버에서는 관리자만 저장할 수 있습니다.", "Seuls les administrateurs peuvent enregistrer sur ce serveur.", "На этом сервере сохранять могут только администраторы." )
R( "rtx.nothing_save", "Nothing to save.", "没有需要保存的内容。", "保存する変更はありません。", "저장할 내용이 없습니다.", "Aucune modification à enregistrer.", "Нет изменений для сохранения." )
R( "rtx.synchronizing", "Synchronizing RTX profiles from the server…", "正在从服务器同步 RTX 配置…", "サーバーから RTX プロファイルを同期中…", "서버에서 RTX 프로필을 동기화하는 중…", "Synchronisation des profils RTX depuis le serveur…", "Синхронизация профилей RTX с сервером…" )
R( "rtx.sync_blocked", "RTX profiles cannot synchronize until native owned state is reset: {{reason}}", "在重置原生模块所拥有的状态之前，无法同步 RTX 配置：{{reason}}", "ネイティブ側が所有する状態をリセットするまで、RTX プロファイルを同期できません: {{reason}}", "네이티브 모듈이 소유한 상태를 초기화할 때까지 RTX 프로필을 동기화할 수 없습니다: {{reason}}", "Impossible de synchroniser les profils RTX tant que l’état détenu par le module natif n’a pas été réinitialisé : {{reason}}", "Невозможно синхронизировать профили RTX, пока состояние, принадлежащее нативному модулю, не сброшено: {{reason}}" )
R( "rtx.saving", "Saving RTX profiles…", "正在保存 RTX 配置…", "RTX プロファイルを保存中…", "RTX 프로필 저장 중…", "Enregistrement des profils RTX…", "Сохранение профилей RTX…" )
R( "rtx.local_saved", "Saved locally. Syncing in the background…", "已在本地保存，正在后台同步…", "ローカルに保存しました。バックグラウンドで同期中…", "로컬에 저장했습니다. 백그라운드에서 동기화 중…", "Enregistré localement. Synchronisation en arrière-plan…", "Сохранено локально. Синхронизация в фоновом режиме…" )
R( "rtx.background_synced", "Saved locally and synced with the server.", "已在本地保存并同步到服务器。", "ローカルに保存し、サーバーと同期しました。", "로컬 저장 및 서버 동기화를 완료했습니다.", "Enregistré localement et synchronisé avec le serveur.", "Сохранено локально и синхронизировано с сервером." )
R( "rtx.background_failed", "Server sync failed for {{material}}: {{reason}}. Your local changes are retained; Save to retry.", "{{material}} 的服务器同步失败：{{reason}}。本地修改已保留，请点击“保存”重试。", "{{material}} のサーバー同期に失敗しました: {{reason}}。ローカルの変更は保持されています。「保存」で再試行できます。", "{{material}} 서버 동기화 실패: {{reason}}. 로컬 변경 사항은 유지됩니다. 저장을 눌러 다시 시도하세요.", "Échec de la synchronisation de {{material}} avec le serveur : {{reason}}. Vos modifications locales sont conservées ; enregistrez pour réessayer.", "Не удалось синхронизировать {{material}} с сервером: {{reason}}. Локальные изменения сохранены; нажмите «Сохранить», чтобы повторить попытку." )
R( "rtx.save_failed", "One or more RTX profiles could not be saved.", "一个或多个 RTX 配置无法保存。", "1 つ以上の RTX プロファイルを保存できませんでした。", "하나 이상의 RTX 프로필을 저장하지 못했습니다.", "Un ou plusieurs profils RTX n’ont pas pu être enregistrés.", "Не удалось сохранить один или несколько профилей RTX." )
R( "rtx.generated_path_failed", "Could not derive a safe path for the generated texture.", "无法为生成的纹理确定安全路径。", "生成テクスチャの安全なパスを確定できませんでした。", "생성된 텍스처의 안전한 경로를 결정할 수 없습니다.", "Impossible de déterminer un chemin sûr pour la texture générée.", "Не удалось определить безопасный путь для сгенерированной текстуры." )
R( "rtx.saved_pending_hash", "RTX drafts were saved, but one or more materials have no captured texture hash yet. Keep them visible, recapture, then Save again.", "RTX 草稿已保存，但一个或多个材质尚无捕获到的纹理哈希。请让这些材质在世界中保持可见，重新捕获后再保存。", "RTX ドラフトは保存されましたが、1 つ以上のマテリアルにキャプチャ済みのテクスチャハッシュがまだありません。ワールド内に表示し、再キャプチャしてからもう一度保存してください。", "RTX 초안은 저장되었지만 하나 이상의 재질에 아직 캡처된 텍스처 해시가 없습니다. 월드에 보이게 한 뒤 다시 캡처하고 저장하세요.", "Les brouillons RTX ont été enregistrés, mais un ou plusieurs matériaux n’ont pas encore de hachage de texture capturé. Laissez-les visibles, relancez la capture, puis enregistrez de nouveau.", "Черновики RTX сохранены, но для одного или нескольких материалов пока нет захваченного хеша текстуры. Оставьте их видимыми, повторите захват и снова сохраните." )
R( "rtx.saved_apply_warning", "RTX profiles were saved, but one or more could not be applied. Check Diagnostics or reload Remix.", "RTX 配置已保存，但一个或多个配置无法应用。请检查“诊断”或重新加载 Remix。", "RTX プロファイルは保存されましたが、1 つ以上を適用できませんでした。「診断」を確認するか、Remix を再読み込みしてください。", "RTX 프로필은 저장되었지만 하나 이상 적용하지 못했습니다. 진단을 확인하거나 Remix를 다시 불러오세요.", "Les profils RTX ont été enregistrés, mais un ou plusieurs n’ont pas pu être appliqués. Consultez Diagnostic ou rechargez Remix.", "Профили RTX сохранены, но один или несколько не удалось применить. Проверьте раздел «Диагностика» или перезагрузите Remix." )
R( "rtx.exported", "RTX profiles exported.", "RTX 配置已导出。", "RTX プロファイルをエクスポートしました。", "RTX 프로필을 내보냈습니다.", "Profils RTX exportés.", "Профили RTX экспортированы." )
R( "rtx.saved", "RTX profiles saved and queued for Remix reload.", "RTX 配置已保存，并已加入 Remix 重新载入队列。", "RTX プロファイルを保存し、Remix の再読み込み待ちに追加しました。", "RTX 프로필을 저장하고 Remix 다시 불러오기 대기열에 추가했습니다.", "Profils RTX enregistrés et mis en attente du rechargement de Remix.", "Профили RTX сохранены и поставлены в очередь на перезагрузку Remix." )
R( "rtx.removed", "RTX material override removed.", "RTX 材质覆盖已移除。", "RTX マテリアルの上書きを削除しました。", "RTX 재질 재정의를 제거했습니다.", "Remplacement du matériau RTX supprimé.", "Переопределение материала RTX удалено." )
R( "rtx.removed_cleanup_warning", "RTX profile was removed from the server, but local Remix cleanup is still retrying. Check Diagnostics or reload Remix.", "RTX 配置已从服务器移除，但本地 Remix 清理仍在重试。请检查“诊断”或重新加载 Remix。", "RTX プロファイルはサーバーから削除されましたが、ローカルの Remix クリーンアップはまだ再試行中です。「診断」を確認するか、Remix を再読み込みしてください。", "RTX 프로필은 서버에서 제거되었지만 로컬 Remix 정리를 계속 재시도하고 있습니다. 진단을 확인하거나 Remix를 다시 불러오세요.", "Le profil RTX a été supprimé du serveur, mais le nettoyage local de Remix est toujours en cours de nouvelle tentative. Consultez Diagnostic ou rechargez Remix.", "Профиль RTX удалён с сервера, но локальная очистка Remix всё ещё повторяется. Проверьте раздел «Диагностика» или перезагрузите Remix." )

R( "rtx.graph.hint", "Right-click to add a node. Drag an output pin to an input pin. Delete removes the selected node.", "右键单击可添加节点。将输出接口拖到输入接口即可连接。按 Delete 键可删除所选节点。", "右クリックでノードを追加します。出力ピンを入力ピンへドラッグして接続します。Delete キーで選択中のノードを削除します。", "마우스 오른쪽 버튼으로 노드를 추가합니다. 출력 핀을 입력 핀으로 끌어 연결합니다. Delete 키로 선택한 노드를 삭제합니다.", "Faites un clic droit pour ajouter un nœud. Faites glisser une broche de sortie vers une broche d’entrée. La touche Suppr supprime le nœud sélectionné.", "Щёлкните правой кнопкой, чтобы добавить узел. Перетащите выходной контакт на входной. Клавиша Delete удаляет выбранный узел." )
R( "rtx.graph.select", "Select a node to edit its settings.", "选择一个节点以编辑其设置。", "設定を編集するノードを選択してください。", "설정을 편집할 노드를 선택하세요.", "Sélectionnez un nœud pour modifier ses réglages.", "Выберите узел, чтобы изменить его параметры." )
R( "rtx.graph.node_label", "Optional node label", "可选的节点标签", "任意のノードラベル", "선택적 노드 이름", "Libellé facultatif du nœud", "Необязательная подпись узла" )
R( "rtx.graph.texture_path", "Texture path", "纹理路径", "テクスチャのパス", "텍스처 경로", "Chemin de la texture", "Путь к текстуре" )
R( "rtx.graph.browse", "Browse", "浏览", "参照", "찾아보기", "Parcourir", "Обзор" )
R( "rtx.graph.value", "Value", "值", "値", "값", "Valeur", "Значение" )
R( "rtx.graph.unlinked_value", "Unlinked value", "未连接值", "未接続時の値", "연결되지 않은 값", "Valeur non connectée", "Значение без подключения" )
R( "rtx.graph.strength", "Strength", "强度", "強度", "강도", "Intensité", "Сила" )
R( "rtx.graph.delete_node", "Delete node", "删除节点", "ノードを削除", "노드 삭제", "Supprimer le nœud", "Удалить узел" )
R( "rtx.node.output_surface", "Material output", "材质输出", "マテリアル出力", "재질 출력", "Sortie du matériau", "Выход материала" )
R( "rtx.node.texture", "Texture", "纹理", "テクスチャ", "텍스처", "Texture", "Текстура" )
R( "rtx.node.value", "Value", "值", "値", "값", "Valeur", "Значение" )
R( "rtx.node.color", "Colour", "颜色", "カラー", "색상", "Couleur", "Цвет" )
R( "rtx.node.invert", "Invert", "反相", "反転", "반전", "Inverser", "Инверсия" )
R( "rtx.node.multiply", "Multiply", "相乘", "乗算", "곱하기", "Multiplier", "Умножение" )
R( "rtx.node.normal_from_height", "Normal from height", "从高度生成法线", "高さから法線を生成", "높이에서 노멀 생성", "Normale depuis la hauteur", "Нормаль из высоты" )
R( "rtx.mode_badge", "RTX REMIX  •  APERTURE PBR", "RTX REMIX  •  APERTURE PBR", "RTX REMIX  •  APERTURE PBR", "RTX REMIX  •  APERTURE PBR", "RTX REMIX  •  APERTURE PBR", "RTX REMIX  •  APERTURE PBR" )

R( "rtx.socket.albedo", "Base colour", "基础色", "ベースカラー", "기본 색상", "Couleur de base", "Базовый цвет" )
R( "rtx.socket.normal", "Normal", "法线", "法線", "노멀", "Normale", "Нормаль" )
R( "rtx.socket.roughness", "Roughness", "粗糙度", "粗さ", "거칠기", "Rugosité", "Шероховатость" )
R( "rtx.socket.metallic", "Metallic", "金属度", "メタリック", "금속성", "Métallique", "Металличность" )
R( "rtx.socket.height", "Height", "高度", "高さ", "높이", "Hauteur", "Высота" )
R( "rtx.socket.emissive", "Emission colour", "自发光颜色", "発光色", "발광 색상", "Couleur d’émission", "Цвет эмиссии" )
R( "rtx.socket.emissive_intensity", "Emission strength", "自发光强度", "発光強度", "발광 강도", "Intensité d’émission", "Сила эмиссии" )
R( "rtx.socket.opacity", "Opacity", "不透明度", "不透明度", "불투명도", "Opacité", "Непрозрачность" )
R( "rtx.socket.anisotropy", "Anisotropy", "各向异性", "異方性", "비등방성", "Anisotropie", "Анизотропия" )
R( "rtx.socket.thin_film_thickness", "Thin-film thickness", "薄膜厚度", "薄膜の厚さ", "박막 두께", "Épaisseur de couche mince", "Толщина тонкой плёнки" )
R( "rtx.socket.displace_in", "Displace in", "向内位移", "内向きに変位", "안쪽으로 변위", "Déplacer vers l’intérieur", "Сместить внутрь" )
R( "rtx.socket.displace_out", "Displace out", "向外位移", "外向きに変位", "바깥쪽으로 변위", "Déplacer vers l’extérieur", "Сместить наружу" )
R( "rtx.socket.subsurface_transmittance", "Transmittance colour", "透射颜色", "透過色", "투과 색상", "Couleur de transmission", "Цвет пропускания" )
R( "rtx.socket.subsurface_thickness", "Measurement distance", "测量距离", "測定距離", "측정 거리", "Distance de mesure", "Расстояние измерения" )
R( "rtx.socket.subsurface_scattering", "Single-scattering albedo", "单次散射反照率", "単一散乱アルベド", "단일 산란 알베도", "Albédo de diffusion simple", "Альбедо однократного рассеяния" )
R( "rtx.socket.subsurface_volumetric_anisotropy", "Volumetric anisotropy", "体积各向异性", "体積異方性", "체적 비등방성", "Anisotropie volumétrique", "Объёмная анизотропия" )
R( "rtx.socket.subsurface_radius", "Subsurface-scattering radius", "次表面散射半径", "サブサーフェス散乱半径", "서브서피스 산란 반경", "Rayon de diffusion sous-surface", "Радиус подповерхностного рассеяния" )
R( "rtx.socket.subsurface_radius_scale", "Subsurface radius scale", "次表面散射半径缩放", "サブサーフェス散乱半径のスケール", "서브서피스 산란 반경 배율", "Échelle du rayon sous-surface", "Масштаб радиуса подповерхностного рассеяния" )
R( "rtx.socket.subsurface_max_sample_radius", "Maximum sample radius", "最大采样半径", "最大サンプル半径", "최대 샘플 반경", "Rayon d’échantillonnage maximal", "Максимальный радиус выборки" )
R( "rtx.socket.color", "Colour", "颜色", "カラー", "색상", "Couleur", "Цвет" )
R( "rtx.socket.value", "Value", "值", "値", "값", "Valeur", "Значение" )
R( "rtx.socket.a", "A", "A", "A", "A", "A", "A" )
R( "rtx.socket.b", "B", "B", "B", "B", "B", "B" )

R( "rtx.channel.luminance", "Luminance", "亮度", "輝度", "휘도", "Luminance", "Яркость" )
R( "rtx.channel.r", "R", "R", "R", "R", "R", "R" )
R( "rtx.channel.g", "G", "G", "G", "G", "G", "G" )
R( "rtx.channel.b", "B", "B", "B", "B", "B", "B" )
R( "rtx.channel.a", "A", "A", "A", "A", "A", "A" )

R( "rtx.option.nearest", "Nearest", "最近邻", "最近傍", "최근접", "Au plus proche", "Ближайший" )
R( "rtx.option.linear", "Linear", "线性", "線形", "선형", "Linéaire", "Линейный" )
R( "rtx.option.repeat", "Repeat", "重复", "繰り返し", "반복", "Répéter", "Повтор" )
R( "rtx.option.mirror", "Mirror", "镜像", "ミラー", "미러", "Miroir", "Зеркально" )
R( "rtx.option.clamp", "Clamp to edge", "钳制到边缘", "端でクランプ", "가장자리로 클램프", "Limiter aux bords", "Ограничить краями" )
R( "rtx.option.clip", "Clip outside the texture", "截断纹理外区域", "テクスチャ外をクリップ", "텍스처 바깥쪽 자르기", "Rogner hors de la texture", "Отсекать за пределами текстуры" )
R( "rtx.option.opaque", "Opaque", "不透明", "不透明", "불투명", "Opaque", "Непрозрачный" )
R( "rtx.option.alpha", "Alpha", "Alpha", "アルファ", "알파", "Alpha", "Альфа" )
R( "rtx.option.alpha_emissive", "Alpha emissive", "Alpha 自发光", "アルファ発光", "알파 발광", "Alpha émissif", "Альфа-эмиссия" )
R( "rtx.option.reverse_alpha_emissive", "Reverse alpha emissive", "反向 Alpha 自发光", "反転アルファ発光", "반전 알파 발광", "Alpha émissif inversé", "Обратная альфа-эмиссия" )
R( "rtx.option.color", "Colour", "颜色", "カラー", "색상", "Couleur", "Цвет" )
R( "rtx.option.color_emissive", "Colour emissive", "颜色自发光", "カラー発光", "색상 발광", "Couleur émissive", "Цветовая эмиссия" )
R( "rtx.option.reverse_color_emissive", "Reverse colour emissive", "反向颜色自发光", "反転カラー発光", "반전 색상 발광", "Couleur émissive inversée", "Обратная цветовая эмиссия" )
R( "rtx.option.emissive", "Emissive", "自发光", "発光", "발광", "Émissif", "Эмиссия" )
R( "rtx.option.multiplicative", "Multiplicative", "正片叠底", "乗算", "곱하기", "Multiplicatif", "Умножение" )
R( "rtx.option.double_multiplicative", "Double multiplicative", "双倍正片叠底", "2 倍乗算", "이중 곱하기", "Multiplicatif double", "Двойное умножение" )
R( "rtx.option.none", "None", "无", "なし", "없음", "Aucun", "Нет" )
R( "rtx.option.never", "Never", "从不", "常に不合格", "항상 실패", "Jamais", "Никогда" )
R( "rtx.option.equal", "Equal", "等于", "等しい", "같음", "Égal à", "Равно" )
R( "rtx.option.not_equal", "Not equal", "不等于", "等しくない", "같지 않음", "Différent de", "Не равно" )
R( "rtx.option.greater", "Greater than", "大于", "より大きい", "초과", "Supérieur à", "Больше" )
R( "rtx.option.greater_equal", "Greater than or equal", "大于或等于", "以上", "이상", "Supérieur ou égal", "Больше или равно" )
R( "rtx.option.less", "Less than", "小于", "より小さい", "미만", "Inférieur à", "Меньше" )
R( "rtx.option.less_equal", "Less than or equal", "小于或等于", "以下", "이하", "Inférieur ou égal", "Меньше или равно" )
R( "rtx.option.octahedral", "Octahedral", "八面体编码", "オクタヘドラル", "옥타헤드럴", "Octaédrique", "Октаэдрическое" )
R( "rtx.option.tangent_space_ogl", "Tangent space (OpenGL)", "切线空间（OpenGL）", "接空間（OpenGL）", "탄젠트 공간(OpenGL)", "Espace tangent (OpenGL)", "Касательное пространство (OpenGL)" )
R( "rtx.option.tangent_space_dx", "Tangent space (DirectX)", "切线空间（DirectX）", "接空間（DirectX）", "탄젠트 공간(DirectX)", "Espace tangent (DirectX)", "Касательное пространство (DirectX)" )

R( "rtx.shared_alias", "This row shares one captured RTX material identity. Editing the canonical row instead:", "此行与另一行共享同一个已捕获的 RTX 材质标识。将改为编辑规范行：", "この行は、別の行と同じキャプチャ済み RTX マテリアル ID を共有しています。代わりに基準行を編集します：", "이 행은 다른 행과 동일한 캡처된 RTX 재질 ID를 공유합니다. 대신 기준 행을 편집합니다:", "Cette ligne partage la même identité de matériau RTX capturée. Modification de la ligne de référence à la place :", "Эта строка использует тот же захваченный идентификатор материала RTX. Вместо неё будет открыта основная строка:" )
R( "rtx.shared_alias_conflict", "Two unsaved rows now share one captured RTX identity. Keep one working copy before saving.", "两个未保存的行现在共享同一个已捕获的 RTX 标识。保存前请只保留一个工作副本。", "未保存の 2 行が同じキャプチャ済み RTX ID を共有しています。保存前に作業コピーを 1 つだけ残してください。", "저장되지 않은 두 행이 이제 동일한 캡처된 RTX ID를 공유합니다. 저장하기 전에 작업 사본 하나만 남기세요.", "Deux lignes non enregistrées partagent désormais la même identité RTX capturée. Ne conservez qu’une seule copie de travail avant d’enregistrer.", "Две несохранённые строки теперь используют один захваченный идентификатор RTX. Перед сохранением оставьте только одну рабочую копию." )
R( "rtx.compiler_unavailable", "Cannot save RTX profiles: the RTX material compiler is unavailable.", "无法保存 RTX 配置：RTX 材质编译器不可用。", "RTX プロファイルを保存できません：RTX マテリアルコンパイラが利用できません。", "RTX 프로필을 저장할 수 없습니다. RTX 재질 컴파일러를 사용할 수 없습니다.", "Impossible d’enregistrer les profils RTX : le compilateur de matériaux RTX est indisponible.", "Не удалось сохранить профили RTX: компилятор материалов RTX недоступен." )
R( "rtx.compile_failed", "Cannot save RTX profile for {{material}}: {{reason}}", "无法保存 {{material}} 的 RTX 配置：{{reason}}", "{{material}} の RTX プロファイルを保存できません：{{reason}}", "{{material}}의 RTX 프로필을 저장할 수 없습니다: {{reason}}", "Impossible d’enregistrer le profil RTX de {{material}} : {{reason}}", "Не удалось сохранить профиль RTX для {{material}}: {{reason}}" )

R( "rtx.yes", "yes", "是", "はい", "예", "oui", "да" )
R( "rtx.no", "no", "否", "いいえ", "아니요", "non", "нет" )
R( "rtx.cap_tracking", "Legacy hash tracking: {{state}}", "旧式材质哈希跟踪：{{state}}", "従来型ハッシュの追跡：{{state}}", "기존 해시 추적: {{state}}", "Suivi des hachages de l’ancien pipeline : {{state}}", "Отслеживание хешей старого конвейера: {{state}}" )
R( "rtx.cap_inspection", "Source material inspection: {{state}}", "Source 材质检查：{{state}}", "Source マテリアルの検査：{{state}}", "Source 재질 검사: {{state}}", "Inspection des matériaux Source : {{state}}", "Анализ материалов Source: {{state}}" )
R( "rtx.cap_writer", "Native legacy writer: {{state}}", "原生旧式材质写入模块：{{state}}", "従来型マテリアルのネイティブ書き込み：{{state}}", "기존 재질 네이티브 쓰기 모듈: {{state}}", "Module d’écriture natif pour l’ancien pipeline : {{state}}", "Нативный модуль записи для старого конвейера: {{state}}" )
R( "rtx.cap_preview", "World preview: {{state}}", "世界预览：{{state}}", "ワールド内プレビュー：{{state}}", "월드 미리보기: {{state}}", "Aperçu dans le monde : {{state}}", "Предпросмотр в игровом мире: {{state}}" )
R( "rtx.cap_texture", "DDS/map writer: {{state}}", "DDS / 贴图写入模块：{{state}}", "DDS / マップ書き込み：{{state}}", "DDS/맵 쓰기 모듈: {{state}}", "Module d’écriture DDS/maps : {{state}}", "Модуль записи DDS/карт: {{state}}" )

R( "rtx.inspect.shaderName", "Shader: {{value}}", "着色器：{{value}}", "シェーダー：{{value}}", "셰이더: {{value}}", "Shader : {{value}}", "Шейдер: {{value}}" )
R( "rtx.inspect.baseTexture", "Base texture: {{value}}", "基础纹理：{{value}}", "ベーステクスチャ：{{value}}", "기본 텍스처: {{value}}", "Texture de base : {{value}}", "Базовая текстура: {{value}}" )
R( "rtx.inspect.bumpMap", "Bump / normal map: {{value}}", "凹凸 / 法线贴图：{{value}}", "バンプ / 法線マップ：{{value}}", "범프/노멀 맵: {{value}}", "Map de relief / normales : {{value}}", "Карта рельефа / нормалей: {{value}}" )
R( "rtx.inspect.roughness", "Roughness: {{value}}", "粗糙度：{{value}}", "粗さ：{{value}}", "거칠기: {{value}}", "Rugosité : {{value}}", "Шероховатость: {{value}}" )
R( "rtx.inspect.metallic", "Metallic: {{value}}", "金属度：{{value}}", "メタリック：{{value}}", "금속성: {{value}}", "Métallique : {{value}}", "Металличность: {{value}}" )
R( "rtx.inspect.detectedFormat", "Detected format: {{value}}", "检测到的格式：{{value}}", "検出形式：{{value}}", "감지된 형식: {{value}}", "Format détecté : {{value}}", "Определённый формат: {{value}}" )
R( "rtx.inspect.surfaceProp", "Surface property: {{value}}", "表面属性：{{value}}", "サーフェスプロパティ：{{value}}", "표면 속성: {{value}}", "Propriété de surface : {{value}}", "Свойство поверхности: {{value}}" )

-- RTX Remix enhancement mods (cl_28_rtx_enhance.lua)
R( "rtx.enh.title", "RTX Remix enhancement", "RTX Remix 增强", "RTX Remix エンハンスメント", "RTX Remix 인핸스먼트", "Amélioration RTX Remix", "Улучшение RTX Remix" )
R( "rtx.enh.source", "{{mod}}  •  {{layer}}  •  {{shader}}", "{{mod}}  •  {{layer}}  •  {{shader}}", "{{mod}}  •  {{layer}}  •  {{shader}}", "{{mod}}  •  {{layer}}  •  {{shader}}", "{{mod}}  •  {{layer}}  •  {{shader}}", "{{mod}}  •  {{layer}}  •  {{shader}}" )
R( "rtx.enh.active", "Remix draws this enhancement. These controls start from it, and a Save keeps every map and value you do not change.", "Remix 正在使用此增强进行渲染。下方控件以它为起点，保存时会保留所有你未改动的贴图和数值。", "Remix はこのエンハンスメントで描画しています。下のコントロールはこれを起点とし、保存しても変更していないマップや値はすべてそのまま残ります。", "Remix가 이 인핸스먼트로 렌더링하고 있습니다. 아래 컨트롤은 이것에서 시작하며, 저장해도 바꾸지 않은 맵과 값은 모두 그대로 유지됩니다.", "Remix affiche cette amélioration. Ces réglages partent d’elle, et l’enregistrement conserve toutes les maps et valeurs que vous ne modifiez pas.", "Remix отображает это улучшение. Эти параметры начинаются с него, а при сохранении все карты и значения, которые вы не меняли, сохраняются." )
R( "rtx.enh.overridden", "Your AME profile replaces this enhancement. Remove override to return to it.", "你的 AME 配置正在取代此增强。移除覆盖即可恢复为该增强。", "AME のプロファイルがこのエンハンスメントを置き換えています。上書きを削除すると元に戻ります。", "AME 프로필이 이 인핸스먼트를 대체하고 있습니다. 재정의를 제거하면 인핸스먼트로 돌아갑니다.", "Votre profil AME remplace cette amélioration. Supprimez le remplacement pour y revenir.", "Ваш профиль AME заменяет это улучшение. Удалите переопределение, чтобы вернуться к нему." )
R( "rtx.enh.automatic", "Made automatically by the RTX client's ToPBR pass from the Source material. AME does not start from it, and a Save replaces it.", "由 RTX 客户端的 ToPBR 流程根据 Source 材质自动生成。AME 不会以它为起点，保存时会将其取代。", "RTX クライアントの ToPBR 処理が Source マテリアルから自動生成したものです。AME はこれを起点にせず、保存するとこれを置き換えます。", "RTX 클라이언트의 ToPBR 과정이 Source 재질로부터 자동 생성한 것입니다. AME는 이것을 시작점으로 쓰지 않으며, 저장하면 이것을 대체합니다.", "Créée automatiquement par l’étape ToPBR du client RTX à partir du matériau Source. AME ne part pas d’elle, et l’enregistrement la remplace.", "Создано автоматически этапом ToPBR клиента RTX из материала Source. AME не берёт его за основу, и сохранение его заменит." )
R( "rtx.enh.shader_warning", "This enhancement is a {{shader}} material. AME writes opaque AperturePBR materials only, so a Save replaces it with an opaque surface.", "此增强是 {{shader}} 材质。AME 只能写入不透明的 AperturePBR 材质，因此保存会将其替换为不透明表面。", "このエンハンスメントは {{shader}} マテリアルです。AME は不透明な AperturePBR マテリアルしか書き出せないため、保存すると不透明な表面に置き換わります。", "이 인핸스먼트는 {{shader}} 재질입니다. AME는 불투명 AperturePBR 재질만 기록할 수 있으므로 저장하면 불투명 표면으로 대체됩니다.", "Cette amélioration est un matériau {{shader}}. AME n’écrit que des matériaux AperturePBR opaques : l’enregistrement la remplace par une surface opaque.", "Это улучшение — материал {{shader}}. AME записывает только непрозрачные материалы AperturePBR, поэтому сохранение заменит его непрозрачной поверхностью." )
R( "rtx.enh.unsupported", "Not kept by a Save (AME has no control for them): {{inputs}}", "保存时不会保留（AME 没有对应的控件）：{{inputs}}", "保存しても保持されません（AME に対応する設定がありません）：{{inputs}}", "저장 시 유지되지 않음(AME에 해당 컨트롤이 없음): {{inputs}}", "Non conservés à l’enregistrement (AME n’a pas de réglage pour eux) : {{inputs}}", "Не сохраняются (в AME нет для них параметров): {{inputs}}" )
R( "rtx.enh.clamped", "Outside AME's range, so a Save changes them: {{inputs}}", "超出 AME 的取值范围，保存时会被修改：{{inputs}}", "AME の範囲外のため、保存すると値が変わります：{{inputs}}", "AME 범위를 벗어나 저장 시 값이 바뀝니다: {{inputs}}", "Hors de la plage d’AME, l’enregistrement les modifie : {{inputs}}", "Вне диапазона AME, при сохранении изменятся: {{inputs}}" )
R( "rtx.enh.unreadable_maps", "{{count}} map(s) the enhancement names cannot be used: the file is missing or outside the game folder.", "此增强引用的 {{count}} 张贴图无法使用：文件缺失或位于游戏文件夹之外。", "このエンハンスメントが指定する {{count}} 枚のマップは使用できません。ファイルが存在しないか、ゲームフォルダーの外にあります。", "이 인핸스먼트가 지정한 맵 {{count}}개를 사용할 수 없습니다. 파일이 없거나 게임 폴더 밖에 있습니다.", "{{count}} map(s) désignée(s) par l’amélioration sont inutilisables : fichier absent ou hors du dossier du jeu.", "Карты ({{count}}), указанные улучшением, нельзя использовать: файл отсутствует или находится вне папки игры." )
R( "rtx.enh.stale", "This profile names enhancement files that no longer exist ({{maps}}): the enhancement was rebuilt. Use its values to start again from it.", "此配置引用的增强文件已不存在（{{maps}}）：该增强已被重新生成。请使用增强数值，从它重新开始。", "このプロファイルが指定するエンハンスメントのファイル（{{maps}}）はもう存在しません。エンハンスメントが作り直されています。その値を使ってやり直してください。", "이 프로필이 지정한 인핸스먼트 파일({{maps}})이 더 이상 없습니다. 인핸스먼트가 다시 만들어졌습니다. 해당 값으로 다시 시작하세요.", "Ce profil désigne des fichiers d’amélioration qui n’existent plus ({{maps}}) : l’amélioration a été reconstruite. Reprenez ses valeurs pour repartir d’elle.", "Профиль ссылается на файлы улучшения, которых больше нет ({{maps}}): улучшение было пересобрано. Возьмите его значения, чтобы начать заново." )
R( "rtx.enh.carry", "{{count}} map(s) cannot go to the installed RTX bridge as they are (over {{limit}} px, in a linked mod folder, or with operations); AME saves decoded copies of them, at most {{copy}} px. The enhancement's own files are not changed.", "{{count}} 张贴图无法原样交给已安装的 RTX 桥接（超过 {{limit}} px、位于链接的模组文件夹中，或带有运算）；AME 会为其保存解码后的副本，最大 {{copy}} px。增强自身的文件不会被修改。", "{{count}} 枚のマップは、インストール済みの RTX ブリッジにそのままでは渡せません（{{limit}} px 超、リンクされた MOD フォルダー内、または演算あり）。AME はそれらをデコードしたコピー（最大 {{copy}} px）として保存します。エンハンスメント自体のファイルは変更されません。", "맵 {{count}}개는 설치된 RTX 브리지에 그대로 넘길 수 없습니다({{limit}} px 초과, 링크된 모드 폴더 안, 또는 연산 있음). AME는 이를 디코딩한 사본(최대 {{copy}} px)으로 저장합니다. 인핸스먼트 자체 파일은 바뀌지 않습니다.", "{{count}} map(s) ne peuvent pas être transmises telles quelles au pont RTX installé (plus de {{limit}} px, dossier de mod lié ou opérations) ; AME en enregistre des copies décodées d’au plus {{copy}} px. Les fichiers de l’amélioration ne sont pas modifiés.", "Карты ({{count}}) нельзя передать установленному мосту RTX как есть (больше {{limit}} px, в связанной папке мода или с операциями); AME сохраняет их декодированные копии размером до {{copy}} px. Файлы самого улучшения не меняются." )
R( "rtx.enh.edit_fit", "{{count}} edited map(s) are larger than the installed RTX bridge decodes, so Remix gets copies of them at most {{copy}} px. The edits themselves keep their size.", "{{count}} 张编辑过的贴图超过已安装的 RTX 桥接可解码的尺寸，因此 Remix 得到的是最大 {{copy}} px 的副本。编辑本身保持原尺寸。", "編集した {{count}} 枚のマップは、インストール済みの RTX ブリッジがデコードできるサイズを超えているため、Remix には最大 {{copy}} px のコピーが渡されます。編集自体のサイズは変わりません。", "편집한 맵 {{count}}개는 설치된 RTX 브리지가 디코딩할 수 있는 크기보다 커서, Remix에는 최대 {{copy}} px 사본이 전달됩니다. 편집 자체의 크기는 그대로입니다.", "{{count}} map(s) modifiée(s) dépassent ce que le pont RTX installé sait décoder ; Remix en reçoit donc des copies d’au plus {{copy}} px. Les modifications elles-mêmes gardent leur taille.", "Изменённые карты ({{count}}) больше, чем может декодировать установленный мост RTX, поэтому Remix получает их копии размером до {{copy}} px. Сами правки сохраняют свой размер." )
R( "rtx.enh.reread", "Re-read enhancements", "重新读取增强", "エンハンスメントを再読み込み", "인핸스먼트 다시 읽기", "Relire les améliorations", "Перечитать улучшения" )
R( "rtx.enh.reread_tip", "Read every mod in rtx-remix/mods again, for example after publishing new enhancement files.", "重新读取 rtx-remix/mods 中的所有模组，例如在发布新的增强文件之后。", "rtx-remix/mods 内のすべての MOD を読み直します。新しいエンハンスメントファイルを公開した後などに使います。", "rtx-remix/mods의 모든 모드를 다시 읽습니다. 예를 들어 새 인핸스먼트 파일을 게시한 뒤에 사용합니다.", "Relit tous les mods de rtx-remix/mods, par exemple après la publication de nouveaux fichiers d’amélioration.", "Заново прочитать все моды в rtx-remix/mods, например после публикации новых файлов улучшения." )
R( "rtx.enh.reread_done", "Read {{mods}} Remix mod(s) with {{materials}} material(s) in {{ms}} ms.", "已读取 {{mods}} 个 Remix 模组，共 {{materials}} 个材质，用时 {{ms}} 毫秒。", "{{mods}} 個の Remix MOD（マテリアル {{materials}} 個）を {{ms}} ミリ秒で読み込みました。", "Remix 모드 {{mods}}개(재질 {{materials}}개)를 {{ms}}ms 만에 읽었습니다.", "{{mods}} mod(s) Remix lu(s), {{materials}} matériau(x), en {{ms}} ms.", "Прочитано модов Remix: {{mods}}, материалов: {{materials}}, за {{ms}} мс." )
R( "rtx.enh.use", "Use enhancement values", "使用增强数值", "エンハンスメントの値を使う", "인핸스먼트 값 사용", "Utiliser les valeurs de l’amélioration", "Взять значения улучшения" )
R( "rtx.enh.use_tip", "Replace this working copy with the enhancement's current maps and values. Save to keep it; Undo brings your copy back.", "用增强当前的贴图和数值替换此工作副本。保存即可保留；撤销可恢复你的副本。", "この作業コピーをエンハンスメントの現在のマップと値に置き換えます。保存すると確定し、元に戻すで以前のコピーに戻せます。", "이 작업 사본을 인핸스먼트의 현재 맵과 값으로 바꿉니다. 저장하면 유지되고, 실행 취소로 이전 사본을 되돌릴 수 있습니다.", "Remplace cette copie de travail par les maps et valeurs actuelles de l’amélioration. Enregistrez pour la garder ; Annuler rétablit votre copie.", "Заменить рабочую копию текущими картами и значениями улучшения. Сохраните, чтобы оставить; «Отменить» вернёт вашу копию." )
R( "rtx.enh.from", "From {{mod}}", "来自 {{mod}}", "{{mod}} から", "{{mod}}에서", "Depuis {{mod}}", "Из {{mod}}" )
R( "rtx.enh.preparing", "Preparing {{file}} for editing…", "正在准备编辑 {{file}}…", "{{file}} を編集用に準備しています…", "{{file}}을(를) 편집용으로 준비하는 중…", "Préparation de {{file}} pour la modification…", "Подготовка {{file}} к редактированию…" )
R( "rtx.enh.prepare_failed", "Could not read {{file}}: {{reason}}", "无法读取 {{file}}：{{reason}}", "{{file}} を読み込めませんでした：{{reason}}", "{{file}}을(를) 읽을 수 없습니다: {{reason}}", "Impossible de lire {{file}} : {{reason}}", "Не удалось прочитать {{file}}: {{reason}}" )
R( "rtx.enh.normal_source", "The normal map is made from the Source base texture: the enhancement's albedo is a DDS file the generator cannot read.", "法线贴图将根据 Source 基础纹理生成：增强的反照率贴图是生成器无法读取的 DDS 文件。", "法線マップは Source のベーステクスチャから作られます。エンハンスメントのアルベドは、ジェネレーターが読めない DDS ファイルです。", "노멀 맵은 Source 기본 텍스처로 만들어집니다. 인핸스먼트의 알베도는 생성기가 읽을 수 없는 DDS 파일입니다.", "La map de normales est créée à partir de la texture de base Source : l’albédo de l’amélioration est un fichier DDS que le générateur ne peut pas lire.", "Карта нормалей создаётся из базовой текстуры Source: альбедо улучшения — файл DDS, который генератор не может прочитать." )
R( "rtx.enh.diag_title", "RTX Remix mods replacing this hash", "替换此哈希的 RTX Remix 模组", "このハッシュを置き換える RTX Remix MOD", "이 해시를 대체하는 RTX Remix 모드", "Mods RTX Remix qui remplacent ce hachage", "Моды RTX Remix, заменяющие этот хеш" )
R( "rtx.enh.diag_own", "AME profile", "AME 配置", "AME プロファイル", "AME 프로필", "profil AME", "профиль AME" )
R( "rtx.enh.diag_automatic", "automatic ToPBR material", "ToPBR 自动材质", "ToPBR の自動マテリアル", "ToPBR 자동 재질", "matériau ToPBR automatique", "автоматический материал ToPBR" )
R( "rtx.enh.diag_enhancement", "enhancement", "增强", "エンハンスメント", "인핸스먼트", "amélioration", "улучшение" )
R( "rtx.enh.diag_drawn", "drawn", "正在渲染", "描画中", "렌더링 중", "affiché", "отображается" )
R( "rtx.enh.diag_hidden", "hidden by a mod before it", "被排在前面的模组遮盖", "前の MOD に隠されています", "앞선 모드에 가려짐", "masqué par un mod placé avant", "перекрыт модом перед ним" )
R( "rtx.enh.diag_none", "No mod in rtx-remix/mods replaces this hash.", "rtx-remix/mods 中没有模组替换此哈希。", "rtx-remix/mods にこのハッシュを置き換える MOD はありません。", "rtx-remix/mods에 이 해시를 대체하는 모드가 없습니다.", "Aucun mod de rtx-remix/mods ne remplace ce hachage.", "Ни один мод в rtx-remix/mods не заменяет этот хеш." )
R( "rtx.enh.diag_errors", "Could not read: {{list}}", "无法读取：{{list}}", "読み込めませんでした：{{list}}", "읽을 수 없음: {{list}}", "Lecture impossible : {{list}}", "Не удалось прочитать: {{list}}" )
R( "rtx.enh.confirm_shader", "{{material}} is drawn from a {{shader}} enhancement in {{mod}}. AME writes opaque materials only, so saving replaces it with an opaque surface. Save anyway?", "{{material}} 正在使用 {{mod}} 中的 {{shader}} 增强进行渲染。AME 只能写入不透明材质，保存会将其替换为不透明表面。仍要保存吗？", "{{material}} は {{mod}} の {{shader}} エンハンスメントで描画されています。AME は不透明マテリアルしか書き出せないため、保存すると不透明な表面に置き換わります。それでも保存しますか？", "{{material}}은(는) {{mod}}의 {{shader}} 인핸스먼트로 렌더링되고 있습니다. AME는 불투명 재질만 기록하므로 저장하면 불투명 표면으로 대체됩니다. 그래도 저장할까요?", "{{material}} est affiché par une amélioration {{shader}} de {{mod}}. AME n’écrit que des matériaux opaques : l’enregistrement la remplace par une surface opaque. Enregistrer quand même ?", "{{material}} отображается улучшением {{shader}} из {{mod}}. AME записывает только непрозрачные материалы, поэтому сохранение заменит его непрозрачной поверхностью. Всё равно сохранить?" )
R( "rtx.enh.confirm_title", "Replace this enhancement?", "要取代此增强吗？", "このエンハンスメントを置き換えますか？", "이 인핸스먼트를 대체할까요?", "Remplacer cette amélioration ?", "Заменить это улучшение?" )
R( "rtx.enh.confirm_save", "Save anyway", "仍然保存", "それでも保存", "그래도 저장", "Enregistrer quand même", "Всё равно сохранить" )
R( "rtx.enh.removed", "RTX material override removed. Remix draws the {{mod}} enhancement again.", "RTX 材质覆盖已移除。Remix 重新使用 {{mod}} 增强进行渲染。", "RTX マテリアルの上書きを削除しました。Remix は再び {{mod}} のエンハンスメントで描画します。", "RTX 재질 재정의를 제거했습니다. Remix가 다시 {{mod}} 인핸스먼트로 렌더링합니다.", "Remplacement du matériau RTX supprimé. Remix affiche de nouveau l’amélioration de {{mod}}.", "Переопределение материала RTX удалено. Remix снова отображает улучшение из {{mod}}." )

R( "common.ok", "OK", "确定", "OK", "확인", "OK", "ОК" )
R( "common.cancel", "Cancel", "取消", "キャンセル", "취소", "Annuler", "Отмена" )
R( "common.close", "Close", "关闭", "閉じる", "닫기", "Fermer", "Закрыть" )
R( "common.save", "Save", "保存", "保存", "저장", "Enregistrer", "Сохранить" )
R( "common.undo", "Undo", "撤销", "元に戻す", "실행 취소", "Annuler", "Отменить" )
R( "common.redo", "Redo", "重做", "やり直す", "다시 실행", "Rétablir", "Повторить" )
R( "common.edit", "Edit", "编辑", "編集", "편집", "Modifier", "Изменить" )
R( "common.clear", "Clear", "清除", "クリア", "지우기", "Effacer", "Очистить" )
R( "common.reset", "Reset", "重置", "リセット", "초기화", "Réinitialiser", "Сбросить" )
R( "common.drop", "Drop", "丢弃", "破棄", "버리기", "Abandonner", "Удалить" )
R( "common.make", "Make", "生成", "作成", "만들기", "Créer", "Создать" )
R( "common.adjust", "Adjust", "调整", "調整", "조정", "Ajuster", "Настроить" )
R( "common.hide", "Hide", "隐藏", "隠す", "숨기기", "Masquer", "Скрыть" )
R( "common.play", "Play", "播放", "再生", "재생", "Lire", "Воспроизвести" )
R( "common.stop", "Stop", "停止", "停止", "정지", "Arrêter", "Остановить" )
R( "common.none", "Nothing here.", "此处没有内容。", "ここには何もありません。", "여기에 아무것도 없습니다.", "Rien ici.", "Здесь ничего нет." )
R( "common.unchanged", "unchanged", "不变", "変更なし", "변경 없음", "inchangé", "без изменений" )
R( "common.copied", "Copied.", "已复制。", "コピーしました。", "복사했습니다.", "Copié.", "Скопировано." )
R( "common.generating", "generating...", "正在生成…", "生成中…", "생성 중…", "génération…", "создание…" )
R( "common.nothing_loaded", "Nothing loaded", "未载入任何内容", "何も読み込まれていません", "불러온 항목 없음", "Rien de chargé", "Ничего не загружено" )
R( "common.off", "off", "关闭", "オフ", "꺼짐", "inactif", "выкл." )
R( "common.generated", "generated", "已生成", "生成済み", "생성됨", "généré", "создано" )
R( "common.blank_image", "a blank image", "空白图像", "空画像", "빈 이미지", "une image vide", "пустое изображение" )

R( "window.drag_tip", "Drag the title bar to move this window.", "拖动标题栏可移动此窗口。", "タイトルバーをドラッグすると、このウィンドウを移動できます。", "제목 표시줄을 드래그하여 이 창을 이동하세요.", "Faites glisser la barre de titre pour déplacer cette fenêtre.", "Перетащите окно за строку заголовка." )
R( "window.resize_tip", "Drag the lower-right corner to resize this window.", "拖动右下角可调整此窗口的大小。", "右下隅をドラッグすると、このウィンドウのサイズを変更できます。", "오른쪽 아래 모서리를 드래그하여 이 창의 크기를 조절하세요.", "Faites glisser le coin inférieur droit pour redimensionner cette fenêtre.", "Перетащите правый нижний угол, чтобы изменить размер окна." )
R( "window.move_resize_hint", "Drag title bar to move • drag lower-right corner to resize", "拖动标题栏移动 • 拖动右下角调整大小", "タイトルバーで移動 • 右下隅でサイズ変更", "제목 표시줄로 이동 • 오른쪽 아래 모서리로 크기 조절", "Barre de titre : déplacer • coin inférieur droit : redimensionner", "Заголовок — перемещение • правый нижний угол — размер" )
R( "window.move_beside", "Move beside target", "移到编辑目标旁", "編集対象の横へ移動", "편집 대상 옆으로 이동", "Placer à côté de la cible", "Переместить к объекту" )
R( "window.move_beside_tip", "Move this window beside the object you are editing.", "将此窗口移到正在编辑的目标旁边。", "このウィンドウを編集中の対象の横へ移動します。", "이 창을 편집 중인 대상 옆으로 이동합니다.", "Place cette fenêtre à côté de l’objet en cours de modification.", "Перемещает окно рядом с редактируемым объектом." )

R( "editor.title", "Advanced Material Editor", "高级材质编辑器", "高機能マテリアルエディター", "고급 재질 편집기", "Éditeur de matériaux avancé", "Расширенный редактор материалов" )
R( "editor.save_target", "Save target:", "保存目标：", "保存先：", "저장 대상:", "Cible d’enregistrement :", "Область сохранения:" )
R( "editor.size", "Size:", "大小：", "サイズ：", "크기:", "Taille :", "Размер:" )
R( "editor.window_size", "Window size:", "窗口大小：", "ウィンドウサイズ：", "창 크기:", "Taille de la fenêtre :", "Размер окна:" )
R( "editor.allow_movement", "Allow player movement while editing", "编辑时允许玩家移动", "編集中もプレイヤーの移動を許可", "편집 중 플레이어 이동 허용", "Autoriser les déplacements pendant l’édition", "Разрешить движение игрока при редактировании" )
R( "editor.allow_movement_tip", "Movement keys control your player while the editor remains open. Hold RMB over the visible world to look around; release it to edit. Text fields capture the keyboard while you type.", "编辑器保持打开时，移动键仍可控制玩家。将鼠标移到可见的游戏世界上并按住鼠标右键可环顾四周；松开右键即可继续编辑。输入文字时，文本框会接管键盘输入。", "エディターを開いたまま、移動キーでプレイヤーを操作できます。画面に見えているゲーム世界上で右マウスボタンを押し続けると周囲を見回せ、離すと編集に戻ります。テキスト入力中は、その欄がキーボード入力を受け取ります。", "편집기를 연 상태에서도 이동 키로 플레이어를 조작할 수 있습니다. 화면에 보이는 게임 월드 위에서 마우스 오른쪽 버튼을 누르고 있으면 주변을 둘러볼 수 있으며, 놓으면 편집으로 돌아갑니다. 텍스트 입력란은 입력하는 동안 키보드 입력을 사용합니다.", "Les touches de déplacement contrôlent votre personnage pendant que l’éditeur reste ouvert. Maintenez le bouton droit de la souris au-dessus de la partie visible du monde pour regarder autour de vous ; relâchez-le pour reprendre l’édition. Les champs de texte capturent le clavier pendant la saisie.", "Клавиши движения управляют игроком, пока редактор остаётся открытым. Удерживайте правую кнопку мыши над видимой областью игрового мира, чтобы осмотреться; отпустите её, чтобы вернуться к редактированию. Во время ввода текстовые поля перехватывают клавиатуру." )
R( "editor.player_controls_on", "Player controls enabled", "玩家控制已启用", "プレイヤー操作が有効", "플레이어 조작 활성화", "Commandes du joueur activées", "Управление игроком включено" )
R( "editor.player_controls_hint", "WASD to move • hold RMB over visible world to look • release to edit", "WASD 移动 • 在可见游戏世界上按住鼠标右键环顾 • 松开右键继续编辑", "WASD で移動 • 表示中のゲーム世界上で右マウスボタンを押して見回す • 離して編集に戻る", "WASD로 이동 • 보이는 게임 월드 위에서 마우스 오른쪽 버튼을 눌러 둘러보기 • 놓으면 편집", "WASD : se déplacer • maintenir le bouton droit sur le monde visible : regarder • relâcher : modifier", "WASD — движение • удерживайте ПКМ над видимой областью мира, чтобы осмотреться • отпустите для редактирования" )
R( "editor.shader", "Shader", "着色器", "シェーダー", "셰이더", "Shader", "Шейдер" )
R( "editor.submaterials", "Sub-materials", "子材质", "サブマテリアル", "하위 재질", "Sous-matériaux", "Подматериалы" )
R( "editor.select_material", "Select a sub-material on the left", "请在左侧选择一个子材质", "左側でサブマテリアルを選択してください", "왼쪽에서 하위 재질을 선택하세요", "Sélectionnez un sous-matériau à gauche", "Выберите подматериал слева" )
R( "editor.live", "Live preview", "实时预览", "ライブプレビュー", "실시간 미리보기", "Aperçu en direct", "Предпросмотр в реальном времени" )
R( "editor.highlight", "Highlight selected sub-material", "高亮所选子材质", "選択中のサブマテリアルを強調", "선택한 하위 재질 강조", "Surligner le sous-matériau sélectionné", "Подсветить выбранный подматериал" )
R( "editor.show_all", "Show every supported parameter", "显示所有支持的参数", "対応する全パラメーターを表示", "지원되는 모든 매개변수 표시", "Afficher tous les paramètres pris en charge", "Показать все поддерживаемые параметры" )
R( "editor.search", "Search parameters by name or description...", "按名称或说明搜索参数…", "名前または説明でパラメーターを検索…", "이름 또는 설명으로 매개변수 검색…", "Rechercher les paramètres par nom ou description…", "Поиск параметров по имени или описанию…" )
R( "editor.no_matches", "  Nothing matches. Try turning on \"Show every supported parameter\".", "  没有匹配项。请尝试开启“显示所有支持的参数”。", "  一致する項目がありません。「対応する全パラメーターを表示」を有効にしてください。", "  일치하는 항목이 없습니다. ‘지원되는 모든 매개변수 표시’를 켜 보세요.", "  Aucun résultat. Essayez d’activer « Afficher tous les paramètres pris en charge ».", "  Совпадений нет. Попробуйте включить «Показать все поддерживаемые параметры»." )
R( "editor.add_parameter", "Add a parameter by name...", "按名称添加参数…", "名前でパラメーターを追加…", "이름으로 매개변수 추가…", "Ajouter un paramètre par son nom…", "Добавить параметр по имени…" )
R( "editor.add_parameter_title", "Add parameter", "添加参数", "パラメーターを追加", "매개변수 추가", "Ajouter un paramètre", "Добавить параметр" )
R( "editor.add_parameter_prompt", "VMT parameter name, including the $ or % sigil:", "VMT 参数名称（包括 $ 或 % 前缀）：", "VMT パラメーター名（$ または % 記号を含む）：", "$ 또는 % 기호를 포함한 VMT 매개변수 이름:", "Nom du paramètre VMT, avec le signe $ ou % :", "Имя параметра VMT, включая знак $ или %:" )
R( "editor.preset_title", "Save preset", "保存预设", "プリセットを保存", "프리셋 저장", "Enregistrer le préréglage", "Сохранить предустановку" )
R( "editor.preset_prompt", "Preset name:", "预设名称：", "プリセット名：", "프리셋 이름:", "Nom du préréglage :", "Имя предустановки:" )
R( "editor.preset_default", "my preset", "我的预设", "マイプリセット", "내 프리셋", "mon préréglage", "моя предустановка" )
R( "editor.reset_default", "Reset to Default", "恢复默认值", "既定値に戻す", "기본값으로 초기화", "Rétablir les valeurs par défaut", "Восстановить значения по умолчанию" )
R( "editor.presets", "Presets", "预设", "プリセット", "프리셋", "Préréglages", "Предустановки" )
R( "editor.trace", "Trace", "跟踪", "トレース", "추적", "Tracer", "Трассировка" )
R( "editor.copy_vmt", "Copy .vmt", "复制 .vmt", ".vmt をコピー", ".vmt 복사", "Copier le .vmt", "Копировать .vmt" )
R( "editor.scope_entity", "This entity only", "仅此实体", "このエンティティのみ", "이 엔티티만", "Cette entité uniquement", "Только этот объект" )
R( "editor.scope_model", "Every prop with this model", "使用此模型的所有物件", "このモデルを使う全プロップ", "이 모델을 사용하는 모든 프롭", "Tous les props utilisant ce modèle", "Все объекты с этой моделью" )
R( "editor.scope_material", "Every material with this path", "使用此路径的所有材质", "このパスを使う全マテリアル", "이 경로를 사용하는 모든 재질", "Tous les matériaux ayant ce chemin", "Все материалы с этим путём" )
R( "editor.scope_surface", "This map surface material", "此地图表面材质", "このマップ表面のマテリアル", "이 맵 표면 재질", "Ce matériau de surface de la carte", "Этот материал поверхности карты" )
R( "editor.size_auto", "Auto", "自动", "自動", "자동", "Auto", "Авто" )
R( "editor.size_small", "Small", "小", "小", "작게", "Petite", "Маленький" )
R( "editor.size_medium", "Medium", "中", "中", "중간", "Moyenne", "Средний" )
R( "editor.size_large", "Large", "大", "大", "크게", "Grande", "Большой" )
R( "editor.size_max", "Maximised", "最大化", "最大化", "최대화", "Maximisée", "Развёрнуто" )
R( "editor.scope_tip", "Where Save writes the override to.", "“保存”会将覆盖写入此范围。", "「保存」が上書きを書き込む範囲です。", "‘저장’이 재정의를 기록할 범위입니다.", "Définit où Enregistrer écrit le remplacement.", "Определяет, куда «Сохранить» записывает переопределение." )
R( "editor.size_tip", "Window size. Auto follows your screen resolution.", "窗口大小。“自动”会根据屏幕分辨率调整。", "ウィンドウサイズ。「自動」は画面解像度に合わせます。", "창 크기입니다. ‘자동’은 화면 해상도에 맞춥니다.", "Taille de la fenêtre. Auto suit la résolution de votre écran.", "Размер окна. «Авто» подстраивается под разрешение экрана." )
R( "editor.live_tip", "Show unsaved changes on the real prop, for you only.", "仅为你在实际物件上显示未保存的更改。", "未保存の変更を自分だけ実物のプロップに表示します。", "저장하지 않은 변경 사항을 실제 프롭에 나에게만 표시합니다.", "Affiche les modifications non enregistrées sur le prop réel, pour vous uniquement.", "Показывает несохранённые изменения на реальном объекте только вам." )
R( "editor.highlight_tip", "Paints the selected slot magenta in the preview.\nUse this to confirm you are editing the part you think you are.", "在预览中以洋红色显示所选槽位。\n可用于确认正在编辑预期的部件。", "選択スロットをプレビューでマゼンタ表示します。\n意図した部分を編集しているか確認できます。", "선택한 슬롯을 미리보기에서 자홍색으로 표시합니다.\n원하는 부분을 편집 중인지 확인할 수 있습니다.", "Colore en magenta l’emplacement sélectionné dans l’aperçu.\nPermet de confirmer que vous modifiez la bonne partie.", "Окрашивает выбранный слот в пурпурный цвет в предпросмотре.\nПомогает убедиться, что редактируется нужная часть." )
R( "editor.save_tip", "Store these settings on the server so they come back every map load.", "将这些设置保存到服务器，以便每次载入地图时恢复。", "設定をサーバーに保存し、マップ読み込み時に復元します。", "이 설정을 서버에 저장하여 맵을 불러올 때마다 복원합니다.", "Enregistre ces réglages sur le serveur afin de les restaurer à chaque chargement de carte.", "Сохранить настройки на сервере, чтобы они восстанавливались при каждой загрузке карты." )
R( "editor.undo_tip", "Throw away every unsaved change and go back to what is saved.", "丢弃所有未保存的更改并恢复为已保存状态。", "未保存の変更をすべて破棄して保存済み状態に戻します。", "저장하지 않은 모든 변경 사항을 버리고 저장된 상태로 돌아갑니다.", "Abandonne toutes les modifications non enregistrées et revient à l’état enregistré.", "Отбросить все несохранённые изменения и вернуться к сохранённому состоянию." )
R( "editor.reset_tip", "Put the selected sub-material back to how the model shipped, deleting every saved override on it in all three scopes.", "将所选子材质恢复为模型原始状态，并删除其在全部三个范围内保存的覆盖。", "選択したサブマテリアルを元の状態に戻し、3つの範囲すべての保存済み上書きを削除します。", "선택한 하위 재질을 원래 상태로 되돌리고 세 범위에 저장된 모든 재정의를 삭제합니다.", "Rétablit le sous-matériau sélectionné tel qu’il était fourni et supprime ses remplacements enregistrés dans les trois portées.", "Вернуть выбранный подматериал к исходному виду и удалить его сохранённые переопределения во всех трёх областях." )
R( "editor.presets_tip", "Save, load or copy a set of parameters.", "保存、载入或复制一组参数。", "パラメーター一式を保存、読み込み、コピーします。", "매개변수 모음을 저장, 불러오기 또는 복사합니다.", "Enregistrer, charger ou copier un ensemble de paramètres.", "Сохранить, загрузить или скопировать набор параметров." )
R( "editor.filter_tip", "Type to narrow the list below. Matches parameter names and their descriptions.", "输入文本以筛选下方列表；会匹配参数名称和说明。", "入力して下の一覧を絞り込みます。パラメーター名と説明が検索対象です。", "입력하여 아래 목록을 좁힙니다. 매개변수 이름과 설명을 검색합니다.", "Saisissez du texte pour filtrer la liste. La recherche porte sur les noms et descriptions des paramètres.", "Введите текст для фильтрации списка. Поиск выполняется по именам и описаниям параметров." )
R( "editor.shader_tip", "Changing this rebuilds the material with a different shader.", "更改此项会使用其他着色器重建材质。", "変更すると別のシェーダーでマテリアルを再構築します。", "변경하면 다른 셰이더로 재질을 다시 빌드합니다.", "La modification reconstruit le matériau avec un shader différent.", "При изменении материал перестраивается с другим шейдером." )
R( "editor.save_preset", "Save these parameters as a preset...", "将这些参数保存为预设…", "これらのパラメーターをプリセットとして保存…", "이 매개변수를 프리셋으로 저장…", "Enregistrer ces paramètres comme préréglage…", "Сохранить эти параметры как предустановку…" )
R( "editor.copy_all", "Copy these parameters to every other sub-material", "将这些参数复制到所有其他子材质", "これらのパラメーターを他の全サブマテリアルにコピー", "이 매개변수를 다른 모든 하위 재질에 복사", "Copier ces paramètres vers tous les autres sous-matériaux", "Копировать эти параметры во все остальные подматериалы" )
R( "editor.prefix_surface", "Map surface    ", "地图表面    ", "マップ表面    ", "맵 표면    ", "Surface de carte    ", "Поверхность карты    " )
R( "editor.slot_tip", "{{material}}\nSlot {{slot}} (the index passed to Entity:SetSubMaterial)", "{{material}}\n槽位 {{slot}}（传给 Entity:SetSubMaterial 的索引）", "{{material}}\nスロット {{slot}}（Entity:SetSubMaterial に渡すインデックス）", "{{material}}\n슬롯 {{slot}}(Entity:SetSubMaterial에 전달되는 인덱스)", "{{material}}\nEmplacement {{slot}} (indice transmis à Entity:SetSubMaterial)", "{{material}}\nСлот {{slot}} (индекс, передаваемый Entity:SetSubMaterial)" )
R( "editor.world_in_place", "Edited in place: affects every surface using this .vmt, and only you see it.", "直接编辑：影响所有使用此 .vmt 的表面，且只有你能看到。", "直接編集：この .vmt を使うすべての面に影響し、自分にだけ表示されます。", "직접 편집: 이 .vmt를 사용하는 모든 표면에 영향을 주며 나에게만 보입니다.", "Modification directe : affecte toutes les surfaces utilisant ce .vmt et n’est visible que par vous.", "Прямое редактирование: влияет на все поверхности с этим .vmt и видно только вам." )
R( "editor.world_flags", "{{count}} flag parameter(s) cannot be changed on a map material at runtime.", "地图材质运行时无法更改 {{count}} 个标志参数。", "マップマテリアルでは実行時に {{count}} 個のフラグパラメーターを変更できません。", "맵 재질에서는 실행 중 플래그 매개변수 {{count}}개를 변경할 수 없습니다.", "{{count}} paramètre(s) d’indicateur ne peuvent pas être modifiés à l’exécution sur un matériau de carte.", "Параметры-флаги ({{count}} шт.) нельзя изменить у материала карты во время выполнения." )
R( "editor.brush_shader", "{{shader}} is a brush shader and will not render correctly on a model.", "{{shader}} 是笔刷着色器，无法在模型上正确渲染。", "{{shader}} はブラシ用シェーダーのため、モデルでは正しく描画されません。", "{{shader}}는 브러시 셰이더이므로 모델에서 올바르게 렌더링되지 않습니다.", "{{shader}} est un shader de brosse et ne s’affichera pas correctement sur un modèle.", "{{shader}} — шейдер поверхностей карты; на модели он будет отображаться неправильно." )
R( "editor.not_model_shader", "{{shader}} is not a model shader; expect fullbright or missing lighting.", "{{shader}} 不是模型着色器；可能出现全亮或缺少光照。", "{{shader}} はモデル用シェーダーではないため、フルブライトやライティング欠落が起こります。", "{{shader}}는 모델 셰이더가 아니므로 전체 밝기 또는 조명 누락이 발생할 수 있습니다.", "{{shader}} n’est pas un shader de modèle ; attendez-vous à un rendu en pleine luminosité ou sans éclairage.", "{{shader}} не является шейдером модели; возможен fullbright или отсутствие освещения." )
R( "editor.missing_vmt", "No .vmt found for this slot, so its original settings could not be read.", "未找到此槽位的 .vmt，因此无法读取其原始设置。", "このスロットの .vmt が見つからないため、元の設定を読み取れません。", "이 슬롯의 .vmt를 찾을 수 없어 원래 설정을 읽지 못했습니다.", "Aucun .vmt n’a été trouvé pour cet emplacement ; ses réglages d’origine n’ont donc pas pu être lus.", "Для этого слота не найден .vmt, поэтому исходные настройки прочитать не удалось." )
R( "editor.inert_count", "{{count}} parameter(s) you have set cannot render on this build; they are tagged \"off\" and the ? explains why.", "你设置的 {{count}} 个参数无法在此版本中渲染；它们标记为“关闭”，点击 ? 可查看原因。", "設定した {{count}} 個のパラメーターはこのビルドでは描画できません。「オフ」と表示され、? で理由を確認できます。", "설정한 매개변수 {{count}}개는 이 빌드에서 렌더링할 수 없습니다. ‘꺼짐’으로 표시되며 ?에서 이유를 확인할 수 있습니다.", "{{count}} paramètre(s) défini(s) ne peuvent pas être rendus dans cette version ; ils portent la mention « inactif » et le ? en explique la raison.", "Заданные параметры ({{count}} шт.) не работают в этой сборке; они помечены «выкл.», а кнопка ? объясняет причину." )
R( "editor.map_shader_locked", "A map material's shader cannot be changed at runtime.", "地图材质的着色器无法在运行时更改。", "マップマテリアルのシェーダーは実行時に変更できません。", "맵 재질의 셰이더는 실행 중 변경할 수 없습니다.", "Le shader d’un matériau de carte ne peut pas être modifié à l’exécution.", "Шейдер материала карты нельзя изменить во время выполнения." )

R( "row.remove", "Remove this override and fall back to the material's own value", "移除此覆盖并恢复材质自身的值", "この上書きを削除してマテリアル本来の値に戻します", "이 재정의를 제거하고 재질 자체 값으로 되돌립니다", "Supprime ce remplacement et rétablit la valeur propre au matériau", "Удалить переопределение и вернуться к значению самого материала" )
R( "row.help", "What does this do?", "这有什么作用？", "これは何をしますか？", "어떤 기능인가요?", "À quoi cela sert-il ?", "Что это делает?" )
R( "row.pick_colour", "Pick a colour", "选择颜色", "色を選択", "색상 선택", "Choisir une couleur", "Выбрать цвет" )
R( "row.vmt_literal", "VMT literal, for example [1 0.5 0.25]. Values above 1 are allowed for HDR tints.", "VMT 字面值，例如 [1 0.5 0.25]。HDR 色调允许使用大于 1 的值。", "VMT リテラル（例：[1 0.5 0.25]）。HDR ティントでは 1 を超える値も使用できます。", "VMT 리터럴(예: [1 0.5 0.25]). HDR 색조에는 1보다 큰 값도 사용할 수 있습니다.", "Valeur VMT littérale, par exemple [1 0.5 0.25]. Les teintes HDR acceptent des valeurs supérieures à 1.", "Литерал VMT, например [1 0.5 0.25]. Для HDR-оттенков допустимы значения больше 1." )
R( "row.browse", "Browse for a texture", "浏览纹理", "テクスチャを参照", "텍스처 찾아보기", "Parcourir les textures", "Выбрать текстуру" )
R( "row.make_tip", "Build this map automatically from another texture", "从另一张纹理自动生成此贴图", "別のテクスチャからこのマップを自動生成します", "다른 텍스처에서 이 맵을 자동으로 만듭니다", "Génère automatiquement cette map à partir d’une autre texture", "Автоматически создать эту карту из другой текстуры" )
R( "row.edit_tip", "Paint on this texture, recolour part of it, or cut a hole in it", "在此纹理上绘制、为局部重新着色或挖出透明区域", "このテクスチャへの描画、一部の色変更、穴開けを行います", "이 텍스처에 그리거나 일부 색상을 바꾸거나 구멍을 냅니다", "Peindre sur cette texture, en recolorer une partie ou y découper un trou", "Рисовать на текстуре, перекрашивать её части или вырезать отверстия" )
R( "row.import", "Import", "导入", "読み込み", "가져오기", "Importer", "Импорт" )
R( "row.import_tip", "Use an image from your computer (PNG or JPEG) as this texture. Model Hotloader opens a file window, and only the file you choose is read.", "将电脑中的图像（PNG 或 JPEG）用作此纹理。Model Hotloader 会打开文件窗口，只读取你选择的文件。", "PC 内の画像（PNG または JPEG）をこのテクスチャとして使います。Model Hotloader がファイル選択ウィンドウを開き、選んだファイルだけを読み込みます。", "컴퓨터에 있는 이미지(PNG 또는 JPEG)를 이 텍스처로 사용합니다. Model Hotloader가 파일 창을 열고, 선택한 파일만 읽습니다.", "Utilise une image de votre ordinateur (PNG ou JPEG) pour cette texture. Model Hotloader ouvre une fenêtre de fichiers, et seul le fichier choisi est lu.", "Использовать изображение с компьютера (PNG или JPEG) в качестве этой текстуры. Model Hotloader откроет окно выбора файла и прочитает только выбранный файл." )
R( "row.texture_placeholder", "models/folder/texture  (no materials/ prefix, no extension)", "models/文件夹/纹理  （无 materials/ 前缀和扩展名）", "models/フォルダー/テクスチャ  （materials/ 接頭辞と拡張子なし）", "models/폴더/텍스처  (materials/ 접두사와 확장자 없음)", "models/dossier/texture  (sans préfixe materials/ ni extension)", "models/папка/текстура  (без префикса materials/ и расширения)" )
R( "row.reset_transform", "Reset to no transform", "清除变换", "変換なしに戻す", "변환 없음으로 초기화", "Supprimer la transformation", "Сбросить преобразование" )
R( "row.drop_recipe", "Throw the recipe away and go back to a plain texture path", "丢弃生成配方并恢复为普通纹理路径", "生成レシピを破棄して通常のテクスチャパスに戻します", "생성 설정을 버리고 일반 텍스처 경로로 돌아갑니다", "Abandonne la recette et revient à un simple chemin de texture", "Отбросить рецепт и вернуться к обычному пути текстуры" )
R( "row.reopen_recipe", "Reopen the window that made this, on the same settings", "使用相同设置重新打开生成窗口", "同じ設定で生成ウィンドウを開き直します", "같은 설정으로 생성 창을 다시 엽니다", "Rouvre la fenêtre de création avec les mêmes réglages", "Снова открыть окно создания с теми же настройками" )
R( "row.generated_from", "{{kind}} from {{source}}   -   {{summary}}", "{{kind}}，来源：{{source}}   -   {{summary}}", "{{source}} から作成した {{kind}}   -   {{summary}}", "{{source}}에서 만든 {{kind}}   -   {{summary}}", "{{kind}} depuis {{source}}   -   {{summary}}", "{{kind}} из {{source}}   -   {{summary}}" )
R( "row.written_data", "Written to garrysmod/data/{{path}}", "已写入 garrysmod/data/{{path}}", "garrysmod/data/{{path}} に書き込みました", "garrysmod/data/{{path}}에 기록됨", "Écrit dans garrysmod/data/{{path}}", "Записано в garrysmod/data/{{path}}" )

-- Hot material import (cl_61_import.lua). The picker's title, purpose and
-- filter label are shown inside Model Hotloader's own window, quoted.
R( "import.picker_title", "Choose an image for {{param}}", "为 {{param}} 选择图像", "{{param}} に使う画像を選択", "{{param}}에 사용할 이미지 선택", "Choisir une image pour {{param}}", "Выберите изображение для {{param}}" )
R( "import.purpose", "Use an image from your computer as a material texture", "将电脑中的图像用作材质纹理", "PC 内の画像をマテリアルのテクスチャとして使う", "컴퓨터의 이미지를 재질 텍스처로 사용", "Utiliser une image de votre ordinateur comme texture de matériau", "Использовать изображение с компьютера как текстуру материала" )
R( "import.filter", "Images (PNG, JPEG)", "图像（PNG、JPEG）", "画像（PNG、JPEG）", "이미지(PNG, JPEG)", "Images (PNG ou JPEG)", "Изображения (PNG, JPEG)" )
R( "import.busy", "An image is already being imported. If Model Hotloader's file window is open, choose the image there (press Alt+Tab if it is behind the game).", "已有一张图像正在导入。如果 Model Hotloader 的文件窗口已打开，请在其中选择图像（若窗口位于游戏后方，请按 Alt+Tab）。", "すでに画像を読み込み中です。Model Hotloader のファイルウィンドウが開いている場合は、そこで画像を選んでください（ゲームの後ろにある場合は Alt+Tab を押してください）。", "이미 이미지를 가져오는 중입니다. Model Hotloader의 파일 창이 열려 있다면 그 창에서 이미지를 선택하세요(창이 게임 뒤에 있으면 Alt+Tab을 누르세요).", "Une image est déjà en cours d’importation. Si la fenêtre de fichiers de Model Hotloader est ouverte, choisissez-y l’image (Alt+Tab si elle est derrière le jeu).", "Изображение уже импортируется. Если окно выбора файла Model Hotloader открыто, выберите изображение в нём (нажмите Alt+Tab, если оно за окном игры)." )
R( "import.done", "Imported {{name}} as a {{size}} texture.", "已导入 {{name}}，纹理尺寸为 {{size}}。", "{{name}} を {{size}} のテクスチャとして読み込みました。", "{{name}}을(를) {{size}} 텍스처로 가져왔습니다.", "Image importée : {{name}}, en texture de {{size}}.", "Изображение {{name}} импортировано как текстура {{size}}." )
R( "import.done_resized", "Imported {{name}} at {{size}}; the image itself is {{native}}. Edit can change the size.", "已导入 {{name}}，尺寸为 {{size}}（原图为 {{native}}）。可在“编辑”中更改尺寸。", "{{name}} を {{size}} で読み込みました（元の画像は {{native}}）。サイズは「編集」で変更できます。", "{{name}}을(를) {{size}} 크기로 가져왔습니다(원본은 {{native}}). 크기는 ‘편집’에서 바꿀 수 있습니다.", "Image importée : {{name}}, en {{size}} (l’original fait {{native}}). Modifier permet de changer la taille.", "Изображение {{name}} импортировано в размере {{size}} (оригинал — {{native}}). Размер можно изменить кнопкой «Изменить»." )
R( "import.failed", "Could not import the image: {{reason}}", "无法导入图像：{{reason}}", "画像を読み込めませんでした：{{reason}}", "이미지를 가져올 수 없습니다: {{reason}}", "Impossible d’importer l’image : {{reason}}", "Не удалось импортировать изображение: {{reason}}" )
R( "import.error_format", "only PNG and JPEG images can be imported", "只能导入 PNG 和 JPEG 图像", "読み込めるのは PNG と JPEG の画像だけです", "PNG와 JPEG 이미지만 가져올 수 있습니다", "seules les images PNG et JPEG peuvent être importées", "импортировать можно только изображения PNG и JPEG" )
R( "import.error_large", "the file is larger than {{size}} MB", "文件超过 {{size}} MB", "ファイルが {{size}} MB を超えています", "파일이 {{size}}MB보다 큽니다", "le fichier dépasse {{size}} Mo", "файл больше {{size}} МБ" )
R( "import.error_dims", "the image is {{size}}; at most {{max}} pixels per side can be imported", "图像尺寸为 {{size}}；每边最多只能导入 {{max}} 像素", "画像は {{size}} です。読み込めるのは一辺 {{max}} ピクセルまでです", "이미지 크기가 {{size}}입니다. 한 변은 최대 {{max}}픽셀까지 가져올 수 있습니다", "l’image fait {{size}} ; au plus {{max}} pixels par côté peuvent être importés", "размер изображения {{size}}; можно импортировать не больше {{max}} пикселей по стороне" )
R( "import.error_decode", "Garry's Mod could not open this image", "Garry's Mod 无法打开此图像", "Garry's Mod がこの画像を開けませんでした", "Garry's Mod가 이 이미지를 열 수 없습니다", "Garry's Mod n’a pas pu ouvrir cette image", "Garry's Mod не смог открыть это изображение" )
R( "import.error_write", "it could not be saved in garrysmod/data/advmat/imports", "无法将其保存到 garrysmod/data/advmat/imports", "garrysmod/data/advmat/imports に保存できませんでした", "garrysmod/data/advmat/imports에 저장할 수 없습니다", "impossible de l’enregistrer dans garrysmod/data/advmat/imports", "не удалось сохранить его в garrysmod/data/advmat/imports" )
R( "import.error_closed", "the material editor was closed before the image arrived", "图像读取完成前，材质编辑器已关闭", "画像の読み込みが終わる前にマテリアルエディターが閉じられました", "이미지를 읽기 전에 재질 편집기가 닫혔습니다", "l’éditeur de matériaux a été fermé avant l’arrivée de l’image", "редактор материалов был закрыт до получения изображения" )
R( "import.error_unreadable", "the chosen file could not be read", "无法读取所选文件", "選んだファイルを読み込めませんでした", "선택한 파일을 읽을 수 없습니다", "le fichier choisi n’a pas pu être lu", "не удалось прочитать выбранный файл" )
R( "import.error_recipe", "the image could not be turned into a texture", "无法将图像转换为纹理", "画像をテクスチャに変換できませんでした", "이미지를 텍스처로 변환할 수 없습니다", "l’image n’a pas pu être convertie en texture", "не удалось превратить изображение в текстуру" )
-- Fills {{source}} in row.generated_from, hence the Russian genitive.
R( "import.source", "an imported image", "导入的图像", "読み込んだ画像", "가져온 이미지", "une image importée", "импортированного изображения" )
R( "import.source_named", "the imported image {{name}}", "导入的图像 {{name}}", "読み込んだ画像 {{name}}", "가져온 이미지 {{name}}", "l’image importée {{name}}", "импортированного изображения {{name}}" )
-- Stands alone, in a title or as {{name}} when the file name is unknown.
R( "import.image", "imported image", "导入图像", "インポート画像", "가져온 이미지 파일", "image importée", "импортированное изображение" )
R( "import.error_server", "the server could not send this imported image", "服务器无法发送这张导入的图像", "サーバーがこの読み込み画像を送信できませんでした", "서버가 이 가져온 이미지를 보낼 수 없습니다", "le serveur n’a pas pu envoyer cette image importée", "сервер не смог передать это импортированное изображение" )
R( "import.too_large_to_save", "The imported texture came out at {{size}} MB, over this server's {{limit}} MB limit for shared textures, so it cannot be saved at this size. Use Edit to choose a smaller one.", "导入的纹理大小为 {{size}} MB，超过此服务器共享纹理 {{limit}} MB 的上限，因此无法以此尺寸保存。请使用“编辑”选择更小的尺寸。", "読み込んだテクスチャは {{size}} MB になり、このサーバーの共有テクスチャの上限 {{limit}} MB を超えるため、このサイズでは保存できません。「編集」で小さいサイズを選んでください。", "가져온 텍스처가 {{size}}MB로, 이 서버의 공유 텍스처 한도인 {{limit}}MB를 넘어 이 크기로는 저장할 수 없습니다. ‘편집’에서 더 작은 크기를 선택하세요.", "La texture importée pèse {{size}} Mo, au-delà de la limite de {{limit}} Mo de ce serveur pour les textures partagées : elle ne peut pas être enregistrée à cette taille. Utilisez Modifier pour en choisir une plus petite.", "Импортированная текстура занимает {{size}} МБ — больше лимита этого сервера для общих текстур ({{limit}} МБ), поэтому сохранить её в таком размере нельзя. Выберите размер поменьше через «Изменить»." )
R( "import.notice_missing", "Model Hotloader is not installed, so hot material import is not available.", "未安装 Model Hotloader，无法使用材质热导入。", "Model Hotloader がインストールされていないため、マテリアルのホットインポートは使用できません。", "Model Hotloader가 설치되어 있지 않아 재질 핫 임포트를 사용할 수 없습니다.", "Model Hotloader n’est pas installé : l’import à chaud de matériaux est indisponible.", "Model Hotloader не установлен, поэтому горячий импорт материалов недоступен." )
R( "import.notice_update", "Model Hotloader's native module is missing or older than 2.3.0, so hot material import is not available.", "Model Hotloader 的原生模块缺失或版本低于 2.3.0，无法使用材质热导入。", "Model Hotloader のネイティブモジュールが見つからないか 2.3.0 より古いため、マテリアルのホットインポートは使用できません。", "Model Hotloader의 네이티브 모듈이 없거나 2.3.0보다 오래되어 재질 핫 임포트를 사용할 수 없습니다.", "Le module natif de Model Hotloader est absent ou antérieur à la 2.3.0 : l’import à chaud de matériaux est indisponible.", "Нативный модуль Model Hotloader отсутствует или старше версии 2.3.0, поэтому горячий импорт материалов недоступен." )
R( "import.notice_disabled", "File access is turned off in Model Hotloader, so hot material import is not available.", "Model Hotloader 中的文件访问已关闭，无法使用材质热导入。", "Model Hotloader のファイルアクセスがオフになっているため、マテリアルのホットインポートは使用できません。", "Model Hotloader의 파일 접근이 꺼져 있어 재질 핫 임포트를 사용할 수 없습니다.", "L’accès aux fichiers est désactivé dans Model Hotloader : l’import à chaud de matériaux est indisponible.", "Доступ к файлам в Model Hotloader выключен, поэтому горячий импорт материалов недоступен." )
R( "import.notice_remote", "Hot material import only works in single player or on a server you host.", "材质热导入仅可在单人游戏或你自己主持的服务器上使用。", "マテリアルのホットインポートは、シングルプレイか自分がホストするサーバーでのみ使用できます。", "재질 핫 임포트는 싱글플레이 또는 직접 호스팅하는 서버에서만 사용할 수 있습니다.", "L’import à chaud de matériaux ne fonctionne qu’en solo ou sur un serveur que vous hébergez.", "Горячий импорт материалов работает только в одиночной игре или на сервере, который вы запустили сами." )
R( "import.notice_other", "Model Hotloader cannot open its file window right now, so hot material import is not available.", "Model Hotloader 目前无法打开文件窗口，无法使用材质热导入。", "Model Hotloader が現在ファイルウィンドウを開けないため、マテリアルのホットインポートは使用できません。", "Model Hotloader가 지금 파일 창을 열 수 없어 재질 핫 임포트를 사용할 수 없습니다.", "Model Hotloader ne peut pas ouvrir sa fenêtre de fichiers pour le moment : l’import à chaud de matériaux est indisponible.", "Model Hotloader сейчас не может открыть окно выбора файла, поэтому горячий импорт материалов недоступен." )
R( "import.resolve", "Resolve", "解决", "解決", "해결", "Résoudre", "Исправить" )
R( "import.resolve_tip", "What hot material import needs, and where to get Model Hotloader", "材质热导入需要什么，以及从哪里获取 Model Hotloader", "マテリアルのホットインポートに必要なものと、Model Hotloader の入手先", "재질 핫 임포트에 필요한 것과 Model Hotloader를 받는 곳", "Ce dont l’import à chaud de matériaux a besoin, et où obtenir Model Hotloader", "Что нужно для горячего импорта материалов и где взять Model Hotloader" )
R( "import.resolve_title", "Hot material import", "材质热导入", "マテリアルのホットインポート", "재질 핫 임포트", "Import à chaud de matériaux", "Горячий импорт материалов" )
R( "import.resolve_ready", "Hot material import is available. Every texture parameter has an Import button next to Edit.", "材质热导入可用。每个纹理参数的“编辑”按钮旁都有“导入”按钮。", "マテリアルのホットインポートを使用できます。各テクスチャパラメーターの「編集」の隣に「読み込み」ボタンがあります。", "재질 핫 임포트를 사용할 수 있습니다. 모든 텍스처 매개변수의 ‘편집’ 옆에 ‘가져오기’ 버튼이 있습니다.", "L’import à chaud de matériaux est disponible. Chaque paramètre de texture a un bouton Importer à côté de Modifier.", "Горячий импорт материалов доступен. У каждого параметра текстуры рядом с «Изменить» есть кнопка «Импорт»." )
R( "import.resolve_reason", "Model Hotloader reports: {{reason}}", "Model Hotloader 提示：{{reason}}", "Model Hotloader からの報告：{{reason}}", "Model Hotloader 메시지: {{reason}}", "Model Hotloader indique : {{reason}}", "Model Hotloader сообщает: {{reason}}" )
R( "import.resolve_about", "Import, next to Edit on every texture parameter, puts an image from your computer (PNG or JPEG) straight onto the material. Garry's Mod cannot read files outside its own folders, so the image is read through the native module of Model Hotloader 2.3.0 or newer: you choose the file in a window Model Hotloader shows, and this editor receives that file and nothing else. An imported texture is saved and shared with other players like any painted texture.", "每个纹理参数的“编辑”旁都有“导入”按钮，可将电脑中的图像（PNG 或 JPEG）直接用于材质。Garry's Mod 无法读取其自身文件夹之外的文件，因此图像通过 Model Hotloader 2.3.0 或更高版本的原生模块读取：你在 Model Hotloader 显示的窗口中选择文件，本编辑器只会收到该文件，不会获得其他任何内容。导入的纹理会像绘制的纹理一样保存，并共享给其他玩家。", "各テクスチャパラメーターの「編集」の隣にある「読み込み」は、PC 内の画像（PNG または JPEG）をそのままマテリアルに適用します。Garry's Mod は自身のフォルダー外のファイルを読めないため、画像は Model Hotloader 2.3.0 以降のネイティブモジュールを通して読み込みます。Model Hotloader が表示するウィンドウでファイルを選ぶと、このエディターはそのファイルだけを受け取ります。読み込んだテクスチャは、描画したテクスチャと同じように保存され、他のプレイヤーとも共有されます。", "모든 텍스처 매개변수의 ‘편집’ 옆에 있는 ‘가져오기’는 컴퓨터의 이미지(PNG 또는 JPEG)를 재질에 바로 적용합니다. Garry's Mod는 자체 폴더 밖의 파일을 읽을 수 없으므로, 이미지는 Model Hotloader 2.3.0 이상의 네이티브 모듈을 통해 읽습니다. Model Hotloader가 표시하는 창에서 파일을 선택하면 이 편집기는 그 파일만 받습니다. 가져온 텍스처는 페인팅한 텍스처처럼 저장되고 다른 플레이어와 공유됩니다.", "Importer, à côté de Modifier sur chaque paramètre de texture, applique directement au matériau une image de votre ordinateur (PNG ou JPEG). Garry's Mod ne peut pas lire les fichiers hors de ses propres dossiers : l’image est donc lue par le module natif de Model Hotloader 2.3.0 ou plus récent. Vous choisissez le fichier dans une fenêtre affichée par Model Hotloader, et cet éditeur ne reçoit que ce fichier. Une texture importée est enregistrée et partagée avec les autres joueurs comme toute texture peinte.", "Кнопка «Импорт» рядом с «Изменить» у каждого параметра текстуры сразу применяет к материалу изображение с вашего компьютера (PNG или JPEG). Garry's Mod не может читать файлы вне своих папок, поэтому изображение читается через нативный модуль Model Hotloader 2.3.0 или новее: вы выбираете файл в окне Model Hotloader, и редактор получает только этот файл. Импортированная текстура сохраняется и передаётся другим игрокам так же, как нарисованная." )
R( "import.resolve_install", "To set it up:\n1. Subscribe to Model Hotloader on the Steam Workshop.\n2. Download its native module from the Releases section of its GitHub page and install it as described there.\n3. Restart Garry's Mod and open this editor again.", "设置方法：\n1. 在 Steam 创意工坊订阅 Model Hotloader。\n2. 从其 GitHub 页面的 Releases 部分下载原生模块，并按照页面说明进行安装。\n3. 重新启动 Garry's Mod，然后再次打开此编辑器。", "設定方法：\n1. Steam ワークショップで Model Hotloader をサブスクライブします。\n2. GitHub ページの Releases からネイティブモジュールをダウンロードし、記載の手順どおりにインストールします。\n3. Garry's Mod を再起動し、このエディターを開き直します。", "설정 방법:\n1. Steam 창작마당에서 Model Hotloader를 구독합니다.\n2. GitHub 페이지의 Releases에서 네이티브 모듈을 내려받아 안내대로 설치합니다.\n3. Garry's Mod를 다시 시작한 뒤 이 편집기를 다시 엽니다.", "Pour l’installer :\n1. Abonnez-vous à Model Hotloader sur le Workshop Steam.\n2. Téléchargez son module natif dans la section Releases de sa page GitHub et installez-le comme indiqué.\n3. Redémarrez Garry's Mod, puis rouvrez cet éditeur.", "Как установить:\n1. Подпишитесь на Model Hotloader в Мастерской Steam.\n2. Скачайте нативный модуль из раздела Releases на его странице GitHub и установите его по инструкции.\n3. Перезапустите Garry's Mod и снова откройте этот редактор." )
R( "import.resolve_disabled", "Model Hotloader is installed, but it does not let addons ask to read files at the moment. Turn that back on in its file access settings.", "Model Hotloader 已安装，但目前不允许插件请求读取文件。请在其文件访问设置中重新开启。", "Model Hotloader はインストールされていますが、現在アドオンによるファイル読み取りの要求を許可していません。ファイルアクセス設定でオンに戻してください。", "Model Hotloader는 설치되어 있지만 현재 애드온의 파일 읽기 요청을 허용하지 않습니다. 파일 접근 설정에서 다시 켜세요.", "Model Hotloader est installé, mais il n’autorise pas pour l’instant les addons à demander la lecture de fichiers. Réactivez-le dans ses paramètres d’accès aux fichiers.", "Model Hotloader установлен, но сейчас не разрешает аддонам запрашивать чтение файлов. Снова включите это в его настройках доступа к файлам." )
R( "import.resolve_remote", "Model Hotloader lets addons read your files only in single player or on a server you host: on anyone else's server, every client script comes from that server. Start a single-player game, or host one, to import images.", "Model Hotloader 仅在单人游戏或你自己主持的服务器上允许插件读取你的文件：在他人的服务器上，所有客户端脚本都来自该服务器。要导入图像，请开始单人游戏或自行主持游戏。", "Model Hotloader がアドオンにファイルの読み取りを許可するのは、シングルプレイか自分がホストするサーバーだけです。他人のサーバーでは、クライアントのスクリプトはすべてそのサーバーから送られてきます。画像を読み込むには、シングルプレイを始めるか自分でホストしてください。", "Model Hotloader는 싱글플레이나 직접 호스팅하는 서버에서만 애드온이 파일을 읽도록 허용합니다. 다른 사람의 서버에서는 모든 클라이언트 스크립트가 그 서버에서 오기 때문입니다. 이미지를 가져오려면 싱글플레이를 시작하거나 직접 호스팅하세요.", "Model Hotloader ne laisse les addons lire vos fichiers qu’en solo ou sur un serveur que vous hébergez : sur le serveur de quelqu’un d’autre, tous les scripts clients viennent de ce serveur. Lancez une partie solo, ou hébergez-en une, pour importer des images.", "Model Hotloader разрешает аддонам читать ваши файлы только в одиночной игре или на сервере, который вы запустили сами: на чужом сервере все клиентские скрипты приходят с этого сервера. Чтобы импортировать изображения, начните одиночную игру или запустите сервер сами." )
R( "import.resolve_other", "Model Hotloader is installed, but the window it uses to ask you for files is not working. Its installation window says why and how to repair it.", "Model Hotloader 已安装，但用于向你请求文件的窗口无法正常工作。其安装窗口会说明原因和修复方法。", "Model Hotloader はインストールされていますが、ファイルを尋ねるためのウィンドウが動作していません。原因と修復方法はインストールウィンドウで確認できます。", "Model Hotloader는 설치되어 있지만 파일을 요청하는 창이 작동하지 않습니다. 설치 창에서 원인과 해결 방법을 확인하세요.", "Model Hotloader est installé, mais la fenêtre qu’il utilise pour vous demander des fichiers ne fonctionne pas. Sa fenêtre d’installation indique pourquoi et comment la réparer.", "Model Hotloader установлен, но окно, в котором он запрашивает файлы, не работает. Окно установки покажет причину и способ исправления." )
R( "import.open_installation", "Open Model Hotloader's installation window", "打开 Model Hotloader 的安装窗口", "Model Hotloader のインストールウィンドウを開く", "Model Hotloader 설치 창 열기", "Ouvrir la fenêtre d’installation de Model Hotloader", "Открыть окно установки Model Hotloader" )
R( "import.open_file_access", "Open Model Hotloader's file access settings", "打开 Model Hotloader 的文件访问设置", "Model Hotloader のファイルアクセス設定を開く", "Model Hotloader 파일 접근 설정 열기", "Ouvrir les paramètres d’accès aux fichiers de Model Hotloader", "Открыть настройки доступа к файлам Model Hotloader" )
R( "import.link_workshop", "Model Hotloader on the Steam Workshop", "Steam 创意工坊上的 Model Hotloader", "Steam ワークショップの Model Hotloader", "Steam 창작마당의 Model Hotloader", "Model Hotloader sur le Workshop Steam", "Model Hotloader в Мастерской Steam" )
R( "import.link_github", "Model Hotloader on GitHub (native module downloads)", "GitHub 上的 Model Hotloader（原生模块下载）", "GitHub の Model Hotloader（ネイティブモジュールのダウンロード）", "GitHub의 Model Hotloader(네이티브 모듈 다운로드)", "Model Hotloader sur GitHub (téléchargement du module natif)", "Model Hotloader на GitHub (загрузка нативного модуля)" )
R( "import.open_link", "Open page", "打开页面", "ページを開く", "페이지 열기", "Ouvrir la page", "Открыть страницу" )
R( "import.copy_link", "Copy link", "复制链接", "リンクをコピー", "링크 복사", "Copier le lien", "Копировать ссылку" )
R( "import.copied", "Link copied to the clipboard.", "链接已复制到剪贴板。", "リンクをクリップボードにコピーしました。", "링크를 클립보드에 복사했습니다.", "Lien copié dans le presse-papiers.", "Ссылка скопирована в буфер обмена." )
R( "import.check_again", "Check again", "重新检查", "再確認", "다시 확인", "Vérifier à nouveau", "Проверить снова" )
R( "import.check_again_tip", "Ask Model Hotloader again, after installing it or changing its settings", "安装 Model Hotloader 或更改其设置后，重新向其查询", "Model Hotloader をインストールしたり設定を変えたりした後に、もう一度確認します", "Model Hotloader를 설치하거나 설정을 바꾼 뒤 다시 확인합니다", "Interroger à nouveau Model Hotloader après l’avoir installé ou avoir changé ses paramètres", "Снова опросить Model Hotloader после установки или изменения его настроек" )
R( "import.now_ready", "Hot material import is available now.", "材质热导入现已可用。", "マテリアルのホットインポートを使用できるようになりました。", "이제 재질 핫 임포트를 사용할 수 있습니다.", "L’import à chaud de matériaux est maintenant disponible.", "Горячий импорт материалов теперь доступен." )

R( "picker.title", "Choose a texture", "选择纹理", "テクスチャを選択", "텍스처 선택", "Choisir une texture", "Выбрать текстуру" )
R( "picker.use", "Use texture", "使用纹理", "このテクスチャを使用", "텍스처 사용", "Utiliser la texture", "Использовать текстуру" )
R( "picker.search", "Search every mounted material... (min 3 characters)", "搜索所有已挂载材质…（至少 3 个字符）", "マウント済みの全マテリアルを検索…（3文字以上）", "마운트된 모든 재질 검색…(3자 이상)", "Rechercher dans tous les matériaux montés… (3 caractères min.)", "Поиск по всем подключённым материалам… (минимум 3 символа)" )
R( "picker.folder_tip", "Folder the search starts from. Narrow it to make searching fast.", "搜索起始文件夹。缩小范围可提高搜索速度。", "検索を開始するフォルダーです。範囲を絞ると高速になります。", "검색을 시작할 폴더입니다. 범위를 좁히면 더 빠릅니다.", "Dossier de départ de la recherche. Réduisez-le pour accélérer la recherche.", "Папка, с которой начинается поиск. Сузьте её для ускорения." )

R( "texture.title", "Texture editor", "纹理编辑器", "テクスチャエディター", "텍스처 편집기", "Éditeur de texture", "Редактор текстур" )
R( "texture.use", "Use this texture", "使用此纹理", "このテクスチャを使用", "이 텍스처 사용", "Utiliser cette texture", "Использовать эту текстуру" )
R( "texture.save_at", "Save at", "保存尺寸", "保存サイズ", "저장 크기", "Enregistrer en", "Сохранить в размере" )
R( "texture.fit", "Fit", "适应", "全体表示", "맞춤", "Ajuster", "Вписать" )
R( "texture.select_all", "Select all", "全选", "すべて選択", "모두 선택", "Tout sélectionner", "Выбрать всё" )
R( "texture.nothing_selected", "Nothing selected", "未选择", "未選択", "선택 없음", "Aucune sélection", "Ничего не выбрано" )
R( "texture.whole_selected", "The whole picture is selected.", "已选择整张图像。", "画像全体が選択されています。", "전체 이미지가 선택되었습니다.", "L’image entière est sélectionnée.", "Выбрано всё изображение." )
R( "texture.none_affects_all", "Nothing selected - changes affect the whole picture.", "未选择区域——更改会影响整张图像。", "未選択です。変更は画像全体に適用されます。", "선택 영역 없음 - 변경 사항이 전체 이미지에 적용됩니다.", "Aucune sélection : les modifications affectent toute l’image.", "Ничего не выбрано — изменения затронут всё изображение." )
R( "texture.percent_selected", "You have {{value}}% of the picture selected.", "已选择图像的 {{value}}%。", "画像の {{value}}% を選択しています。", "이미지의 {{value}}%를 선택했습니다.", "{{value}} % de l’image sont sélectionnés.", "Выбрано {{value}}% изображения." )
R( "texture.start_texture", "Start: the texture", "起始：当前纹理", "開始：テクスチャ", "시작: 텍스처", "Départ : la texture", "Начало: текстура" )
R( "texture.start_blank", "Start: blank", "起始：空白", "開始：空画像", "시작: 빈 이미지", "Départ : image vide", "Начало: пустое изображение" )
R( "texture.show_both", "Show: outline + shading", "显示：轮廓 + 阴影", "表示：輪郭 + 陰影", "표시: 윤곽선 + 음영", "Afficher : contour + ombrage", "Показать: контур + затенение" )
R( "texture.show_outline", "Show: outline", "显示：轮廓", "表示：輪郭", "표시: 윤곽선", "Afficher : contour", "Показать: контур" )
R( "texture.show_shading", "Show: shading", "显示：阴影", "表示：陰影", "표시: 음영", "Afficher : ombrage", "Показать: затенение" )
R( "texture.show_nothing", "Show: nothing", "显示：无", "表示：なし", "표시: 없음", "Afficher : rien", "Показать: ничего" )
R( "texture.flip", "Flip", "反选", "反転", "반전", "Inverser", "Инвертировать" )
R( "texture.saved_areas", "Saved areas", "已保存区域", "保存済み領域", "저장된 영역", "Zones enregistrées", "Сохранённые области" )
R( "texture.steps", "Steps - done in this order, top to bottom", "步骤——按从上到下的顺序执行", "手順（上から順に実行）", "단계 - 위에서 아래 순서로 실행", "Étapes — exécutées de haut en bas", "Шаги — выполняются сверху вниз" )
R( "texture.model_hint", "Click the model to select that piece of the skin", "点击模型以选择对应的纹理区域", "モデルをクリックして対応するスキン部分を選択", "모델을 클릭해 해당 스킨 부분 선택", "Cliquez sur le modèle pour sélectionner cette partie du skin", "Щёлкните по модели, чтобы выбрать эту часть текстуры" )
R( "texture.erase_all", "Erase everything I have selected", "擦除所选的全部内容", "選択範囲をすべて消去", "선택한 모든 영역 지우기", "Effacer tout ce qui est sélectionné", "Стереть всё выделенное" )
R( "texture.restore", "Put it back", "恢复", "元に戻す", "복원", "Rétablir", "Вернуть" )
R( "texture.other", "Other changes...", "其他更改…", "その他の変更…", "기타 변경…", "Autres modifications…", "Другие изменения…" )
R( "texture.adjust", "Brightness, colour and contrast...", "亮度、颜色和对比度…", "明るさ・色・コントラスト…", "밝기, 색상 및 대비…", "Luminosité, couleur et contraste…", "Яркость, цвет и контраст…" )
R( "texture.adjust_title", "Brightness, colour and contrast", "亮度、颜色和对比度", "明るさ・色・コントラスト", "밝기, 색상 및 대비", "Luminosité, couleur et contraste", "Яркость, цвет и контраст" )
R( "texture.choose_area_more", "Choose the area...", "选择区域…", "領域を選択…", "영역 선택…", "Choisir la zone…", "Выбрать область…" )
R( "texture.noise_worn", "Add noise (worn look)", "添加噪点（磨损效果）", "ノイズを追加（摩耗表現）", "노이즈 추가(낡은 효과)", "Ajouter du bruit (aspect usé)", "Добавить шум (эффект износа)" )
R( "texture.other_tip", "Brightness, blur, noise and the rest, applied to the selection.", "对选区应用亮度、模糊、噪点等更改。", "選択範囲に明るさ、ぼかし、ノイズなどを適用します。", "선택 영역에 밝기, 흐림, 노이즈 등의 변경을 적용합니다.", "Applique à la sélection la luminosité, le flou, le bruit et les autres réglages.", "Применяет к выделению яркость, размытие, шум и другие изменения." )
R( "texture.erase_all_tip", "Cuts the whole selection away in one go instead of scrubbing at it.", "一次性擦除整个选区，无需反复涂擦。", "こすらずに選択範囲全体を一度で消去します。", "문지르지 않고 전체 선택 영역을 한 번에 지웁니다.", "Découpe toute la sélection d’un coup au lieu de devoir la gommer.", "Удаляет всё выделение сразу, без стирания кистью." )
R( "texture.restore_tip", "Makes the selection solid again.", "使选区恢复不透明。", "選択範囲を再び不透明にします。", "선택 영역을 다시 불투명하게 만듭니다.", "Rend la sélection à nouveau opaque.", "Снова делает выделение непрозрачным." )
R( "texture.swatch_tip", "The colour to paint with. Click to change it.", "用于绘制的颜色。点击可更改。", "描画に使う色です。クリックして変更します。", "그릴 색상입니다. 클릭하여 변경합니다.", "Couleur utilisée pour peindre. Cliquez pour la modifier.", "Цвет рисования. Щёлкните, чтобы изменить." )
R( "texture.limit_tip", "Limit the generator to what you have selected.", "将生成范围限制在所选区域。", "生成範囲を選択部分に限定します。", "생성 범위를 선택한 영역으로 제한합니다.", "Limite le générateur à la zone sélectionnée.", "Ограничить генератор выбранной областью." )
R( "texture.uv_tip", "Draws the edges of the model's faces over the texture, so you can see which part of the picture goes where.", "在纹理上绘制模型面的边缘，以便查看图像各部分对应的位置。", "モデル面の輪郭をテクスチャ上に描き、画像の各部分がどこに対応するか示します。", "텍스처 위에 모델 면의 가장자리를 그려 이미지의 각 부분이 어디에 해당하는지 보여 줍니다.", "Dessine les bords des faces du modèle sur la texture afin de voir où se place chaque partie de l’image.", "Рисует границы граней модели поверх текстуры, чтобы было видно соответствие частей изображения." )
R( "texture.size_tip", "The size the finished texture is written at, defaulting to the texture's own - up to the limit beside this.\nPainting happens at a fraction of it so it stays responsive; everything you draw is stored as a fraction of the texture, so the two agree exactly.", "最终纹理的写出尺寸，默认使用原纹理尺寸，但不会超过旁边的限制。\n绘制时使用较低的工作分辨率以保持流畅；所有笔画均按纹理比例保存，因此最终结果会精确对应。", "完成テクスチャの出力サイズです。既定では元テクスチャのサイズ（隣の上限まで）です。\n操作中は軽い解像度で描画しますが、すべて比率で保存されるため最終結果は正確に一致します。", "완성된 텍스처의 저장 크기이며 기본값은 원본 텍스처 크기(옆의 제한 이하)입니다.\n작업 중에는 반응성을 위해 낮은 해상도를 사용하지만 모든 그리기는 비율로 저장되어 최종 결과와 정확히 일치합니다.", "Taille d’écriture de la texture finale, par défaut celle de la texture source dans la limite indiquée.\nLa peinture utilise une résolution réduite pour rester fluide ; les tracés sont stockés en proportions et correspondent exactement au résultat final.", "Размер записи готовой текстуры; по умолчанию равен размеру исходной в пределах соседнего ограничения.\nДля отзывчивости рисование идёт в меньшем разрешении, но штрихи хранятся в долях текстуры и точно совпадают с итогом." )
R( "texture.prefix_title", "Texture editor - ", "纹理编辑器 - ", "テクスチャエディター - ", "텍스처 편집기 - ", "Éditeur de texture - ", "Редактор текстур - " )
R( "texture.prefix_up_to", "Up to ", "最高 ", "最大 ", "최대 ", "Jusqu’à ", "До " )
R( "texture.prefix_remove", "remove ", "移除 ", "削除 ", "제거 ", "supprimer ", "удалить " )
R( "texture.add_step", "Add this step", "添加此步骤", "この手順を追加", "이 단계 추가", "Ajouter cette étape", "Добавить этот шаг" )
R( "texture.choose_area", "Choose the area", "选择区域", "領域を選択", "영역 선택", "Choisir la zone", "Выбрать область" )
R( "texture.use_area", "Use this area", "使用此区域", "この領域を使用", "이 영역 사용", "Utiliser cette zone", "Использовать эту область" )
R( "texture.whole", "Whole texture", "整张纹理", "テクスチャ全体", "전체 텍스처", "Texture entière", "Вся текстура" )
R( "texture.inside_outside", "Inside / outside", "内部 / 外部", "内側 / 外側", "안쪽 / 바깥쪽", "Intérieur / extérieur", "Внутри / снаружи" )
R( "texture.where", "Where to change", "更改位置", "変更する場所", "변경할 위치", "Zone à modifier", "Область изменения" )
R( "texture.blur", "Blur", "模糊", "ぼかし", "흐림", "Flou", "Размытие" )
R( "texture.sharpen", "Sharpen", "锐化", "シャープ", "선명하게", "Netteté", "Резкость" )
R( "texture.noise", "Add noise", "添加噪点", "ノイズを追加", "노이즈 추가", "Ajouter du bruit", "Добавить шум" )
R( "texture.erase", "Erase to transparent", "擦除为透明", "透明に消去", "투명하게 지우기", "Effacer en transparence", "Стереть до прозрачности" )
R( "texture.solid", "Make solid again", "恢复不透明", "再び不透明にする", "다시 불투명하게 만들기", "Rendre à nouveau opaque", "Снова сделать непрозрачным" )
R( "texture.fill", "Fill with colour", "填充颜色", "色で塗りつぶす", "색상으로 채우기", "Remplir avec une couleur", "Залить цветом" )
R( "texture.tint", "Tint", "着色", "色合い", "색조", "Teinte", "Тонирование" )
R( "texture.adjust_colours", "Adjust colours", "调整颜色", "色を調整", "색상 조정", "Ajuster les couleurs", "Настроить цвета" )
R( "texture.tool_island", "Pick model piece", "选择模型部件", "モデルの部分を選択", "모델 부분 선택", "Choisir une pièce du modèle", "Выбрать часть модели" )
R( "texture.tool_box", "Box select", "矩形选择", "矩形選択", "사각형 선택", "Sélection rectangulaire", "Прямоугольное выделение" )
R( "texture.tool_round", "Round select", "椭圆选择", "楕円選択", "원형 선택", "Sélection elliptique", "Овальное выделение" )
R( "texture.tool_lasso", "Freehand select", "手绘选择", "フリーハンド選択", "자유 선택", "Sélection à main levée", "Свободное выделение" )
R( "texture.tool_wand", "Pick same colour", "选择相近颜色", "同じ色を選択", "같은 색상 선택", "Choisir la même couleur", "Выбрать похожий цвет" )
R( "texture.tool_paint", "Paint", "绘制", "ペイント", "그리기", "Peindre", "Рисовать" )
R( "texture.tool_erase", "Eraser", "橡皮擦", "消しゴム", "지우개", "Gomme", "Ластик" )
R( "texture.tool_fill", "Fill or recolour", "填充或重新着色", "塗りつぶし / 色変更", "채우기 또는 색상 변경", "Remplir ou recolorer", "Залить или перекрасить" )
R( "texture.tool_picker", "Colour picker", "颜色吸管", "カラーピッカー", "색상 선택기", "Pipette de couleur", "Пипетка" )
R( "texture.tool_pan", "Move the view", "移动视图", "表示を移動", "보기 이동", "Déplacer la vue", "Переместить вид" )
R( "texture.mode_replace", "Replace", "替换", "置換", "바꾸기", "Remplacer", "Заменить" )
R( "texture.mode_add", "Add", "添加", "追加", "추가", "Ajouter", "Добавить" )
R( "texture.mode_sub", "Take away", "减去", "除外", "빼기", "Soustraire", "Вычесть" )
R( "texture.mode_overlap", "Overlap only", "仅保留重叠", "重なりのみ", "겹치는 부분만", "Intersection uniquement", "Только пересечение" )
R( "texture.layers", "Layers", "图层", "レイヤー", "레이어", "Calques", "Слои" )
R( "texture.layer_tool", "Transform layer", "变换图层", "レイヤーを変形", "레이어 변형", "Transformer le calque", "Трансформировать слой" )
R( "texture.layer_tool_tip", "Move an imported texture layer, resize it by its corners, or drag the handle above it to rotate.", "移动导入的纹理图层，拖动四角调整大小，或拖动上方手柄进行旋转。", "読み込んだテクスチャレイヤーを移動し、角でサイズを変更するか、上のハンドルをドラッグして回転します。", "가져온 텍스처 레이어를 이동하고 모서리로 크기를 조절하거나 위쪽 핸들을 드래그해 회전합니다.", "Déplacez un calque de texture importé, redimensionnez-le par ses coins ou faites glisser la poignée supérieure pour le faire pivoter.", "Перемещайте импортированный слой текстуры, изменяйте его размер за углы или вращайте верхним маркером." )
R( "texture.layer_import", "Import a mounted texture as a new layer", "将已挂载的纹理导入为新图层", "マウント済みテクスチャを新しいレイヤーとして読み込む", "마운트된 텍스처를 새 레이어로 가져오기", "Importer une texture montée comme nouveau calque", "Импортировать подключённую текстуру как новый слой" )
R( "texture.layer_duplicate", "Duplicate the selected layer", "复制所选图层", "選択中のレイヤーを複製", "선택한 레이어 복제", "Dupliquer le calque sélectionné", "Дублировать выбранный слой" )
R( "texture.layer_up", "Move the selected layer up", "上移所选图层", "選択中のレイヤーを上へ移動", "선택한 레이어 위로 이동", "Monter le calque sélectionné", "Поднять выбранный слой" )
R( "texture.layer_down", "Move the selected layer down", "下移所选图层", "選択中のレイヤーを下へ移動", "선택한 레이어 아래로 이동", "Descendre le calque sélectionné", "Опустить выбранный слой" )
R( "texture.layer_delete", "Delete the selected layer", "删除所选图层", "選択中のレイヤーを削除", "선택한 레이어 삭제", "Supprimer le calque sélectionné", "Удалить выбранный слой" )
R( "texture.layer_visibility", "Show or hide this layer", "显示或隐藏此图层", "このレイヤーの表示 / 非表示", "이 레이어 표시 또는 숨기기", "Afficher ou masquer ce calque", "Показать или скрыть этот слой" )
R( "texture.layer_base_tip", "The source and paint/effect steps below every imported layer", "位于所有导入图层下方的源图像以及绘制/效果步骤", "すべての読み込みレイヤーの下にある元画像と描画・効果の手順", "모든 가져온 레이어 아래의 원본 및 그리기/효과 단계", "La source et les étapes de peinture/effet sous tous les calques importés", "Исходник и шаги рисования/эффектов под всеми импортированными слоями" )
R( "texture.layer_empty", "Import a texture layer, then select it here to move, resize and rotate it.", "导入纹理图层，然后在此处选择它以移动、调整大小和旋转。", "テクスチャレイヤーを読み込み、ここで選択して移動・サイズ変更・回転します。", "텍스처 레이어를 가져온 뒤 여기서 선택해 이동, 크기 조절 및 회전하세요.", "Importez un calque de texture, puis sélectionnez-le ici pour le déplacer, le redimensionner et le faire pivoter.", "Импортируйте слой текстуры, затем выберите его здесь для перемещения, изменения размера и вращения." )
R( "texture.layer_source", "Texture: {{texture}}\nClick to choose another", "纹理：{{texture}}\n点击选择其他纹理", "テクスチャ：{{texture}}\nクリックして別のものを選択", "텍스처: {{texture}}\n클릭하여 다른 텍스처 선택", "Texture : {{texture}}\nCliquez pour en choisir une autre", "Текстура: {{texture}}\nЩёлкните, чтобы выбрать другую" )
R( "texture.layer_base", "Base: {{texture}}", "底图：{{texture}}", "ベース：{{texture}}", "기본: {{texture}}", "Base : {{texture}}", "Основа: {{texture}}" )
R( "texture.layer_base_blank", "Base: blank image", "底图：空白图像", "ベース：空画像", "기본: 빈 이미지", "Base : image vide", "Основа: пустое изображение" )
R( "texture.layer_x", "Horizontal position (%)", "水平位置（%）", "水平位置（%）", "가로 위치(%)", "Position horizontale (%)", "Положение по горизонтали (%)" )
R( "texture.layer_y", "Vertical position (%)", "垂直位置（%）", "垂直位置（%）", "세로 위치(%)", "Position verticale (%)", "Положение по вертикали (%)" )
R( "texture.layer_aspect", "Keep texture proportions", "保持纹理比例", "テクスチャの縦横比を維持", "텍스처 비율 유지", "Conserver les proportions de la texture", "Сохранять пропорции текстуры" )
R( "texture.layer_aspect_tip", "When enabled, either size control scales both sides together.", "启用后，调整任一尺寸都会同时缩放两个方向。", "有効にすると、どちらのサイズを変更しても両辺が一緒に拡大縮小されます。", "활성화하면 어느 크기 조절값을 바꿔도 양쪽이 함께 조정됩니다.", "Si cette option est activée, chaque réglage de taille redimensionne les deux côtés ensemble.", "Если включено, изменение любого размера масштабирует обе стороны вместе." )
R( "texture.layer_width", "Width (%)", "宽度（%）", "幅（%）", "너비(%)", "Largeur (%)", "Ширина (%)" )
R( "texture.layer_height", "Height (%)", "高度（%）", "高さ（%）", "높이(%)", "Hauteur (%)", "Высота (%)" )
R( "texture.layer_rotation", "Rotation (degrees)", "旋转（度）", "回転（度）", "회전(도)", "Rotation (degrés)", "Поворот (градусы)" )
R( "texture.layer_opacity", "Layer opacity (%)", "图层不透明度（%）", "レイヤーの不透明度（%）", "레이어 불투명도(%)", "Opacité du calque (%)", "Непрозрачность слоя (%)" )
R( "texture.layer_flip_x", "Flip horizontally", "水平翻转", "左右反転", "좌우 뒤집기", "Retourner horizontalement", "Отразить по горизонтали" )
R( "texture.layer_flip_y", "Flip vertically", "垂直翻转", "上下反転", "상하 뒤집기", "Retourner verticalement", "Отразить по вертикали" )
R( "texture.layer_opaque", "Ignore the texture's alpha channel", "忽略纹理的 Alpha 通道", "テクスチャのアルファチャンネルを無視", "텍스처의 알파 채널 무시", "Ignorer le canal alpha de la texture", "Игнорировать альфа-канал текстуры" )
R( "texture.layer_opaque_tip", "Use this when the alpha channel stores a phong or reflection mask rather than transparency.", "当 Alpha 通道存储 Phong 或反射遮罩而非透明度时使用此选项。", "アルファチャンネルが透明度ではなく Phong または反射マスクを格納している場合に使用します。", "알파 채널이 투명도가 아니라 퐁 또는 반사 마스크를 저장할 때 사용하세요.", "Utilisez ceci lorsque le canal alpha contient un masque de Phong ou de réflexion plutôt que de la transparence.", "Используйте, если альфа-канал хранит маску Phong или отражений, а не прозрачность." )
R( "texture.layer_centre", "Centre", "居中", "中央", "가운데", "Centrer", "По центру" )
R( "texture.layer_centre_tip", "Put the layer in the middle of the canvas", "将图层置于画布中央", "レイヤーをキャンバス中央に置く", "레이어를 캔버스 가운데에 배치", "Placer le calque au centre du canevas", "Поместить слой в центр холста" )
R( "texture.layer_fit", "Fit the whole layer inside the canvas", "使整个图层适合画布范围", "レイヤー全体をキャンバス内に収める", "전체 레이어를 캔버스 안에 맞추기", "Ajuster tout le calque dans le canevas", "Вписать весь слой в холст" )
R( "texture.layer_reset", "Centre, fit and remove rotation and flips", "居中并适合画布，同时清除旋转和翻转", "中央に合わせて収め、回転と反転を解除", "가운데에 맞추고 회전과 뒤집기 제거", "Centrer, ajuster et supprimer la rotation et les retournements", "Центрировать, вписать и убрать поворот и отражения" )
R( "texture.layer_drag_tip", "Drag the layer to move it. Drag a corner to resize it, or the handle above it to rotate.", "拖动图层以移动；拖动四角调整大小，或拖动上方手柄进行旋转。", "レイヤーをドラッグして移動します。角でサイズを変更し、上のハンドルで回転します。", "레이어를 드래그해 이동하세요. 모서리로 크기를 조절하거나 위쪽 핸들로 회전하세요.", "Faites glisser le calque pour le déplacer, un coin pour le redimensionner ou la poignée supérieure pour le faire pivoter.", "Перетаскивайте слой для перемещения, угол — для изменения размера, верхний маркер — для вращения." )
R( "texture.layer_limit", "That is as many imported layers as one texture can hold.", "此纹理已达到可容纳的导入图层上限。", "このテクスチャに追加できる読み込みレイヤーはこれが上限です。", "이 텍스처에 가져올 수 있는 레이어 수가 최대입니다.", "Cette texture contient déjà le nombre maximal de calques importés.", "Достигнут предел импортированных слоёв для одной текстуры." )
R( "texture.layer_open_failed", "That texture could not be opened as a shared image layer.", "无法将该纹理作为共享图像图层打开。", "そのテクスチャを共有画像レイヤーとして開けませんでした。", "해당 텍스처를 공유 이미지 레이어로 열 수 없습니다.", "Cette texture n’a pas pu être ouverte comme calque d’image partagé.", "Не удалось открыть эту текстуру как общий слой изображения." )
R( "texture.layer_name", "Imported texture layer", "导入的纹理图层", "読み込んだテクスチャレイヤー", "가져온 텍스처 레이어", "Calque de texture importé", "Импортированный слой текстуры" )
R( "texture.nothing_apply", "There is nothing to apply yet - add a step or layer first.", "尚无可应用的内容——请先添加步骤或图层。", "まだ適用する内容がありません。手順またはレイヤーを追加してください。", "아직 적용할 내용이 없습니다. 단계 또는 레이어를 먼저 추가하세요.", "Il n’y a encore rien à appliquer — ajoutez d’abord une étape ou un calque.", "Пока нечего применять — сначала добавьте шаг или слой." )
R( "texture.blank_white", "A blank white image", "空白白色图像", "白い空画像", "빈 흰색 이미지", "Une image blanche vide", "Пустое белое изображение" )
R( "texture.blank_alpha", "A blank transparent image", "空白透明图像", "透明な空画像", "빈 투명 이미지", "Une image transparente vide", "Пустое прозрачное изображение" )
R( "texture.blank_colour", "A blank image in the current colour", "使用当前颜色的空白图像", "現在の色の空画像", "현재 색상의 빈 이미지", "Une image vide de la couleur actuelle", "Пустое изображение текущего цвета" )
R( "texture.current", "The texture that is there now", "当前纹理", "現在のテクスチャ", "현재 텍스처", "La texture actuellement présente", "Текущая текстура" )
R( "texture.keep", "Keep this area...", "保存此区域…", "この領域を保存…", "이 영역 저장…", "Enregistrer cette zone…", "Сохранить эту область…" )
R( "texture.keep_empty", "Keep this area... (nothing is selected)", "保存此区域…（尚未选择）", "この領域を保存…（未選択）", "이 영역 저장…(선택 없음)", "Enregistrer cette zone… (aucune sélection)", "Сохранить эту область… (ничего не выбрано)" )
R( "texture.keep_title", "Keep this area", "保存此区域", "この領域を保存", "이 영역 저장", "Enregistrer cette zone", "Сохранить эту область" )
R( "texture.keep_prompt", "Call it:", "命名为：", "名前：", "이름:", "Nom :", "Название:" )
R( "texture.keep_default", "my area", "我的区域", "マイ領域", "내 영역", "ma zone", "моя область" )
R( "texture.dark_alpha", "Make the dark parts see-through", "使暗部透明", "暗い部分を透明にする", "어두운 부분을 투명하게 만들기", "Rendre les parties sombres transparentes", "Сделать тёмные части прозрачными" )
R( "texture.selection_alpha", "Make the selection see-through", "使所选区域透明", "選択範囲を透明にする", "선택 영역을 투명하게 만들기", "Rendre la sélection transparente", "Сделать выделение прозрачным" )
R( "texture.empty_selection", "Your selection is empty - nothing will change.", "所选区域为空——不会发生更改。", "選択範囲が空です。何も変更されません。", "선택 영역이 비어 있어 아무것도 변경되지 않습니다.", "Votre sélection est vide : rien ne sera modifié.", "Выделение пусто — ничего не изменится." )
R( "texture.step_empty", "  Nothing yet.\n  Pick a piece of the model, then paint or fill.", "  尚无步骤。\n  请选择模型部件，然后绘制或填充。", "  まだ手順はありません。\n  モデルの部分を選び、描画または塗りつぶしてください。", "  아직 단계가 없습니다.\n  모델 부분을 선택한 뒤 그리거나 채우세요.", "  Rien pour le moment.\n  Choisissez une pièce du modèle, puis peignez ou remplissez.", "  Пока ничего нет.\n  Выберите часть модели, затем рисуйте или заливайте." )
R( "texture.switch_step", "Switch this step off without deleting it", "关闭此步骤但不删除", "削除せずにこの手順をオフにします", "이 단계를 삭제하지 않고 끕니다", "Désactiver cette étape sans la supprimer", "Отключить шаг, не удаляя его" )
R( "texture.brush_size", "Brush size", "画笔大小", "ブラシサイズ", "브러시 크기", "Taille du pinceau", "Размер кисти" )
R( "texture.grow", "Grow by (pixels)", "扩展（像素）", "拡張（ピクセル）", "확장(픽셀)", "Agrandir de (pixels)", "Расширить на (пиксели)" )
R( "texture.feather", "Soften the edge (pixels)", "柔化边缘（像素）", "エッジをぼかす（ピクセル）", "가장자리 부드럽게(픽셀)", "Adoucir le bord (pixels)", "Смягчить край (пиксели)" )
R( "texture.tolerance", "How close a colour has to be", "颜色相近程度", "色の近さ", "색상 유사 정도", "Tolérance de couleur", "Допуск цвета" )
R( "texture.touching", "Only areas that touch", "仅相连区域", "接触する領域のみ", "서로 닿는 영역만", "Seulement les zones contiguës", "Только соприкасающиеся области" )
R( "texture.keep_square", "Keep it square", "保持正方形", "正方形を維持", "정사각형 유지", "Conserver un carré", "Сохранять квадрат" )
R( "texture.scale", "Make it bigger or smaller", "放大或缩小", "拡大 / 縮小", "크게 또는 작게", "Agrandir ou réduire", "Увеличить или уменьшить" )
R( "texture.hue_shift", "Shift the colour", "偏移色相", "色相をずらす", "색조 이동", "Décaler la teinte", "Сдвинуть цветовой тон" )
R( "texture.colourful", "How colourful", "鲜艳程度", "鮮やかさ", "색상 선명도", "Saturation", "Насыщенность" )
R( "texture.multiply_brightness", "Brightness (multiply)", "亮度（乘法）", "明るさ（乗算）", "밝기(곱하기)", "Luminosité (multiplication)", "Яркость (умножение)" )
R( "texture.lift_brightness", "Brightness (lift)", "亮度（提升）", "明るさ（持ち上げ）", "밝기(리프트)", "Luminosité (élévation)", "Яркость (подъём)" )
R( "texture.desaturate", "Drain the colour out", "去除颜色", "色を抜く", "색상 제거", "Retirer la couleur", "Убрать цвет" )
R( "texture.hue_tip", "Rotates every colour around the rainbow.", "沿色相环旋转所有颜色。", "すべての色を色相環に沿って回転させます。", "모든 색상을 색상환을 따라 회전합니다.", "Fait tourner toutes les couleurs sur le cercle chromatique.", "Сдвигает все цвета по цветовому кругу." )
R( "texture.saturation_tip", "0 is grey, 1 is unchanged.", "0 为灰度，1 保持不变。", "0 はグレースケール、1 は変更なしです。", "0은 회색조, 1은 변경 없음입니다.", "0 donne du gris, 1 ne change rien.", "0 — оттенки серого, 1 — без изменений." )
R( "texture.lift_tip", "Adds or removes an even amount of light.", "均匀增加或减少亮度。", "明るさを全体に均等に加減します。", "밝기를 전체적으로 균일하게 더하거나 뺍니다.", "Ajoute ou retire uniformément de la luminosité.", "Равномерно добавляет или убирает яркость." )
R( "texture.desaturate_tip", "1 makes it completely grey.", "1 会使图像完全变为灰度。", "1 にすると完全なグレースケールになります。", "1로 설정하면 완전한 회색조가 됩니다.", "1 rend l’image entièrement grise.", "Значение 1 полностью обесцвечивает изображение." )
R( "texture.average", "How much to average", "平均程度", "平均化の強さ", "평균화 정도", "Niveau de moyenne", "Степень усреднения" )
R( "texture.keep_shading", "Keep the shading", "保留明暗细节", "陰影を維持", "명암 유지", "Conserver les ombres", "Сохранить светотень" )
R( "texture.show_uv", "Show the model's outlines", "显示模型轮廓", "モデルの輪郭を表示", "모델 윤곽선 표시", "Afficher les contours du modèle", "Показать контуры модели" )
R( "texture.tip_island", "Click the model or the texture to select one connected piece of the skin.\nThis is the easy way to find the bit you want.", "点击模型或纹理以选择一块相连的皮肤区域。\n这是查找目标部位的最简单方法。", "モデルまたはテクスチャをクリックして、連結したスキン領域を選択します。\n目的の部分を簡単に見つけられます。", "모델이나 텍스처를 클릭해 연결된 스킨 부분 하나를 선택합니다.\n원하는 부분을 쉽게 찾는 방법입니다.", "Cliquez sur le modèle ou la texture pour sélectionner un îlot de skin connexe.\nC’est le moyen le plus simple de trouver la partie voulue.", "Щёлкните по модели или текстуре, чтобы выбрать связанный участок развёртки.\nТак проще всего найти нужную часть." )
R( "texture.tip_box", "Drag out a rectangle.", "拖出一个矩形。", "ドラッグして長方形を作ります。", "드래그하여 사각형을 만듭니다.", "Tracez un rectangle par glissement.", "Протяните прямоугольник." )
R( "texture.tip_round", "Drag out an oval.", "拖出一个椭圆。", "ドラッグして楕円を作ります。", "드래그하여 타원을 만듭니다.", "Tracez une ellipse par glissement.", "Протяните овал." )
R( "texture.tip_lasso", "Draw around the area. It closes itself when you let go.", "沿区域边缘绘制；松开时会自动闭合。", "領域を囲んで描きます。離すと自動的に閉じます。", "영역 둘레를 그리세요. 놓으면 자동으로 닫힙니다.", "Dessinez autour de la zone ; elle se referme au relâchement.", "Обведите область; при отпускании контур замкнётся." )
R( "texture.tip_wand", "Click a colour to select everything like it.", "点击一种颜色以选择所有相近颜色。", "色をクリックして似た色をすべて選択します。", "색상을 클릭해 비슷한 색상을 모두 선택합니다.", "Cliquez sur une couleur pour sélectionner toutes les couleurs semblables.", "Щёлкните по цвету, чтобы выбрать все похожие цвета." )
R( "texture.tip_paint", "Brush colour on. Only inside the selection, if there is one.", "用画笔涂色；如有选区，则仅在选区内生效。", "ブラシで色を塗ります。選択範囲がある場合はその内側だけに適用されます。", "브러시로 색을 칠합니다. 선택 영역이 있으면 그 안에만 적용됩니다.", "Peignez au pinceau, uniquement dans la sélection si elle existe.", "Рисуйте кистью; при наличии выделения — только внутри него." )
R( "texture.tip_erase", "Rub out paint to bring back the original texture, or cut see-through holes.", "擦除绘制内容以恢复原始纹理，或挖出透明孔洞。", "塗った部分を消して元のテクスチャに戻すか、透明な穴を開けます。", "칠한 부분을 지워 원래 텍스처로 되돌리거나, 투명한 구멍을 냅니다.", "Gommez la peinture pour retrouver la texture d’origine, ou découpez des trous transparents.", "Стирайте краску, возвращая исходную текстуру, или вырезайте прозрачные отверстия." )
R( "texture.tip_fill", "Colour the whole selection in one click.", "单击即可为整个选区着色。", "1クリックで選択範囲全体を塗ります。", "한 번 클릭해 전체 선택 영역을 칠합니다.", "Colorez toute la sélection en un clic.", "Окрасьте всё выделение одним щелчком." )
R( "texture.tip_picker", "Take a colour from the texture or from the model.", "从纹理或模型中吸取颜色。", "テクスチャまたはモデルから色を取得します。", "텍스처나 모델에서 색상을 가져옵니다.", "Prélevez une couleur sur la texture ou le modèle.", "Возьмите цвет с текстуры или модели." )
R( "texture.tip_pan", "Drag to move the view around.\nOn the texture, middle or right mouse does this from any tool.\nOn the model, middle mouse moves it and right mouse turns it.", "拖动以移动视图。\n在纹理上，任何工具都可用鼠标中键或右键移动。\n在模型上，中键移动，右键旋转。", "ドラッグして表示を移動します。\nテクスチャではどのツールでも中または右ボタンで移動できます。\nモデルでは中ボタンで移動、右ボタンで回転します。", "드래그하여 보기를 이동합니다.\n텍스처에서는 어떤 도구든 가운데 또는 오른쪽 버튼으로 이동합니다.\n모델에서는 가운데 버튼으로 이동하고 오른쪽 버튼으로 회전합니다.", "Faites glisser pour déplacer la vue.\nSur la texture, le bouton central ou droit le fait avec n’importe quel outil.\nSur le modèle, le bouton central déplace et le droit fait tourner.", "Перетаскивайте для перемещения вида.\nНа текстуре средняя или правая кнопка работает с любым инструментом.\nНа модели средняя кнопка перемещает, правая вращает." )
R( "texture.mode_tip", "Shift adds, Ctrl takes away, both together keeps only the overlap.", "Shift 添加，Ctrl 减去；同时按下则仅保留重叠区域。", "Shift で追加、Ctrl で除外、両方で重なりだけを残します。", "Shift는 추가, Ctrl은 빼기, 둘 다 누르면 겹치는 부분만 유지합니다.", "Maj ajoute, Ctrl soustrait et les deux ensemble ne conservent que l’intersection.", "Shift добавляет, Ctrl вычитает, вместе они оставляют только пересечение." )

-- Single-window, image-editor-style workspace. These exact English phrases are
-- also the source text used by legacy Derma controls and their tooltips.
R( "texture.tip_gradient", "Drag from the foreground colour to the background colour.", "从前景色拖动到背景色以创建渐变。", "前景色から背景色へドラッグしてグラデーションを作ります。", "전경색에서 배경색으로 드래그해 그라디언트를 만듭니다.", "Faites glisser du premier plan vers l’arrière-plan pour créer un dégradé.", "Протяните градиент от цвета переднего плана к цвету фона." )
R( "texture.tab_effects", "Effects", "效果", "エフェクト", "효과", "Effets", "Эффекты" )
R( "texture.tab_history", "History", "历史记录", "履歴", "기록", "Historique", "История" )
R( "texture.tools", "Tools", "工具", "ツール", "도구", "Outils", "Инструменты" )
R( "texture.history_opened", "Opened texture", "打开纹理", "テクスチャを開く", "텍스처 열기", "Ouverture de la texture", "Открытие текстуры" )
R( "texture.history_earlier", "Earlier state", "较早状态", "以前の状態", "이전 상태", "État antérieur", "Предыдущее состояние" )
R( "texture.history_current", "Current state", "当前状态", "現在の状態", "현재 상태", "État actuel", "Текущее состояние" )
R( "texture.history_later", "Later state", "后续状态", "後の状態", "이후 상태", "État ultérieur", "Последующее состояние" )
R( "texture.history_start", "Change starting image", "更改起始图像", "開始画像を変更", "시작 이미지 변경", "Modifier l’image de départ", "Изменить исходное изображение" )
R( "texture.history_import_layer", "Import layer", "导入图层", "レイヤーを読み込み", "레이어 가져오기", "Importer un calque", "Импортировать слой" )
R( "texture.history_change_layer", "Change layer source", "更改图层源", "レイヤーの参照元を変更", "레이어 원본 변경", "Modifier la source du calque", "Изменить источник слоя" )
R( "texture.history_duplicate_layer", "Duplicate layer", "复制图层", "レイヤーを複製", "레이어 복제", "Dupliquer le calque", "Дублировать слой" )
R( "texture.history_raise_layer", "Raise layer", "上移图层", "レイヤーを上へ移動", "레이어 올리기", "Monter le calque", "Поднять слой" )
R( "texture.history_lower_layer", "Lower layer", "下移图层", "レイヤーを下へ移動", "레이어 내리기", "Descendre le calque", "Опустить слой" )
R( "texture.history_delete_layer", "Delete layer", "删除图层", "レイヤーを削除", "레이어 삭제", "Supprimer le calque", "Удалить слой" )
R( "texture.history_edit_layer", "Edit layer", "编辑图层", "レイヤーを編集", "레이어 편집", "Modifier le calque", "Изменить слой" )
R( "texture.history_toggle_layer", "Toggle layer visibility", "切换图层可见性", "レイヤーの表示を切り替え", "레이어 표시 전환", "Basculer la visibilité du calque", "Переключить видимость слоя" )
R( "texture.history_delete_effect", "Delete effect", "删除效果", "エフェクトを削除", "효과 삭제", "Supprimer l’effet", "Удалить эффект" )
R( "texture.history_effect_later", "Move effect later", "后移效果", "エフェクトを後へ移動", "효과를 뒤로 이동", "Déplacer l’effet plus tard", "Переместить эффект позже" )
R( "texture.history_effect_earlier", "Move effect earlier", "前移效果", "エフェクトを前へ移動", "효과를 앞으로 이동", "Déplacer l’effet plus tôt", "Переместить эффект раньше" )
R( "texture.history_toggle_effect", "Toggle effect visibility", "切换效果可见性", "エフェクトの表示を切り替え", "효과 표시 전환", "Basculer la visibilité de l’effet", "Переключить видимость эффекта" )

R( "texture.close_tip", "Close without changing anything.", "关闭且不应用任何更改。", "何も変更せずに閉じます。", "아무것도 변경하지 않고 닫습니다.", "Fermer sans rien modifier.", "Закрыть без изменений." )
R( "texture.use_tip", "Put this edited texture on the material and close.", "将编辑后的纹理应用到材质并关闭。", "編集したテクスチャをマテリアルに適用して閉じます。", "편집한 텍스처를 재질에 적용하고 닫습니다.", "Appliquer cette texture modifiée au matériau, puis fermer.", "Применить отредактированную текстуру к материалу и закрыть." )
R( "texture.undo_tip", "Undo the last change.", "撤销上一次更改。", "直前の変更を元に戻します。", "마지막 변경을 실행 취소합니다.", "Annuler la dernière modification.", "Отменить последнее изменение." )
R( "texture.redo_tip", "Redo the last undone change.", "重做上一次撤销的更改。", "最後に取り消した変更をやり直します。", "마지막으로 취소한 변경을 다시 실행합니다.", "Rétablir la dernière modification annulée.", "Повторить последнее отменённое изменение." )
R( "texture.size_tip_compact", "The size the finished texture is written at, defaulting to the texture's own - up to the limit beside this.\nPainting happens at a fraction of it so it stays responsive.", "最终纹理的写出尺寸，默认使用原纹理尺寸，但不会超过旁边的限制。\n绘制时使用较低的工作分辨率以保持流畅。", "完成テクスチャの出力サイズです。既定では元テクスチャのサイズ（隣の上限まで）です。\n操作中は応答性を保つため低い解像度で描画します。", "완성된 텍스처의 저장 크기이며 기본값은 원본 텍스처 크기(옆의 제한 이하)입니다.\n작업 중에는 반응성을 위해 낮은 해상도로 그립니다.", "Taille d’écriture de la texture finale, par défaut celle de la texture source dans la limite indiquée.\nLa peinture utilise une résolution réduite pour rester fluide.", "Размер записи готовой текстуры; по умолчанию равен размеру исходной в пределах соседнего ограничения.\nДля отзывчивости рисование выполняется в меньшем разрешении." )

R( "texture.foreground", "Foreground colour", "前景色", "前景色", "전경색", "Couleur de premier plan", "Цвет переднего плана" )
R( "texture.background", "Background colour", "背景色", "背景色", "배경색", "Couleur d’arrière-plan", "Цвет фона" )
R( "texture.foreground_more", "Foreground colour...", "前景色…", "前景色…", "전경색…", "Couleur de premier plan…", "Цвет переднего плана…" )
R( "texture.background_more", "Background colour...", "背景色…", "背景色…", "배경색…", "Couleur d’arrière-plan…", "Цвет фона…" )
R( "texture.foreground_tip", "Foreground colour. Click to change it.", "前景色。点击以更改。", "前景色です。クリックして変更します。", "전경색입니다. 클릭하여 변경하세요.", "Couleur de premier plan. Cliquez pour la modifier.", "Цвет переднего плана. Щёлкните, чтобы изменить." )
R( "texture.background_tip", "Background colour. Click to change it.", "背景色。点击以更改。", "背景色です。クリックして変更します。", "배경색입니다. 클릭하여 변경하세요.", "Couleur d’arrière-plan. Cliquez pour la modifier.", "Цвет фона. Щёлкните, чтобы изменить." )
R( "texture.foreground_short", "FG: {{colour}}", "前景：{{colour}}", "前景：{{colour}}", "전경: {{colour}}", "PP : {{colour}}", "Передний план: {{colour}}" )
R( "texture.background_short", "BG: {{colour}}", "背景：{{colour}}", "背景：{{colour}}", "배경: {{colour}}", "AP : {{colour}}", "Фон: {{colour}}" )
R( "texture.default_colours", "Use default colours", "使用默认颜色", "既定の色を使用", "기본 색상 사용", "Utiliser les couleurs par défaut", "Использовать цвета по умолчанию" )
R( "texture.swap_colours", "Swap colours", "交换颜色", "色を入れ替え", "색상 바꾸기", "Permuter les couleurs", "Поменять цвета местами" )
R( "texture.default_colours_tip", "Reset foreground/background to black and white (D)", "将前景色和背景色重置为黑色与白色（D）", "前景色と背景色を黒と白に戻します（D）", "전경색과 배경색을 검정과 흰색으로 초기화합니다(D)", "Rétablir le premier plan et l’arrière-plan en noir et blanc (D)", "Сбросить цвета переднего плана и фона на чёрный и белый (D)" )
R( "texture.swap_colours_tip", "Swap foreground and background colours (X)", "交换前景色与背景色（X）", "前景色と背景色を入れ替えます（X）", "전경색과 배경색을 서로 바꿉니다(X)", "Permuter les couleurs de premier plan et d’arrière-plan (X)", "Поменять местами цвета переднего плана и фона (X)" )
R( "texture.reset_tool", "Reset tool options", "重置工具选项", "ツールオプションをリセット", "도구 옵션 초기화", "Réinitialiser les options de l’outil", "Сбросить параметры инструмента" )
R( "texture.reset_tool_tip", "Restore the selected tool's normal settings.", "恢复所选工具的默认设置。", "選択中のツールを標準設定に戻します。", "선택한 도구의 기본 설정을 복원합니다.", "Rétablir les réglages habituels de l’outil sélectionné.", "Восстановить обычные настройки выбранного инструмента." )

R( "texture.menu_file", "File", "文件", "ファイル", "파일", "Fichier", "Файл" )
R( "texture.menu_edit", "Edit", "编辑", "編集", "편집", "Édition", "Правка" )
R( "texture.menu_select", "Select", "选择", "選択", "선택", "Sélection", "Выделение" )
R( "texture.menu_image", "Image", "图像", "画像", "이미지", "Image", "Изображение" )
R( "texture.menu_colours", "Colors", "颜色", "色", "색상", "Couleurs", "Цвета" )
R( "texture.menu_filters", "Filters", "滤镜", "フィルター", "필터", "Filtres", "Фильтры" )
R( "texture.menu_layer", "Layer", "图层", "レイヤー", "레이어", "Calque", "Слой" )
R( "texture.menu_view", "View", "视图", "表示", "보기", "Affichage", "Вид" )
R( "texture.menu_help", "Help", "帮助", "ヘルプ", "도움말", "Aide", "Справка" )
R( "texture.start_source", "Start from the source texture", "从源纹理开始", "元のテクスチャから開始", "원본 텍스처에서 시작", "Partir de la texture source", "Начать с исходной текстуры" )
R( "texture.start_white", "Start from a blank white image", "从空白白色图像开始", "白い空画像から開始", "빈 흰색 이미지에서 시작", "Partir d’une image blanche vide", "Начать с пустого белого изображения" )
R( "texture.start_transparent", "Start from a blank transparent image", "从空白透明图像开始", "透明な空画像から開始", "빈 투명 이미지에서 시작", "Partir d’une image transparente vide", "Начать с пустого прозрачного изображения" )
R( "texture.start_foreground", "Start from the foreground colour", "从前景色开始", "前景色から開始", "전경색에서 시작", "Partir de la couleur de premier plan", "Начать с цвета переднего плана" )
R( "texture.import_layer_more", "Import as layer...", "导入为图层…", "レイヤーとして読み込み…", "레이어로 가져오기…", "Importer comme calque…", "Импортировать как слой…" )

R( "texture.select_none", "Select none", "取消选择", "選択を解除", "선택 해제", "Tout désélectionner", "Снять выделение" )
R( "texture.invert_selection", "Invert selection", "反选", "選択範囲を反転", "선택 영역 반전", "Inverser la sélection", "Инвертировать выделение" )
R( "texture.grow_selection", "Grow selection", "扩展选区", "選択範囲を拡大", "선택 영역 늘리기", "Agrandir la sélection", "Расширить выделение" )
R( "texture.grow_selection_more", "Grow selection...", "扩展选区…", "選択範囲を拡大…", "선택 영역 늘리기…", "Agrandir la sélection…", "Расширить выделение…" )
R( "texture.shrink_selection", "Shrink selection", "收缩选区", "選択範囲を縮小", "선택 영역 줄이기", "Réduire la sélection", "Сжать выделение" )
R( "texture.shrink_selection_more", "Shrink selection...", "收缩选区…", "選択範囲を縮小…", "선택 영역 줄이기…", "Réduire la sélection…", "Сжать выделение…" )
R( "texture.feather_selection", "Feather selection", "羽化选区", "選択範囲をぼかす", "선택 영역 가장자리 부드럽게", "Adoucir les bords de la sélection", "Растушевать выделение" )
R( "texture.feather_selection_more", "Feather selection...", "羽化选区…", "選択範囲をぼかす…", "선택 영역 가장자리 부드럽게…", "Adoucir les bords de la sélection…", "Растушевать выделение…" )
R( "texture.saved_selections", "Saved selections...", "已保存选区…", "保存済みの選択範囲…", "저장된 선택 영역…", "Sélections enregistrées…", "Сохранённые выделения…" )
R( "texture.select_first", "Select an area first.", "请先选择一个区域。", "先に領域を選択してください。", "먼저 영역을 선택하세요.", "Sélectionnez d’abord une zone.", "Сначала выделите область." )
R( "texture.pixels", "Pixels", "像素", "ピクセル", "픽셀", "Pixels", "Пиксели" )
R( "texture.enter_value", "Enter a value", "输入数值", "値を入力", "값 입력", "Saisissez une valeur", "Введите значение" )

R( "texture.source_dimensions", "Use source dimensions", "使用源图像尺寸", "元画像の寸法を使用", "원본 이미지 크기 사용", "Utiliser les dimensions de la source", "Использовать размеры исходника" )
R( "texture.scale_output", "Scale output", "缩放输出", "出力サイズを変更", "출력 크기 조절", "Redimensionner la sortie", "Масштабировать результат" )
R( "texture.reset_canvas", "Reset canvas view", "重置画布视图", "キャンバス表示をリセット", "캔버스 보기 초기화", "Réinitialiser la vue du canevas", "Сбросить вид холста" )
R( "texture.desaturate_direct", "Desaturate", "去色", "彩度を下げる", "채도 제거", "Désaturer", "Обесцветить" )
R( "texture.invert_colours", "Invert colours", "反转颜色", "色を反転", "색상 반전", "Inverser les couleurs", "Инвертировать цвета" )
R( "texture.dark_transparent", "Make dark parts transparent", "使暗部透明", "暗い部分を透明にする", "어두운 부분을 투명하게 만들기", "Rendre les parties sombres transparentes", "Сделать тёмные части прозрачными" )

R( "texture.layer_source_more", "Change layer source...", "更改图层源…", "レイヤーの参照元を変更…", "레이어 원본 변경…", "Modifier la source du calque…", "Изменить источник слоя…" )
R( "texture.layer_centre_full", "Centre layer", "居中图层", "レイヤーを中央に配置", "레이어 가운데 맞추기", "Centrer le calque", "Центрировать слой" )
R( "texture.layer_fit_full", "Fit layer to canvas", "使图层适合画布", "レイヤーをキャンバスに合わせる", "레이어를 캔버스에 맞추기", "Ajuster le calque au canevas", "Вписать слой в холст" )
R( "texture.layer_reset_full", "Reset layer transform", "重置图层变换", "レイヤー変形をリセット", "레이어 변형 초기화", "Réinitialiser la transformation du calque", "Сбросить преобразование слоя" )

R( "texture.workspace_texture", "Texture only", "仅纹理", "テクスチャのみ", "텍스처만", "Texture uniquement", "Только текстура" )
R( "texture.workspace_split", "Split", "分屏", "分割", "분할", "Partagé", "Разделённый вид" )
R( "texture.workspace_split_full", "Split texture and 3D preview", "分屏显示纹理与 3D 预览", "テクスチャと3Dプレビューを分割表示", "텍스처와 3D 미리보기 분할", "Partager entre la texture et l’aperçu 3D", "Разделить текстуру и 3D-предпросмотр" )
R( "texture.workspace_model", "3D preview", "3D 预览", "3Dプレビュー", "3D 미리보기", "Aperçu 3D", "3D-предпросмотр" )
R( "texture.workspace_model_only", "3D preview only", "仅 3D 预览", "3Dプレビューのみ", "3D 미리보기만", "Aperçu 3D uniquement", "Только 3D-предпросмотр" )
R( "texture.workspace_texture_tip", "Show only the flat texture canvas.", "仅显示平面纹理画布。", "平面テクスチャのキャンバスだけを表示します。", "평면 텍스처 캔버스만 표시합니다.", "Afficher uniquement le canevas de texture à plat.", "Показать только плоский холст текстуры." )
R( "texture.workspace_split_tip", "Show the texture and 3D preview together.", "同时显示纹理与 3D 预览。", "テクスチャと3Dプレビューを同時に表示します。", "텍스처와 3D 미리보기를 함께 표시합니다.", "Afficher ensemble la texture et l’aperçu 3D.", "Показать текстуру и 3D-предпросмотр вместе." )
R( "texture.workspace_model_tip", "Show only the model preview.", "仅显示模型预览。", "モデルのプレビューだけを表示します。", "모델 미리보기만 표시합니다.", "Afficher uniquement l’aperçu du modèle.", "Показать только предпросмотр модели." )
R( "texture.fit_canvas", "Fit canvas in window", "使画布适应窗口", "キャンバスをウィンドウに合わせる", "캔버스를 창에 맞추기", "Ajuster le canevas à la fenêtre", "Вписать холст в окно" )
R( "texture.zoom_100", "Zoom to 100%", "缩放至 100%", "100%で表示", "100%로 확대/축소", "Zoom à 100 %", "Масштаб 100%" )
R( "texture.zoom_in", "Zoom in", "放大", "拡大", "확대", "Zoom avant", "Увеличить масштаб" )
R( "texture.zoom_out", "Zoom out", "缩小", "縮小", "축소", "Zoom arrière", "Уменьшить масштаб" )
R( "texture.selection_display", "Cycle selection display", "循环切换选区显示", "選択範囲の表示を切り替え", "선택 영역 표시 전환", "Changer l’affichage de la sélection", "Переключить отображение выделения" )
R( "texture.toggle_uv", "Toggle UV overlay", "切换 UV 叠加层", "UVオーバーレイを切り替え", "UV 오버레이 전환", "Basculer la superposition UV", "Переключить UV-развёртку" )
R( "texture.toggle_docks", "Toggle docks", "切换停靠面板", "ドックの表示を切り替え", "도킹 패널 전환", "Afficher ou masquer les panneaux", "Показать или скрыть панели" )

R( "texture.shortcuts", "Keyboard shortcuts", "键盘快捷键", "キーボードショートカット", "키보드 단축키", "Raccourcis clavier", "Сочетания клавиш" )
R( "texture.shortcuts_undo", "Undo / Redo", "撤销 / 重做", "元に戻す / やり直す", "실행 취소 / 다시 실행", "Annuler / Rétablir", "Отменить / Повторить" )
R( "texture.shortcuts_select", "Select all / none", "全选 / 取消选择", "すべて選択 / 選択解除", "모두 선택 / 선택 해제", "Tout sélectionner / Tout désélectionner", "Выбрать всё / Снять выделение" )
R( "texture.shortcuts_colours", "Default / swap colours", "默认 / 交换颜色", "既定色 / 色を入れ替え", "기본 / 색상 바꾸기", "Couleurs par défaut / Permuter", "Цвета по умолчанию / Поменять местами" )

R( "texture.brush_hardness", "Brush hardness", "画笔硬度", "ブラシの硬さ", "브러시 경도", "Dureté du pinceau", "Жёсткость кисти" )
R( "texture.brush_hardness_tip", "100 gives a crisp edge. Lower values feather each brush dab toward its rim.", "100 会产生清晰边缘。较低数值会使每个笔触向边缘逐渐羽化。", "100では輪郭がくっきりします。値を下げると各ブラシ跡の縁がぼけます。", "100은 선명한 가장자리를 만듭니다. 값을 낮추면 각 붓 자국의 가장자리로 갈수록 부드러워집니다.", "100 produit un bord net. Des valeurs plus faibles adoucissent chaque touche de pinceau vers son bord.", "При 100 край чёткий. Меньшие значения растушёвывают каждый мазок к краям." )
R( "texture.paint_blend", "Paint blend mode", "绘制混合模式", "ペイントのブレンドモード", "페인트 혼합 모드", "Mode de fusion de la peinture", "Режим смешивания кисти" )
R( "texture.paint_blend_tip", "Controls how ordinary paint combines with the image. Keep shading uses a tint instead.", "控制普通绘制与图像的混合方式。“保留明暗细节”会改用着色模式。", "通常のペイントを画像にどう合成するかを設定します。「陰影を維持」では代わりに色合いを適用します。", "일반 페인트가 이미지와 혼합되는 방식을 정합니다. ‘명암 유지’는 대신 색조를 적용합니다.", "Définit comment la peinture ordinaire se combine avec l’image. « Conserver les ombres » applique plutôt une teinte.", "Определяет смешивание обычной кисти с изображением. «Сохранить светотень» вместо этого применяет тонирование." )
R( "texture.gradient_drag_tip", "Drag from the foreground colour to the background colour. The gradient extends past both endpoints.", "从前景色拖动到背景色。渐变会延伸到两个端点之外。", "前景色から背景色へドラッグします。グラデーションは両端より外側にも続きます。", "전경색에서 배경색으로 드래그하세요. 그라디언트는 양 끝점 너머까지 이어집니다.", "Faites glisser du premier plan vers l’arrière-plan. Le dégradé se prolonge au-delà des deux extrémités.", "Протяните от цвета переднего плана к цвету фона. Градиент продолжается за обе конечные точки." )
R( "texture.gradient_blend", "Gradient blend mode", "渐变混合模式", "グラデーションのブレンドモード", "그라디언트 혼합 모드", "Mode de fusion du dégradé", "Режим смешивания градиента" )
R( "texture.blend_normal", "Normal", "常规", "通常", "보통", "Normal", "Обычный" )
R( "texture.blend_replace", "Replace, transparency included", "替换（包括透明度）", "置き換え（透明度を含む）", "교체(투명도 포함)", "Remplacer, transparence comprise", "Замена с прозрачностью" )
R( "texture.blend_multiply", "Multiply (darken)", "正片叠底（变暗）", "乗算（暗く）", "곱하기(어둡게)", "Multiplier (assombrir)", "Умножение (затемнение)" )
R( "texture.blend_screen", "Screen (lighten)", "滤色（变亮）", "スクリーン（明るく）", "스크린(밝게)", "Écran (éclaircir)", "Экран (осветление)" )
R( "texture.blend_add", "Add", "相加", "加算", "더하기", "Addition", "Сложение" )
R( "history.gradient", "Blend a gradient", "混合渐变", "グラデーションを合成", "그라디언트 혼합", "Créer un dégradé", "Создать градиент" )

-- The eraser's two modes, the brush's selection notice, and the step limits.
-- Brush strokes no longer count towards the effect limit, so the messages say
-- which kind of step ran out instead of one generic "too many steps".
R( "texture.erase_mode_revert", "Back to original", "恢复原样", "オリジナルに戻す", "원래대로 되돌리기", "Retour à l’original", "Вернуть исходное" )
R( "texture.erase_mode_holes", "Make see-through", "变为透明", "透明にする", "투명하게 만들기", "Rendre transparent", "Сделать прозрачным" )
R( "texture.erase_mode_revert_tip", "Rubs out paint, effects and holes, bringing back the texture you started from.", "擦除绘制、效果和孔洞，恢复起始纹理。", "塗り・エフェクト・穴を消して、開始時のテクスチャに戻します。", "칠, 효과, 구멍을 지워 시작할 때의 텍스처로 되돌립니다.", "Gomme la peinture, les effets et les trous pour retrouver la texture de départ.", "Стирает краску, эффекты и отверстия, возвращая исходную текстуру." )
R( "texture.erase_mode_holes_tip", "Rubs the texture itself away, so the model shows a hole there.", "擦除纹理本身，使模型在该处显示孔洞。", "テクスチャそのものを消し、モデルのその部分に穴を開けます。", "텍스처 자체를 지워 모델의 그 부분에 구멍이 보이게 합니다.", "Efface la texture elle-même pour que le modèle laisse voir un trou à cet endroit.", "Стирает саму текстуру, чтобы в модели в этом месте появилось отверстие." )
R( "texture.erase_revert_help", "Rubs out your paint, effects and holes, and brings back the texture you started from. Where nothing has been changed there is nothing to rub out.", "擦除你的绘制、效果和孔洞，恢复起始纹理。未作更改的地方没有可擦除的内容。", "塗り・エフェクト・穴を消して、開始時のテクスチャに戻します。何も変更していない場所には、消すものはありません。", "칠, 효과, 구멍을 지워 시작할 때의 텍스처로 되돌립니다. 아무것도 바꾸지 않은 곳에는 지울 것이 없습니다.", "Gomme votre peinture, vos effets et vos trous, et restaure la texture de départ. Là où rien n’a été modifié, il n’y a rien à gommer.", "Стирает вашу краску, эффекты и отверстия и возвращает исходную текстуру. Там, где ничего не менялось, стирать нечего." )
R( "texture.erase_holes_help", "Rubs the texture itself away so the model shows a hole. The material is made see-through ($translucent) for you when you press Use this texture.", "擦除纹理本身，使模型显示孔洞。按下“使用此纹理”时，材质会自动设为透明（$translucent）。", "テクスチャそのものを消してモデルに穴を開けます。「このテクスチャを使用」を押すと、マテリアルは自動的に透過（$translucent）になります。", "텍스처 자체를 지워 모델에 구멍이 보이게 합니다. ‘이 텍스처 사용’을 누르면 재질이 자동으로 투명($translucent)하게 설정됩니다.", "Efface la texture elle-même pour que le modèle montre un trou. Le matériau devient transparent ($translucent) automatiquement lorsque vous cliquez sur Utiliser cette texture.", "Стирает саму текстуру, и в модели появляется отверстие. При нажатии «Использовать эту текстуру» материал автоматически станет прозрачным ($translucent)." )
R( "texture.erase_strength_tip", "How much each stroke rubs away. 100 goes all the way back to the original, or all the way to see-through.", "每一笔擦除的程度。100 会完全恢复原样或完全透明。", "1ストロークで消す強さです。100 で完全に元に戻るか、完全に透明になります。", "한 획에 지워지는 정도입니다. 100이면 완전히 원래대로 되돌리거나 완전히 투명해집니다.", "Quantité gommée à chaque trait. 100 revient entièrement à l’original, ou rend entièrement transparent.", "Насколько сильно стирает каждый мазок. 100 — полностью вернуть исходное или сделать полностью прозрачным." )
R( "texture.strength_tip", "How far towards the new colour, or how much comes away per stroke.", "向新颜色靠近的程度，或每一笔去除的程度。", "新しい色へどれだけ近づけるか、または1ストロークでどれだけ消すかです。", "새 색상에 얼마나 가까워질지, 또는 한 획에 얼마나 지워질지입니다.", "Degré de rapprochement de la nouvelle couleur, ou quantité retirée à chaque trait.", "Насколько приблизиться к новому цвету или сколько убрать за один мазок." )
R( "texture.works_anywhere", "Works anywhere - nothing is selected.", "可在任意位置使用——当前未选择区域。", "どこでも使えます（何も選択されていません）。", "어디서나 작동합니다. 선택된 영역이 없습니다.", "Agit partout : rien n’est sélectionné.", "Работает везде: ничего не выделено." )
R( "texture.works_anywhere_all", "Works anywhere - the whole picture is selected.", "可在任意位置使用——已选择整张图像。", "どこでも使えます（画像全体が選択されています）。", "어디서나 작동합니다. 전체 이미지가 선택되어 있습니다.", "Agit partout : toute l’image est sélectionnée.", "Работает везде: выделено всё изображение." )
R( "texture.works_inside", "Only works inside the selection. The dimmed area is protected.", "仅在选区内生效，变暗的区域受到保护。", "選択範囲の内側だけに作用します。暗くなっている部分は保護されています。", "선택 영역 안에서만 작동합니다. 어둡게 표시된 영역은 보호됩니다.", "N’agit qu’à l’intérieur de la sélection. La zone assombrie est protégée.", "Работает только внутри выделения. Затемнённая область защищена." )
R( "texture.erase_selection_holes", "Make selection see-through", "使选区透明", "選択範囲を透明に", "선택 영역 투명하게", "Rendre la sélection transparente", "Сделать выделение прозрачным" )
R( "texture.solid_selection", "Make selection solid", "使选区不透明", "選択範囲を不透明に", "선택 영역 불투명하게", "Rendre la sélection opaque", "Сделать выделение непрозрачным" )
R( "texture.solid_selection_tip", "Fills the holes inside the selection back in.", "填补选区内的孔洞。", "選択範囲内の穴を埋め戻します。", "선택 영역 안의 구멍을 다시 메웁니다.", "Rebouche les trous à l’intérieur de la sélection.", "Заполняет отверстия внутри выделения." )
R( "texture.revert_selection", "Selection back to original", "选区恢复原样", "選択範囲をオリジナルに戻す", "선택 영역 원래대로", "Sélection à l’original", "Вернуть выделению исходное" )
R( "texture.revert_selection_tip", "Rubs out every change inside the selection in one go.", "一次性擦除选区内的所有更改。", "選択範囲内の変更をすべて一度に消します。", "선택 영역 안의 모든 변경 사항을 한 번에 지웁니다.", "Gomme d’un coup toutes les modifications à l’intérieur de la sélection.", "Стирает сразу все изменения внутри выделения." )
R( "texture.revert_in_selection", "Bring back the original in the selection", "在选区内恢复原始纹理", "選択範囲を元のテクスチャに戻す", "선택 영역을 원래대로 되돌리기", "Restaurer l’original dans la sélection", "Вернуть исходный вид в выделении" )
R( "texture.select_first", "Select something first, or this would change the whole texture.", "请先选择区域，否则将更改整张纹理。", "先に範囲を選択してください。選択しないとテクスチャ全体が変更されます。", "먼저 영역을 선택하세요. 그렇지 않으면 전체 텍스처가 바뀝니다.", "Sélectionnez d’abord une zone, sinon toute la texture serait modifiée.", "Сначала выделите область, иначе изменится вся текстура." )
R( "texture.shortcut_erase_mode", "Again on the eraser: switch Back to original / Make see-through", "在橡皮擦工具下再次按下：在“恢复原样”与“变为透明”之间切换", "消しゴム使用中にもう一度押す：「オリジナルに戻す」と「透明にする」を切り替え", "지우개 사용 중 다시 누르기: ‘원래대로 되돌리기’와 ‘투명하게 만들기’ 전환", "Encore une fois sur la gomme : basculer entre Retour à l’original et Rendre transparent", "Повторно на ластике: переключить «Вернуть исходное» / «Сделать прозрачным»" )
R( "texture.shortcut_alt", "While erasing: use the other eraser mode for that stroke", "擦除时：该笔画使用另一种橡皮擦模式", "消している間：そのストロークだけもう一方の消しゴムモードを使う", "지우는 동안: 그 획에만 다른 지우개 모드 사용", "Pendant le gommage : utiliser l’autre mode de gomme pour ce trait", "Во время стирания: другой режим ластика для этого мазка" )
R( "texture.stroke_outside", "Nothing changed: the brush only works inside the selection. Press Ctrl+Shift+A to select nothing.", "没有任何更改：画笔只在选区内生效。按 Ctrl+Shift+A 可取消选择。", "変化はありません：ブラシは選択範囲の内側だけに作用します。Ctrl+Shift+A で選択を解除できます。", "바뀐 것이 없습니다. 브러시는 선택 영역 안에서만 작동합니다. Ctrl+Shift+A를 눌러 선택을 해제하세요.", "Rien n’a changé : le pinceau n’agit qu’à l’intérieur de la sélection. Appuyez sur Ctrl+Maj+A pour tout désélectionner.", "Ничего не изменилось: кисть работает только внутри выделения. Нажмите Ctrl+Shift+A, чтобы снять выделение." )
R( "texture.stroke_nothing_revert", "Nothing to rub out there - it already matches the original texture. To cut a hole instead, switch the eraser to Make see-through, or hold Alt.", "那里没有可擦除的内容——它已与原始纹理一致。若要挖出孔洞，请将橡皮擦切换为“变为透明”，或按住 Alt。", "そこには消すものがありません。すでに元のテクスチャと同じです。穴を開けたい場合は、消しゴムを「透明にする」に切り替えるか、Alt を押しながら消してください。", "그곳에는 지울 것이 없습니다. 이미 원래 텍스처와 같습니다. 대신 구멍을 내려면 지우개를 ‘투명하게 만들기’로 바꾸거나 Alt를 누르세요.", "Rien à gommer ici : c’est déjà identique à la texture d’origine. Pour découper un trou, passez la gomme en mode Rendre transparent, ou maintenez Alt.", "Здесь нечего стирать — это место уже совпадает с исходной текстурой. Чтобы вырезать отверстие, переключите ластик в режим «Сделать прозрачным» или удерживайте Alt." )
R( "texture.stroke_nothing_holes", "Nothing changed - that part is already see-through.", "没有任何更改——该部分已经是透明的。", "変化はありません。その部分はすでに透明です。", "바뀐 것이 없습니다. 그 부분은 이미 투명합니다.", "Rien n’a changé : cette partie est déjà transparente.", "Ничего не изменилось — эта часть уже прозрачна." )
R( "texture.limit_effects", "That is as many fills, adjustments and filters as one texture can hold. Delete some in the Effects list - brush strokes do not count towards this.", "此纹理已达到可容纳的填充、调整和滤镜数量上限。请在“效果”列表中删除一些——画笔笔画不计入此上限。", "このテクスチャに追加できる塗りつぶし・調整・フィルターはこれが上限です。エフェクト一覧からいくつか削除してください。ブラシのストロークはこの上限に数えられません。", "이 텍스처에 넣을 수 있는 채우기, 조정, 필터 수가 최대입니다. 효과 목록에서 일부를 삭제하세요. 브러시 획은 이 한도에 포함되지 않습니다.", "Cette texture contient déjà le nombre maximal de remplissages, réglages et filtres. Supprimez-en quelques-uns dans la liste Effets – les traits de pinceau ne comptent pas.", "Достигнут предел заливок, настроек и фильтров для одной текстуры. Удалите часть из них в списке «Эффекты» — мазки кисти сюда не входят." )
R( "texture.limit_strokes", "That is as much brushwork as one texture can hold. Delete some strokes in the Effects list to keep painting.", "此纹理已达到可容纳的画笔绘制量上限。请在“效果”列表中删除一些笔画以继续绘制。", "このテクスチャに描けるブラシ作業はこれが上限です。描き続けるには、エフェクト一覧からストロークをいくつか削除してください。", "이 텍스처에 담을 수 있는 브러시 작업량이 최대입니다. 계속 그리려면 효과 목록에서 일부 획을 삭제하세요.", "Cette texture contient déjà autant de coups de pinceau qu’elle peut en contenir. Supprimez quelques traits dans la liste Effets pour continuer à peindre.", "Достигнут предел работы кистью для одной текстуры. Удалите часть мазков в списке «Эффекты», чтобы продолжить рисовать." )
R( "texture.limit_size", "This edit is now as large as one save can send to the server. Delete steps you no longer need in the Effects list to keep editing.", "此编辑已达到单次保存可发送到服务器的大小上限。请在“效果”列表中删除不再需要的步骤以继续编辑。", "この編集は、1回の保存でサーバーに送れる大きさの上限に達しました。編集を続けるには、エフェクト一覧から不要な手順を削除してください。", "이 편집은 한 번의 저장으로 서버에 보낼 수 있는 크기의 한도에 도달했습니다. 계속 편집하려면 효과 목록에서 더 이상 필요 없는 단계를 삭제하세요.", "Cette modification atteint la taille maximale qu’une sauvegarde peut envoyer au serveur. Supprimez les étapes inutiles dans la liste Effets pour continuer.", "Эта правка достигла размера, который одно сохранение может отправить на сервер. Удалите ненужные шаги в списке «Эффекты», чтобы продолжить." )
R( "texture.limit_steps", "That is as many steps as one texture can hold.", "此纹理已达到可容纳的步骤上限。", "このテクスチャに追加できる手順はこれが上限です。", "이 텍스처에 넣을 수 있는 단계 수가 최대입니다.", "Cette texture contient déjà le nombre maximal d’étapes.", "Достигнут предел шагов для одной текстуры." )
R( "texture.step_summary", "Brush strokes: {{strokes}}. Other effects: {{effects}} of {{max}}.", "画笔笔画：{{strokes}}。其他效果：{{effects}} / {{max}}。", "ブラシのストローク：{{strokes}}。その他のエフェクト：{{effects}} / {{max}}。", "브러시 획: {{strokes}}. 기타 효과: {{effects}}/{{max}}.", "Traits de pinceau : {{strokes}}. Autres effets : {{effects}} sur {{max}}.", "Мазков кисти: {{strokes}}. Других эффектов: {{effects}} из {{max}}." )
R( "texture.save_size", "Save size: {{percent}}% of the limit.", "保存大小：上限的 {{percent}}%。", "保存サイズ：上限の {{percent}}%。", "저장 크기: 한도의 {{percent}}%.", "Taille de sauvegarde : {{percent}} % de la limite.", "Размер сохранения: {{percent}}% от предела." )
R( "texture.revert", "Restore the original", "恢复原始纹理", "元のテクスチャを復元", "원본 복원", "Restaurer l’original", "Восстановить исходное" )
R( "op.revert", "Restore the original in {{where}}", "在{{where}}中恢复原始纹理", "{{where}}を元のテクスチャに復元", "{{where}}을(를) 원본으로 복원", "Restaurer l’original dans {{where}}", "Восстановить исходное: {{where}}" )

-- The hint bar above the texture canvas: the active tool's state and the
-- keys that change it. Key names (Alt, Shift, Ctrl, X) stay as printed on
-- the keyboard; the mouse actions are words and are translated.
R( "texture.hint_inside", "Only inside the selection", "仅在选区内", "選択範囲の内側のみ", "선택 영역 안에서만", "Uniquement dans la sélection", "Только внутри выделения" )
R( "texture.hint_anywhere", "Works anywhere", "任意位置", "どこでも", "어디서나", "Partout", "Везде" )
R( "texture.hint_select_first", "Select an area first", "请先选择区域", "先に範囲を選択", "먼저 영역 선택", "Sélectionnez d’abord une zone", "Сначала выделите область" )
R( "texture.hint_tolerance", "Tolerance {{value}}%", "容差 {{value}}%", "許容値 {{value}}%", "허용 오차 {{value}}%", "Tolérance {{value}} %", "Допуск {{value}}%" )
R( "texture.hint_everywhere", "Everywhere on the sheet", "整张纹理", "テクスチャ全体", "텍스처 전체", "Partout sur la texture", "По всей текстуре" )
R( "texture.hint_average", "Averages {{size}} x {{size}} pixels", "取 {{size}} x {{size}} 像素平均", "{{size}} x {{size}} ピクセルを平均", "{{size}} x {{size}} 픽셀 평균", "Moyenne sur {{size}} x {{size}} pixels", "Среднее по {{size}} x {{size}} пикселям" )
R( "texture.hint_no_layer", "No layer selected", "未选择图层", "レイヤー未選択", "선택된 레이어 없음", "Aucun calque sélectionné", "Слой не выбран" )
R( "texture.key_click", "Click", "点击", "クリック", "클릭", "Clic", "Щелчок" )
R( "texture.key_drag", "Drag", "拖动", "ドラッグ", "드래그", "Glisser", "Перетаскивание" )
R( "texture.key_wheel", "Wheel", "滚轮", "ホイール", "휠", "Molette", "Колесо" )
R( "texture.key_ctrl_wheel", "Ctrl+Wheel", "Ctrl+滚轮", "Ctrl+ホイール", "Ctrl+휠", "Ctrl+molette", "Ctrl+колесо" )
R( "texture.key_right_drag", "Right drag", "右键拖动", "右ドラッグ", "오른쪽 드래그", "Glisser clic droit", "Правой кнопкой" )
R( "texture.key_corner", "Corner", "四角", "角", "모서리", "Coin", "Угол" )
R( "texture.key_top_handle", "Top handle", "顶部手柄", "上のハンドル", "위쪽 핸들", "Poignée du haut", "Верхний маркер" )
R( "texture.hint_island", "select a piece, on the texture or the model", "在纹理或模型上选择一个部件", "テクスチャかモデルで部分を選択", "텍스처나 모델에서 부분 선택", "choisir une pièce, sur la texture ou le modèle", "выбрать часть на текстуре или модели" )
R( "texture.hint_rect", "draw a rectangle", "拖出矩形", "長方形を描く", "사각형 그리기", "tracer un rectangle", "нарисовать прямоугольник" )
R( "texture.hint_oval", "draw an oval", "拖出椭圆", "楕円を描く", "타원 그리기", "tracer une ellipse", "нарисовать овал" )
R( "texture.hint_lasso", "draw around the area", "沿区域绘制", "範囲を囲んで描く", "영역을 따라 그리기", "entourer la zone", "обвести область" )
R( "texture.hint_wand", "select by colour", "按颜色选择", "色で選択", "색상으로 선택", "sélectionner par couleur", "выделить по цвету" )
R( "texture.hint_alt_revert", "Back to original for one stroke", "单次笔画恢复原样", "1ストロークだけオリジナルに戻す", "한 획만 원래대로 되돌리기", "retour à l’original pour un trait", "вернуть исходное для одного мазка" )
R( "texture.hint_alt_holes", "Make see-through for one stroke", "单次笔画变为透明", "1ストロークだけ透明にする", "한 획만 투명하게 만들기", "rendre transparent pour un trait", "сделать прозрачным для одного мазка" )
R( "texture.hint_switch_mode", "switch mode", "切换模式", "モード切替", "모드 전환", "changer de mode", "сменить режим" )
R( "texture.hint_brush_size", "brush size {{size}}%", "画笔大小 {{size}}%", "ブラシサイズ {{size}}%", "브러시 크기 {{size}}%", "taille du pinceau {{size}} %", "размер кисти {{size}}%" )
R( "texture.hint_swap", "swap colours", "交换颜色", "色を入れ替え", "색상 바꾸기", "inverser les couleurs", "поменять цвета" )
R( "texture.hint_fill", "fill the selection", "填充选区", "選択範囲を塗りつぶす", "선택 영역 채우기", "remplir la sélection", "залить выделение" )
R( "texture.hint_gradient", "foreground to background colour", "从前景色到背景色", "前景色から背景色へ", "전경색에서 배경색으로", "du premier plan à l’arrière-plan", "от основного цвета к фоновому" )
R( "texture.hint_pick", "take a colour, from the texture or the model", "从纹理或模型吸取颜色", "テクスチャかモデルから色を取得", "텍스처나 모델에서 색상 가져오기", "prélever une couleur sur la texture ou le modèle", "взять цвет с текстуры или модели" )
R( "texture.hint_pan", "move the view", "移动视图", "表示を移動", "보기 이동", "déplacer la vue", "перемещать вид" )
R( "texture.hint_move", "move", "移动", "移動", "이동", "déplacer", "переместить" )
R( "texture.hint_resize", "resize", "调整大小", "サイズ変更", "크기 조절", "redimensionner", "изменить размер" )
R( "texture.hint_rotate", "rotate", "旋转", "回転", "회전", "faire pivoter", "повернуть" )
R( "texture.hint_zoom", "zoom", "缩放", "ズーム", "확대/축소", "zoom", "масштаб" )
R( "texture.hint_undo", "undo", "撤销", "元に戻す", "실행 취소", "annuler", "отменить" )

R( "texture.apply_gamma", "Apply gamma", "应用伽马校正", "ガンマ補正を適用", "감마 적용", "Appliquer le gamma", "Применить гамма-коррекцию" )
R( "texture.gamma", "Gamma", "伽马", "ガンマ", "감마", "Gamma", "Гамма" )
R( "texture.gamma_more", "Gamma...", "伽马…", "ガンマ…", "감마…", "Gamma…", "Гамма…" )
R( "texture.gamma_tip", "Values above 1 brighten midtones; values below 1 darken them.", "高于 1 的数值会提亮中间调；低于 1 则会压暗中间调。", "1より大きいと中間調が明るくなり、1未満では暗くなります。", "1보다 높으면 중간톤이 밝아지고 1보다 낮으면 어두워집니다.", "Les valeurs supérieures à 1 éclaircissent les tons moyens ; celles inférieures à 1 les assombrissent.", "Значения выше 1 осветляют средние тона, ниже 1 — затемняют их." )
R( "texture.posterize", "Posterize", "色调分离", "ポスタリゼーション", "포스터화", "Postériser", "Постеризация" )
R( "texture.posterize_more", "Posterize...", "色调分离…", "ポスタリゼーション…", "포스터화…", "Postériser…", "Постеризация…" )
R( "texture.posterize_levels", "Colour levels", "颜色级数", "色の階調数", "색상 단계", "Niveaux de couleur", "Число уровней цвета" )
R( "texture.posterize_tip", "Reduce each colour channel to a small number of levels.", "将每个颜色通道减少到少量级数。", "各カラーチャンネルの階調数を少なくします。", "각 색상 채널의 단계 수를 줄입니다.", "Réduire chaque canal de couleur à un petit nombre de niveaux.", "Сократить каждый цветовой канал до небольшого числа уровней." )
R( "texture.apply_threshold", "Apply threshold", "应用阈值", "しきい値を適用", "임곗값 적용", "Appliquer un seuil", "Применить порог" )
R( "texture.threshold", "Threshold", "阈值", "しきい値", "임곗값", "Seuil", "Порог" )
R( "texture.threshold_more", "Threshold...", "阈值…", "しきい値…", "임곗값…", "Seuil…", "Порог…" )
R( "texture.threshold_tip", "Convert each pixel to black or white from its brightness at this cutoff.", "根据亮度是否达到此阈值，将每个像素转换为黑色或白色。", "明るさがこのしきい値を超えるかどうかで、各ピクセルを黒または白へ変換します。", "밝기가 이 임곗값에 도달하는지에 따라 각 픽셀을 검정 또는 흰색으로 변환합니다.", "Convertir chaque pixel en noir ou blanc selon sa luminosité à ce seuil.", "Преобразовать каждый пиксель в чёрный или белый по его яркости относительно этого порога." )

R( "gen.height", "Height", "高度", "高さ", "높이", "Hauteur", "Высота" )
R( "gen.read_from", "Read from", "读取通道", "読み取り元", "읽을 채널", "Lire depuis", "Читать из" )
R( "gen.detail", "Detail", "细节", "ディテール", "디테일", "Détail", "Детали" )
R( "gen.uneven", "Uneven surface", "不均匀表面", "表面の凹凸", "불규칙한 표면", "Surface irrégulière", "Неровная поверхность" )
R( "gen.uneven_enable", "Add random-like height variation", "添加程序化随机高度变化", "ランダムな高さ変化を追加", "무작위 높이 변화 추가", "Ajouter des variations de hauteur pseudo-aléatoires", "Добавить случайные вариации высоты" )
R( "gen.uneven_amount", "Amount", "强度", "量", "강도", "Intensité", "Интенсивность" )
R( "gen.uneven_density", "Feature density", "起伏密度", "凹凸の密度", "요철 밀도", "Densité des irrégularités", "Плотность неровностей" )
R( "gen.uneven_seed", "Pattern seed", "图案种子", "パターンシード", "패턴 시드", "Graine du motif", "Сид узора" )
R( "gen.uneven_new", "New pattern", "新图案", "新しいパターン", "새 패턴", "Nouveau motif", "Новый узор" )
R( "gen.uneven_enable_tip", "Adds a smooth, seeded procedural height pattern before the normal map is calculated. The same seed always produces the same surface.", "在计算法线贴图前添加平滑且带种子的程序化高度图案。相同种子始终会生成相同表面。", "法線マップの計算前に、シード付きの滑らかなプロシージャル高さパターンを加えます。同じシードからは常に同じ表面が生成されます。", "노멀 맵을 계산하기 전에 시드 기반의 부드러운 절차적 높이 패턴을 추가합니다. 같은 시드는 항상 같은 표면을 만듭니다.", "Ajoute un motif de hauteur procédural, lisse et défini par une graine avant le calcul de la normal map. Une même graine produit toujours la même surface.", "Перед расчётом карты нормалей добавляет плавный процедурный рельеф с заданным сидом. Один и тот же сид всегда создаёт одинаковую поверхность." )
R( "gen.uneven_amount_tip", "How far the generated height varies. Small values add subtle material grain; large values make the surface much rougher.", "控制生成高度的变化幅度。较小值会增加细微材质纹理，较大值会使表面明显更粗糙。", "生成する高さの変化量です。小さい値では控えめな素材感を加え、大きい値では表面をより粗くします。", "생성된 높이의 변화 폭입니다. 작은 값은 은은한 재질 결을 더하고 큰 값은 표면을 훨씬 거칠게 만듭니다.", "Règle l’amplitude des variations de hauteur. Une faible valeur ajoute un grain subtil ; une valeur élevée rend la surface beaucoup plus irrégulière.", "Задаёт амплитуду перепадов высоты. Малые значения добавляют лёгкую фактуру, большие делают поверхность намного грубее." )
R( "gen.uneven_density_tip", "How many broad features cross the texture. Low values make large, soft undulations; high values make smaller grain.", "控制纹理上的大范围起伏数量。较低值会形成宽大柔和的波动，较高值会形成更细小的颗粒。", "テクスチャを横切る大きな凹凸の数です。低い値では大きく緩やかなうねり、高い値では細かな粒になります。", "텍스처를 가로지르는 넓은 요철의 수입니다. 낮은 값은 크고 부드러운 굴곡을, 높은 값은 더 작은 결을 만듭니다.", "Détermine le nombre de larges irrégularités sur la texture. Une valeur faible crée de grandes ondulations douces ; une valeur élevée produit un grain plus fin.", "Задаёт количество крупных неровностей на текстуре. Малые значения дают широкие плавные волны, большие — более мелкую фактуру." )
R( "gen.uneven_seed_tip", "Identifies the pattern. Equal settings and seeds rebuild identical maps on every client.", "用于标识图案。相同设置和种子会在每个客户端重建出完全相同的贴图。", "パターンを識別する値です。同じ設定とシードなら、どのクライアントでも同一のマップが再構築されます。", "패턴을 식별하는 값입니다. 설정과 시드가 같으면 모든 클라이언트에서 동일한 맵을 다시 만듭니다.", "Identifie le motif. Des réglages et une graine identiques reconstruisent la même map sur chaque client.", "Определяет узор. Одинаковые настройки и сид пересоздают идентичную карту на каждом клиенте." )
R( "gen.uneven_new_tip", "Choose a different seed and preview a new pattern.", "选择另一个种子并预览新图案。", "別のシードを選び、新しいパターンをプレビューします。", "다른 시드를 선택해 새 패턴을 미리 봅니다.", "Choisit une autre graine et affiche un nouveau motif.", "Выбрать другой сид и показать новый узор." )
R( "gen.invert_height", "Invert height", "反转高度", "高さを反転", "높이 반전", "Inverser la hauteur", "Инвертировать высоту" )
R( "gen.gradient", "Gradient", "梯度", "グラデーション", "그래디언트", "Gradient", "Градиент" )
R( "gen.filter", "Filter", "滤波器", "フィルター", "필터", "Filtre", "Фильтр" )
R( "gen.strength", "Strength", "强度", "強さ", "강도", "Intensité", "Сила" )
R( "gen.invert_x", "Invert X", "反转 X", "X を反転", "X 반전", "Inverser X", "Инвертировать X" )
R( "gen.invert_y", "Invert Y", "反转 Y", "Y を反転", "Y 반전", "Inverser Y", "Инвертировать Y" )
R( "gen.output", "Output", "输出", "出力", "출력", "Sortie", "Результат" )
R( "gen.resolution", "Resolution", "分辨率", "解像度", "해상도", "Résolution", "Разрешение" )
R( "gen.tile", "Tile edges", "平铺边缘", "端をタイル接続", "가장자리 타일링", "Raccorder les bords", "Состыковать края" )
R( "gen.smoothing", "Smoothing", "平滑", "平滑化", "매끄럽게", "Lissage", "Сглаживание" )
R( "gen.contrast", "Contrast", "对比度", "コントラスト", "대비", "Contraste", "Контраст" )
R( "gen.most_reflective", "Most reflective", "最大反射度", "最大反射", "최대 반사도", "Réflexion maximale", "Максимальная отражающая способность" )
R( "gen.least_reflective", "Least reflective", "最小反射度", "最小反射", "최소 반사도", "Réflexion minimale", "Минимальная отражающая способность" )
R( "gen.source_preview", "Source", "源图像", "元画像", "원본", "Source", "Источник" )
R( "gen.generating", "Generating...", "正在生成…", "生成中…", "생성 중…", "Génération…", "Создание…" )
R( "gen.what_made", "What is it made of", "材质类型", "材質の種類", "재질 종류", "Type de matière", "Тип материала" )
R( "gen.base_sharp", "Base sharpness", "基础高光锐度", "基本の鋭さ", "기본 선명도", "Netteté de base", "Базовая резкость" )
R( "gen.texture_change", "How much the texture changes it", "纹理影响程度", "テクスチャによる変化量", "텍스처 영향 정도", "Influence de la texture", "Влияние текстуры" )
R( "gen.ignore_detail", "Ignore fine detail", "忽略细微细节", "細部を無視", "미세 디테일 무시", "Ignorer les détails fins", "Игнорировать мелкие детали" )
R( "gen.zones", "Number of zones", "分区数量", "領域数", "영역 수", "Nombre de zones", "Количество зон" )
R( "gen.highlight_colour", "Colour the highlight", "高光着色", "ハイライトに色を付ける", "하이라이트 색상", "Colorer le reflet", "Окрашивать блик" )
R( "gen.colour_amount", "How much colour", "颜色强度", "色の強さ", "색상 강도", "Quantité de couleur", "Количество цвета" )
R( "gen.rim_mask", "Rim light mask", "边缘光遮罩", "リムライトマスク", "림 라이트 마스크", "Masque d’éclairage de contour", "Маска контурного света" )
R( "gen.what_shiny", "What counts as shiny", "光泽判定方式", "光沢とみなす部分", "광택으로 판단할 부분", "Ce qui est considéré brillant", "Что считать блестящим" )
R( "gen.curve", "Curve", "曲线", "カーブ", "곡선", "Courbe", "Кривая" )
R( "gen.invert", "Turn it inside out", "反转结果", "結果を反転", "결과 반전", "Inverser le résultat", "Инвертировать результат" )
R( "gen.make_phong", "Make a phong exponent map", "生成 Phong 指数贴图", "Phong 指数マップを作成", "Phong 지수 맵 만들기", "Créer une map d’exposant Phong", "Создать карту экспоненты Phong" )
R( "gen.make_reflect", "Make a reflection mask", "生成反射遮罩", "反射マスクを作成", "반사 마스크 만들기", "Créer un masque de réflexion", "Создать маску отражений" )
R( "choice.luminance", "Luminance", "亮度", "輝度", "휘도", "Luminance", "Яркость" )
R( "choice.average", "Average RGB", "RGB 平均值", "RGB 平均", "RGB 평균", "Moyenne RVB", "Среднее RGB" )
R( "choice.red", "Red channel", "红色通道", "赤チャンネル", "빨강 채널", "Canal rouge", "Красный канал" )
R( "choice.green", "Green channel", "绿色通道", "緑チャンネル", "초록 채널", "Canal vert", "Зелёный канал" )
R( "choice.blue", "Blue channel", "蓝色通道", "青チャンネル", "파랑 채널", "Canal bleu", "Синий канал" )
R( "choice.alpha", "Alpha channel", "Alpha 通道", "アルファチャンネル", "알파 채널", "Canal alpha", "Альфа-канал" )
R( "choice.everything", "Everything", "全部", "すべて", "모두", "Tout", "Всё" )
R( "choice.rectangle", "Rectangle", "矩形", "長方形", "사각형", "Rectangle", "Прямоугольник" )
R( "choice.ellipse", "Ellipse", "椭圆", "楕円", "타원", "Ellipse", "Эллипс" )
R( "choice.free", "Free shape", "自由形状", "自由形状", "자유 형상", "Forme libre", "Свободная форма" )
R( "choice.painted", "Painted", "绘制区域", "描画領域", "그린 영역", "Peint", "Нарисованная область" )
R( "choice.similar", "Similar colour", "相近颜色", "似た色", "비슷한 색상", "Couleur similaire", "Похожий цвет" )
R( "choice.model_face", "One model face", "一个模型面", "モデルの1面", "모델 면 하나", "Une face du modèle", "Одна грань модели" )
R( "choice.uv_piece", "Connected UV piece", "相连的 UV 区块", "連結 UV パーツ", "연결된 UV 부분", "Îlot UV connexe", "Связанный участок UV" )
R( "choice.model_uses", "Everything the model uses", "模型使用的全部区域", "モデルが使う全領域", "모델이 사용하는 모든 영역", "Tout ce qu’utilise le modèle", "Всё, что использует модель" )
R( "choice.skin", "Skin", "皮肤", "肌", "피부", "Peau", "Кожа" )
R( "choice.cloth", "Cloth or fabric", "布料或织物", "布 / 生地", "천 또는 직물", "Tissu", "Ткань" )
R( "choice.leather", "Leather or vinyl", "皮革或乙烯基", "革 / ビニール", "가죽 또는 비닐", "Cuir ou vinyle", "Кожа или винил" )
R( "choice.plastic", "Hard plastic", "硬塑料", "硬質プラスチック", "경질 플라스틱", "Plastique dur", "Твёрдый пластик" )
R( "choice.metal", "Metal", "金属", "金属", "금속", "Métal", "Металл" )
R( "choice.hair", "Hair", "头发", "髪", "머리카락", "Cheveux", "Волосы" )
R( "choice.custom", "Custom", "自定义", "カスタム", "사용자 지정", "Personnalisé", "Пользовательский" )
R( "choice.bright_colourless", "Bright and colourless first (recommended)", "优先明亮且无色的区域（推荐）", "明るく無彩色の部分を優先（推奨）", "밝고 무채색인 부분 우선(권장)", "Priorité aux zones claires et incolores (recommandé)", "Сначала яркие бесцветные области (рекомендуется)" )
R( "choice.brightness", "Brightness only", "仅亮度", "明るさのみ", "밝기만", "Luminosité uniquement", "Только яркость" )
R( "choice.colourless", "Colourless areas only", "仅无色区域", "無彩色部分のみ", "무채색 영역만", "Zones incolores uniquement", "Только бесцветные области" )
R( "choice.flat", "Ignore the texture, use one level", "忽略纹理并使用单一值", "テクスチャを無視して単一レベルを使用", "텍스처를 무시하고 한 단계 사용", "Ignorer la texture et utiliser un seul niveau", "Игнорировать текстуру и использовать один уровень" )
R( "choice.tint_metal", "Only where the surface looks metallic", "仅在表面看起来像金属的区域", "金属らしく見える部分のみ", "표면이 금속처럼 보이는 부분만", "Seulement là où la surface paraît métallique", "Только там, где поверхность выглядит металлической" )
R( "choice.tint_colour", "A hint of the surface's own colour", "略微采用表面自身颜色", "表面本来の色を少し反映", "표면 자체 색상을 약간 반영", "Une touche de la couleur propre à la surface", "Лёгкий оттенок собственного цвета поверхности" )
R( "choice.tint_same", "The same everywhere", "所有区域相同", "全体で同じ", "모든 곳에서 동일", "Identique partout", "Одинаково везде" )
R( "choice.tint_none", "Never tint the highlight", "高光永不着色", "ハイライトに色を付けない", "하이라이트에 색상을 입히지 않음", "Ne jamais teinter le reflet", "Никогда не окрашивать блик" )
R( "selection.whole", "the whole texture", "整张纹理", "テクスチャ全体", "전체 텍스처", "toute la texture", "вся текстура" )
R( "selection.region", "a region", "一个区域", "領域", "영역", "une zone", "область" )
R( "selection.rect", "a rectangle", "一个矩形", "長方形", "사각형", "un rectangle", "прямоугольник" )
R( "selection.ellipse", "an ellipse", "一个椭圆", "楕円", "타원", "une ellipse", "эллипс" )
R( "selection.poly", "a free shape", "一个自由形状", "自由形状", "자유 형상", "une forme libre", "свободная форма" )
R( "selection.brush", "a painted area", "一个绘制区域", "描画領域", "그린 영역", "une zone peinte", "нарисованная область" )
R( "selection.wand", "a colour", "一种颜色", "色", "색상", "une couleur", "цвет" )
R( "selection.face", "one model face", "一个模型面", "モデルの1面", "모델 면 하나", "une face du modèle", "одна грань модели" )
R( "selection.island", "a connected piece of the model", "模型的一块相连区域", "モデルの連結部分", "모델의 연결된 부분", "une pièce connexe du modèle", "связанный участок модели" )
R( "selection.model", "everything the model uses", "模型使用的全部区域", "モデルが使う全領域", "모델이 사용하는 모든 영역", "tout ce qu’utilise le modèle", "всё, что использует модель" )
R( "selection.more", "{{base}} and {{count}} more step(s)", "{{base}}，另有 {{count}} 个步骤", "{{base}}、ほか {{count}} 手順", "{{base}} 및 추가 단계 {{count}}개", "{{base}} et {{count}} étape(s) de plus", "{{base}} и ещё {{count}} шаг(а)" )
R( "selection.inverted", "inverted", "已反转", "反転", "반전됨", "inversée", "инвертировано" )
R( "selection.grown", "grown {{value}}%", "扩展 {{value}}%", "{{value}}% 拡張", "{{value}}% 확장", "agrandie de {{value}} %", "расширено на {{value}}%" )
R( "selection.shrunk", "shrunk {{value}}%", "收缩 {{value}}%", "{{value}}% 縮小", "{{value}}% 축소", "réduite de {{value}} %", "сужено на {{value}}%" )
R( "selection.soft", "softened {{value}}%", "柔化 {{value}}%", "{{value}}% ソフト化", "{{value}}% 부드럽게", "adoucie de {{value}} %", "смягчено на {{value}}%" )
R( "selection.limited", "{{base}}, limited to {{clip}}", "{{base}}，限制在 {{clip}}", "{{base}}（{{clip}} に制限）", "{{base}}, {{clip}}로 제한", "{{base}}, limitée à {{clip}}", "{{base}}, ограничено: {{clip}}" )
R( "op.fill", "Fill {{where}} with {{colour}}{{opacity}}", "用 {{colour}}{{opacity}} 填充{{where}}", "{{where}}を {{colour}}{{opacity}} で塗りつぶす", "{{where}}을(를) {{colour}}{{opacity}}로 채우기", "Remplir {{where}} avec {{colour}}{{opacity}}", "Залить {{where}} цветом {{colour}}{{opacity}}" )
R( "op.opacity", " at {{value}}%", "，不透明度 {{value}}%", "（不透明度 {{value}}%）", "(불투명도 {{value}}%)", " à {{value}} %", " с непрозрачностью {{value}}%" )
R( "op.gradient", "Blend {{where}} from {{colour1}} to {{colour2}}{{opacity}}", "将{{where}}从 {{colour1}} 渐变到 {{colour2}}{{opacity}}", "{{where}}を {{colour1}} から {{colour2}} へグラデーション{{opacity}}", "{{where}}을(를) {{colour1}}에서 {{colour2}}로 그라디언트{{opacity}}", "Créer un dégradé sur {{where}} de {{colour1}} vers {{colour2}}{{opacity}}", "Создать градиент для {{where}} от {{colour1}} к {{colour2}}{{opacity}}" )
R( "op.tint", "Tint {{where}} towards {{colour}}", "将{{where}}着色为接近 {{colour}}", "{{where}}を {{colour}} に近づけて着色", "{{where}}을(를) {{colour}} 방향으로 색조 변경", "Teinter {{where}} vers {{colour}}", "Тонировать {{where}} к цвету {{colour}}" )
R( "op.adjust_none", "Adjust {{where}} (no change)", "调整{{where}}（无更改）", "{{where}}を調整（変更なし）", "{{where}} 조정(변경 없음)", "Ajuster {{where}} (aucun changement)", "Настроить {{where}} (без изменений)" )
R( "op.adjust", "Adjust {{where}}: {{changes}}", "调整{{where}}：{{changes}}", "{{where}}を調整：{{changes}}", "{{where}} 조정: {{changes}}", "Ajuster {{where}} : {{changes}}", "Настроить {{where}}: {{changes}}" )
R( "op.blur", "Blur {{where}} by {{value}}px", "将{{where}}模糊 {{value}}px", "{{where}}を {{value}}px ぼかす", "{{where}}을(를) {{value}}px 흐리게", "Flouter {{where}} de {{value}} px", "Размыть {{where}} на {{value}} пкс." )
R( "op.sharpen", "Sharpen {{where}} by {{value}}", "将{{where}}锐化 {{value}}", "{{where}}を {{value}} シャープ化", "{{where}}을(를) {{value}}만큼 선명하게", "Accentuer {{where}} de {{value}}", "Повысить резкость {{where}} на {{value}}" )
R( "op.noise", "Add {{value}}% noise to {{where}}", "向{{where}}添加 {{value}}% 噪点", "{{where}}に {{value}}% のノイズを追加", "{{where}}에 {{value}}% 노이즈 추가", "Ajouter {{value}} % de bruit à {{where}}", "Добавить {{value}}% шума к {{where}}" )
R( "op.erase", "Erase {{where}} to transparent", "将{{where}}擦除为透明", "{{where}}を透明に消去", "{{where}}을(를) 투명하게 지우기", "Effacer {{where}} en transparence", "Стереть {{where}} до прозрачности" )
R( "op.restore", "Make {{where}} solid again", "使{{where}}恢复不透明", "{{where}}を再び不透明にする", "{{where}}을(를) 다시 불투명하게 만들기", "Rendre {{where}} à nouveau opaque", "Снова сделать {{where}} непрозрачным" )
R( "op.alpha_from", "Transparency from {{source}} over {{where}}", "根据{{where}}上的{{source}}生成透明度", "{{where}}の{{source}}から透明度を生成", "{{where}}의 {{source}}에서 투명도 생성", "Transparence depuis {{source}} sur {{where}}", "Прозрачность из {{source}} поверх {{where}}" )
R( "op.layer", "Layer {{texture}}{{opacity}}", "图层 {{texture}}{{opacity}}", "レイヤー {{texture}}{{opacity}}", "레이어 {{texture}}{{opacity}}", "Calque {{texture}}{{opacity}}", "Слой {{texture}}{{opacity}}" )
R( "op.hue", "hue", "色相", "色相", "색조", "teinte", "тон" )
R( "op.saturation", "saturation", "饱和度", "彩度", "채도", "saturation", "насыщенность" )
R( "op.brightness", "brightness", "亮度", "明るさ", "밝기", "luminosité", "яркость" )
R( "op.lift", "lift", "提亮", "持ち上げ", "리프트", "élévation", "подъём" )
R( "op.gamma", "gamma", "伽马", "ガンマ", "감마", "gamma", "гамма" )
R( "op.greyscale", "greyscale", "灰度", "グレースケール", "회색조", "niveaux de gris", "оттенки серого" )
R( "op.posterize", "posterize", "色调分离", "ポスタリゼーション", "포스터화", "postérisation", "постеризация" )
R( "op.threshold", "threshold", "阈值", "しきい値", "임곗값", "seuil", "порог" )
R( "recipe.steps", "{{count}} step(s)", "{{count}} 个步骤", "{{count}} 手順", "단계 {{count}}개", "{{count}} étape(s)", "Шагов: {{count}}" )
R( "recipe.layers", "{{count}} layer(s)", "{{count}} 个图层", "{{count}} レイヤー", "레이어 {{count}}개", "{{count}} calque(s)", "Слоёв: {{count}}" )
R( "recipe.off", "{{count}} off", "{{count}} 个已关闭", "{{count}} 件オフ", "{{count}}개 꺼짐", "{{count}} désactivée(s)", "Отключено: {{count}}" )
R( "recipe.blank", "from a blank image", "源自空白图像", "空画像から", "빈 이미지에서", "depuis une image vide", "из пустого изображения" )
R( "recipe.strength", "strength {{value}}", "强度 {{value}}", "強さ {{value}}", "강도 {{value}}", "intensité {{value}}", "сила {{value}}" )
R( "recipe.blur", "blur {{value}}", "模糊 {{value}}", "ぼかし {{value}}", "흐림 {{value}}", "flou {{value}}", "размытие {{value}}" )
R( "recipe.detail", "detail {{value}}", "细节 {{value}}", "ディテール {{value}}", "디테일 {{value}}", "détail {{value}}", "детали {{value}}" )
R( "recipe.uneven", "uneven {{amount}}% / density {{density}} / seed {{seed}}", "不均匀 {{amount}}% / 密度 {{density}} / 种子 {{seed}}", "凹凸 {{amount}}% / 密度 {{density}} / シード {{seed}}", "불규칙 {{amount}}% / 밀도 {{density}} / 시드 {{seed}}", "irrégularité {{amount}} % / densité {{density}} / graine {{seed}}", "неровность {{amount}}% / плотность {{density}} / сид {{seed}}" )
R( "recipe.alpha_mask", "reflection mask in alpha", "Alpha 通道中的反射遮罩", "アルファ内の反射マスク", "알파의 반사 마스크", "masque de réflexion dans l’alpha", "маска отражений в альфа-канале" )
R( "recipe.smooth", "smooth", "平滑", "滑らか", "매끄럽게", "lisse", "плавно" )
R( "recipe.zones", "{{count}} zones", "{{count}} 个分区", "{{count}} 領域", "영역 {{count}}개", "{{count}} zones", "Зон: {{count}}" )
R( "recipe.tint", "tinted highlight", "着色高光", "色付きハイライト", "색조가 적용된 하이라이트", "reflet teinté", "окрашенный блик" )
R( "recipe.smoothed", "smoothed {{value}}", "平滑 {{value}}", "平滑化 {{value}}", "매끄럽게 {{value}}", "lissé {{value}}", "сглажено {{value}}" )
R( "recipe.exponent", "exponent {{min}} to {{max}}", "指数 {{min}} 到 {{max}}", "指数 {{min}} ～ {{max}}", "지수 {{min}}~{{max}}", "exposant de {{min}} à {{max}}", "экспонента от {{min}} до {{max}}" )
R( "recipe.clamped", "clamped", "边缘夹紧", "端を固定", "가장자리 고정", "bords verrouillés", "края ограничены" )
R( "colour.colour", "colour", "颜色", "色", "색상", "couleur", "цвет" )
R( "colour.black", "black", "黑色", "黒", "검정", "noir", "чёрный" )
R( "colour.white", "white", "白色", "白", "흰색", "blanc", "белый" )
R( "colour.grey", "grey", "灰色", "灰色", "회색", "gris", "серый" )
R( "colour.light_grey", "light grey", "浅灰色", "明るい灰色", "밝은 회색", "gris clair", "светло-серый" )
R( "colour.dark_grey", "dark grey", "深灰色", "濃い灰色", "어두운 회색", "gris foncé", "тёмно-серый" )
R( "colour.red", "red", "红色", "赤", "빨강", "rouge", "красный" )
R( "colour.dark_red", "dark red", "深红色", "濃い赤", "진한 빨강", "rouge foncé", "тёмно-красный" )
R( "colour.orange", "orange", "橙色", "オレンジ", "주황", "orange", "оранжевый" )
R( "colour.gold", "gold", "金色", "金", "금색", "or", "золотой" )
R( "colour.yellow", "yellow", "黄色", "黄", "노랑", "jaune", "жёлтый" )
R( "colour.olive", "olive", "橄榄色", "オリーブ", "올리브", "olive", "оливковый" )
R( "colour.green", "green", "绿色", "緑", "초록", "vert", "зелёный" )
R( "colour.dark_green", "dark green", "深绿色", "濃い緑", "진한 초록", "vert foncé", "тёмно-зелёный" )
R( "colour.teal", "teal", "蓝绿色", "青緑", "청록", "sarcelle", "бирюзово-зелёный" )
R( "colour.cyan", "cyan", "青色", "シアン", "시안", "cyan", "голубой" )
R( "colour.sky", "sky blue", "天蓝色", "空色", "하늘색", "bleu ciel", "небесно-голубой" )
R( "colour.blue", "blue", "蓝色", "青", "파랑", "bleu", "синий" )
R( "colour.navy", "navy", "藏青色", "紺", "남색", "bleu marine", "тёмно-синий" )
R( "colour.purple", "purple", "紫色", "紫", "보라", "violet", "фиолетовый" )
R( "colour.magenta", "magenta", "洋红色", "マゼンタ", "자홍", "magenta", "пурпурный" )
R( "colour.pink", "pink", "粉色", "ピンク", "분홍", "rose", "розовый" )
R( "colour.brown", "brown", "棕色", "茶色", "갈색", "brun", "коричневый" )
R( "colour.tan", "tan", "棕褐色", "黄褐色", "황갈색", "fauve", "светло-коричневый" )
R( "colour.cream", "cream", "奶油色", "クリーム", "크림색", "crème", "кремовый" )

R( "normal.title", "Generate normal map", "生成法线贴图", "法線マップを生成", "노멀 맵 생성", "Générer une normal map", "Создать карту нормалей" )
R( "normal.source", "Source texture", "源纹理", "元テクスチャ", "원본 텍스처", "Texture source", "Исходная текстура" )
R( "normal.generate", "Generate and use", "生成并使用", "生成して使用", "생성 후 사용", "Générer et utiliser", "Создать и использовать" )
R( "normal.no_source", "No source texture chosen.", "尚未选择源纹理。", "元テクスチャが選択されていません。", "원본 텍스처를 선택하지 않았습니다.", "Aucune texture source sélectionnée.", "Исходная текстура не выбрана." )
R( "normal.generate_tip", "Build the map at the chosen resolution and plug it into the parameter.", "以所选分辨率生成贴图并将其填入参数。", "選択した解像度でマップを生成し、パラメーターに設定します。", "선택한 해상도로 맵을 만들고 매개변수에 연결합니다.", "Génère la map à la résolution choisie et l’affecte au paramètre.", "Создать карту в выбранном разрешении и назначить её параметру." )
R( "normal.mask_tip", "Fills this normal map's alpha channel with a mask of how reflective and shiny each part of the surface is.\n\nOn a material with $phong or a bump map the engine reads its mask from here and ignores $envmapmask entirely, so this is where it has to live.", "在法线贴图的 Alpha 通道中写入遮罩，表示表面各部分的反射和光泽强度。\n\n使用 $phong 或凹凸贴图时，引擎从此处读取遮罩并完全忽略 $envmapmask，因此遮罩必须放在这里。", "法線マップのアルファに、表面各部の反射・光沢の強さを示すマスクを書き込みます。\n\n$phong またはバンプマップを使うマテリアルではエンジンがここからマスクを読み、$envmapmask を無視するため、ここに入れる必要があります。", "노멀 맵의 알파 채널에 표면 각 부분의 반사 및 광택 정도를 나타내는 마스크를 넣습니다.\n\n$phong 또는 범프 맵이 있는 재질은 엔진이 여기서 마스크를 읽고 $envmapmask를 무시하므로 반드시 여기에 있어야 합니다.", "Remplit l’alpha de la normal map avec un masque indiquant la réflexion et la brillance de chaque partie.\n\nAvec $phong ou une bump map, le moteur lit ce masque ici et ignore entièrement $envmapmask ; il doit donc se trouver dans ce canal.", "Заполняет альфа-канал карты нормалей маской отражения и блеска частей поверхности.\n\nПри наличии $phong или карты рельефа движок читает маску отсюда и полностью игнорирует $envmapmask, поэтому маска должна находиться здесь." )
R( "normal.mask_alpha", "Put a reflection mask in the alpha channel", "将反射遮罩放入 Alpha 通道", "反射マスクをアルファチャンネルに入れる", "알파 채널에 반사 마스크 넣기", "Placer un masque de réflexion dans le canal alpha", "Поместить маску отражений в альфа-канал" )
R( "normal.storage_note", "The image is written to garrysmod/data/advmat/normals/ as a PNG. Convert it to a .vtf if you want to ship it with the model; until then the settings travel with the override and every client rebuilds it.", "图像会以 PNG 写入 garrysmod/data/advmat/normals/。若要随模型发布，请将其转换为 .vtf；在此之前，设置会随覆盖传输并由每个客户端重建。", "画像は PNG として garrysmod/data/advmat/normals/ に書き込まれます。モデルと配布する場合は .vtf に変換してください。それまでは設定が上書きと共に送られ、各クライアントが再構築します。", "이미지는 PNG로 garrysmod/data/advmat/normals/에 저장됩니다. 모델과 함께 배포하려면 .vtf로 변환하세요. 그전에는 설정이 재정의와 함께 전달되고 각 클라이언트가 다시 만듭니다.", "L’image est écrite en PNG dans garrysmod/data/advmat/normals/. Convertissez-la en .vtf pour la distribuer avec le modèle ; jusque-là, les réglages accompagnent le remplacement et chaque client la reconstruit.", "Изображение записывается как PNG в garrysmod/data/advmat/normals/. Для поставки с моделью преобразуйте его в .vtf; до этого настройки передаются с переопределением, и каждый клиент пересоздаёт изображение." )
R( "normal.rtx_note", "This build renders with mat_bumpmap off, so a normal map will not show up in game. The PNG is still worth making: convert it to a .vtf and it becomes the normal map of an RTX Remix replacement.", "此版本关闭了 mat_bumpmap，因此法线贴图不会在游戏中显示。该 PNG 仍有用途：将其转换为 .vtf 后，可用作 RTX Remix 替换材质的法线贴图。", "このビルドは mat_bumpmap がオフのため、法線マップはゲーム内に表示されません。ただし PNG を .vtf に変換すれば、RTX Remix 置換マテリアルの法線マップとして使えます。", "이 빌드는 mat_bumpmap이 꺼져 있어 노멀 맵이 게임에 표시되지 않습니다. 그래도 PNG를 .vtf로 변환하면 RTX Remix 대체 재질의 노멀 맵으로 사용할 수 있습니다.", "Cette version rend avec mat_bumpmap désactivé ; la normal map n’apparaîtra pas en jeu. Le PNG reste utile : converti en .vtf, il peut servir de normal map à un remplacement RTX Remix.", "В этой сборке mat_bumpmap отключён, поэтому карта нормалей не будет видна в игре. PNG всё равно полезен: преобразуйте его в .vtf и используйте как карту нормалей замены RTX Remix." )
R( "surface.largest", "Largest allowed", "允许的最大尺寸", "許可する最大サイズ", "허용되는 최대 크기", "Taille maximale autorisée", "Максимально допустимый размер" )
R( "surface.read_from", "Read the colours from", "从此处读取颜色", "色の読み取り元", "색상을 읽을 원본", "Lire les couleurs depuis", "Источник цветов" )
R( "surface.needs", "What else this needs", "还需要以下设置", "ほかに必要な設定", "추가로 필요한 설정", "Autres réglages nécessaires", "Дополнительные необходимые настройки" )
R( "surface.use_map", "Use this map", "使用此贴图", "このマップを使用", "이 맵 사용", "Utiliser cette map", "Использовать эту карту" )
R( "surface.limit_tip", "The largest texture this machine will read or generate.\nEvery pixel is handled one at a time in Lua here, so the big sizes cost real time and real memory: 4096 x 4096 is a few hundred megabytes and a pause of several seconds. Raise it when a material needs it.", "此机器将读取或生成的最大纹理尺寸。\nLua 会逐像素处理，因此大尺寸会占用大量时间和内存：4096 × 4096 需要数百 MB，并可能暂停数秒。仅在材质确有需要时提高。", "この環境で読み取り・生成する最大テクスチャサイズです。\nLua で全ピクセルを処理するため、大きなサイズは時間とメモリを消費します。4096×4096 は数百 MB と数秒の停止を伴います。必要な場合だけ上げてください。", "이 컴퓨터에서 읽거나 생성할 최대 텍스처 크기입니다.\nLua에서 픽셀마다 처리하므로 큰 크기는 시간과 메모리를 많이 사용합니다. 4096×4096은 수백 MB와 몇 초의 멈춤이 필요합니다. 재질에 필요할 때만 높이세요.", "Taille maximale lue ou générée par cette machine.\nChaque pixel est traité en Lua : les grandes tailles consomment réellement du temps et de la mémoire. 4096 × 4096 représente plusieurs centaines de Mo et une pause de quelques secondes. N’augmentez cette limite qu’en cas de besoin.", "Максимальный размер текстуры, которую система прочитает или создаст.\nКаждый пиксель обрабатывается в Lua, поэтому большие размеры требуют времени и памяти: 4096 × 4096 занимает сотни МБ и вызывает паузу на несколько секунд. Увеличивайте только при необходимости." )
R( "surface.choose_tip", "Opens the texture editor's selection tools, including clicking the model to pick a piece of it.", "打开纹理编辑器的选择工具，其中包括点击模型以选择部件。", "テクスチャエディターの選択ツールを開き、モデルをクリックして部分を選べます。", "텍스처 편집기의 선택 도구를 열어 모델을 클릭해 부분을 선택할 수 있습니다.", "Ouvre les outils de sélection de l’éditeur de texture, dont la sélection d’une pièce en cliquant sur le modèle.", "Открывает инструменты выделения редактора текстур, включая выбор части щелчком по модели." )
R( "surface.flip_tip", "Swap between changing what you picked and changing everything else.", "在更改所选区域与更改其余区域之间切换。", "選択部分を変更するか、それ以外を変更するか切り替えます。", "선택한 영역 변경과 나머지 영역 변경을 전환합니다.", "Bascule entre la modification de la sélection et celle de tout le reste.", "Переключает изменение выделенного и всего остального." )
R( "surface.setup_tip", "Sets the other parameters this map needs. Without them the map is generated but the engine never reads it.", "设置此贴图所需的其他参数。若未设置，贴图虽会生成，但引擎不会读取。", "このマップに必要な他のパラメーターも設定します。設定しないと生成されてもエンジンが読み取りません。", "이 맵에 필요한 다른 매개변수도 설정합니다. 설정하지 않으면 맵은 생성되지만 엔진이 읽지 않습니다.", "Définit les autres paramètres nécessaires à cette map. Sans eux, elle est générée mais jamais lue par le moteur.", "Задаёт другие параметры, необходимые карте. Без них карта создаётся, но движок её не читает." )
R( "surface.setup", "Also set the material up to use it", "同时设置材质以使用此贴图", "マテリアル側も使用できるよう設定", "재질에서도 사용하도록 함께 설정", "Configurer aussi le matériau pour l’utiliser", "Также настроить материал для её использования" )
R( "surface.invert_negative", "Turn it inside out (negative)", "反转结果（负片）", "結果を反転（ネガ）", "결과 반전(네거티브)", "Inverser le résultat (négatif)", "Инвертировать результат (негатив)" )
R( "surface.phong", "Phong exponent map", "Phong 指数贴图", "Phong 指数マップ", "Phong 지수 맵", "Map d’exposant Phong", "Карта экспоненты Phong" )
R( "surface.reflect", "Reflection mask", "反射遮罩", "反射マスク", "반사 마스크", "Masque de réflexion", "Маска отражений" )
R( "surface.whole_desc", "The whole texture", "整张纹理", "テクスチャ全体", "전체 텍스처", "Toute la texture", "Вся текстура" )
R( "surface.region_inside", "Only inside {{area}}", "仅 {{area}} 内部", "{{area}} の内側のみ", "{{area}} 안쪽만", "Uniquement à l’intérieur de {{area}}", "Только внутри: {{area}}" )
R( "surface.region_outside", "Only outside {{area}}", "仅 {{area}} 外部", "{{area}} の外側のみ", "{{area}} 바깥쪽만", "Uniquement à l’extérieur de {{area}}", "Только снаружи: {{area}}" )
R( "surface.note_exponent", "$phongexponent is set to {{value}} on this material, and any positive value there replaces the whole exponent texture. It will be set to 0, which is how you tell the shader to read the texture instead.", "此材质的 $phongexponent 设为 {{value}}，任何正值都会完全取代指数纹理。它将被设为 0，以通知着色器改为读取纹理。", "このマテリアルでは $phongexponent が {{value}} になっており、正の値は指数テクスチャ全体を上書きします。テクスチャを読むようシェーダーに指示するため 0 に設定します。", "이 재질의 $phongexponent가 {{value}}(으)로 설정되어 있으며 양수 값은 지수 텍스처 전체를 대체합니다. 셰이더가 텍스처를 읽도록 0으로 설정합니다.", "$phongexponent vaut {{value}} sur ce matériau ; toute valeur positive remplace entièrement la texture d’exposant. Il sera réglé sur 0 afin d’indiquer au shader de lire la texture.", "У этого материала $phongexponent равен {{value}}; любое положительное значение полностью заменяет текстуру экспоненты. Параметр будет установлен в 0, чтобы шейдер читал текстуру." )
R( "surface.note_phongtint", "$phongtint is set, and it overrides the green channel entirely. Remove it if you want the tint this map describes.", "$phongtint 已设置，会完全覆盖绿色通道。若要使用此贴图描述的色调，请移除它。", "$phongtint が設定されており、緑チャンネルを完全に上書きします。このマップの色合いを使うには削除してください。", "$phongtint가 설정되어 있어 초록 채널을 완전히 덮어씁니다. 이 맵의 색조를 사용하려면 제거하세요.", "$phongtint est défini et remplace entièrement le canal vert. Supprimez-le pour utiliser la teinte décrite par cette map.", "$phongtint задан и полностью заменяет зелёный канал. Удалите его, чтобы использовать оттенок, заданный этой картой." )
R( "surface.note_no_bump", "This material has no $bumpmap. Phong needs one: without it the engine never routes to the shader that reads any of this, and nothing at all will change. Generate a normal map first.", "此材质没有 $bumpmap。Phong 需要法线贴图；若缺少它，引擎不会进入读取这些设置的着色器路径，因此不会产生任何变化。请先生成法线贴图。", "このマテリアルには $bumpmap がありません。Phong には必要で、なければエンジンはこれらを読むシェーダーへ進まず何も変わりません。先に法線マップを生成してください。", "이 재질에는 $bumpmap이 없습니다. Phong에는 범프맵이 필요합니다. 없으면 엔진이 이 설정을 읽는 셰이더 경로로 들어가지 않아 아무 변화도 없습니다. 먼저 노멀 맵을 생성하세요.", "Ce matériau n’a pas de $bumpmap. Phong en exige une ; sans elle, le moteur n’emprunte jamais le shader qui lit ces réglages et rien ne change. Générez d’abord une normal map.", "У материала нет $bumpmap. Для Phong она обязательна: без неё движок не использует шейдер, читающий эти настройки, и ничего не изменится. Сначала создайте карту нормалей." )
R( "surface.note_route", "A separate $envmapmask will not work here. Open the normal map generator instead and switch on \"Put a reflection mask in the alpha channel\", which puts it where the shader is actually looking.", "单独的 $envmapmask 在此处无效。请改为打开法线贴图生成器并启用“将反射遮罩放入 Alpha 通道”，以将遮罩放到着色器实际读取的位置。", "ここでは別の $envmapmask は機能しません。代わりに法線マップ生成器を開き、「反射マスクをアルファチャンネルに入れる」を有効にして、シェーダーが実際に読む場所へ入れてください。", "별도의 $envmapmask는 여기서 작동하지 않습니다. 노멀 맵 생성기를 열고 ‘알파 채널에 반사 마스크 넣기’를 켜 셰이더가 실제로 읽는 위치에 넣으세요.", "Un $envmapmask séparé ne fonctionnera pas ici. Ouvrez plutôt le générateur de normal map et activez « Placer un masque de réflexion dans le canal alpha », afin de le placer là où le shader le lit réellement.", "Отдельный $envmapmask здесь не сработает. Откройте генератор карты нормалей и включите «Поместить маску отражений в альфа-канал», чтобы записать её туда, откуда шейдер действительно читает." )
R( "surface.note_envmap", "A mask on its own does nothing, so $envmap env_cubemap will be set as well. On a map with no cubemaps built, that reflection can come out black or as a stock desert sky rather than the room around you.", "遮罩本身不起作用，因此也会设置 $envmap env_cubemap。若地图未构建立方体贴图，反射可能显示为黑色或默认沙漠天空，而非周围房间。", "マスクだけでは効果がないため、$envmap env_cubemap も設定します。キューブマップがビルドされていないマップでは、周囲の部屋ではなく黒や既定の砂漠の空が映る場合があります。", "마스크만으로는 효과가 없으므로 $envmap env_cubemap도 설정합니다. 큐브맵이 빌드되지 않은 맵에서는 주변 공간 대신 검게 보이거나 기본 사막 하늘이 반사될 수 있습니다.", "Un masque seul ne produit aucun effet ; $envmap env_cubemap sera donc également défini. Sur une carte sans cubemaps compilées, le reflet peut être noir ou afficher le ciel désertique par défaut au lieu de la pièce environnante.", "Одна маска ничего не делает, поэтому будет также задано $envmap env_cubemap. На карте без собранных кубических карт отражение может быть чёрным или показывать стандартное пустынное небо вместо помещения." )
R( "surface.route_base_phong", "This material has $phong 1 and $basemapalphaphongmask 1, so the shader reads its reflection and highlight mask from the alpha channel of $basetexture. A separate $envmapmask texture is not read at all.", "此材质设置了 $phong 1 和 $basemapalphaphongmask 1，因此着色器从 $basetexture 的 Alpha 通道读取反射和高光遮罩；单独的 $envmapmask 完全不会被读取。", "このマテリアルは $phong 1 と $basemapalphaphongmask 1 のため、反射・ハイライトマスクを $basetexture のアルファから読みます。別の $envmapmask はまったく読み込まれません。", "이 재질은 $phong 1과 $basemapalphaphongmask 1이 설정되어 셰이더가 $basetexture의 알파 채널에서 반사 및 하이라이트 마스크를 읽습니다. 별도의 $envmapmask는 읽지 않습니다.", "Ce matériau utilise $phong 1 et $basemapalphaphongmask 1 ; le shader lit donc le masque de réflexion et de reflet spéculaire dans le canal alpha de $basetexture. Une texture $envmapmask séparée n’est pas lue.", "У материала заданы $phong 1 и $basemapalphaphongmask 1, поэтому шейдер читает маску отражений и бликов из альфа-канала $basetexture. Отдельный $envmapmask не читается." )
R( "surface.route_bump_phong", "This material has $phong 1, so the shader reads its reflection and highlight mask from the alpha channel of $bumpmap. A separate $envmapmask texture is not read at all.", "此材质设置了 $phong 1，因此着色器从 $bumpmap 的 Alpha 通道读取反射和高光遮罩；单独的 $envmapmask 完全不会被读取。", "このマテリアルは $phong 1 のため、反射・ハイライトマスクを $bumpmap のアルファから読みます。別の $envmapmask はまったく読み込まれません。", "이 재질은 $phong 1이 설정되어 셰이더가 $bumpmap의 알파 채널에서 반사 및 하이라이트 마스크를 읽습니다. 별도의 $envmapmask는 읽지 않습니다.", "Ce matériau utilise $phong 1 ; le shader lit donc le masque de réflexion et de reflet spéculaire dans le canal alpha de $bumpmap. Une texture $envmapmask séparée n’est pas lue.", "У материала задан $phong 1, поэтому шейдер читает маску отражений и бликов из альфа-канала $bumpmap. Отдельный $envmapmask не читается." )
R( "surface.route_base_no_bump", "This material has $phong 1 with no $bumpmap, so the mask comes from the alpha channel of $basetexture.", "此材质设置了 $phong 1，但没有 $bumpmap，因此遮罩来自 $basetexture 的 Alpha 通道。", "このマテリアルは $phong 1 ですが $bumpmap がないため、マスクは $basetexture のアルファから取得されます。", "이 재질은 $phong 1이지만 $bumpmap이 없어 마스크를 $basetexture의 알파 채널에서 가져옵니다.", "Ce matériau utilise $phong 1 sans $bumpmap ; le masque provient donc du canal alpha de $basetexture.", "У материала задан $phong 1, но нет $bumpmap, поэтому маска берётся из альфа-канала $basetexture." )
R( "surface.route_bump", "This material has a $bumpmap. $envmapmask is ignored once a bump map is present, and setting it would switch $envmap off as well, so the mask has to go in the alpha channel of $bumpmap with $normalmapalphaenvmapmask 1.", "此材质含有 $bumpmap。存在凹凸贴图时 $envmapmask 会被忽略，设置它还会关闭 $envmap，因此遮罩必须放入 $bumpmap 的 Alpha 通道，并设置 $normalmapalphaenvmapmask 1。", "このマテリアルには $bumpmap があります。バンプマップがあると $envmapmask は無視され、設定すると $envmap も無効になるため、$normalmapalphaenvmapmask 1 と共に $bumpmap のアルファへマスクを入れる必要があります。", "이 재질에는 $bumpmap이 있습니다. 범프맵이 있으면 $envmapmask는 무시되고 설정 시 $envmap도 꺼지므로 $normalmapalphaenvmapmask 1과 함께 마스크를 $bumpmap의 알파 채널에 넣어야 합니다.", "Ce matériau possède un $bumpmap. Dès qu’une bump map est présente, $envmapmask est ignoré et son activation désactive aussi $envmap ; le masque doit donc être placé dans le canal alpha de $bumpmap avec $normalmapalphaenvmapmask 1.", "У материала есть $bumpmap. При наличии карты рельефа $envmapmask игнорируется, а его установка также отключит $envmap, поэтому маску нужно поместить в альфа-канал $bumpmap и задать $normalmapalphaenvmapmask 1." )
R( "surface.route_separate", "This material has no $bumpmap and no $phong, so a separate $envmapmask texture is read normally.", "此材质没有 $bumpmap 和 $phong，因此会正常读取单独的 $envmapmask 纹理。", "このマテリアルには $bumpmap も $phong もないため、別の $envmapmask テクスチャが通常どおり読み込まれます。", "이 재질에는 $bumpmap과 $phong이 없으므로 별도의 $envmapmask 텍스처를 정상적으로 읽습니다.", "Ce matériau ne possède ni $bumpmap ni $phong ; une texture $envmapmask séparée est donc lue normalement.", "У материала нет ни $bumpmap, ни $phong, поэтому отдельная текстура $envmapmask читается как обычно." )
R( "normal.map", "Normal map", "法线贴图", "法線マップ", "노멀 맵", "Normal map", "Карта нормалей" )

R( "model.frame", "Frame", "帧", "フレーム", "프레임", "Image", "Кадр" )
R( "model.hide_parts", "Hide parts", "隐藏部件", "パーツを隠す", "부분 숨기기", "Masquer des pièces", "Скрыть части" )
R( "model.hide_materials", "Hide materials", "隐藏材质", "マテリアルを隠す", "재질 숨기기", "Masquer des matériaux", "Скрыть материалы" )
R( "model.reset_view", "Reset view", "重置视图", "表示をリセット", "보기 초기화", "Réinitialiser la vue", "Сбросить вид" )
R( "model.show_all", "Show everything", "全部显示", "すべて表示", "모두 표시", "Tout afficher", "Показать всё" )
R( "model.one_piece", "This model is one piece - it has no parts to hide.", "此模型是一个整体——没有可隐藏的部件。", "このモデルは一体型で、隠せるパーツがありません。", "이 모델은 한 부분으로 되어 있어 숨길 부품이 없습니다.", "Ce modèle est d’un seul tenant : il ne possède aucune pièce à masquer.", "Эта модель цельная — у неё нет частей для скрытия." )
R( "model.no_materials", "This model does not report its materials.", "此模型未报告其材质。", "このモデルはマテリアル情報を報告しません。", "이 모델은 재질 정보를 제공하지 않습니다.", "Ce modèle ne fournit pas la liste de ses matériaux.", "Эта модель не сообщает свои материалы." )
R( "model.ticked", "Ticked ones are shown", "勾选项会显示", "チェックしたものを表示", "체크한 항목 표시", "Les éléments cochés sont affichés", "Отмеченные элементы показаны" )
R( "model.speed_tip", "How fast to play. Slower is easier to stop on the right frame.", "播放速度。较慢时更容易停在正确帧。", "再生速度です。遅いほど目的のフレームで止めやすくなります。", "재생 속도입니다. 느릴수록 원하는 프레임에서 멈추기 쉽습니다.", "Vitesse de lecture. Une vitesse plus lente permet de s’arrêter plus facilement sur la bonne image.", "Скорость воспроизведения. На меньшей скорости проще остановиться на нужном кадре." )
R( "model.playing", "Playing. Click the model to stop on this frame and select from it.", "正在播放。点击模型可停在当前帧并从中选择。", "再生中です。モデルをクリックすると現在のフレームで停止し、そこから選択できます。", "재생 중입니다. 모델을 클릭하면 현재 프레임에서 멈추고 선택할 수 있습니다.", "Lecture en cours. Cliquez sur le modèle pour vous arrêter sur cette image et y sélectionner une zone.", "Воспроизведение. Щёлкните по модели, чтобы остановиться на этом кадре и выбирать на нём." )
R( "model.hidden_suffix", "{{base}}  Some parts are hidden - those cannot be clicked until you show them again.", "{{base}}  某些部件已隐藏——重新显示前无法点击。", "{{base}}  一部のパーツが非表示です。再表示するまでクリックできません。", "{{base}}  일부 부품이 숨겨져 있어 다시 표시하기 전에는 클릭할 수 없습니다.", "{{base}}  Certaines pièces sont masquées ; elles ne peuvent pas être cliquées avant d’être réaffichées.", "{{base}}  Некоторые части скрыты; их нельзя выбрать, пока они снова не показаны." )
R( "editor.model_count", "{{model}}    ({{count}} sub-material(s){{trimmed}})", "{{model}}    （{{count}} 个子材质{{trimmed}}）", "{{model}}    （サブマテリアル {{count}} 個{{trimmed}}）", "{{model}}    (하위 재질 {{count}}개{{trimmed}})", "{{model}}    ({{count}} sous-matériau(x){{trimmed}})", "{{model}}    (подматериалов: {{count}}{{trimmed}})" )
R( "editor.model_trimmed", ", the rest are past the engine's 32 slot limit", "，其余部分超过引擎的 32 槽位限制", "、残りはエンジンの32スロット制限を超えています", ", 나머지는 엔진의 32슬롯 제한을 초과함", ", les autres dépassent la limite de 32 emplacements du moteur", ", остальные превышают ограничение движка в 32 слота" )
R( "model.play_tip", "Move the model, so you can see a part that is folded away in its standing pose.\n\nWhile it is playing you cannot click it. Click once to stop on the frame you are looking at, then click the model to select from that pose.", "播放模型动画，以查看站立姿势中被遮挡的部件。\n\n播放时无法点击模型。先点击一次停在当前帧，再点击模型即可从该姿势选择。", "アニメーションでモデルを動かし、立ち姿で隠れている部分を見られます。\n\n再生中はモデルをクリックできません。一度クリックして表示中のフレームで止め、その後モデルをクリックして選択します。", "모델을 움직여 기본 자세에서 가려진 부분을 볼 수 있습니다.\n\n재생 중에는 모델을 클릭할 수 없습니다. 한 번 클릭해 현재 프레임에서 멈춘 뒤 모델을 클릭해 해당 자세에서 선택하세요.", "Anime le modèle afin de voir une partie cachée dans sa pose debout.\n\nLe modèle n’est pas cliquable pendant la lecture. Cliquez une fois pour l’arrêter sur l’image affichée, puis cliquez sur le modèle pour sélectionner depuis cette pose.", "Воспроизводит анимацию модели, чтобы увидеть части, скрытые в стойке.\n\nВо время воспроизведения модель нельзя выбирать. Щёлкните один раз для остановки на текущем кадре, затем щёлкните по модели для выбора." )
R( "model.sequence_tip", "Which animation to play. The names come out of the model, so what is in this list depends entirely on how it was built.", "选择要播放的动画。名称来自模型，因此列表内容完全取决于模型的制作方式。", "再生するアニメーションです。名前はモデル由来なので、一覧の内容はモデルの作り方に依存します。", "재생할 애니메이션입니다. 이름은 모델에서 가져오므로 목록 내용은 모델 제작 방식에 따라 달라집니다.", "Animation à lire. Les noms proviennent du modèle ; le contenu de la liste dépend donc entièrement de sa conception.", "Выбор анимации. Имена берутся из модели, поэтому список полностью зависит от того, как она создана." )
R( "model.scrub_tip", "Step through the animation by hand to hold exactly the pose you want. A held pose can be clicked.", "手动逐帧浏览动画以保持所需姿势；停住的姿势可以点击选择。", "手動でアニメーションを進め、目的の姿勢を保持します。停止中の姿勢はクリックできます。", "애니메이션을 직접 이동해 원하는 자세를 유지합니다. 멈춘 자세는 클릭할 수 있습니다.", "Parcourez l’animation manuellement pour conserver exactement la pose voulue. Une pose arrêtée peut être cliquée.", "Перемещайтесь по анимации вручную, чтобы зафиксировать нужную позу. Зафиксированную позу можно выбирать щелчком." )
R( "model.parts_tip", "Switch a bodygroup - hair, a coat, a hat - to another option so it stops covering what you are working on.\n\nModels do not tell the game what their options are called, only how many there are. The empty one is usually last.\n\nThis only changes the preview. Nothing about the material you are editing changes - but the editor does have to read the model again, which takes a moment on a detailed one.", "将身体组（头发、外套、帽子等）切换到其他选项，使其不再遮挡编辑区域。\n\n模型只会报告选项数量，不会提供名称；空选项通常在最后。\n\n此操作仅影响预览，不会更改材质；但编辑器需要重新读取模型，复杂模型可能需要片刻。", "ボディグループ（髪、コート、帽子など）を別の選択肢に切り替え、作業部分を隠さないようにします。\n\nモデルは選択肢の数だけを報告し、名前は報告しません。空の選択肢は通常最後です。\n\n変更されるのはプレビューだけで、マテリアルは変わりません。ただしモデルの再読み込みに少し時間がかかる場合があります。", "바디그룹(머리카락, 코트, 모자 등)을 다른 옵션으로 바꿔 작업 영역을 가리지 않게 합니다.\n\n모델은 옵션 개수만 제공하고 이름은 제공하지 않습니다. 빈 옵션은 보통 마지막입니다.\n\n미리보기만 바뀌고 편집 중인 재질은 변경되지 않습니다. 다만 상세한 모델은 다시 읽는 데 잠시 걸릴 수 있습니다.", "Bascule un bodygroup — cheveux, manteau, chapeau — vers une autre option afin qu’il ne couvre plus la zone travaillée.\n\nLes modèles indiquent seulement le nombre d’options, pas leur nom ; l’option vide est généralement la dernière.\n\nSeul l’aperçu change, pas le matériau. La relecture d’un modèle détaillé peut toutefois prendre un instant.", "Переключает бодигруппу — волосы, пальто, шляпу — на другой вариант, чтобы она не закрывала рабочую область.\n\nМодель сообщает только число вариантов, но не их имена; пустой вариант обычно последний.\n\nМеняется только предпросмотр, материал не затрагивается. Повторное чтение сложной модели может занять время." )
R( "model.materials_tip", "Stop drawing one of the model's other materials, so you can see past it to the one you are editing.\n\nThis only changes the preview. Nothing about the material you are editing changes.", "停止绘制模型的其他材质，以便看见正在编辑的材质。\n\n此操作仅影响预览，不会更改正在编辑的材质。", "モデルの他のマテリアルを非表示にし、奥にある編集中のマテリアルを見やすくします。\n\n変更されるのはプレビューだけで、編集中のマテリアルは変わりません。", "모델의 다른 재질을 그리지 않아 뒤에 있는 편집 중인 재질을 볼 수 있게 합니다.\n\n미리보기만 바뀌며 편집 중인 재질은 변경되지 않습니다.", "Masque l’un des autres matériaux du modèle pour voir celui que vous modifiez derrière lui.\n\nSeul l’aperçu change ; le matériau modifié reste intact.", "Отключает отрисовку другого материала модели, чтобы увидеть редактируемый за ним.\n\nМеняется только предпросмотр; редактируемый материал не изменяется." )
R( "model.reset_tip", "Point the camera back at the material you are editing, from the front, at a distance that holds all of it.\n\nThe way back when the model has been dragged out of the view.\n\nTo turn around somewhere else instead, middle CLICK that spot - it moves to the middle and everything then turns around it.", "将摄像机从正面重新对准正在编辑的材质，并调整距离以完整显示。\n\n当模型被拖出视野时可用此功能找回。\n\n若要围绕其他位置旋转，请用中键点击该位置；它会移到中央并成为旋转中心。", "カメラを編集中のマテリアル正面に戻し、全体が収まる距離にします。\n\nモデルを画面外へ動かしたときに戻す機能です。\n\n別の場所を中心に回転するには、その場所を中クリックします。中央へ移動し、以後そこを中心に回転します。", "카메라를 편집 중인 재질의 정면으로 돌리고 전체가 보이는 거리로 맞춥니다.\n\n모델을 화면 밖으로 이동했을 때 되돌리는 기능입니다.\n\n다른 위치를 중심으로 회전하려면 그 지점을 가운데 클릭하세요. 해당 지점이 중앙으로 이동하고 그 주위를 회전합니다.", "Replace la caméra face au matériau modifié, assez loin pour l’afficher entièrement.\n\nPermet de retrouver un modèle déplacé hors de la vue.\n\nPour tourner autour d’un autre point, cliquez dessus avec le bouton central : il devient le centre de rotation.", "Возвращает камеру к редактируемому материалу спереди и на расстояние, где он виден целиком.\n\nПомогает вернуть модель, утащенную за пределы вида.\n\nЧтобы вращаться вокруг другой точки, щёлкните по ней средней кнопкой: она переместится в центр и станет центром вращения." )
R( "model.part", "Part {{number}}", "部件 {{number}}", "パーツ {{number}}", "부분 {{number}}", "Pièce {{number}}", "Часть {{number}}" )
R( "model.option", "Option {{number}}", "选项 {{number}}", "選択肢 {{number}}", "옵션 {{number}}", "Option {{number}}", "Вариант {{number}}" )
R( "model.option_normal", "Option 1 (normal)", "选项 1（正常）", "選択肢 1（通常）", "옵션 1(기본)", "Option 1 (normale)", "Вариант 1 (обычный)" )
R( "model.being_edited", "{{material}}   (being edited)", "{{material}}   （正在编辑）", "{{material}}   （編集中）", "{{material}}   (편집 중)", "{{material}}   (en cours de modification)", "{{material}}   (редактируется)" )

R( "browser.title", "Saved material overrides", "已保存的材质覆盖", "保存済みマテリアル上書き", "저장된 재질 재정의", "Remplacements de matériaux enregistrés", "Сохранённые переопределения материалов" )
R( "browser.scope", "Scope", "范围", "範囲", "범위", "Portée", "Область" )
R( "browser.target", "Target", "目标", "対象", "대상", "Cible", "Цель" )
R( "browser.params", "Params", "参数", "パラメーター", "매개변수", "Paramètres", "Параметры" )
R( "browser.parameter", "Parameter", "参数", "パラメーター", "매개변수", "Paramètre", "Параметр" )
R( "browser.value", "Value", "值", "値", "값", "Valeur", "Значение" )
R( "browser.refresh", "Refresh", "刷新", "更新", "새로 고침", "Actualiser", "Обновить" )
R( "browser.import", "Import...", "导入…", "インポート…", "가져오기…", "Importer…", "Импорт…" )
R( "browser.export", "Export", "导出", "エクスポート", "내보내기", "Exporter", "Экспорт" )
R( "browser.delete", "Delete this rule", "删除此规则", "このルールを削除", "이 규칙 삭제", "Supprimer cette règle", "Удалить это правило" )
R( "browser.apply", "Apply to what I am looking at", "应用到当前注视的对象", "見ている対象に適用", "바라보는 대상에 적용", "Appliquer à l’objet regardé", "Применить к объекту под прицелом" )
R( "browser.status", "{{count}} persistent rule(s) on the server.", "服务器上有 {{count}} 条持久规则。", "サーバーに永続ルールが {{count}} 件あります。", "서버에 영구 규칙 {{count}}개가 있습니다.", "{{count}} règle(s) persistante(s) sur le serveur.", "Постоянных правил на сервере: {{count}}." )
R( "browser.shader_tip", "{{id}}\nshader: {{shader}}", "{{id}}\n着色器：{{shader}}", "{{id}}\nシェーダー：{{shader}}", "{{id}}\n셰이더: {{shader}}", "{{id}}\nshader : {{shader}}", "{{id}}\nшейдер: {{shader}}" )
R( "export.title", "Copy this material as a .vmt", "将此材质复制为 .vmt", "このマテリアルを .vmt としてコピー", "이 재질을 .vmt로 복사", "Copier ce matériau sous forme de .vmt", "Копировать этот материал как .vmt" )
R( "export.copy", "Copy to clipboard", "复制到剪贴板", "クリップボードにコピー", "클립보드에 복사", "Copier dans le presse-papiers", "Копировать в буфер обмена" )
R( "export.copy_tip", "Puts the text above on your clipboard.", "将上方文本复制到剪贴板。", "上のテキストをクリップボードに入れます。", "위 텍스트를 클립보드에 복사합니다.", "Place le texte ci-dessus dans le presse-papiers.", "Помещает текст выше в буфер обмена." )
R( "export.write", "Write the files", "写出文件", "ファイルを書き出す", "파일 쓰기", "Écrire les fichiers", "Записать файлы" )
R( "export.include", "Include the material's original settings", "包含材质的原始设置", "マテリアルの元設定を含める", "재질의 원래 설정 포함", "Inclure les réglages d’origine du matériau", "Включить исходные настройки материала" )
R( "export.full_tip", "On: a complete material you can ship on its own.\nOff: only the parameters you changed, which is what you want if you are pasting into a .vmt that already exists.", "开启：可独立发布的完整材质。\n关闭：仅包含你更改的参数，适合粘贴到已有的 .vmt 中。", "オン：単体で配布できる完全なマテリアル。\nオフ：変更したパラメーターのみ。既存の .vmt に貼り付ける場合に適します。", "켜기: 단독 배포 가능한 완전한 재질.\n끄기: 변경한 매개변수만 포함하며 기존 .vmt에 붙여넣을 때 적합합니다.", "Activé : un matériau complet utilisable seul.\nDésactivé : uniquement les paramètres modifiés, pour les coller dans un .vmt existant.", "Вкл.: полный материал для самостоятельной поставки.\nВыкл.: только изменённые параметры для вставки в существующий .vmt." )
R( "export.ready", "Ready to use", "可以使用", "使用準備完了", "사용 준비 완료", "Prêt à l’emploi", "Готово к использованию" )
R( "export.needs_images", "This needs {{count}} image file(s)", "需要 {{count}} 个图像文件", "画像ファイルが {{count}} 個必要です", "이미지 파일 {{count}}개가 필요합니다", "Nécessite {{count}} fichier(s) image", "Требуется файлов изображений: {{count}}" )
R( "export.prefix_title", "Copy this material as a .vmt   -   ", "将此材质复制为 .vmt   -   ", "このマテリアルを .vmt としてコピー   -   ", "이 재질을 .vmt로 복사   -   ", "Copier ce matériau sous forme de .vmt   -   ", "Копировать материал как .vmt   -   " )
R( "export.prefix_written", "Written to garrysmod/data/", "已写入 garrysmod/data/", "garrysmod/data/ に書き込みました：", "garrysmod/data/에 기록됨: ", "Écrit dans garrysmod/data/", "Записано в garrysmod/data/" )
R( "export.write_tip", "Writes the .vmt, every image it needs and a readme into garrysmod/data/{{folder}}/", "将 .vmt、所需的所有图像和说明文件写入 garrysmod/data/{{folder}}/", ".vmt、必要な全画像、readme を garrysmod/data/{{folder}}/ に書き込みます", ".vmt, 필요한 모든 이미지와 readme를 garrysmod/data/{{folder}}/에 기록합니다", "Écrit le .vmt, toutes les images requises et un fichier d’instructions dans garrysmod/data/{{folder}}/", "Записывает .vmt, все нужные изображения и инструкцию в garrysmod/data/{{folder}}/" )
R( "export.ready_body", "Every texture this material names already exists on disk, so the text on the left is a complete .vmt. Save it as materials/{{path}}.vmt inside an addon.", "此材质引用的所有纹理都已存在于磁盘上，因此左侧文本是完整的 .vmt。请在附加组件中将其保存为 materials/{{path}}.vmt。", "このマテリアルが参照するテクスチャはすべてディスク上にあるため、左のテキストは完成した .vmt です。アドオン内の materials/{{path}}.vmt として保存してください。", "이 재질이 참조하는 모든 텍스처가 디스크에 있으므로 왼쪽 텍스트는 완성된 .vmt입니다. 애드온 안에 materials/{{path}}.vmt로 저장하세요.", "Toutes les textures référencées par ce matériau existent déjà sur le disque ; le texte de gauche est donc un .vmt complet. Enregistrez-le sous materials/{{path}}.vmt dans un addon.", "Все текстуры, указанные материалом, уже есть на диске, поэтому текст слева — готовый .vmt. Сохраните его в аддоне как materials/{{path}}.vmt." )
R( "export.images_body", "The maps you generated or painted live as .png files in your data folder. Source cannot load a .png as a material texture, so each has to be converted to a .vtf before this .vmt will work. Press \"Write the files\" and follow the readme it puts next to them.", "生成或绘制的贴图以 .png 文件存放在 data 文件夹中。Source 无法将 .png 作为材质纹理载入，因此必须先将每张图转换为 .vtf，此 .vmt 才能工作。按“写出文件”，然后按照同时生成的说明操作。", "生成・編集したマップは data フォルダーに .png として保存されています。Source は .png をマテリアルテクスチャとして読み込めないため、この .vmt を使う前に各画像を .vtf へ変換する必要があります。「ファイルを書き出す」を押し、隣に作成される readme に従ってください。", "생성하거나 편집한 맵은 data 폴더에 .png 파일로 저장됩니다. Source는 .png를 재질 텍스처로 불러올 수 없으므로 이 .vmt가 작동하려면 각각을 .vtf로 변환해야 합니다. ‘파일 쓰기’를 누르고 함께 생성되는 readme를 따르세요.", "Les maps générées ou peintes sont des fichiers .png dans votre dossier data. Source ne peut pas charger un .png comme texture de matériau ; chacune doit être convertie en .vtf pour que ce .vmt fonctionne. Cliquez sur « Écrire les fichiers » et suivez le fichier d’instructions créé à côté.", "Созданные или нарисованные карты хранятся как .png в папке data. Source не загружает .png как текстуру материала, поэтому каждую карту нужно преобразовать в .vtf. Нажмите «Записать файлы» и следуйте созданной рядом инструкции." )
R( "export.asset_body", "{{summary}}\n\nSave as:  materials/{{path}}.vtf\nFormat:   {{format}}{{flag}}\n\n{{why}}", "{{summary}}\n\n保存为：materials/{{path}}.vtf\n格式：{{format}}{{flag}}\n\n{{why}}", "{{summary}}\n\n保存先：materials/{{path}}.vtf\n形式：{{format}}{{flag}}\n\n{{why}}", "{{summary}}\n\n저장 위치: materials/{{path}}.vtf\n형식: {{format}}{{flag}}\n\n{{why}}", "{{summary}}\n\nEnregistrer sous : materials/{{path}}.vtf\nFormat : {{format}}{{flag}}\n\n{{why}}", "{{summary}}\n\nСохранить как: materials/{{path}}.vtf\nФормат: {{format}}{{flag}}\n\n{{why}}" )
R( "export.flag_tick", "  (tick \"{{flag}}\")", "  （勾选“{{flag}}”）", "  （「{{flag}}」をチェック）", "  (‘{{flag}}’ 체크)", "  (cocher « {{flag}} »)", "  (отметьте «{{flag}}»)" )
R( "export.why_normal_alpha", "It carries a mask in its alpha channel, so it needs a format with alpha. BGR888 would silently throw the mask away.", "其 Alpha 通道中包含遮罩，因此需要支持 Alpha 的格式。BGR888 会直接丢弃该遮罩。", "アルファチャンネルにマスクを含むため、アルファ対応形式が必要です。BGR888 ではマスクが失われます。", "알파 채널에 마스크가 있으므로 알파를 지원하는 형식이 필요합니다. BGR888은 마스크를 버립니다.", "Le canal alpha contient un masque ; un format avec alpha est donc nécessaire. BGR888 supprimerait ce masque.", "Альфа-канал содержит маску, поэтому нужен формат с альфой. BGR888 отбросит маску." )
R( "export.why_normal", "Normal maps must not be DXT compressed: the 5:6:5 colour endpoints cannot represent a flat normal and the surface comes out banded.", "法线贴图不能使用 DXT 压缩：5:6:5 颜色端点无法表示平坦法线，会导致表面出现色带。", "法線マップを DXT 圧縮してはいけません。5:6:5 の色端点では平坦な法線を表現できず、面に縞が出ます。", "노멀 맵은 DXT로 압축하면 안 됩니다. 5:6:5 색상 끝점으로 평평한 노멀을 표현할 수 없어 표면에 밴딩이 생깁니다.", "Les normal maps ne doivent pas être compressées en DXT : les extrémités de couleur 5:6:5 ne représentent pas une normale plane et créent des bandes sur la surface.", "Карты нормалей нельзя сжимать DXT: цветовые точки 5:6:5 не передают плоскую нормаль, и на поверхности появляются полосы." )
R( "export.why_phong", "The red and green channels mean completely different things here, and DXT compresses colour in 4x4 blocks, so the two would bleed into each other. Alpha carries the rim mask.", "此处红、绿通道含义完全不同，而 DXT 以 4×4 块压缩颜色，会使两者相互串色。Alpha 通道承载边缘光遮罩。", "ここでは赤と緑の用途が完全に異なり、DXT は色を 4×4 ブロックで圧縮するため互いににじみます。アルファにはリムマスクが入ります。", "여기서는 빨강과 초록 채널의 의미가 완전히 다르며 DXT는 색상을 4×4 블록으로 압축하므로 두 채널이 서로 번집니다. 알파에는 림 마스크가 들어갑니다.", "Les canaux rouge et vert ont ici des rôles totalement différents ; la compression DXT par blocs de 4×4 les ferait déborder l’un dans l’autre. L’alpha contient le masque de contour.", "Красный и зелёный каналы здесь имеют разный смысл, а DXT сжимает цвет блоками 4×4, поэтому они смешаются. В альфа-канале хранится контурная маска." )
R( "export.why_greyscale", "A greyscale mask with no alpha.", "不含 Alpha 的灰度遮罩。", "アルファなしのグレースケールマスクです。", "알파가 없는 회색조 마스크입니다.", "Un masque en niveaux de gris sans alpha.", "Полутоновая маска без альфа-канала." )
R( "export.why_transparency", "It has see-through areas, so it needs an alpha channel. Use BGRA8888 instead if the edges look blocky.", "它含有透明区域，因此需要 Alpha 通道。如果边缘出现块状锯齿，请改用 BGRA8888。", "透過部分があるためアルファチャンネルが必要です。輪郭がブロック状になる場合は BGRA8888 を使ってください。", "투명한 영역이 있으므로 알파 채널이 필요합니다. 가장자리가 블록처럼 보이면 BGRA8888을 사용하세요.", "L’image comporte des zones transparentes et nécessite donc un canal alpha. Utilisez plutôt BGRA8888 si les bords paraissent en blocs.", "Есть прозрачные области, поэтому нужен альфа-канал. Если края выглядят блочно, используйте BGRA8888." )
R( "export.why_opaque", "No transparency, so the smaller format is fine.", "不含透明度，因此可以使用较小的格式。", "透過部分がないため、小さい形式で問題ありません。", "투명도가 없으므로 더 작은 형식을 사용해도 됩니다.", "Aucune transparence : le format plus compact convient.", "Прозрачности нет, поэтому подходит формат меньшего размера." )
R( "export.readme_title", "Advanced Material Editor - what to do with these files", "高级材质编辑器——这些文件的使用方法", "高機能マテリアルエディター — これらのファイルの使い方", "고급 재질 편집기 - 이 파일 사용 방법", "Éditeur de matériaux avancé — utilisation de ces fichiers", "Расширенный редактор материалов — что делать с этими файлами" )
R( "export.readme_intro", "The .vmt in this folder is ready to use. The .png files are not: Source cannot load a .png as a material texture, so each one has to be converted to a .vtf first.", "此文件夹中的 .vmt 已可使用，但 .png 尚不可用：Source 无法将 .png 载入为材质纹理，因此必须先将每个文件转换为 .vtf。", "このフォルダーの .vmt はそのまま使えますが、.png は使えません。Source は .png をマテリアルテクスチャとして読み込めないため、先に各ファイルを .vtf へ変換してください。", "이 폴더의 .vmt는 바로 사용할 수 있지만 .png는 그렇지 않습니다. Source는 .png를 재질 텍스처로 불러올 수 없으므로 각각을 먼저 .vtf로 변환해야 합니다.", "Le .vmt de ce dossier est prêt à l’emploi, mais pas les fichiers .png : Source ne peut pas charger un .png comme texture de matériau ; chacun doit d’abord être converti en .vtf.", ".vmt в этой папке готов к использованию, но файлы .png — нет: Source не загружает .png как текстуру материала, поэтому каждый файл нужно сначала преобразовать в .vtf." )
R( "export.readme_step1", "1. Get VTFEdit Reloaded, or VTFCmd from VTFLib. Both are free.\n   (Crowbar cannot do this - it decompiles models, not textures.)", "1. 获取 VTFEdit Reloaded，或 VTFLib 中的 VTFCmd。两者均免费。\n   （Crowbar 无法完成此操作——它用于反编译模型，而非纹理。）", "1. VTFEdit Reloaded、または VTFLib の VTFCmd を入手します。どちらも無料です。\n   （Crowbar はモデルの逆コンパイル用で、テクスチャ変換には使えません。）", "1. VTFEdit Reloaded 또는 VTFLib의 VTFCmd를 받으세요. 둘 다 무료입니다.\n   (Crowbar는 모델을 디컴파일하는 도구이며 텍스처 변환은 할 수 없습니다.)", "1. Téléchargez VTFEdit Reloaded ou VTFCmd de VTFLib. Les deux sont gratuits.\n   (Crowbar ne convient pas : il décompile les modèles, pas les textures.)", "1. Установите VTFEdit Reloaded или VTFCmd из VTFLib. Обе программы бесплатны.\n   (Crowbar не подходит: он декомпилирует модели, а не текстуры.)" )
R( "export.readme_step2", "2. Convert each image with the format listed below. The format matters; the wrong one does not fail, it just looks wrong.", "2. 使用下列格式转换每张图像。格式很重要；选错格式不会报错，只会导致显示异常。", "2. 各画像を下記の形式で変換します。形式は重要です。間違えてもエラーにはならず、見た目だけが崩れます。", "2. 아래에 표시된 형식으로 각 이미지를 변환하세요. 형식이 중요합니다. 잘못된 형식도 오류는 나지 않지만 결과가 잘못 보입니다.", "2. Convertissez chaque image avec le format indiqué ci-dessous. Le format est important : un mauvais choix ne provoque pas d’erreur, mais donne un rendu incorrect.", "2. Преобразуйте каждое изображение в указанный ниже формат. Формат важен: неверный вариант не вызовет ошибку, но изображение будет выглядеть неправильно." )
R( "export.readme_file", "file    {{value}}", "文件    {{value}}", "ファイル    {{value}}", "파일    {{value}}", "fichier    {{value}}", "файл    {{value}}" )
R( "export.readme_save", "save as materials/{{value}}.vtf", "保存为 materials/{{value}}.vtf", "materials/{{value}}.vtf として保存", "materials/{{value}}.vtf로 저장", "enregistrer sous materials/{{value}}.vtf", "сохранить как materials/{{value}}.vtf" )
R( "export.readme_format", "format  {{format}}{{flag}}", "格式    {{format}}{{flag}}", "形式    {{format}}{{flag}}", "형식    {{format}}{{flag}}", "format  {{format}}{{flag}}", "формат  {{format}}{{flag}}" )
R( "export.readme_with_flag", "   with the \"{{flag}}\" flag ticked", "   并勾选“{{flag}}”标志", "   「{{flag}}」フラグをチェック", "   ‘{{flag}}’ 플래그 체크", "   avec l’indicateur « {{flag}} » coché", "   с отмеченным флагом «{{flag}}»" )
R( "export.readme_why", "why     {{value}}", "原因    {{value}}", "理由    {{value}}", "이유    {{value}}", "raison  {{value}}", "причина {{value}}" )
R( "export.readme_made", "made by {{value}}", "生成方式 {{value}}", "作成方法 {{value}}", "생성 방법 {{value}}", "créé par {{value}}", "создано: {{value}}" )
R( "export.readme_step3", "3. Put the files in an addon:", "3. 将文件放入附加组件：", "3. ファイルをアドオンに配置します：", "3. 파일을 애드온에 넣으세요:", "3. Placez les fichiers dans un addon :", "3. Поместите файлы в аддон:" )
R( "export.readme_step4", "4. Keep every name lowercase. When an addon is packed for the Workshop every filename is lowercased, so a material referenced with capital letters works on your machine and is missing for everyone else.", "4. 所有名称都应使用小写。为创意工坊打包附加组件时，每个文件名都会转为小写，因此使用大写字母引用的材质可能仅在你的电脑上有效，而其他人会缺失该材质。", "4. 名前はすべて小文字にしてください。Workshop 用にアドオンをパックすると全ファイル名が小文字になるため、大文字を含む参照は自分の環境では動いても、他のユーザーには欠落します。", "4. 모든 이름을 소문자로 유지하세요. Workshop용으로 애드온을 패킹하면 모든 파일 이름이 소문자로 바뀌므로 대문자로 참조한 재질은 내 컴퓨터에서만 작동하고 다른 사용자에게는 누락됩니다.", "4. Conservez tous les noms en minuscules. Lorsqu’un addon est empaqueté pour le Workshop, chaque nom de fichier passe en minuscules ; une référence contenant des majuscules peut fonctionner chez vous mais manquer chez tous les autres.", "4. Используйте только строчные имена. При упаковке аддона для Workshop все имена файлов переводятся в нижний регистр, поэтому ссылка с заглавными буквами работает у вас, но у остальных материал будет отсутствовать." )
R( "export.readme_final", "The .vmt does not have to sit next to the .vtf files. Its own location is what gives the material its name; the paths inside it are independent.", ".vmt 不必与 .vtf 文件放在同一位置。.vmt 自身的位置决定材质名称；其中的纹理路径彼此独立。", ".vmt を .vtf と同じ場所に置く必要はありません。.vmt 自身の場所がマテリアル名になり、内部のパスはそれとは独立しています。", ".vmt는 .vtf 파일 옆에 있을 필요가 없습니다. .vmt 자체의 위치가 재질 이름을 결정하며 내부 경로는 서로 독립적입니다.", "Le .vmt n’a pas besoin de se trouver à côté des fichiers .vtf. Son emplacement détermine le nom du matériau ; les chemins qu’il contient sont indépendants.", ".vmt не обязан находиться рядом с файлами .vtf. Расположение самого .vmt задаёт имя материала; пути внутри него независимы." )

R( "notify.choose_source", "Choose a source texture first.", "请先选择源纹理。", "先に元テクスチャを選択してください。", "먼저 원본 텍스처를 선택하세요.", "Choisissez d’abord une texture source.", "Сначала выберите исходную текстуру." )
R( "notify.select_material", "Select a sub-material first.", "请先选择子材质。", "先にサブマテリアルを選択してください。", "먼저 하위 재질을 선택하세요.", "Sélectionnez d’abord un sous-matériau.", "Сначала выберите подматериал." )
R( "notify.nothing_save", "Nothing to save - no parameters have been changed.", "没有可保存的内容——尚未更改任何参数。", "保存する内容がありません。パラメーターは変更されていません。", "저장할 내용이 없습니다. 변경된 매개변수가 없습니다.", "Rien à enregistrer : aucun paramètre n’a été modifié.", "Нечего сохранять: параметры не изменены." )
R( "notify.override_removed", "Override removed.", "覆盖已移除。", "上書きを削除しました。", "재정의를 제거했습니다.", "Remplacement supprimé.", "Переопределение удалено." )
R( "notify.bad_parameter", "Parameter names start with $ or %.", "参数名称必须以 $ 或 % 开头。", "パラメーター名は $ または % で始まります。", "매개변수 이름은 $ 또는 %로 시작합니다.", "Les noms de paramètres commencent par $ ou %.", "Имена параметров начинаются с $ или %." )
R( "notify.disabled", "The Advanced Material Editor is disabled on this server.", "此服务器已禁用高级材质编辑器。", "このサーバーでは高機能マテリアルエディターが無効です。", "이 서버에서는 고급 재질 편집기가 비활성화되어 있습니다.", "L’Éditeur de matériaux avancé est désactivé sur ce serveur.", "Расширенный редактор материалов отключён на этом сервере." )
R( "notify.not_allowed_save", "You are not allowed to save material overrides here.", "你无权在此保存材质覆盖。", "ここにマテリアル上書きを保存する権限がありません。", "여기에 재질 재정의를 저장할 권한이 없습니다.", "Vous n’êtes pas autorisé à enregistrer des remplacements de matériaux ici.", "У вас нет разрешения сохранять здесь переопределения материалов." )
R( "notify.not_allowed_change", "You are not allowed to change material overrides here.", "你无权在此更改材质覆盖。", "ここでマテリアル上書きを変更する権限がありません。", "여기에서 재질 재정의를 변경할 권한이 없습니다.", "Vous n’êtes pas autorisé à modifier les remplacements de matériaux ici.", "У вас нет разрешения изменять здесь переопределения материалов." )
R( "notify.surface_path", "That surface does not report a material path{{detail}}.", "该表面未报告材质路径{{detail}}。", "この表面はマテリアルパスを報告しません{{detail}}。", "이 표면은 재질 경로를 제공하지 않습니다{{detail}}.", "Cette surface ne fournit pas de chemin de matériau{{detail}}.", "Эта поверхность не сообщает путь материала{{detail}}." )
R( "notify.no_copy", "That entity has no material overrides to copy.", "该实体没有可复制的材质覆盖。", "このエンティティにはコピーできるマテリアル上書きがありません。", "이 엔티티에는 복사할 재질 재정의가 없습니다.", "Cette entité ne possède aucun remplacement de matériau à copier.", "У этого объекта нет переопределений материалов для копирования." )
R( "notify.no_overrides", "That entity had no overrides.", "该实体没有覆盖。", "このエンティティには上書きがありませんでした。", "이 엔티티에는 재정의가 없습니다.", "Cette entité ne possédait aucun remplacement.", "У этого объекта не было переопределений." )
R( "notify.copied_overrides", "Copied {{count}} material override(s).", "已复制 {{count}} 个材质覆盖。", "マテリアル上書きを {{count}} 件コピーしました。", "재질 재정의 {{count}}개를 복사했습니다.", "{{count}} remplacement(s) de matériau copié(s).", "Скопировано переопределений материалов: {{count}}." )
R( "notify.pasted_overrides", "Pasted {{count}} material override(s).", "已粘贴 {{count}} 个材质覆盖。", "マテリアル上書きを {{count}} 件貼り付けました。", "재질 재정의 {{count}}개를 붙여넣었습니다.", "{{count}} remplacement(s) de matériau collé(s).", "Вставлено переопределений материалов: {{count}}." )
R( "notify.removed_overrides", "Removed {{count}} material override(s).", "已移除 {{count}} 个材质覆盖。", "マテリアル上書きを {{count}} 件削除しました。", "재질 재정의 {{count}}개를 제거했습니다.", "{{count}} remplacement(s) de matériau supprimé(s).", "Удалено переопределений материалов: {{count}}." )
R( "notify.apply_unconfirmed", "The material apply was not confirmed by the server; its preview was released.", "服务器未确认材质应用；预览已释放。", "サーバーがマテリアルの適用を確認しなかったため、プレビューを解除しました。", "서버에서 재질 적용을 확인하지 않아 미리보기를 해제했습니다.", "L’application du matériau n’a pas été confirmée par le serveur ; son aperçu a été libéré.", "Сервер не подтвердил применение материала; предпросмотр был снят." )
R( "notify.trace_missing", "The material trace module is not loaded.", "材质跟踪模块未加载。", "マテリアルトレースモジュールが読み込まれていません。", "재질 추적 모듈이 로드되지 않았습니다.", "Le module de traçage des matériaux n’est pas chargé.", "Модуль трассировки материалов не загружен." )
R( "notify.preset_bad", "That preset is unreadable.", "无法读取该预设。", "そのプリセットは読み取れません。", "해당 프리셋을 읽을 수 없습니다.", "Ce préréglage est illisible.", "Не удалось прочитать эту предустановку." )
R( "notify.area_bad", "That area is unreadable.", "无法读取该区域。", "その領域は読み取れません。", "해당 영역을 읽을 수 없습니다.", "Cette zone est illisible.", "Не удалось прочитать эту область." )
R( "notify.save_failed", "Could not save that.", "无法保存。", "保存できませんでした。", "저장할 수 없습니다.", "Impossible d’enregistrer.", "Не удалось сохранить." )
R( "notify.export_bad", "That export file is unreadable.", "无法读取该导出文件。", "そのエクスポートファイルは読み取れません。", "해당 내보내기 파일을 읽을 수 없습니다.", "Ce fichier d’export est illisible.", "Не удалось прочитать файл экспорта." )
R( "notify.export_empty", "That export contains no rules.", "该导出文件不含规则。", "そのエクスポートにはルールがありません。", "해당 내보내기에는 규칙이 없습니다.", "Cet export ne contient aucune règle.", "В экспорте нет правил." )
R( "notify.look_prop", "Look at a prop first.", "请先看向一个物件。", "先にプロップを見てください。", "먼저 프롭을 바라보세요.", "Regardez d’abord un prop.", "Сначала наведитесь на объект." )
R( "notify.admin_save", "You can preview changes, but only admins can save them on this server.", "你可以预览更改，但此服务器仅允许管理员保存。", "変更はプレビューできますが、このサーバーで保存できるのは管理者だけです。", "변경 사항을 미리 볼 수 있지만 이 서버에서는 관리자만 저장할 수 있습니다.", "Vous pouvez prévisualiser les changements, mais seuls les administrateurs peuvent les enregistrer sur ce serveur.", "Вы можете просматривать изменения, но сохранять их на этом сервере могут только администраторы." )
R( "notify.rtx_no_copy", "That entity has no RTX material profiles to copy.", "该实体没有可复制的 RTX 材质配置。", "このエンティティにはコピーできる RTX マテリアルプロファイルがありません。", "이 엔티티에는 복사할 RTX 재질 프로필이 없습니다.", "Cette entité ne possède aucun profil de matériau RTX à copier.", "У этого объекта нет профилей материалов RTX для копирования." )
R( "notify.rtx_no_profiles", "That entity had no RTX material profiles.", "该实体没有 RTX 材质配置。", "このエンティティには RTX マテリアルプロファイルがありませんでした。", "이 엔티티에는 RTX 재질 프로필이 없습니다.", "Cette entité ne possédait aucun profil de matériau RTX.", "У этого объекта не было профилей материалов RTX." )
R( "notify.rtx_copied", "Copied {{count}} RTX material profile(s).", "已复制 {{count}} 个 RTX 材质配置。", "RTX マテリアルプロファイルを {{count}} 件コピーしました。", "RTX 재질 프로필 {{count}}개를 복사했습니다.", "{{count}} profil(s) de matériau RTX copié(s).", "Скопировано профилей материалов RTX: {{count}}." )
R( "notify.rtx_pasted", "Pasted {{count}} RTX material profile(s).", "已粘贴 {{count}} 个 RTX 材质配置。", "RTX マテリアルプロファイルを {{count}} 件貼り付けました。", "RTX 재질 프로필 {{count}}개를 붙여넣었습니다.", "{{count}} profil(s) de matériau RTX collé(s).", "Вставлено профилей материалов RTX: {{count}}." )
R( "notify.rtx_removed", "Removed {{count}} RTX material profile(s).", "已移除 {{count}} 个 RTX 材质配置。", "RTX マテリアルプロファイルを {{count}} 件削除しました。", "RTX 재질 프로필 {{count}}개를 제거했습니다.", "{{count}} profil(s) de matériau RTX supprimé(s).", "Удалено профилей материалов RTX: {{count}}." )
R( "notify.rtx_save_denied", "You are not allowed to save RTX material profiles here.", "你无权在此保存 RTX 材质配置。", "ここに RTX マテリアルプロファイルを保存する権限がありません。", "여기에 RTX 재질 프로필을 저장할 권한이 없습니다.", "Vous n’êtes pas autorisé à enregistrer des profils de matériau RTX ici.", "У вас нет разрешения сохранять здесь профили материалов RTX." )
R( "notify.rtx_clear_denied", "You are not allowed to clear RTX material profiles here.", "你无权在此清除 RTX 材质配置。", "ここで RTX マテリアルプロファイルを消去する権限がありません。", "여기에서 RTX 재질 프로필을 지울 권한이 없습니다.", "Vous n’êtes pas autorisé à effacer des profils de matériau RTX ici.", "У вас нет разрешения удалять здесь профили материалов RTX." )
R( "notify.rtx_protocol", "RTX material protocol version mismatch.", "RTX 材质协议版本不匹配。", "RTX マテリアルプロトコルのバージョンが一致しません。", "RTX 재질 프로토콜 버전이 일치하지 않습니다.", "La version du protocole de matériau RTX ne correspond pas.", "Версия протокола материалов RTX не совпадает." )
R( "notify.rtx_rejected", "RTX profile rejected: {{reason}}", "RTX 配置被拒绝：{{reason}}", "RTX プロファイルが拒否されました：{{reason}}", "RTX 프로필이 거부되었습니다: {{reason}}", "Profil RTX refusé : {{reason}}", "Профиль RTX отклонён: {{reason}}" )
R( "notify.rtx_editor_fallback", "RTX Remix was detected, but its editor failed to load. Opening the vanilla editor.", "已检测到 RTX Remix，但其编辑器载入失败。正在打开原版编辑器。", "RTX Remix を検出しましたが、エディターを読み込めませんでした。標準版のエディターを開きます。", "RTX Remix가 감지되었지만 편집기를 불러오지 못했습니다. 기본 편집기를 엽니다.", "RTX Remix a été détecté, mais son éditeur n’a pas pu être chargé. Ouverture de l’éditeur d’origine.", "RTX Remix обнаружен, но его редактор не загрузился. Открывается обычный редактор." )
R( "notify.rtx_paste_requires_capture", "RTX paste was not applied because destination texture hashes must be captured client-side. Open the destination in the RTX editor and save each material there.", "未应用 RTX 粘贴，因为目标纹理哈希必须由客户端捕获。请在 RTX 编辑器中打开目标，并在其中逐一保存每个材质。", "貼り付け先のテクスチャハッシュをクライアント側でキャプチャする必要があるため、RTX の貼り付けは適用されませんでした。貼り付け先を RTX エディターで開き、各マテリアルをそこで保存してください。", "대상 텍스처 해시는 클라이언트에서 캡처해야 하므로 RTX 붙여넣기를 적용하지 않았습니다. RTX 편집기에서 대상을 열고 각 재질을 저장하세요.", "Le collage RTX n’a pas été appliqué, car les hachages des textures de destination doivent être capturés côté client. Ouvrez la destination dans l’éditeur RTX et enregistrez-y chaque matériau.", "Вставка RTX не применена: хеши текстур назначения должны быть захвачены на клиенте. Откройте объект назначения в редакторе RTX и сохраните там каждый материал." )
R( "notify.set_related", "Set {{count}} related parameter(s).", "已设置 {{count}} 个相关参数。", "関連パラメーターを {{count}} 件設定しました。", "관련 매개변수 {{count}}개를 설정했습니다.", "{{count}} paramètre(s) associé(s) défini(s).", "Установлено связанных параметров: {{count}}." )
R( "notify.saved", "Saved {{count}} override(s){{removed}}.", "已保存 {{count}} 个覆盖{{removed}}。", "上書きを {{count}} 件保存しました{{removed}}。", "재정의 {{count}}개를 저장했습니다{{removed}}.", "{{count}} remplacement(s) enregistré(s){{removed}}.", "Сохранено переопределений: {{count}}{{removed}}." )
R( "notify.removed_suffix", " and removed {{count}}", "，并移除 {{count}} 个", "、{{count}} 件削除", ", {{count}}개 제거", " et {{count}} supprimé(s)", ", удалено: {{count}}" )
R( "notify.preset_saved", "Preset saved as {{name}}", "预设已保存为 {{name}}", "プリセットを {{name}} として保存しました", "프리셋을 {{name}}(으)로 저장했습니다", "Préréglage enregistré sous {{name}}", "Предустановка сохранена как {{name}}" )
R( "notify.preset_deleted", "Deleted preset {{name}}", "已删除预设 {{name}}", "プリセット {{name}} を削除しました", "프리셋 {{name}}을(를) 삭제했습니다", "Préréglage {{name}} supprimé", "Предустановка {{name}} удалена" )
R( "notify.copied_submats", "Copied to {{count}} sub-material(s).", "已复制到 {{count}} 个子材质。", "{{count}} 個のサブマテリアルにコピーしました。", "하위 재질 {{count}}개에 복사했습니다.", "Copié vers {{count}} sous-matériau(x).", "Скопировано в подматериалы: {{count}}." )
R( "notify.kept", "Kept as {{name}}", "已保存为 {{name}}", "{{name}} として保存しました", "{{name}}(으)로 저장했습니다", "Enregistré sous {{name}}", "Сохранено как {{name}}" )
R( "notify.forgot", "Forgot {{name}}", "已删除 {{name}}", "{{name}} を削除しました", "{{name}}을(를) 삭제했습니다", "{{name}} oublié", "Удалено: {{name}}" )
R( "notify.imported", "Imported {{count}} rule(s).", "已导入 {{count}} 条规则。", "ルールを {{count}} 件インポートしました。", "규칙 {{count}}개를 가져왔습니다.", "{{count}} règle(s) importée(s).", "Импортировано правил: {{count}}." )
R( "notify.importing", "Importing {{count}} rule(s)...", "正在导入 {{count}} 条规则…", "ルールを {{count}} 件インポート中…", "규칙 {{count}}개 가져오는 중…", "Importation de {{count}} règle(s)…", "Импорт правил ({{count}})…" )
R( "notify.applied", "Applied to {{name}}", "已应用到 {{name}}", "{{name}} に適用しました", "{{name}}에 적용했습니다", "Appliqué à {{name}}", "Применено к {{name}}" )
R( "notify.clipboard_missing", "This build has no clipboard access; use Write the files instead.", "此版本无法访问剪贴板；请改用“写出文件”。", "このビルドではクリップボードを使えません。代わりに「ファイルを書き出す」を使用してください。", "이 빌드는 클립보드에 접근할 수 없습니다. 대신 ‘파일 쓰기’를 사용하세요.", "Cette version n’a pas accès au presse-papiers ; utilisez plutôt Écrire les fichiers.", "В этой сборке нет доступа к буферу обмена; используйте «Записать файлы»." )
R( "notify.images_pending", "{{count}} image(s) had not been generated yet. Wait a moment and press Write the files again.", "尚有 {{count}} 张图像未生成。请稍候片刻，然后再次按“写出文件”。", "まだ {{count}} 個の画像が生成されていません。少し待ってから、もう一度「ファイルを書き出す」を押してください。", "이미지 {{count}}개가 아직 생성되지 않았습니다. 잠시 기다린 뒤 ‘파일 쓰기’를 다시 누르세요.", "{{count}} image(s) n’avaient pas encore été générée(s). Patientez un instant, puis cliquez de nouveau sur Écrire les fichiers.", "Изображения ({{count}} шт.) ещё не созданы. Подождите немного и снова нажмите «Записать файлы»." )
R( "notify.put_export", "Put a file at garrysmod/data/{{path}} first.", "请先将文件放到 garrysmod/data/{{path}}。", "先にファイルを garrysmod/data/{{path}} に置いてください。", "먼저 garrysmod/data/{{path}}에 파일을 넣으세요.", "Placez d’abord un fichier dans garrysmod/data/{{path}}.", "Сначала поместите файл в garrysmod/data/{{path}}." )
R( "notify.cannot_preview", "Cannot be saved, so not being previewed either: {{items}}", "无法保存，因此也不会预览：{{items}}", "保存できないため、プレビューにも反映されません：{{items}}", "저장할 수 없어 미리보기에도 적용되지 않습니다: {{items}}", "Impossible à enregistrer, donc également exclu de l’aperçu : {{items}}", "Нельзя сохранить, поэтому и в предпросмотре не показывается: {{items}}" )
R( "notify.shadowed", "An existing \"{{scope}}\" override still takes priority over what you just saved. Reset to Default clears every scope for the selected slot.", "现有的“{{scope}}”覆盖优先级仍高于刚保存的内容。“恢复默认值”会清除所选槽位的所有范围。", "既存の「{{scope}}」上書きが、今保存した内容より優先されています。「既定値に戻す」で選択スロットの全範囲を消去できます。", "기존 ‘{{scope}}’ 재정의가 방금 저장한 내용보다 우선합니다. ‘기본값으로 초기화’는 선택한 슬롯의 모든 범위를 지웁니다.", "Un remplacement « {{scope}} » existant reste prioritaire sur ce que vous venez d’enregistrer. Rétablir les valeurs par défaut efface toutes les portées de l’emplacement sélectionné.", "Существующее переопределение «{{scope}}» по-прежнему важнее только что сохранённого. «Восстановить значения по умолчанию» очищает все области выбранного слота." )
R( "notify.build_failed", "Could not build {{kind}}: {{reason}}", "无法生成{{kind}}：{{reason}}", "{{kind}} を作成できませんでした：{{reason}}", "{{kind}}을(를) 만들 수 없습니다: {{reason}}", "Impossible de créer {{kind}} : {{reason}}", "Не удалось создать {{kind}}: {{reason}}" )
R( "notify.asset_preparing", "Preparing {{count}} override(s); edited textures are being verified or uploaded first.", "正在准备 {{count}} 个覆盖；将先验证或上传已编辑的纹理。", "上書き {{count}} 件を準備しています。編集済みテクスチャを先に検証またはアップロードしています。", "재정의 {{count}}개를 준비 중입니다. 편집한 텍스처를 먼저 확인하거나 업로드하고 있습니다.", "Préparation de {{count}} remplacement(s) ; les textures modifiées sont d’abord vérifiées ou téléversées.", "Подготовка переопределений: {{count}}; сначала проверяются или загружаются изменённые текстуры." )
R( "notify.asset_prepare_failed", "Could not prepare the edited texture for multiplayer: {{reason}}", "无法为多人游戏准备已编辑的纹理：{{reason}}", "マルチプレイ用の編集済みテクスチャを準備できませんでした：{{reason}}", "멀티플레이용 편집 텍스처를 준비할 수 없습니다: {{reason}}", "Impossible de préparer la texture modifiée pour le multijoueur : {{reason}}", "Не удалось подготовить отредактированную текстуру для сетевой игры: {{reason}}" )
R( "notify.manual_save", "Applied. This server keeps material overrides in memory until an admin saves them (advmat_autosave is off).", "已应用。此服务器在管理员保存之前只将材质覆盖保留在内存中（advmat_autosave 已关闭）。", "適用しました。このサーバーは管理者が保存するまでマテリアルの上書きをメモリ上にのみ保持します（advmat_autosave はオフ）。", "적용했습니다. 이 서버는 관리자가 저장할 때까지 재질 재정의를 메모리에만 보관합니다(advmat_autosave 꺼짐).", "Appliqué. Ce serveur garde les remplacements de matériau en mémoire jusqu’à ce qu’un administrateur les enregistre (advmat_autosave est désactivé).", "Применено. Этот сервер хранит переопределения материалов только в памяти, пока администратор их не сохранит (advmat_autosave выключен)." )
R( "notify.sync_failed", "Could not load the server's material overrides: {{reason}}. Trying again.", "无法加载服务器的材质覆盖：{{reason}}。正在重试。", "サーバーのマテリアル上書きを読み込めませんでした：{{reason}}。再試行しています。", "서버의 재질 재정의를 불러올 수 없습니다: {{reason}}. 다시 시도하는 중입니다.", "Impossible de charger les remplacements de matériau du serveur : {{reason}}. Nouvelle tentative.", "Не удалось загрузить переопределения материалов с сервера: {{reason}}. Повторная попытка." )
R( "notify.persist_failed", "Your material change is live, but the server could not save it to disk: {{reason}}. It will keep trying.", "你的材质更改已生效，但服务器无法将其保存到磁盘：{{reason}}。服务器将继续重试。", "マテリアルの変更は反映されましたが、サーバーがディスクに保存できませんでした：{{reason}}。再試行を続けます。", "재질 변경은 적용되었지만 서버가 디스크에 저장하지 못했습니다: {{reason}}. 계속 다시 시도합니다.", "Votre modification de matériau est appliquée, mais le serveur n’a pas pu l’enregistrer sur le disque : {{reason}}. Il continue d’essayer.", "Изменение материала применено, но сервер не смог сохранить его на диск: {{reason}}. Попытки продолжатся." )
R( "notify.dupe_skipped", "{{count}} material override(s) in that dupe were not applied: {{reason}}", "该复制品中有 {{count}} 个材质覆盖未被应用：{{reason}}", "そのデュープ内の {{count}} 件のマテリアル上書きは適用されませんでした：{{reason}}", "해당 복제물의 재질 재정의 {{count}}개가 적용되지 않았습니다: {{reason}}", "{{count}} remplacement(s) de matériau de cette copie n’ont pas été appliqués : {{reason}}", "Не применено переопределений материала из этой копии: {{count}}. Причина: {{reason}}" )
R( "notify.rule_rejected", "Material override rejected: {{reason}}", "材质覆盖被拒绝：{{reason}}", "マテリアルの上書きが拒否されました：{{reason}}", "재질 재정의가 거부되었습니다: {{reason}}", "Remplacement de matériau refusé : {{reason}}", "Переопределение материала отклонено: {{reason}}" )
R( "notify.save_conflict", "Slot {{slot}} was not saved: somebody else changed it after you opened the editor. Save again to replace their change, or Undo to load it.", "槽位 {{slot}} 未保存：在你打开编辑器后，其他人修改了它。再次保存将覆盖对方的更改，或撤销以加载对方的版本。", "スロット {{slot}} は保存されませんでした：エディターを開いた後に他の人が変更しました。もう一度保存すると相手の変更を置き換え、元に戻すと相手の版を読み込みます。", "슬롯 {{slot}}이(가) 저장되지 않았습니다: 편집기를 연 뒤 다른 사람이 변경했습니다. 다시 저장하면 상대의 변경을 덮어쓰고, 실행 취소하면 상대의 버전을 불러옵니다.", "L’emplacement {{slot}} n’a pas été enregistré : quelqu’un d’autre l’a modifié après l’ouverture de l’éditeur. Enregistrez à nouveau pour remplacer sa modification, ou annulez pour la charger.", "Слот {{slot}} не сохранён: кто-то другой изменил его после открытия редактора. Сохраните ещё раз, чтобы заменить его изменение, или отмените, чтобы загрузить его." )
R( "notify.trace_started", "Advanced Material Editor trace recording started.", "高级材质编辑器已开始记录跟踪。", "高機能マテリアルエディターのトレース記録を開始しました。", "고급 재질 편집기 추적 기록을 시작했습니다.", "L’enregistrement de la trace de l’Éditeur de matériaux avancé a commencé.", "Начата запись трассировки Расширенного редактора материалов." )
R( "notify.trace_written", "Trace written to data/{{path}}", "跟踪已写入 data/{{path}}", "トレースを data/{{path}} に書き込みました", "추적을 data/{{path}}에 기록했습니다", "Trace écrite dans data/{{path}}", "Трассировка записана в data/{{path}}" )
R( "notify.trace_failed", "Could not write the material trace.", "无法写入材质跟踪。", "マテリアルトレースを書き込めませんでした。", "재질 추적을 기록할 수 없습니다.", "Impossible d’écrire la trace du matériau.", "Не удалось записать трассировку материала." )
R( "error.read", "could not read {{path}}", "无法读取 {{path}}", "{{path}} を読み取れませんでした", "{{path}}을(를) 읽을 수 없습니다", "impossible de lire {{path}}", "не удалось прочитать {{path}}" )
R( "error.write", "could not write {{path}}", "无法写入 {{path}}", "{{path}} に書き込めませんでした", "{{path}}에 기록할 수 없습니다", "impossible d’écrire {{path}}", "не удалось записать {{path}}" )
R( "error.builder", "no builder for {{kind}}", "没有 {{kind}} 的生成器", "{{kind}} のビルダーがありません", "{{kind}}용 빌더가 없습니다", "aucun générateur pour {{kind}}", "нет обработчика для {{kind}}" )
R( "error.capture_unavailable", "engine PNG capture is unavailable", "引擎 PNG 捕获不可用", "エンジンの PNG キャプチャを使用できません", "엔진 PNG 캡처를 사용할 수 없습니다", "la capture PNG du moteur est indisponible", "захват PNG средствами движка недоступен" )
R( "error.allocate_edit", "could not allocate the edit render target", "无法分配编辑渲染目标", "編集用レンダーターゲットを確保できませんでした", "편집 렌더 타깃을 할당할 수 없습니다", "impossible d’allouer la cible de rendu d’édition", "не удалось выделить цель рендера для редактирования" )
R( "error.edit_target_size", "edit render target is {{actualw}}x{{actualh}} instead of {{expectedw}}x{{expectedh}}", "编辑渲染目标为 {{actualw}}x{{actualh}}，而非 {{expectedw}}x{{expectedh}}", "編集用レンダーターゲットは {{expectedw}}x{{expectedh}} ではなく {{actualw}}x{{actualh}} です", "편집 렌더 타깃이 {{expectedw}}x{{expectedh}}가 아니라 {{actualw}}x{{actualh}}입니다", "la cible de rendu d’édition mesure {{actualw}}x{{actualh}} au lieu de {{expectedw}}x{{expectedh}}", "размер цели рендера для редактирования — {{actualw}}x{{actualh}}, а не {{expectedw}}x{{expectedh}}" )
R( "error.edit_full_resolution", "this renderer cannot save {{width}}x{{height}} texture edits at full resolution", "此渲染器无法以完整分辨率保存 {{width}}x{{height}} 的纹理编辑", "このレンダラーでは {{width}}x{{height}} のテクスチャ編集をフル解像度で保存できません", "이 렌더러에서는 {{width}}x{{height}} 텍스처 편집을 전체 해상도로 저장할 수 없습니다", "ce moteur de rendu ne peut pas enregistrer les modifications de texture en {{width}}x{{height}} à leur pleine résolution", "этот рендерер не может сохранить правки текстуры {{width}}x{{height}} в полном разрешении" )
R( "error.capture_empty", "engine PNG capture returned no image", "引擎 PNG 捕获未返回图像", "エンジンの PNG キャプチャから画像が返されませんでした", "엔진 PNG 캡처가 이미지를 반환하지 않았습니다", "la capture PNG du moteur n’a renvoyé aucune image", "захват PNG средствами движка не вернул изображение" )
R( "error.no_steps", "the edit has no steps", "编辑中没有步骤", "編集に手順がありません", "편집에 단계가 없습니다", "la modification ne contient aucune étape", "в редактировании нет шагов" )
R( "error.incomplete", "the settings are incomplete", "设置不完整", "設定が不完全です", "설정이 완전하지 않습니다", "les réglages sont incomplets", "настройки неполны" )

R( "group.base", "Base texture", "基础纹理", "ベーステクスチャ", "기본 텍스처", "Texture de base", "Основная текстура" )
R( "group.colour", "Colour and tint", "颜色和色调", "色と色合い", "색상 및 색조", "Couleur et teinte", "Цвет и оттенок" )
R( "group.transparency", "Transparency", "透明度", "透明度", "투명도", "Transparence", "Прозрачность" )
R( "group.bump", "Bump / normal map", "凹凸 / 法线贴图", "バンプ / 法線マップ", "범프 / 노멀 맵", "Relief / normal map", "Рельеф / карта нормалей" )
R( "group.phong", "Phong (specular highlight)", "Phong（镜面高光）", "Phong（鏡面ハイライト）", "Phong(정반사 하이라이트)", "Phong (reflet spéculaire)", "Phong (зеркальный блик)" )
R( "group.rim", "Rim light", "边缘光", "リムライト", "림 라이트", "Éclairage de contour", "Контурный свет" )
R( "group.reflections", "Reflections (cube map)", "反射（立方体贴图）", "反射（キューブマップ）", "반사(큐브 맵)", "Réflexions (cube map)", "Отражения (кубическая карта)" )
R( "group.selfillum", "Self illumination", "自发光", "自己発光", "자체 발광", "Auto-illumination", "Самосвечение" )
R( "group.detail", "Detail texture", "细节纹理", "ディテールテクスチャ", "디테일 텍스처", "Texture de détail", "Детальная текстура" )
R( "group.lighting", "Lighting", "光照", "ライティング", "조명", "Éclairage", "Освещение" )
R( "group.transform", "Texture transform", "纹理变换", "テクスチャ変換", "텍스처 변환", "Transformation de texture", "Преобразование текстуры" )
R( "group.emissive", "Emissive blend (scrolling glow)", "自发光混合（滚动辉光）", "発光ブレンド（流れる光）", "발광 블렌드(흐르는 빛)", "Mélange émissif (lueur défilante)", "Эмиссионное смешивание (движущееся свечение)" )
R( "group.distance_alpha", "Distance alpha (sharp edges)", "距离透明度（锐利边缘）", "距離アルファ（鋭いエッジ）", "거리 알파(선명한 가장자리)", "Alpha selon la distance (bords nets)", "Альфа по расстоянию (резкие края)" )
R( "group.sway", "Tree sway", "树木摇摆", "木の揺れ", "나무 흔들림", "Balancement d’arbre", "Раскачивание дерева" )
R( "group.eye", "Eye", "眼睛", "目", "눈", "Œil", "Глаз" )
R( "group.wrinkle", "Wrinkle maps (flex driven)", "皱纹贴图（由表情驱动）", "しわマップ（フレックス連動）", "주름 맵(플렉스 구동)", "Maps de rides (pilotées par les flex)", "Карты морщин (управляются флексами)" )
R( "group.sheen", "Sheen (killstreak pass)", "光泽（连杀特效层）", "光沢（キルストリークパス）", "광택(킬스트릭 패스)", "Brillance (passe killstreak)", "Блеск (проход killstreak)" )
R( "group.cloak", "Cloak (refraction pass)", "隐形（折射层）", "クローク（屈折パス）", "은폐(굴절 패스)", "Camouflage (passe de réfraction)", "Маскировка (проход преломления)" )
R( "group.flesh", "Flesh interior", "内部血肉", "肉体内部", "신체 내부", "Intérieur organique", "Внутренняя плоть" )
R( "group.refraction", "Refraction", "折射", "屈折", "굴절", "Réfraction", "Преломление" )
R( "group.water", "Water", "水体", "水", "물", "Eau", "Вода" )
R( "group.blending", "Texture blending", "纹理混合", "テクスチャブレンド", "텍스처 블렌딩", "Mélange de textures", "Смешивание текстур" )
R( "group.flags", "Render flags", "渲染标志", "描画フラグ", "렌더링 플래그", "Indicateurs de rendu", "Флаги отрисовки" )
R( "group.compile", "Compile-time flags", "编译时标志", "コンパイル時フラグ", "컴파일 시 플래그", "Indicateurs de compilation", "Флаги времени компиляции" )
R( "group.misc", "Misc", "其他", "その他", "기타", "Divers", "Прочее" )
R( "group.other", "Other parameters on this material", "此材质的其他参数", "このマテリアルのその他のパラメーター", "이 재질의 기타 매개변수", "Autres paramètres de ce matériau", "Другие параметры этого материала" )

-- Help chrome is fully localised.  Parameter names, VMT literals and shader
-- names are technical identifiers and intentionally remain unchanged.
R( "help.none", "No description available for this parameter.", "此参数暂无说明。", "このパラメーターの説明はありません。", "이 매개변수에 대한 설명이 없습니다.", "Aucune description disponible pour ce paramètre.", "Описание этого параметра отсутствует." )
R( "help.generic", "Technical VMT parameter {{name}} in the {{group}} group. Its exact effect depends on the active shader and game build.", "{{group}}组中的技术性 VMT 参数 {{name}}。其具体效果取决于当前着色器和游戏版本。", "{{group}} グループの技術的な VMT パラメーター {{name}} です。正確な効果は使用中のシェーダーとゲームのビルドに依存します。", "{{group}} 그룹의 기술 VMT 매개변수 {{name}}입니다. 정확한 효과는 현재 셰이더와 게임 빌드에 따라 달라집니다.", "Paramètre VMT technique {{name}} du groupe {{group}}. Son effet exact dépend du shader actif et de la version du jeu.", "Технический параметр VMT {{name}} из группы «{{group}}». Точный эффект зависит от активного шейдера и сборки игры." )
R( "help.bool", "On or off", "开或关", "オン / オフ", "켜기 / 끄기", "Activé ou désactivé", "Вкл. или выкл." )
R( "help.int", "Whole number", "整数", "整数", "정수", "Nombre entier", "Целое число" )
R( "help.float", "Number", "数值", "数値", "숫자", "Nombre", "Число" )
R( "help.color", "Colour", "颜色", "色", "색상", "Couleur", "Цвет" )
R( "help.vector2", "Two numbers", "两个数值", "2つの数値", "숫자 두 개", "Deux nombres", "Два числа" )
R( "help.vector3", "Three numbers", "三个数值", "3つの数値", "숫자 세 개", "Trois nombres", "Три числа" )
R( "help.vector4", "Four numbers", "四个数值", "4つの数値", "숫자 네 개", "Quatre nombres", "Четыре числа" )
R( "help.texture", "Texture path", "纹理路径", "テクスチャパス", "텍스처 경로", "Chemin de texture", "Путь текстуры" )
R( "help.text", "Text", "文本", "テキスト", "텍스트", "Texte", "Текст" )
R( "help.transform", "Texture transform", "纹理变换", "テクスチャ変換", "텍스처 변환", "Transformation de texture", "Преобразование текстуры" )
R( "help.value", "Value", "值", "値", "값", "Valeur", "Значение" )
R( "help.default", "default {{value}}", "默认 {{value}}", "既定値 {{value}}", "기본값 {{value}}", "valeur par défaut {{value}}", "по умолчанию {{value}}" )
R( "help.range", "usual range {{min}} to {{max}}", "常用范围 {{min}} 到 {{max}}", "通常範囲 {{min}} ～ {{max}}", "일반 범위 {{min}}~{{max}}", "plage habituelle de {{min}} à {{max}}", "обычный диапазон от {{min}} до {{max}}" )
R( "help.needs", "needs {{value}}", "需要 {{value}}", "{{value}} が必要", "{{value}} 필요", "nécessite {{value}}", "требуется {{value}}" )
R( "help.rebuild", "rebuilds the material when changed", "更改时会重建材质", "変更時にマテリアルを再構築", "변경 시 재질을 다시 빌드함", "reconstruit le matériau en cas de modification", "при изменении перестраивает материал" )
R( "help.unavailable", "This parameter is unavailable with the current renderer settings or game build.", "当前渲染器设置或游戏版本不支持此参数。", "現在のレンダラー設定またはゲームのビルドでは、このパラメーターは使用できません。", "현재 렌더러 설정 또는 게임 빌드에서는 이 매개변수를 사용할 수 없습니다.", "Ce paramètre est indisponible avec les réglages de rendu ou la version du jeu actuels.", "Этот параметр недоступен при текущих настройках рендера или в данной сборке игры." )
R( "help.remix_detail", "RTX Remix removes detail textures from materials, so this will not appear in game.", "RTX Remix 会移除材质中的细节纹理，因此此效果不会在游戏中显示。", "RTX Remix はマテリアルからディテールテクスチャを除去するため、ゲーム内には表示されません。", "RTX Remix는 재질에서 디테일 텍스처를 제거하므로 게임에 표시되지 않습니다.", "RTX Remix retire les textures de détail des matériaux ; cet effet n’apparaîtra donc pas en jeu.", "RTX Remix удаляет детальные текстуры из материалов, поэтому эффект не появится в игре." )
R( "help.inert", "Unavailable on this build - press ? for details", "此版本不可用——按 ? 查看详情", "このビルドでは使用不可 — ? で詳細を表示", "이 빌드에서 사용할 수 없음 - ?를 눌러 자세히 보기", "Indisponible dans cette version — appuyez sur ? pour les détails", "Недоступно в этой сборке — нажмите ? для подробностей" )

function I.DetectLanguage()
	local value = string.lower( ConVarString( "gmod_language", DEFAULT ) )
	value = string.gsub( value, "[%s%-]+", "_" )
	local function begins( prefix ) return string.sub( value, 1, #prefix ) == prefix end
	local function contains( part ) return string.find( value, part, 1, true ) ~= nil end
	if begins( "zh" ) or value == "schinese" or value == "tchinese"
	or value == "chs" or value == "cht" or contains( "chinese" )
	or contains( "hans" ) or contains( "hant" ) then return "zh" end
	if begins( "ja" ) or begins( "jp" ) or contains( "japanese" ) then return "ja" end
	if begins( "ko" ) or begins( "kr" ) or value == "koreana"
	or contains( "korean" ) then return "ko" end
	if begins( "fr" ) or contains( "french" ) or contains( "francais" ) then return "fr" end
	if begins( "ru" ) or contains( "russian" ) then return "ru" end
	return DEFAULT
end

function I.Reload()
	local selected = string.lower( ConVarString( "advmat_language", "auto" ) )
	if selected == "" or selected == "auto" then selected = I.DetectLanguage() end
	I.language = SUPPORTED[ selected ] and selected or DEFAULT
end

function I.GetLanguageOptions()
	return { "auto", "en", "zh", "ja", "ko", "fr", "ru" }
end

local function Interpolate( output, variables )
	if not variables then return output end
	local replaced = string.gsub( output, "{{%s*([%w_]+)%s*}}", function( name )
		local value = variables[ name ]
		return value == nil and "{{" .. name .. "}}" or tostring( value )
	end )
	return replaced
end

function AdvMat.L( key, variables )
	local selected = I.locales[ I.language or DEFAULT ] or I.locales[ DEFAULT ]
	return Interpolate( selected[ key ] or I.locales[ DEFAULT ][ key ] or tostring( key ), variables )
end

function AdvMat.LText( source, variables )
	if not isstring( source ) or source == "" then return source end
	local key = I.reverse[ source ]
	if key then return AdvMat.L( key, variables ) end

	-- The texture editor appends shortcut hints to translated tool names and
	-- combines the name and explanation into one tooltip. Translate those exact
	-- source components independently while leaving the shortcut itself intact.
	local toolName, shortcut, toolTip = string.match( source,
		"^(.-)%s%s%((.-)%)\n(.*)$" )
	if toolName and I.reverse[ toolName ] and I.reverse[ toolTip ] then
		return AdvMat.LText( toolName ) .. "  (" .. shortcut .. ")\n" ..
			AdvMat.LText( toolTip )
	end
	local shortcutName, shortcutKey = string.match( source, "^(.-)\t(.+)$" )
	if shortcutName and I.reverse[ shortcutName ] then
		return AdvMat.LText( shortcutName ) .. "\t" .. shortcutKey
	end

	-- Foreground/background names are live values. ColourName has already
	-- localised each colour, so only the two labels need interpolation here.
	local foreground, background = string.match( source, "^FG: (.-)\nBG: (.-)$" )
	if foreground then
		return AdvMat.L( "texture.foreground_short", {
			colour = AdvMat.LText( foreground ),
		} ) .. "\n" .. AdvMat.L( "texture.background_short", {
			colour = AdvMat.LText( background ),
		} )
	end

	-- Category headers append a live row count to a translated group name.
	local prefix, count = string.match( source, "^(.-)%s%s%((%d+)%)$" )
	local prefixKey = prefix and I.reverse[ prefix ]
	if prefixKey then return AdvMat.L( prefixKey ) .. "  (" .. count .. ")" end

	for _, dynamicKey in ipairs( {
		"editor.prefix_surface", "texture.prefix_title", "texture.prefix_up_to",
		"texture.prefix_remove", "export.prefix_title", "export.prefix_written",
	} ) do
		local english = I.locales[ DEFAULT ][ dynamicKey ]
		if string.sub( source, 1, #english ) == english then
			return AdvMat.L( dynamicKey ) .. string.sub( source, #english + 1 )
		end
	end

	local n = string.match( source, "^Copied (%d+) material override%(s%)%.$" )
	if n then return AdvMat.L( "notify.copied_overrides", { count = n } ) end
	n = string.match( source, "^Pasted (%d+) material override%(s%)%.$" )
	if n then return AdvMat.L( "notify.pasted_overrides", { count = n } ) end
	n = string.match( source, "^Removed (%d+) material override%(s%)%.$" )
	if n then return AdvMat.L( "notify.removed_overrides", { count = n } ) end
	n = string.match( source, "^Copied (%d+) RTX material profile%(s%)%.$" )
	if n then return AdvMat.L( "notify.rtx_copied", { count = n } ) end
	n = string.match( source, "^Pasted (%d+) RTX material profile%(s%)%.$" )
	if n then return AdvMat.L( "notify.rtx_pasted", { count = n } ) end
	n = string.match( source, "^Removed (%d+) RTX material profile%(s%)%.$" )
	if n then return AdvMat.L( "notify.rtx_removed", { count = n } ) end
	local rejectReason = string.match( source, "^RTX profile rejected: (.+)$" )
	if rejectReason then return AdvMat.L( "notify.rtx_rejected", { reason = rejectReason } ) end
	local ruleReason = string.match( source, "^Material override rejected: (.+)$" )
	if ruleReason then return AdvMat.L( "notify.rule_rejected", { reason = ruleReason } ) end
	local diskReason = string.match( source,
		"^Your material change is live, but the server could not save it to disk: (.+)%. It will keep trying%.$" )
	if diskReason then return AdvMat.L( "notify.persist_failed", { reason = diskReason } ) end
	local dupeCount, dupeReason = string.match( source,
		"^(%d+) material override%(s%) in that dupe were not applied: (.+)$" )
	if dupeCount then
		return AdvMat.L( "notify.dupe_skipped", { count = dupeCount, reason = dupeReason } )
	end
	local detail = string.match( source, "^That surface does not report a material path(.*)%.$" )
	if detail then return AdvMat.L( "notify.surface_path", { detail = detail } ) end
	n = string.match( source, "^Set (%d+) related parameter%(s%)%.$" )
	if n then return AdvMat.L( "notify.set_related", { count = n } ) end
	local saved, removed = string.match( source, "^Saved (%d+) override%(s%), removed (%d+)%.$" )
	if saved then
		return AdvMat.L( "notify.saved", { count = saved,
			removed = AdvMat.L( "notify.removed_suffix", { count = removed } ) } )
	end
	saved = string.match( source, "^Saved (%d+) override%(s%)%.$" )
	if saved then return AdvMat.L( "notify.saved", { count = saved, removed = "" } ) end
	local name = string.match( source, "^Preset saved as (.+)$" )
	if name then return AdvMat.L( "notify.preset_saved", { name = name } ) end
	name = string.match( source, "^Deleted preset (.+)$" )
	if name then return AdvMat.L( "notify.preset_deleted", { name = name } ) end
	n = string.match( source, "^Copied to (%d+) sub%-material%(s%)%.$" )
	if n then return AdvMat.L( "notify.copied_submats", { count = n } ) end
	name = string.match( source, "^Kept as (.+)$" )
	if name then return AdvMat.L( "notify.kept", { name = name } ) end
	name = string.match( source, "^Forgot (.+)$" )
	if name then return AdvMat.L( "notify.forgot", { name = name } ) end
	n = string.match( source, "^Imported (%d+) rule%(s%)%.$" )
	if n then return AdvMat.L( "notify.imported", { count = n } ) end
	n = string.match( source, "^Importing (%d+) rule%(s%)%.%.%.$" )
	if n then return AdvMat.L( "notify.importing", { count = n } ) end
	name = string.match( source, "^Applied to (.+)$" )
	if name then return AdvMat.L( "notify.applied", { name = name } ) end
	local selected = string.match( source, "^You have ([%d%.]+)%% of the picture selected%.$" )
	if selected then return AdvMat.L( "texture.percent_selected", { value = selected } ) end
	local base = string.match( source,
		"^(.-)%s%sSome parts are hidden %- those cannot be clicked until you show them again%.$" )
	if base then return AdvMat.L( "model.hidden_suffix", { base = AdvMat.LText( base ) } ) end
	local model, subCount, modelTail = string.match( source,
		"^(.-)%s%s%s%s%((%d+) sub%-material(.-)%)$" )
	if model then return AdvMat.L( "editor.model_count", {
		model = model, count = subCount,
		trimmed = string.find( modelTail or "", "32 slot", 1, true )
			and AdvMat.L( "editor.model_trimmed" ) or "",
	} ) end
	n = string.match( source, "^(%d+) persistent rule%(s%) on the server%.$" )
	if n then return AdvMat.L( "browser.status", { count = n } ) end
	n = string.match( source, "^This needs (%d+) image file%(s%)$" )
	if n then return AdvMat.L( "export.needs_images", { count = n } ) end
	local path = string.match( source, "^could not read (.+)$" )
	if path then return AdvMat.L( "error.read", { path = path } ) end
	path = string.match( source, "^could not write (.+)$" )
	if path then return AdvMat.L( "error.write", { path = path } ) end
	local kind = string.match( source, "^no builder for (.+)$" )
	if kind then return AdvMat.L( "error.builder", { kind = kind } ) end
	local actualw, actualh, expectedw, expectedh = string.match( source,
		"^edit render target is ([%-]?%d+)x([%-]?%d+) instead of ([%-]?%d+)x([%-]?%d+)$" )
	if actualw then return AdvMat.L( "error.edit_target_size", {
		actualw = actualw, actualh = actualh,
		expectedw = expectedw, expectedh = expectedh,
	} ) end
	local width, height = string.match( source,
		"^this renderer cannot save (%d+)x(%d+) texture edits at full resolution$" )
	if width then return AdvMat.L( "error.edit_full_resolution", {
		width = width, height = height,
	} ) end

	return Interpolate( source, variables )
end

function AdvMat.NotifyLocal( message, kind, duration )
	notification.AddLegacy( AdvMat.LText( message ), kind, duration )
end

function I.HasKey( key ) return I.locales[ DEFAULT ][ key ] ~= nil end

function I.ApplyToolPhrases()
	if not language or not language.Add then return end
	language.Add( "tool.advmateditor.name", AdvMat.L( "tool.name" ) )
	language.Add( "tool.advmateditor.desc", AdvMat.L( "tool.desc" ) )
	language.Add( "tool.advmateditor.left", AdvMat.L( "tool.left" ) )
	language.Add( "tool.advmateditor.left_world", AdvMat.L( "tool.left_world" ) )
	language.Add( "tool.advmateditor.right", AdvMat.L( "tool.right" ) )
	language.Add( "tool.advmateditor.right_paste", AdvMat.L( "tool.right_paste" ) )
	language.Add( "tool.advmateditor.reload", AdvMat.L( "tool.reload" ) )
	language.Add( "tool.advmateditor.reload_strip", AdvMat.L( "tool.reload_strip" ) )
end

-- Weak roots keep localisation out of unrelated addons and do not extend a
-- closed window's lifetime.  Dynamic labels are re-read only when their text
-- changes, so switching language while a window is open remains safe.
I.roots = I.roots or setmetatable( {}, { __mode = "k" } )

local function ClassName( panel )
	return panel.GetClassName and panel:GetClassName() or ""
end

function I.LocalizePanel( panel )
	if not IsValid( panel ) then return end
	local class = ClassName( panel )
	local textPanel = class ~= "DTextEntry" and class ~= "DNumberWang"

	if textPanel and panel.GetText and panel.SetText then
		local current = panel:GetText()
		if panel.AdvMatI18NLastText == nil or current ~= panel.AdvMatI18NLastText then
			panel.AdvMatI18NSourceText = current
		end
		local translated = AdvMat.LText( panel.AdvMatI18NSourceText )
		if current ~= translated then panel:SetText( translated ) end
		panel.AdvMatI18NLastText = translated
		if panel.AdvMatI18NAutoWidth and panel.SetWide and surface
		and surface.SetFont and surface.GetTextSize and AdvMat.RowHeight then
			surface.SetFont( "AdvMatText" )
			local textWidth = surface.GetTextSize( translated )
			panel:SetWide( AdvMat.RowHeight() + textWidth + 20 )
		end
	end

	if panel.GetTooltip and panel.SetTooltip then
		local current = panel:GetTooltip()
		if panel.AdvMatI18NTipParts then
			local parts = {}
			for n, part in ipairs( panel.AdvMatI18NTipParts ) do parts[ n ] = AdvMat.LText( part ) end
			local translated = table.concat( parts, panel.AdvMatI18NTipSeparator or "\n" )
			if current ~= translated then panel:SetTooltip( translated ) end
			panel.AdvMatI18NLastTip = translated
		elseif isstring( current ) and current ~= "" then
			if panel.AdvMatI18NLastTip == nil or current ~= panel.AdvMatI18NLastTip then
				panel.AdvMatI18NSourceTip = current
			end
			local translated = AdvMat.LText( panel.AdvMatI18NSourceTip )
			if current ~= translated then panel:SetTooltip( translated ) end
			panel.AdvMatI18NLastTip = translated
		end
	end

	if panel.GetPlaceholderText and panel.SetPlaceholderText then
		local current = panel:GetPlaceholderText()
		if isstring( current ) and current ~= "" then
			if panel.AdvMatI18NLastHint == nil or current ~= panel.AdvMatI18NLastHint then
				panel.AdvMatI18NSourceHint = current
			end
			local translated = AdvMat.LText( panel.AdvMatI18NSourceHint )
			if current ~= translated then panel:SetPlaceholderText( translated ) end
			panel.AdvMatI18NLastHint = translated
		end
	end

	if class == "DComboBox" and istable( panel.Choices ) then
		panel.AdvMatI18NChoices = panel.AdvMatI18NChoices or {}
		for n, choice in ipairs( panel.Choices ) do
			local source = panel.AdvMatI18NChoices[ n ] or choice
			panel.AdvMatI18NChoices[ n ] = source
			panel.Choices[ n ] = AdvMat.LText( source )
		end
	end

	for _, child in ipairs( panel.GetChildren and panel:GetChildren() or {} ) do
		I.LocalizePanel( child )
	end
end

function I.Track( panel )
	if not IsValid( panel ) then return panel end
	I.roots[ panel ] = true
	I.LocalizePanel( panel )
	return panel
end

function I.ApplyOpenWindows()
	for panel in pairs( I.roots ) do
		if IsValid( panel ) then I.LocalizePanel( panel ) else I.roots[ panel ] = nil end
	end
end

I.Reload()
I.ApplyToolPhrases()

local nextApply = 0
hook.Add( "Think", "AdvMat.LocalizeOpenWindows", function()
	if RealTime() < nextApply then return end
	nextApply = RealTime() + 0.15
	I.ApplyOpenWindows()
end )

local function ReloadLanguage( rebuildSpawnMenu )
	I.Reload()
	I.ApplyToolPhrases()
	I.ApplyOpenWindows()
	if hook and hook.Run then hook.Run( "AdvMatLanguageChanged", I.language ) end
	if rebuildSpawnMenu then timer.Simple( 0, function() RunConsoleCommand( "spawnmenu_reload" ) end ) end
end

if cvars and cvars.AddChangeCallback then
	cvars.AddChangeCallback( "advmat_language", function()
		ReloadLanguage( true )
	end, "AdvMat.LanguageOverrideChanged" )

	cvars.AddChangeCallback( "gmod_language", function()
		local selected = ConVarString( "advmat_language", "auto" )
		if selected == "auto" or selected == "" then ReloadLanguage( true ) end
	end, "AdvMat.GModLanguageChanged" )
end

hook.Add( "InitPostEntity", "AdvMat.DetectLanguageAfterInit", function()
	local before = I.language
	I.Reload()
	I.ApplyToolPhrases()
	if before ~= I.language then RunConsoleCommand( "spawnmenu_reload" ) end
end )
