#include "telemetry.h"
#include "nl/memory.h"
#include <windows.h>
#include <memory>

namespace nl::proxy::telemetry {
namespace {
struct Context { std::filesystem::path root; bool history; HMODULE module; };
DWORD WINAPI worker(void* pointer) noexcept {
  HMODULE module = nullptr;
  {
    std::unique_ptr<Context> context(static_cast<Context*>(pointer));
    module = context->module;
    SetThreadPriority(GetCurrentThread(), THREAD_MODE_BACKGROUND_BEGIN);
    try {
      memory::Sampler sampler(context->history);
      const auto token = memory::process_token();
      bool history = context->history;
      for (;;) {
        const auto sample = sampler.query(history);
        try { memory::write_commit(context->root, sample, token); }
        catch (...) { OutputDebugStringW(L"Native Loader: menu memory snapshot unavailable.\n"); }
        if (history) {
          try { memory::append(context->root, sample); }
          catch (...) {
            // Preserve a changed/locked log and avoid repeating an expensive failure every ten seconds.
            history = false;
            OutputDebugStringW(L"Native Loader: memory history stopped; existing files were kept.\n");
          }
        }
        Sleep(memory::kIntervalMs);
      }
    } catch (...) { OutputDebugStringW(L"Native Loader: memory diagnostics worker stopped.\n"); }
  }
  // Destruct C++/DXGI state before dropping the reference. No join or work in DllMain.
  FreeLibraryAndExitThread(module, 0);
}
}  // namespace
std::string start(const std::filesystem::path& root, bool history) noexcept {
  HMODULE module = nullptr;
  try {
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, reinterpret_cast<LPCWSTR>(&worker), &module))
      return "memory diagnostics worker: cannot retain bootstrap";
    auto context = std::make_unique<Context>(Context{root, history, module});
    const auto thread = CreateThread(nullptr, 0, worker, context.get(), 0, nullptr);
    if (!thread) { FreeLibrary(module); return "memory diagnostics worker: cannot create thread"; }
    context.release();
    CloseHandle(thread);
    return {};
  } catch (...) {
    if (module) FreeLibrary(module);
    return "memory diagnostics worker: cannot allocate context";
  }
}
}  // namespace nl::proxy::telemetry
