// R13-B QA: hold a given amount of VRAM resident in a separate process, meant to make WDDM lower the
// memory budget of a game session running beside it. Measured on an RTX 5090, WDDM pages this process
// instead and lowers the foreground game's budget only to its usage (build_vram_pressure.ps1.md).
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <string>
#include <thread>
#include <vector>

using Microsoft::WRL::ComPtr;

namespace {
constexpr UINT kSide = 8192;                       // 8192 x 8192 RGBA8 = 256 MiB per texture
constexpr uint64_t kTextureBytes = uint64_t(kSide) * kSide * 4;

void report(IDXGIAdapter3* adapter, const char* event, size_t textures) {
  DXGI_QUERY_VIDEO_MEMORY_INFO local{};
  adapter->QueryVideoMemoryInfo(0, DXGI_MEMORY_SEGMENT_GROUP_LOCAL, &local);
  SYSTEMTIME now{};
  GetSystemTime(&now);
  std::printf("{\"event\":\"%s\",\"utc\":\"%04u-%02u-%02uT%02u:%02u:%02uZ\",\"textures\":%zu,\"held_bytes\":%llu,"
              "\"budget\":%llu,\"usage\":%llu}\n",
    event, now.wYear, now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond, textures,
    static_cast<unsigned long long>(textures * kTextureBytes),
    static_cast<unsigned long long>(local.Budget), static_cast<unsigned long long>(local.CurrentUsage));
  std::fflush(stdout);
}
}

int wmain(int argc, wchar_t** argv) {
  if (argc != 3) {
    std::fprintf(stderr, "usage: vram_pressure.exe <GiB to hold> <seconds>\n");
    return 2;
  }
  const double gib = _wtof(argv[1]);
  const int seconds = _wtoi(argv[2]);
  if (gib <= 0 || seconds <= 0) {
    std::fprintf(stderr, "vram_pressure: GiB and seconds must be positive\n");
    return 2;
  }

  // The adapter with the most dedicated memory: the one the game renders on.
  ComPtr<IDXGIFactory1> factory;
  if (FAILED(CreateDXGIFactory1(IID_PPV_ARGS(&factory)))) {
    std::fprintf(stderr, "vram_pressure: no DXGI factory\n");
    return 1;
  }
  ComPtr<IDXGIAdapter1> best;
  SIZE_T bestMemory = 0;
  for (UINT i = 0;; i++) {
    ComPtr<IDXGIAdapter1> adapter;
    if (factory->EnumAdapters1(i, &adapter) == DXGI_ERROR_NOT_FOUND)
      break;
    DXGI_ADAPTER_DESC1 desc{};
    adapter->GetDesc1(&desc);
    if (!(desc.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) && desc.DedicatedVideoMemory > bestMemory) {
      bestMemory = desc.DedicatedVideoMemory;
      best = adapter;
    }
  }
  ComPtr<IDXGIAdapter3> adapter3;
  if (!best || FAILED(best.As(&adapter3))) {
    std::fprintf(stderr, "vram_pressure: no hardware adapter\n");
    return 1;
  }

  ComPtr<ID3D11Device> device;
  ComPtr<ID3D11DeviceContext> context;
  if (FAILED(D3D11CreateDevice(best.Get(), D3D_DRIVER_TYPE_UNKNOWN, nullptr, 0, nullptr, 0,
                               D3D11_SDK_VERSION, &device, nullptr, &context))) {
    std::fprintf(stderr, "vram_pressure: no D3D11 device\n");
    return 1;
  }

  const size_t wanted = size_t(gib * (1ull << 30) / double(kTextureBytes) + 0.5);
  std::vector<ComPtr<ID3D11RenderTargetView>> views;
  std::vector<ComPtr<ID3D11Texture2D>> textures;
  report(adapter3.Get(), "start", 0);
  for (size_t i = 0; i < wanted; i++) {
    D3D11_TEXTURE2D_DESC desc{};
    desc.Width = kSide;
    desc.Height = kSide;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET;
    ComPtr<ID3D11Texture2D> texture;
    ComPtr<ID3D11RenderTargetView> view;
    if (FAILED(device->CreateTexture2D(&desc, nullptr, &texture)) ||
        FAILED(device->CreateRenderTargetView(texture.Get(), nullptr, &view))) {
      std::fprintf(stderr, "vram_pressure: allocation %zu failed\n", i);
      break;
    }
    const float color[4] = { float(i % 7) / 7.0f, 0.25f, 0.5f, 1.0f };
    context->ClearRenderTargetView(view.Get(), color);
    textures.push_back(texture);
    views.push_back(view);
  }
  context->Flush();
  report(adapter3.Get(), "allocated", textures.size());

  // Touch every texture twice a second so the allocations stay resident.
  const auto end = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
  auto nextReport = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  uint32_t pass = 0;
  while (std::chrono::steady_clock::now() < end) {
    const float color[4] = { float(pass % 5) / 5.0f, 0.5f, 0.25f, 1.0f };
    for (const auto& view : views)
      context->ClearRenderTargetView(view.Get(), color);
    context->Flush();
    pass++;
    if (std::chrono::steady_clock::now() >= nextReport) {
      report(adapter3.Get(), "holding", textures.size());
      nextReport += std::chrono::seconds(5);
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(500));
  }
  views.clear();
  textures.clear();
  context->ClearState();
  context->Flush();
  report(adapter3.Get(), "released", 0);
  return 0;
}
