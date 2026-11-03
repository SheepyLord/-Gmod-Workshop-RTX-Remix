// Isolated GPU regression for managed-texture allocation, contents, LOD and Remix hashes.
// R13: a second sequence (argument "r13") checks one copy and idle image release.
#include <windows.h>
#include <psapi.h>
#include <d3d9.h>
#include <wrl/client.h>
#include <remix/remix_c.h>
#include <array>
#include <cstdint>
#include <cstdio>
#include <stdexcept>
#include <string>
#include <vector>

using Microsoft::WRL::ComPtr;
namespace {
void require(bool ok, const char* message) {
  if (!ok) { throw std::runtime_error(message); }
}
void check(HRESULT value, const char* name) {
  if (FAILED(value)) {
    char buffer[256]; sprintf_s(buffer, "%s: HRESULT 0x%08lx", name, static_cast<unsigned long>(value));
    throw std::runtime_error(buffer);
  }
}
void apiCheck(remixapi_ErrorCode code, const char* name) {
  if (code != REMIXAPI_ERROR_CODE_SUCCESS) {
    char buffer[256]; sprintf_s(buffer, "%s: Remix error %u", name, unsigned(code));
    throw std::runtime_error(buffer);
  }
}
std::uint32_t color(unsigned level) { return 0xff102030u + level * 0x00010203u; }
std::uint64_t hash(remixapi_Interface& api, IDirect3DTexture9* texture) {
  std::uint64_t value = 123;
  apiCheck(api.dxvk_GetTextureHash(texture, &value), "texture hash");
  return value;
}
std::uint64_t textureBytes(remixapi_Interface& api) {
  remixapi_VramStats stats{};
  apiCheck(api.GetVramStats(&stats), "VRAM stats");
  return stats.usedAppTextureBytes;
}
void fill(IDirect3DTexture9* texture) {
  for (unsigned mip = 0; mip < texture->GetLevelCount(); ++mip) {
    D3DSURFACE_DESC desc{}; check(texture->GetLevelDesc(mip, &desc), "mip description");
    D3DLOCKED_RECT data{}; check(texture->LockRect(mip, &data, nullptr, 0), "managed write lock");
    for (unsigned y = 0; y < desc.Height; ++y) {
      auto* row = reinterpret_cast<std::uint32_t*>(static_cast<unsigned char*>(data.pBits) + y * data.Pitch);
      for (unsigned x = 0; x < desc.Width; ++x) { row[x] = color(mip); }
    }
    check(texture->UnlockRect(mip), "managed write unlock");
  }
}
std::uint32_t draw(IDirect3DDevice9Ex* device, IDirect3DTexture9* texture) {
  check(device->SetTexture(0, texture), "bind");
  check(device->SetVertexShader(nullptr), "fixed vertex shader");
  check(device->SetPixelShader(nullptr), "fixed pixel shader");
  check(device->SetFVF(D3DFVF_XYZRHW | D3DFVF_TEX1), "FVF");
  device->SetRenderState(D3DRS_LIGHTING, FALSE);
  device->SetRenderState(D3DRS_ZENABLE, FALSE);
  device->SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
  device->SetRenderState(D3DRS_ALPHABLENDENABLE, FALSE);
  device->SetRenderState(D3DRS_SRGBWRITEENABLE, FALSE);
  device->SetTextureStageState(0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
  device->SetTextureStageState(0, D3DTSS_COLORARG1, D3DTA_TEXTURE);
  device->SetTextureStageState(0, D3DTSS_ALPHAOP, D3DTOP_SELECTARG1);
  device->SetTextureStageState(0, D3DTSS_ALPHAARG1, D3DTA_TEXTURE);
  device->SetTextureStageState(1, D3DTSS_COLOROP, D3DTOP_DISABLE);
  device->SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_POINT);
  device->SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_POINT);
  device->SetSamplerState(0, D3DSAMP_MIPFILTER, D3DTEXF_NONE);
  device->SetSamplerState(0, D3DSAMP_SRGBTEXTURE, FALSE);
  struct Vertex { float x, y, z, rhw, u, v; };
  const std::array<Vertex, 4> quad = {{{-.5f, -.5f, .5f, 1, 0, 0}, {63.5f, -.5f, .5f, 1, 1, 0},
                                    {-.5f, 63.5f, .5f, 1, 0, 1}, {63.5f, 63.5f, .5f, 1, 1, 1}}};
  check(device->Clear(0, nullptr, D3DCLEAR_TARGET, 0xff000000, 1, 0), "clear");
  check(device->BeginScene(), "begin scene");
  check(device->DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, quad.data(), sizeof(Vertex)), "draw");
  check(device->EndScene(), "end scene");
  ComPtr<IDirect3DSurface9> target, readback;
  check(device->GetRenderTarget(0, &target), "render target");
  D3DSURFACE_DESC desc{}; check(target->GetDesc(&desc), "target description");
  check(device->CreateOffscreenPlainSurface(desc.Width, desc.Height, desc.Format, D3DPOOL_SYSTEMMEM,
                                           &readback, nullptr), "readback surface");
  check(device->GetRenderTargetData(target.Get(), readback.Get()), "GPU readback");
  D3DLOCKED_RECT data{}; check(readback->LockRect(&data, nullptr, D3DLOCK_READONLY), "readback lock");
  const auto pixel = *reinterpret_cast<const std::uint32_t*>(static_cast<const unsigned char*>(data.pBits) +
                                                           32 * data.Pitch + 32 * 4);
  check(readback->UnlockRect(), "readback unlock");
  return pixel & 0x00ffffff;
}

// R13: content that varies per texel, so a hash or a read-back notices any lost or moved byte.
std::uint32_t texel(unsigned level, unsigned x, unsigned y, std::uint32_t salt) {
  std::uint32_t v = (x * 73856093u) ^ (y * 19349663u) ^ (level * 83492791u) ^ salt;
  v ^= v >> 13; v *= 0x5bd1e995u; v ^= v >> 15;
  return v | 0xff000000u;
}
void fillPattern(IDirect3DTexture9* texture, std::uint32_t salt) {
  for (unsigned mip = 0; mip < texture->GetLevelCount(); ++mip) {
    D3DSURFACE_DESC desc{}; check(texture->GetLevelDesc(mip, &desc), "pattern mip description");
    D3DLOCKED_RECT data{}; check(texture->LockRect(mip, &data, nullptr, 0), "pattern write lock");
    for (unsigned y = 0; y < desc.Height; ++y) {
      auto* row = reinterpret_cast<std::uint32_t*>(static_cast<unsigned char*>(data.pBits) + y * data.Pitch);
      for (unsigned x = 0; x < desc.Width; ++x) { row[x] = texel(mip, x, y, salt); }
    }
    check(texture->UnlockRect(mip), "pattern write unlock");
  }
}
// Reads every texel of a mip through a read-only lock; returns the number of texels that differ.
std::uint64_t mismatches(IDirect3DTexture9* texture, unsigned mip, std::uint32_t salt, const RECT* rewritten = nullptr,
                         std::uint32_t rewriteValue = 0) {
  D3DSURFACE_DESC desc{}; check(texture->GetLevelDesc(mip, &desc), "verify mip description");
  D3DLOCKED_RECT data{}; check(texture->LockRect(mip, &data, nullptr, D3DLOCK_READONLY), "verify read-only lock");
  std::uint64_t wrong = 0;
  for (unsigned y = 0; y < desc.Height; ++y) {
    const auto* row = reinterpret_cast<const std::uint32_t*>(static_cast<const unsigned char*>(data.pBits) + y * data.Pitch);
    for (unsigned x = 0; x < desc.Width; ++x) {
      const bool inside = rewritten && LONG(x) >= rewritten->left && LONG(x) < rewritten->right &&
                          LONG(y) >= rewritten->top && LONG(y) < rewritten->bottom;
      wrong += row[x] != (inside ? rewriteValue : texel(mip, x, y, salt));
    }
  }
  check(texture->UnlockRect(mip), "verify unlock");
  return wrong;
}
std::uint64_t privateBytes() {
  PROCESS_MEMORY_COUNTERS_EX counters{}; counters.cb = sizeof(counters);
  require(K32GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters), sizeof(counters)) != 0,
          "process memory counters");
  return counters.PrivateUsage;
}
// One presented second: the runtime's managed texture passes run at most once per second.
void presentSecond(IDirect3DDevice9Ex* device, int seconds = 1) {
  for (int i = 0; i < seconds; ++i) {
    Sleep(1100);
    check(device->Present(nullptr, nullptr, nullptr, nullptr), "present");
  }
}
// The draw samples one texel near the center of the base level (point filter, no mip filter);
// find which, so later checks know the rewrite covers it.
bool sampledTexel(std::uint32_t pixel, unsigned side, std::uint32_t salt, unsigned& tx, unsigned& ty) {
  for (unsigned y = side / 2 - 48; y < side / 2 + 48; ++y) {
    for (unsigned x = side / 2 - 48; x < side / 2 + 48; ++x) {
      if ((texel(0, x, y, salt) & 0x00ffffff) == pixel) { tx = x; ty = y; return true; }
    }
  }
  return false;
}

// Committed private address space of this process: read-write and write-combined bytes.
struct AddressSpace { std::uint64_t readWrite = 0; std::uint64_t writeCombined = 0; };
AddressSpace addressSpace() {
  AddressSpace result;
  MEMORY_BASIC_INFORMATION info{};
  std::uintptr_t address = 0;
  while (VirtualQuery(reinterpret_cast<LPCVOID>(address), &info, sizeof(info)) == sizeof(info)) {
    if (info.State == MEM_COMMIT && info.Type == MEM_PRIVATE) {
      if (info.Protect == PAGE_READWRITE) { result.readWrite += info.RegionSize; }
      if (info.Protect == (PAGE_READWRITE | PAGE_WRITECOMBINE)) { result.writeCombined += info.RegionSize; }
    }
    const auto next = reinterpret_cast<std::uintptr_t>(info.BaseAddress) + info.RegionSize;
    if (next <= address) { break; }
    address = next;
  }
  return result;
}

// Draws without a texture, so the context drops its view of the last texture drawn.
void drawUntextured(IDirect3DDevice9Ex* device) {
  check(device->SetTexture(0, nullptr), "unbind");
  check(device->Clear(0, nullptr, D3DCLEAR_TARGET, 0xff000000, 1, 0), "untextured clear");
  struct Vertex { float x, y, z, rhw; };
  const std::array<Vertex, 3> tri = {{{0, 0, .5f, 1}, {8, 0, .5f, 1}, {0, 8, .5f, 1}}};
  check(device->SetFVF(D3DFVF_XYZRHW), "untextured FVF");
  device->SetTextureStageState(0, D3DTSS_COLOROP, D3DTOP_SELECTARG1);
  device->SetTextureStageState(0, D3DTSS_COLORARG1, D3DTA_DIFFUSE);
  check(device->BeginScene(), "untextured begin");
  check(device->DrawPrimitiveUP(D3DPT_TRIANGLELIST, 1, tri.data(), sizeof(Vertex)), "untextured draw");
  check(device->EndScene(), "untextured end");
}

// R13 sequence: upload, CPU copy released, read-back lock, rewrite, image release and re-upload,
// device reset. Prints pixels/hashes (identical for every runtime and option) and memory deltas.
// Four 4096-square textures span several of DXVK's 128 MiB host chunks, so a released CPU copy
// shows in the process's private bytes (one empty chunk per memory type stays allocated).
int runR13(remixapi_Interface& api, IDirect3DDevice9Ex* device, D3DPRESENT_PARAMETERS& present) {
  constexpr unsigned kSide = 4096;
  constexpr unsigned kCount = 4;
  constexpr std::uint32_t kSalt = 0x13b00001u;
  check(device->Present(nullptr, nullptr, nullptr, nullptr), "warm-up present");
  const auto bytes0 = textureBytes(api);
  const auto private0 = privateBytes();
  std::array<ComPtr<IDirect3DTexture9>, kCount> textures;
  for (unsigned i = 0; i < kCount; ++i) {
    check(device->CreateTexture(kSide, kSide, 0, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, &textures[i], nullptr), "r13 managed texture");
    fillPattern(textures[i].Get(), kSalt + i);
  }
  IDirect3DTexture9* texture = textures[0].Get();
  const auto privateFilled = privateBytes();

  // 1. First use uploads and hashes the original data.
  std::array<std::uint64_t, kCount> hashesFirst{};
  std::uint32_t pixelFirst = 0;
  for (unsigned i = 0; i < kCount; ++i) {
    const auto pixel = draw(device, textures[i].Get());
    if (i == 0) { pixelFirst = pixel; }
    hashesFirst[i] = hash(api, textures[i].Get());
    require(hashesFirst[i] != 0, "first draw did not hash the texture");
  }
  unsigned sampledX = 0, sampledY = 0;
  require(sampledTexel(pixelFirst, kSide, kSalt, sampledX, sampledY), "first draw pixel is not a texel of the texture's data");
  const auto hashFirst = hashesFirst[0];
  drawUntextured(device);
  check(device->Present(nullptr, nullptr, nullptr, nullptr), "present after first use");
  const auto privateUsed = privateBytes();
  const auto spaceUsed = addressSpace();
  const auto bytesUsed = textureBytes(api);

  // 2. Idle passes: the CPU copy and/or the image may go (depending on the options).
  presentSecond(device, 4);
  const auto privateIdle = privateBytes();
  const auto spaceIdle = addressSpace();
  const auto bytesIdle = textureBytes(api);
  if (GetEnvironmentVariableW(L"R13_PROBE_CENSUS", nullptr, 0) != 0) {
    // The allocation census of the idle state goes to the runtime log on the next present.
    api.SetConfigVariable("rtx.profiler.memory.requestSnapshot", "True");
    check(device->Present(nullptr, nullptr, nullptr, nullptr), "census present");
  }
  for (unsigned i = 0; i < kCount; ++i) {
    require(hash(api, textures[i].Get()) == hashesFirst[i], "the hash changed while the texture was idle (released image or copy)");
  }

  // 3. Read-back lock: every texel of two mips equals what the application wrote.
  require(mismatches(texture, 0, kSalt) == 0, "read-only lock of mip 0 returned different data");
  require(mismatches(texture, 3, kSalt) == 0, "read-only lock of mip 3 returned different data");
  require(mismatches(textures[3].Get(), 0, kSalt + 3) == 0, "read-only lock of another texture returned different data");
  require(hash(api, texture) == hashFirst, "a read-only lock changed the hash");

  // 4. Re-use after release: same pixels, same hash.
  const auto pixelReuse = draw(device, texture);
  require(pixelReuse == pixelFirst, "the re-uploaded texture draws different pixels");
  require(hash(api, texture) == hashFirst, "the re-uploaded texture has a different hash");
  const auto bytesReuse = textureBytes(api);
  drawUntextured(device);

  // 5. Rewrite the center of mip 0 after the copies went: the hash is recomputed from the full data.
  presentSecond(device, 4);
  const RECT region{ LONG(kSide / 2 - 64), LONG(kSide / 2 - 64), LONG(kSide / 2 + 64), LONG(kSide / 2 + 64) };
  const std::uint32_t rewriteValue = 0xff336699u;
  D3DLOCKED_RECT data{};
  check(texture->LockRect(0, &data, &region, 0), "rewrite lock");
  for (LONG y = 0; y < region.bottom - region.top; ++y) {
    auto* row = reinterpret_cast<std::uint32_t*>(static_cast<unsigned char*>(data.pBits) + y * data.Pitch);
    for (LONG x = 0; x < region.right - region.left; ++x) { row[x] = rewriteValue; }
  }
  check(texture->UnlockRect(0), "rewrite unlock");
  const auto pixelRewrite = draw(device, texture);
  require(pixelRewrite == (rewriteValue & 0x00ffffff), "the rewritten texel does not draw");
  const auto hashRewrite = hash(api, texture);
  require(hashRewrite != 0 && hashRewrite != hashFirst, "the rewrite did not refresh the hash");
  drawUntextured(device);
  require(mismatches(texture, 0, kSalt, &region, rewriteValue) == 0, "the rewritten mip reads back differently");

  // 6. Release again, then a device reset while released; managed data survives both.
  presentSecond(device, 4);
  require(hash(api, texture) == hashRewrite, "the rewritten hash changed while idle");
  check(device->Reset(&present), "device reset");
  const auto pixelAfterReset = draw(device, texture);
  require(pixelAfterReset == pixelRewrite, "pixels changed across a device reset");
  require(hash(api, texture) == hashRewrite, "the hash changed across a device reset");
  require(mismatches(texture, 1, kSalt) == 0, "an untouched mip changed across release and reset");
  for (unsigned i = 1; i < kCount; ++i) {
    require(draw(device, textures[i].Get()) == (texel(0, sampledX, sampledY, kSalt + i) & 0x00ffffff), "another texture draws wrong pixels");
    require(hash(api, textures[i].Get()) == hashesFirst[i], "another texture's hash changed");
  }
  drawUntextured(device);

  auto delta = [](std::uint64_t a, std::uint64_t b) { return static_cast<long long>(a) - static_cast<long long>(b); };
  std::printf("{\"sequence\":\"r13\",\"hash_first\":\"0x%016llx\",\"hash_others\":[\"0x%016llx\",\"0x%016llx\",\"0x%016llx\"],"
              "\"hash_rewrite\":\"0x%016llx\",\"pixel_first\":%u,\"pixel_rewrite\":%u,\"sampled_texel\":[%u,%u],"
              "\"private_filled\":%lld,\"private_used\":%lld,\"private_idle\":%lld,"
              "\"rw_idle_vs_used\":%lld,\"wc_idle_vs_used\":%lld,"
              "\"app_texture_used\":%lld,\"app_texture_idle\":%lld,\"app_texture_reuse\":%lld}\n",
    static_cast<unsigned long long>(hashFirst), static_cast<unsigned long long>(hashesFirst[1]),
    static_cast<unsigned long long>(hashesFirst[2]), static_cast<unsigned long long>(hashesFirst[3]),
    static_cast<unsigned long long>(hashRewrite), pixelFirst, pixelRewrite, sampledX, sampledY,
    delta(privateFilled, private0), delta(privateUsed, private0), delta(privateIdle, private0),
    delta(spaceIdle.readWrite, spaceUsed.readWrite), delta(spaceIdle.writeCombined, spaceUsed.writeCombined),
    delta(bytesUsed, bytes0), delta(bytesIdle, bytes0), delta(bytesReuse, bytes0));
  for (auto& t : textures) { t.Reset(); }
  return 0;
}
}

int wmain(int argc, wchar_t** argv) {
  try {
    require(argc == 3 || argc == 4, "usage: managed_texture_probe.exe <runtime d3d9.dll> <dependency folder> [game|r13]");
    // R13: the one-copy/release sequence runs on the game's standard device path.
    const bool r13 = argc == 4 && std::wstring(argv[3]) == L"r13";
    const bool gameMode = argc == 4;
    SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    require(AddDllDirectory(argv[2]) != nullptr, "dependency directory");
    const HMODULE module = LoadLibraryExW(argv[1], nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    require(module != nullptr, "runtime load");
    const auto initialize = reinterpret_cast<PFN_remixapi_InitializeLibrary>(GetProcAddress(module, "remixapi_InitializeLibrary"));
    require(initialize != nullptr, "Remix entry");
    const remixapi_InitializeLibraryInfo info = {REMIXAPI_STRUCT_TYPE_INITIALIZE_LIBRARY_INFO, nullptr,
      REMIXAPI_VERSION_MAKE(REMIXAPI_VERSION_MAJOR, REMIXAPI_VERSION_MINOR, REMIXAPI_VERSION_PATCH)};
    remixapi_Interface api{}; apiCheck(initialize(&info, &api), "Remix initialize");
    WNDCLASSW cls{}; cls.lpfnWndProc = DefWindowProcW; cls.hInstance = GetModuleHandleW(nullptr);
    cls.lpszClassName = L"R12ManagedTextureProbe"; require(RegisterClassW(&cls) != 0, "window class");
    const HWND window = CreateWindowW(cls.lpszClassName, cls.lpszClassName, WS_OVERLAPPEDWINDOW,
      0, 0, 96, 96, nullptr, nullptr, cls.hInstance, nullptr); // intentionally never shown
    require(window != nullptr, "hidden window");
    ComPtr<IDirect3D9Ex> d3d;
    D3DPRESENT_PARAMETERS present{}; present.BackBufferWidth = 64; present.BackBufferHeight = 64;
    present.BackBufferFormat = D3DFMT_A8R8G8B8; present.BackBufferCount = 1;
    present.SwapEffect = D3DSWAPEFFECT_DISCARD; present.Windowed = TRUE; present.hDeviceWindow = window;
    present.PresentationInterval = D3DPRESENT_INTERVAL_IMMEDIATE;
    ComPtr<IDirect3DDevice9Ex> device;
    if (gameMode) {
      const auto create = reinterpret_cast<IDirect3D9* (WINAPI*)(UINT)>(GetProcAddress(module, "Direct3DCreate9"));
      require(create != nullptr, "game D3D9 entry");
      ComPtr<IDirect3D9> standard; standard.Attach(create(D3D_SDK_VERSION));
      require(standard != nullptr, "game D3D9 factory");
      ComPtr<IDirect3DDevice9> standardDevice;
      check(standard->CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, window,
        D3DCREATE_HARDWARE_VERTEXPROCESSING | D3DCREATE_MULTITHREADED, &present, &standardDevice), "game device");
      // This is the known runtime's Device9Ex implementation through its standard D3D9 interfaces,
      // just as the game/fixes register it; no external system device is accepted.
      d3d.Attach(static_cast<IDirect3D9Ex*>(standard.Detach()));
      device.Attach(static_cast<IDirect3DDevice9Ex*>(standardDevice.Detach()));
    } else {
      apiCheck(api.dxvk_CreateD3D9(FALSE, &d3d), "create D3D9");
      check(d3d->CreateDeviceEx(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, window,
        D3DCREATE_HARDWARE_VERTEXPROCESSING | D3DCREATE_MULTITHREADED, &present, nullptr, &device), "device");
    }
    apiCheck(api.dxvk_RegisterD3D9Device(device.Get()), "register device");
    if (r13) {
      const int result = runR13(api, device.Get(), present);
      check(device->SetTexture(0, nullptr), "unbind for shutdown");
      device.Detach(); d3d.Detach();
      apiCheck(api.Shutdown(), "Remix shutdown");
      DestroyWindow(window);
      return result;
    }
    const bool deferred = GetEnvironmentVariableW(L"DXVK_DEFER_MANAGED_TEXTURES", nullptr, 0) != 0 &&
      [] { wchar_t value[16]; GetEnvironmentVariableW(L"DXVK_DEFER_MANAGED_TEXTURES", value, 16); return value[0] == L'1'; }();
    const auto before = textureBytes(api);
    std::array<ComPtr<IDirect3DTexture9>, 4> textures;
    for (auto& texture : textures) {
      check(device->CreateTexture(1024, 1024, 0, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, &texture, nullptr), "managed texture");
    }
    const auto created = textureBytes(api);
    require(hash(api, textures[0].Get()) == 0, "unwritten texture hash must be empty");
    fill(textures[0].Get());
    textures[0]->SetLOD(1);
    require(textures[0]->GetLOD() == 1 && textures[0]->GetLevelCount() == 11, "LOD/mip metadata");
    ComPtr<IDirect3DSurface9> surface;
    check(textures[0]->GetSurfaceLevel(0, &surface), "metadata surface");
    D3DSURFACE_DESC desc{}; check(surface->GetDesc(&desc), "surface description");
    require(desc.Width == 1024 && desc.Height == 1024 && desc.Pool == D3DPOOL_MANAGED, "surface metadata changed");
    D3DLOCKED_RECT data{}; check(surface->LockRect(&data, nullptr, D3DLOCK_READONLY), "CPU readback");
    require(*static_cast<std::uint32_t*>(data.pBits) == color(0), "CPU contents changed");
    check(surface->UnlockRect(), "CPU readback unlock");
    const auto cpu = textureBytes(api);
    if (deferred) { require(created == before && cpu == before, "metadata/CPU access allocated a managed GPU image"); }
    else { require(created > before, "eager control did not allocate"); }
    textures[0]->PreLoad();
    const auto preloaded = textureBytes(api);
    require(preloaded > before, "PreLoad did not allocate");
    const auto firstHash = hash(api, textures[0].Get());
    require(firstHash != 0, "PreLoad did not publish the original texture hash");
    const auto pixel = draw(device.Get(), textures[0].Get());
    require(pixel == (color(1) & 0xffffff), "first draw/LOD pixels changed");
    RECT region{0, 0, 16, 16}; check(textures[0]->LockRect(0, &data, &region, 0), "partial write");
    *static_cast<std::uint32_t*>(data.pBits) ^= 0x00010101;
    check(textures[0]->UnlockRect(0), "partial write unlock");
    require(draw(device.Get(), textures[0].Get()) == pixel, "unmodified mip changed after partial write");
    const auto changedHash = hash(api, textures[0].Get());
    require(changedHash != firstHash && changedHash != 0, "partial write hash was not refreshed");
    // A separate unused managed texture must also become valid on its first draw, without PreLoad.
    fill(textures[1].Get());
    require(draw(device.Get(), textures[1].Get()) == (color(0) & 0xffffff), "first-use upload pixels changed");
    const auto drawHash = hash(api, textures[1].Get());
    require(drawHash == firstHash, "LOD changed texture identity or first-draw hash differs");
    require(draw(device.Get(), textures[3].Get()) == 0, "unwritten managed image lost zero initialization");
    const auto used = textureBytes(api);
    ComPtr<IDirect3DTexture9> normal, system;
    const auto beforeDefault = textureBytes(api);
    check(device->CreateTexture(128, 128, 1, 0, D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT, &normal, nullptr), "default texture");
    const auto defaultBytes = textureBytes(api);
    require(defaultBytes > beforeDefault, "default-pool allocation was deferred");
    check(device->CreateTexture(128, 128, 1, 0, D3DFMT_A8R8G8B8, D3DPOOL_SYSTEMMEM, &system, nullptr), "system texture");
    require(textureBytes(api) == defaultBytes, "system memory got a GPU image");
    std::uint64_t systemHash = 0;
    require(api.dxvk_GetTextureHash(system.Get(), &systemHash) != REMIXAPI_ERROR_CODE_SUCCESS,
      "system-memory hash API result changed");
    ComPtr<IDirect3DCubeTexture9> cube;
    check(device->CreateCubeTexture(64, 1, 0, D3DFMT_A8R8G8B8, D3DPOOL_MANAGED, &cube, nullptr), "managed cube");
    require(textureBytes(api) > defaultBytes, "cube allocation was deferred");
    ComPtr<IDirect3DTexture9> invalid;
    require(device->CreateTexture(64, 64, 1, D3DUSAGE_DYNAMIC, D3DFMT_A8R8G8B8,
      D3DPOOL_MANAGED, &invalid, nullptr) == D3DERR_INVALIDCALL, "invalid managed/dynamic combination changed");
    std::printf("{\"game_mode\":%s,\"deferred\":%s,\"created_bytes\":%llu,\"cpu_bytes\":%llu,\"preloaded_bytes\":%llu,\"used_bytes\":%llu,"
      "\"hash_preload\":\"0x%016llx\",\"hash_write\":\"0x%016llx\",\"hash_draw\":\"0x%016llx\",\"pixel_rgb\":%u}\n",
      gameMode ? "true" : "false", deferred ? "true" : "false", created-before, cpu-before, preloaded-before, used-before,
      firstHash, changedHash, drawHash, pixel);
    check(device->SetTexture(0, nullptr), "unbind for shutdown");
    invalid.Reset(); cube.Reset(); system.Reset(); normal.Reset(); surface.Reset();
    for (auto& texture : textures) { texture.Reset(); }
    // The fork's Shutdown drains its registered objects' public references itself.
    // Detach these final smart pointers so their destructors cannot release the drained objects.
    device.Detach(); d3d.Detach();
    apiCheck(api.Shutdown(), "Remix shutdown");
    DestroyWindow(window);
    return 0;
  } catch (const std::exception& error) {
    std::fprintf(stderr, "managed texture probe: %s\n", error.what()); return 1;
  }
}
