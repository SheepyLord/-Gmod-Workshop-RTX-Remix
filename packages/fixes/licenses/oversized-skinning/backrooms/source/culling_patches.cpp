#ifdef _WIN64

#include "culling_patches.h"
#include "patch_manager.h"
#include "e_utils.h"
#include "vis_pas_policy.h"
#include <cdll_int.h>
#include <cstring>
#include "tier1/convar.h"
#include <GarrysMod/FactoryLoader.hpp>
#include <GarrysMod/InterfacePointers.hpp>
#include <GarrysMod/Lua/Interface.h>
#include <GarrysMod/Lua/LuaShared.h>
#include <GarrysMod/Lua/LuaConVars.h>
#include "interfaces/interfaces.h"
#include <tier0/dbg.h>

// ===================================================================
//      CONVAR REGISTRATION (via ILuaConVars, like garrys-mod-rtx-remixed)
// ===================================================================

static SourceSDK::FactoryLoader loader_lua_shared("lua_shared");
static GarrysMod::Lua::ILuaConVars* g_pLuaConVars = nullptr;

static ConVar* cv_frustumcull_engine = nullptr;
static ConVar* cv_brush_backfaces = nullptr;
static ConVar* cv_world_backfaces1 = nullptr;
static ConVar* cv_world_backfaces2 = nullptr;
static ConVar* cv_cullnode = nullptr;
static ConVar* cv_frustumcull_client = nullptr;
static ConVar* cv_forcenovis = nullptr;
static ConVar* cv_skip_world_draw = nullptr;
static ConVar* cv_vis_pas = nullptr;

static ConVar* CreatePatchConVar(const char* name, const char* defaultVal, const char* help) {
	ConVar* cv = nullptr;

	if (g_pLuaConVars) {
		cv = g_pLuaConVars->CreateConVar(name, defaultVal, help, FCVAR_ARCHIVE);
	}

	if (!cv && cvar) {
		cv = cvar->FindVar(name);
	}

	// Last resort: construct + register directly via ICvar
	if (!cv && cvar) {
		cv = new ConVar(name, defaultVal, FCVAR_ARCHIVE, help);
		cvar->RegisterConCommand(cv);
	}

	if (cv) {
		Msg("[PatchManager] ConVar '%s' ready\n", name);
	} else {
		Warning("[PatchManager] Failed to create ConVar '%s'\n", name);
	}
	return cv;
}

static void RegisterPatchConVars() {
	g_pLuaConVars = loader_lua_shared.GetInterface<GarrysMod::Lua::ILuaConVars>(GMOD_LUACONVARS_INTERFACE);
	if (!g_pLuaConVars) {
		Warning("[PatchManager] Failed to get ILuaConVars interface (lua_shared)\n");
		// Continue anyway - patches will still work, just no ConVar toggling
	} else {
		Msg("[PatchManager] Got ILuaConVars interface\n");
	}

	cv_frustumcull_engine = CreatePatchConVar("rtx_patch_frustumcull_engine", "1", "Disable engine frustum culling");
	cv_brush_backfaces    = CreatePatchConVar("rtx_patch_brush_backfaces", "1", "Force render brush entity backfaces");
	cv_world_backfaces1   = CreatePatchConVar("rtx_patch_world_backfaces1", "1", "Force render world backfaces #1");
	cv_world_backfaces2   = CreatePatchConVar("rtx_patch_world_backfaces2", "1", "Force render world backfaces #2");
	cv_cullnode           = CreatePatchConVar("rtx_patch_cullnode", "1", "Disable R_CullNode BSP culling");
	cv_frustumcull_client = CreatePatchConVar("rtx_patch_frustumcull_client", "1", "Disable client frustum culling");
	cv_forcenovis         = CreatePatchConVar("rtx_patch_forcenovis", "1", "Force r_novis (disable PVS culling)");
	cv_skip_world_draw    = CreatePatchConVar("rtx_patch_skip_world_draw", "0", "Skip engine world surface drawing (Shader_DrawChains) so overlays/decals still render");
	cv_vis_pas            = CreatePatchConVar("rtx_patch_vis_pas", "0", "Widen the engine's PVS to the PAS (everything visible from anything visible) for the loaded map");

	Msg("[PatchManager] ConVar registration complete\n");
}

// ===================================================================
//      PATCH DEFINITIONS
// ===================================================================

static void RegisterCullingPatches() {
	auto& pm = PatchManager::Instance();

	// R_CullBox is compiled into both engine.dll and client.dll. The primary
	// locator identifies the current function entry exactly. The body fallback
	// tolerates small prologue/stack-size changes, then searches backwards for
	// the validated "sub rsp" instruction that still marks the entry point.
	static const char cullBoxEntrySig[] =
		"48 83 EC 48 0F 10 22 33 C0 48 8D 51 20 41 0F 10 28";
	static const char cullBoxBodySig[] =
		"0F 10 22 33 C0 48 8D 51 20 41 0F 10 28 "
		"0F 29 74 24 30";
	const std::vector<uint8_t> expectedCullBoxEntry = {
		0x48, 0x83, 0xEC // sub rsp, imm8
	};
	const std::vector<PatchLocator> cullBoxLocators = {
		{
			"current R_CullBox entry",
			std::string(cullBoxEntrySig, sizeof(cullBoxEntrySig) - 1),
			0,
			0,
			{0x48, 0x83, 0xEC, 0x48, 0x0F, 0x10, 0x22}
		},
		{
			"stable R_CullBox body",
			std::string(cullBoxBodySig, sizeof(cullBoxBodySig) - 1),
			-4,
			8,
			expectedCullBoxEntry
		}
	};

	// engine.dll patches (from applypatch.py patches64)
	{
		// c_frustumcull - uses sse instructions in 64bit
		pm.RegisterPatchWithFallbacks(
			"rtx_patch_frustumcull_engine",
			"engine.dll",
			cullBoxLocators,
			{0x31, 0xC0, 0xC3}); // xor eax,eax; ret
	}
	{
		// brush entity backfaces
		// The body fallback occurs in several related functions, but only this
		// one has a JNZ two bytes before it. PatchManager requires that this
		// expected target validation yields exactly one executable address.
		static const char currentSig[] =
			"85 F6 75 ? F3 0F 10 15 ? ? ? ? "
			"F3 0F 59 51 04 F3 0F 10 05 ? ? ? ?";
		static const char stableBodySig[] =
			"F3 0F 10 15 ? ? ? ? F3 0F 59 51 04 "
			"F3 0F 10 05 ? ? ? ? F3 0F 59 01";
		const std::vector<PatchLocator> locators = {
			{
				"current brush backface branch",
				std::string(currentSig, sizeof(currentSig) - 1),
				2,
				0,
				{0x75} // jnz short
			},
			{
				"stable brush lighting body",
				std::string(stableBodySig, sizeof(stableBodySig) - 1),
				-2,
				4,
				{0x75} // jnz short
			}
		};
		pm.RegisterPatchWithFallbacks(
			"rtx_patch_brush_backfaces",
			"engine.dll",
			locators,
			{0xEB}); // jmp short (unconditional)
	}
	{
		// world backfaces #1
		// PATCH DOCS: in R_DrawLeaf, search for "CBitVec invalid set bitNum" string 
		// Working as of 2026-02-14, cross reference gmod as of that date if you need to refind
		static const char currentSig[] =
			"4D 85 F6 7E ? 8B EF 0F 1F 80 ? ? ? ? "
			"48 8B 05 ? ? ? ? 49 8B 0C EC";
		static const char stableBodySig[] =
			"8B EF 0F 1F 80 ? ? ? ? 48 8B 05 ? ? ? ? "
			"49 8B 0C EC 48 2B 88 E8 00 00 00";
		const std::vector<PatchLocator> locators = {
			{
				"current R_DrawLeaf backface branch #1",
				std::string(currentSig, sizeof(currentSig) - 1),
				3,
				0,
				{0x7E} // jle short
			},
			{
				"stable R_DrawLeaf body after branch #1",
				std::string(stableBodySig, sizeof(stableBodySig) - 1),
				-2,
				4,
				{0x7E} // jle short
			}
		};
		pm.RegisterPatchWithFallbacks(
			"rtx_patch_world_backfaces1",
			"engine.dll",
			locators,
			{0xEB}); // jmp short (unconditional)
	}
	{
		// world backfaces #2
		// PATCH DOCS: in R_DrawLeaf, search for "CBitVec invalid set bitNum" string, but a little lower in the function
		// Working as of 2026-02-14, cross reference gmod as of that date if you need to refind
		static const char currentSig[] =
			"41 85 D1 75 ? F7 45 00 00 02 00 00 75 ? "
			"48 8B 45 ? F3 0F 10 15 ? ? ? ?";
		static const char stableBodySig[] =
			"48 8B 45 ? F3 0F 10 15 ? ? ? ? "
			"F3 0F 10 05 ? ? ? ? F3 0F 10 0D ? ? ? ?";
		const std::vector<PatchLocator> locators = {
			{
				"current R_DrawLeaf backface branch #2",
				std::string(currentSig, sizeof(currentSig) - 1),
				12,
				0,
				{0x75} // jnz short
			},
			{
				"stable R_DrawLeaf body after branch #2",
				std::string(stableBodySig, sizeof(stableBodySig) - 1),
				-2,
				4,
				{0x75} // jnz short
			}
		};
		pm.RegisterPatchWithFallbacks(
			"rtx_patch_world_backfaces2",
			"engine.dll",
			locators,
			{0xEB}); // jmp short (unconditional)
	}
	{
		// R_CullNode. The body fallback allows the stack allocation and RIP
		// displacement to move while requiring a nearby function-entry prologue.
		static const char currentSig[] =
			"48 83 EC 48 80 3D ? ? ? ? 00 48 8B D1 "
			"0F 29 74 24 30 0F 29 7C 24 20";
		static const char stableBodySig[] =
			"48 8B D1 0F 29 74 24 30 0F 29 7C 24 20 "
			"44 0F 29 44 24 10";
		const std::vector<PatchLocator> locators = {
			{
				"current R_CullNode entry",
				std::string(currentSig, sizeof(currentSig) - 1),
				0,
				0,
				{0x48, 0x83, 0xEC, 0x48}
			},
			{
				"stable R_CullNode body",
				std::string(stableBodySig, sizeof(stableBodySig) - 1),
				-11,
				8,
				{0x48, 0x83, 0xEC}
			}
		};
		pm.RegisterPatchWithFallbacks(
			"rtx_patch_cullnode",
			"engine.dll",
			locators,
			{0x31, 0xC0, 0xC3}); // xor eax,eax; ret
	}

	{
		// Shader_DrawChains - skip world surface polygon drawing so overlays/decals still render.
		// Garry's Mod changed the third argument from an 8-bit bool to a 32-bit
		// value in 2026, changing movzx ebp,r8b into mov ebp,r8d. Keep exact
		// signatures for both layouts, then fall back to a stable body signature.
		// The body fallback searches backwards for the validated function prologue
		// so another small argument/prologue change fails safely or still resolves.
		static const char currentSig[] =
			"48 83 EC 60 48 89 6C 24 70 41 8B E8";
		static const char legacySig[] =
			"48 83 EC 60 48 89 6C 24 70 41 0F B6 E8";
		static const char stableBodySig[] =
			"4C 89 64 24 58 4D 8B E1 4C 89 6C 24 50 "
			"4C 89 74 24 48 4C 8B F1";
		const std::vector<uint8_t> expectedEntry = {
			0x40, 0x53,                   // push rbx
			0x48, 0x83, 0xEC, 0x60       // sub rsp, 60h
		};
		const std::vector<PatchLocator> locators = {
			{
				"current 32-bit draw-mode parameter",
				std::string(currentSig, sizeof(currentSig) - 1),
				-2,
				0,
				expectedEntry
			},
			{
				"legacy 8-bit draw-mode parameter",
				std::string(legacySig, sizeof(legacySig) - 1),
				-2,
				0,
				expectedEntry
			},
			{
				"stable Shader_DrawChains body",
				std::string(stableBodySig, sizeof(stableBodySig) - 1),
				-15,
				8,
				expectedEntry
			}
		};

		pm.RegisterPatchWithFallbacks(
			"rtx_patch_skip_world_draw",
			"engine.dll",
			locators,
			{0xC3}); // ret
	}

	// client.dll patches (from applypatch.py patches64)
	{
		// c_frustumcull
		pm.RegisterPatchWithFallbacks(
			"rtx_patch_frustumcull_client",
			"client.dll",
			cullBoxLocators,
			{0x31, 0xC0, 0xC3}); // xor eax,eax; ret
	}
	{
		// r_forcenovis [getter] - force return 1
		// The neighborhood fallback tolerates the member offset changing by
		// identifying the adjacent bool setter/getter and following int getter.
		static const char currentSig[] =
			"0F B6 81 54 03 00 00 C3";
		static const char stableNeighborhoodSig[] =
			"C6 81 ? ? ? ? 01 C3 "
			"CC CC CC CC CC CC CC CC "
			"0F B6 81 ? ? ? ? C3 "
			"CC CC CC CC CC CC CC CC "
			"8B 81 ? ? ? ? C3";
		const std::vector<PatchLocator> locators = {
			{
				"current ShouldForceNoVis getter",
				std::string(currentSig, sizeof(currentSig) - 1),
				0,
				0,
				{0x0F, 0xB6, 0x81}
			},
			{
				"stable ShouldForceNoVis accessor neighborhood",
				std::string(
					stableNeighborhoodSig,
					sizeof(stableNeighborhoodSig) - 1),
				16,
				0,
				{0x0F, 0xB6, 0x81}
			}
		};
		pm.RegisterPatchWithFallbacks(
			"rtx_patch_forcenovis",
			"client.dll",
			locators,
			{0xB0, 0x01, 0xC3}); // mov al,1; ret
	}

	pm.ResolveAll();
}

// ===================================================================
//      VIS WIDENING (rtx_patch_vis_pas)
// ===================================================================
// Path tracing needs more of a map than the camera can see: the room next door bounces light
// into this one, shades it and shows in its reflections. With the engine's PVS on, only the
// clusters visible from the camera's cluster are drawn (and the server sends only their
// entities), which on a maze of small rooms leaves the room next door out of the scene. vvis
// stores a second row per cluster beside the PVS, the PAS: everything visible from any cluster
// in the PVS. CM_Vis decompresses cluster c's row from dvis->bitofs[c][type] of the engine's
// copy of the vis lump, so pointing each cluster's PVS offset at its PAS row makes every PVS
// lookup of the loaded map (the client's world and entity culling, the server's choice of
// entities to send, PVS tests) return the PAS. The offsets are put back when the convar is
// cleared; a map change loads a fresh table.

struct dvis_t {
	int numclusters;
};

static int* g_pNumVisibility = nullptr;   // CCollisionBSPData::numvisibility
static dvis_t** g_ppMapVis = nullptr;     // CCollisionBSPData::map_vis
static IVEngineClient* g_visEngineClient = nullptr;
static VisPAS::State g_visSaved;

static bool ReadVisMemory(const void* from, void* to, size_t bytes) {
	SIZE_T copied = 0;
	return ReadProcessMemory(GetCurrentProcess(), from, to, bytes, &copied) && copied == bytes;
}

static bool VisRangeInModule(const DynLibInfo& module, const void* address, size_t bytes) {
	const uintptr_t begin = reinterpret_cast<uintptr_t>(module.baseAddress);
	const uintptr_t at = reinterpret_cast<uintptr_t>(address);
	return begin && at >= begin && at - begin < module.memorySize &&
		bytes <= module.memorySize - (at - begin);
}

static bool VisMemoryRange(const void* address, size_t bytes, bool writable) {
	uintptr_t at = reinterpret_cast<uintptr_t>(address);
	if (!at || at > UINTPTR_MAX - bytes) return false;
	const uintptr_t end = at + bytes;
	while (at < end) {
		MEMORY_BASIC_INFORMATION info = {};
		if (!VirtualQuery(reinterpret_cast<void*>(at), &info, sizeof(info)) ||
			info.State != MEM_COMMIT || (info.Protect & (PAGE_GUARD | PAGE_NOACCESS))) return false;
		const DWORD access = info.Protect & 0xff;
		const bool canWrite = access == PAGE_READWRITE || access == PAGE_WRITECOPY ||
			access == PAGE_EXECUTE_READWRITE || access == PAGE_EXECUTE_WRITECOPY;
		if (!canWrite && (writable || (access != PAGE_READONLY && access != PAGE_EXECUTE_READ))) return false;
		const uintptr_t base = reinterpret_cast<uintptr_t>(info.BaseAddress);
		if (base > UINTPTR_MAX - info.RegionSize || base + info.RegionSize <= at) return false;
		at = base + info.RegionSize;
	}
	return true;
}

static void ResolveVisData() {
	// CM_Vis, before it decompresses a row:
	//   cmp dword ptr [numvisibility], 0 / je / mov r9, [map_vis] / test r9, r9 / je /
	//   movsxd rcx, r8d / lea r15d, [rdx+7] / sar r15d, 3 / mov rdi, rbp /
	//   lea rcx, [rax+rcx*2] / movsxd rsi, dword ptr [r9+rcx*4+4]
	static const char sig[] =
		"83 3D ? ? ? ? 00 0F 84 ? ? ? ? 4C 8B 0D ? ? ? ? 4D 85 C9 0F 84 ? ? ? ? "
		"49 63 C8 44 8D 7A 07 41 C1 FF 03 48 8B FD 48 8D 0C 48 49 63 74 89 04";
	HMODULE engine = GetModuleHandleA("engine.dll");
	uint8_t* at = engine ? static_cast<uint8_t*>(ScanSign(engine, sig, sizeof(sig) - 1)) : nullptr;
	DynLibInfo module = {};
	MEMORY_BASIC_INFORMATION code = {};
	if (!at || !GetLibraryInfo(engine, module) || !VisRangeInModule(module, at, 52) ||
		ScanSign(engine, sig, sizeof(sig) - 1, at + 1) ||
		!VirtualQuery(at, &code, sizeof(code)) || code.State != MEM_COMMIT ||
		(code.Protect & (PAGE_GUARD | PAGE_NOACCESS)) ||
		!(code.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY))) {
		Warning("[PatchManager] rtx_patch_vis_pas: no unique executable CM_Vis, the PVS cannot be widened\n");
		return;
	}
	int32_t numDisplacement = 0, tableDisplacement = 0;
	if (!ReadVisMemory(at + 2, &numDisplacement, sizeof(numDisplacement)) ||
		!ReadVisMemory(at + 16, &tableDisplacement, sizeof(tableDisplacement))) return;
	auto* num = reinterpret_cast<int*>(reinterpret_cast<uintptr_t>(at) + 7 + numDisplacement);
	auto* table = reinterpret_cast<dvis_t**>(reinterpret_cast<uintptr_t>(at) + 20 + tableDisplacement);
	if (!VisRangeInModule(module, num, sizeof(*num)) ||
		!VisRangeInModule(module, table, sizeof(*table))) {
		Warning("[PatchManager] rtx_patch_vis_pas: CM_Vis data outside engine.dll, disabled\n");
		return;
	}
	static SourceSDK::FactoryLoader engineLoader("engine");
	g_visEngineClient = engineLoader.GetInterface<IVEngineClient>(VENGINE_CLIENT_INTERFACE_VERSION);
	if (!g_visEngineClient) return;
	g_pNumVisibility = num;
	g_ppMapVis = table;
	Msg("[PatchManager] rtx_patch_vis_pas: vis table pointer at %p\n", g_ppMapVis);
}

static void SyncVisPAS(bool closing = false) {
	const bool want = !closing && cv_vis_pas && cv_vis_pas->GetBool();
	if (!want && !g_visSaved.Active()) return; // default-off: no table reads or writes
	int bytes = 0;
	dvis_t* v = nullptr;
	dvis_t header = {};
	if (!g_ppMapVis || !g_pNumVisibility || !g_visEngineClient ||
		!ReadVisMemory(g_pNumVisibility, &bytes, sizeof(bytes)) || bytes < 4 || bytes > VisPAS::MaxVisibilityBytes ||
		!ReadVisMemory(g_ppMapVis, &v, sizeof(v)) || !v ||
		(reinterpret_cast<uintptr_t>(v) % alignof(int)) != 0 ||
		!ReadVisMemory(v, &header, sizeof(header)) || header.numclusters <= 0 ||
		header.numclusters > VisPAS::MaxClusters || bytes < 4 + header.numclusters * 8 ||
		!VisMemoryRange(v, static_cast<size_t>(bytes), false) ||
		!VisMemoryRange(v, 4 + static_cast<size_t>(header.numclusters) * 8, true)) {
		g_visSaved.Forget();
		return;
	}
	const char* map = g_visEngineClient->GetLevelName();
	auto* offsets = reinterpret_cast<int*>(reinterpret_cast<uint8_t*>(v) + 4);
	const auto result = g_visSaved.Sync(v, map ? map : "", bytes, header.numclusters, offsets, want);
	if (result == VisPAS::Result::Widened) {
		Msg("[PatchManager] rtx_patch_vis_pas: the PVS of %d clusters is their PAS\n", header.numclusters);
	} else if (result == VisPAS::Result::Restored) {
		Msg("[PatchManager] rtx_patch_vis_pas: the PVS of %d clusters is restored\n", header.numclusters);
	} else if (result == VisPAS::Result::OwnershipLost) {
		Warning("[PatchManager] rtx_patch_vis_pas: visibility table changed externally; saved offsets discarded\n");
	}
}

void ShutdownCullingPatches() {
	SyncVisPAS(true);
	g_visSaved.Forget();
	g_pNumVisibility = nullptr;
	g_ppMapVis = nullptr;
	g_visEngineClient = nullptr;
}

// ===================================================================
//      APPLY INITIAL PATCHES
// ===================================================================

static void ApplyInitialPatches() {
	auto& pm = PatchManager::Instance();

	// Apply patches based on ConVar values (default to enabled if ConVar failed to create)
	if (!cv_frustumcull_engine || cv_frustumcull_engine->GetBool()) pm.ApplyPatch("rtx_patch_frustumcull_engine");
	if (!cv_brush_backfaces || cv_brush_backfaces->GetBool()) pm.ApplyPatch("rtx_patch_brush_backfaces");
	if (!cv_world_backfaces1 || cv_world_backfaces1->GetBool()) pm.ApplyPatch("rtx_patch_world_backfaces1");
	if (!cv_world_backfaces2 || cv_world_backfaces2->GetBool()) pm.ApplyPatch("rtx_patch_world_backfaces2");
	if (!cv_cullnode || cv_cullnode->GetBool()) pm.ApplyPatch("rtx_patch_cullnode");
	if (!cv_frustumcull_client || cv_frustumcull_client->GetBool()) pm.ApplyPatch("rtx_patch_frustumcull_client");
	if (!cv_forcenovis || cv_forcenovis->GetBool()) pm.ApplyPatch("rtx_patch_forcenovis");
	if (cv_skip_world_draw && cv_skip_world_draw->GetBool()) pm.ApplyPatch("rtx_patch_skip_world_draw");
}

// ===================================================================
//      SYNC PATCHES TO CONVAR VALUES (runtime toggling)
// ===================================================================

static void SyncPatch(const char* name, ConVar* cv) {
	auto& pm = PatchManager::Instance();
	if (!cv) return; // No ConVar, leave patch as-is

	bool wantEnabled = cv->GetBool();
	bool isApplied = pm.IsApplied(name);

	if (wantEnabled && !isApplied) {
		pm.ApplyPatch(name);
	} else if (!wantEnabled && isApplied) {
		pm.RestorePatch(name);
	}
}

void SyncCullingPatches() {
	SyncPatch("rtx_patch_frustumcull_engine", cv_frustumcull_engine);
	SyncPatch("rtx_patch_brush_backfaces", cv_brush_backfaces);
	SyncPatch("rtx_patch_world_backfaces1", cv_world_backfaces1);
	SyncPatch("rtx_patch_world_backfaces2", cv_world_backfaces2);
	SyncPatch("rtx_patch_cullnode", cv_cullnode);
	SyncPatch("rtx_patch_frustumcull_client", cv_frustumcull_client);
	SyncPatch("rtx_patch_forcenovis", cv_forcenovis);
	SyncPatch("rtx_patch_skip_world_draw", cv_skip_world_draw);
	SyncVisPAS();
}

// ===================================================================
//      LUA-CALLABLE FUNCTIONS
// ===================================================================

LUA_FUNCTION_STATIC(RTX_SyncPatches) {
	SyncCullingPatches();
	return 0;
}

void RegisterCullingPatchLuaFunctions(GarrysMod::Lua::ILuaBase* LUA) {
	LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);
		LUA->PushCFunction(RTX_SyncPatches);
		LUA->SetField(-2, "RTX_SyncPatches");
	LUA->Pop();
}

// ===================================================================
//      PUBLIC ENTRY POINT
// ===================================================================

void InitCullingPatches() {
	RegisterPatchConVars();
	RegisterCullingPatches();
	ApplyInitialPatches();
	ResolveVisData();
	SyncVisPAS();
}

#endif // _WIN64
