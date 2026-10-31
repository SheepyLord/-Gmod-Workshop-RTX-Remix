#include "diagnostics.h"
#include "../client/catalog.h"
#include "nl/fs.h"
#include "nl/json.h"
#include "nl/sha256.h"
#include "nl/version.h"
#include "nl/activate.h"

#include <windows.h>
#include <dxgi1_2.h>
#include <intrin.h>
#include <array>
#include <algorithm>
#include <cstring>

namespace nl::proxy::diagnostics {
System query_system() {
  System result;
  result.os = "Windows x64";
  using GetVersion = LONG(WINAPI*)(OSVERSIONINFOW*);
  const auto get_version = reinterpret_cast<GetVersion>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
  OSVERSIONINFOW version{};
  version.dwOSVersionInfoSize = sizeof(version);
  if (get_version && get_version(&version) == 0) {
    result.os = std::string(version.dwBuildNumber >= 22000 ? "Windows 11" : "Windows 10") +
                " x64 (" + std::to_string(version.dwMajorVersion) + "." + std::to_string(version.dwMinorVersion) +
                "." + std::to_string(version.dwBuildNumber) + ")";
  }
  std::array<int, 4> registers{};
  __cpuid(registers.data(), static_cast<int>(0x80000000u));
  if (static_cast<unsigned>(registers[0]) >= 0x80000004u) {
    std::array<char, 49> brand{};
    for (unsigned i = 0; i < 3; ++i) {
      __cpuid(registers.data(), static_cast<int>(0x80000002u + i));
      std::memcpy(brand.data() + i * 16, registers.data(), 16);
    }
    result.cpu = brand.data();
    const auto first = result.cpu.find_first_not_of(' ');
    result.cpu = first == std::string::npos ? "" : result.cpu.substr(first);
    const auto last = result.cpu.find_last_not_of(' ');
    if (last != std::string::npos) result.cpu.resize(last + 1);
  }
  result.threads = GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
  MEMORYSTATUSEX memory{};
  memory.dwLength = sizeof(memory);
  if (GlobalMemoryStatusEx(&memory)) result.memory = memory.ullTotalPhys;
  const auto library = LoadLibraryExW(L"dxgi.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (library) {
    using CreateFactory = HRESULT(WINAPI*)(REFIID, void**);
    const auto create = reinterpret_cast<CreateFactory>(GetProcAddress(library, "CreateDXGIFactory1"));
    IDXGIFactory1* factory = nullptr;
    if (create && SUCCEEDED(create(__uuidof(IDXGIFactory1), reinterpret_cast<void**>(&factory)))) {
      for (UINT index = 0; index < 32; ++index) {
        IDXGIAdapter1* adapter = nullptr;
        if (factory->EnumAdapters1(index, &adapter) != S_OK) break;
        DXGI_ADAPTER_DESC1 description{};
        if (SUCCEEDED(adapter->GetDesc1(&description)) && !(description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
          result.graphics.push_back({activate::adapter_description(description.Description), description.DedicatedVideoMemory,
                                     description.VendorId});
        }
        adapter->Release();
      }
      factory->Release();
    }
    FreeLibrary(library);
  }
  return result;
}

std::string serialize(const System& system, std::string_view version, std::string_view hash,
                      const journal::Generation& generation) {
  std::string out = "{\"os\":" + json::quote(system.os) + ",\"cpu\":" + json::quote(system.cpu) +
    ",\"threads\":" + std::to_string(system.threads) + ",\"memory\":" + std::to_string(system.memory) + ",\"graphics\":[";
  for (std::size_t i = 0; i < system.graphics.size(); ++i) {
    if (i) out += ',';
    out += "{\"name\":" + json::quote(system.graphics[i].name) + ",\"memory\":" + std::to_string(system.graphics[i].memory) + '}';
  }
  out += "],\"loader\":{\"version\":" + json::quote(version) + ",\"sha256\":" + json::quote(hash) + "},\"packages\":[";
  for (std::size_t i = 0; i < generation.packages.size(); ++i) {
    const auto& package = generation.packages[i];
    if (i) out += ',';
    out += "{\"id\":" + json::quote(package.id) + ",\"version\":" + json::quote(package.version) +
           ",\"sha256\":" + json::quote(package.manifest_sha256) + '}';
  }
  out += "],\"performance_tier\":" + (system.performance_tier ? performance::serialize(*system.performance_tier) : "null");
  return out + ",\"client_bootstrap\":" + (client::native_bootstrap_present(generation) ? "true" : "false") + '}';
}

void set_performance_tier(System& system, const activate::Plan& plan, std::wstring_view command_line) {
  system.performance_tier.reset();
  const auto& tier = plan.performance_tier;
  if (plan.activate && !tier.layer.empty() &&
      std::find(plan.dxvk_layers.begin(), plan.dxvk_layers.end(), tier.layer) != plan.dxvk_layers.end() &&
      client::render_recipes_refusal(plan, command_line).empty())
    system.performance_tier = tier;
}

std::string collect(const std::filesystem::path& root, const journal::Generation& generation,
                    const activate::Plan* effective) {
  System system;
  std::string hash;
  try { system = query_system(); } catch (...) { }
  try {
    if (effective) set_performance_tier(system, *effective, GetCommandLineW());
    else {
      // Read-only preview for callers without an applied session; never consume next_start or
      // read a stale previous status.json. The render-recipe gate matches activation (ADR 0056).
      std::vector<performance::Adapter> adapters;
      for (const auto& gpu : system.graphics) adapters.push_back({gpu.vendor, gpu.name, gpu.memory});
      const auto preview = activate::plan(generation, config::load(root), activate::environment_value, GetCommandLineW(),
                                          [] { return activate::Display{}; }, [&] { return adapters; });
      set_performance_tier(system, preview, GetCommandLineW());
    }
  } catch (...) { }
  try {
    constexpr std::string_view binary = "bin/win64/winmm.dll";
    fs::refuse_links(root, binary);
    hash = sha256::of(fs::read_file(fs::join(root, binary), std::size_t{8} << 20));
  } catch (...) { }
  return serialize(system, NL_VERSION_STRING, hash, generation);
}
}  // namespace nl::proxy::diagnostics
