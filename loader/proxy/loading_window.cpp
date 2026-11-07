// The loading window (ADR 0128): a window of its own thread, with user32 and gdi32 bound at run time
// so that the bootstrap's import table stays KERNEL32-only (tests/check_imports.py). It never blocks
// start-up: start() and finish() only create a thread and set an event.
#include "loading.h"
#include <windows.h>
#include <atomic>
#include <cstring>
#include <cwchar>
#include <iterator>
#include <string>

namespace nl::proxy::loading {
namespace {

// user32 and gdi32 entry points. decltype names the system declarations without importing them.
struct Api {
  HMODULE user32 = nullptr;
  HMODULE gdi32 = nullptr;
  decltype(&::RegisterClassExW) RegisterClassExW = nullptr;
  decltype(&::UnregisterClassW) UnregisterClassW = nullptr;
  decltype(&::CreateWindowExW) CreateWindowExW = nullptr;
  decltype(&::DestroyWindow) DestroyWindow = nullptr;
  decltype(&::DefWindowProcW) DefWindowProcW = nullptr;
  decltype(&::ShowWindow) ShowWindow = nullptr;
  decltype(&::UpdateWindow) UpdateWindow = nullptr;
  decltype(&::InvalidateRect) InvalidateRect = nullptr;
  decltype(&::BeginPaint) BeginPaint = nullptr;
  decltype(&::EndPaint) EndPaint = nullptr;
  decltype(&::GetClientRect) GetClientRect = nullptr;
  decltype(&::FillRect) FillRect = nullptr;
  decltype(&::DrawTextW) DrawTextW = nullptr;
  decltype(&::PeekMessageW) PeekMessageW = nullptr;
  decltype(&::TranslateMessage) TranslateMessage = nullptr;
  decltype(&::DispatchMessageW) DispatchMessageW = nullptr;
  decltype(&::MsgWaitForMultipleObjects) MsgWaitForMultipleObjects = nullptr;
  decltype(&::SystemParametersInfoW) SystemParametersInfoW = nullptr;
  decltype(&::LoadImageW) LoadImageW = nullptr;
  decltype(&::LoadCursorW) LoadCursorW = nullptr;
  decltype(&::EnumWindows) EnumWindows = nullptr;
  decltype(&::GetWindowThreadProcessId) GetWindowThreadProcessId = nullptr;
  decltype(&::IsWindowVisible) IsWindowVisible = nullptr;
  decltype(&::GetDC) GetDC = nullptr;
  decltype(&::ReleaseDC) ReleaseDC = nullptr;
  decltype(&::SetWindowPos) SetWindowPos = nullptr;
  decltype(&::AdjustWindowRectEx) AdjustWindowRectEx = nullptr;
  decltype(&::DestroyIcon) DestroyIcon = nullptr;
  decltype(&::SetTimer) SetTimer = nullptr;
  decltype(&::KillTimer) KillTimer = nullptr;
  // Windows 10 1607 and later; without them the window is DPI-unaware and Windows scales it.
  decltype(&::SetThreadDpiAwarenessContext) SetThreadDpiAwarenessContext = nullptr;
  decltype(&::GetDpiForWindow) GetDpiForWindow = nullptr;
  decltype(&::AdjustWindowRectExForDpi) AdjustWindowRectExForDpi = nullptr;
  decltype(&::CreateFontW) CreateFontW = nullptr;
  decltype(&::DeleteObject) DeleteObject = nullptr;
  decltype(&::SelectObject) SelectObject = nullptr;
  decltype(&::SetBkMode) SetBkMode = nullptr;
  decltype(&::SetTextColor) SetTextColor = nullptr;
  decltype(&::CreateSolidBrush) CreateSolidBrush = nullptr;
  decltype(&::CreateCompatibleDC) CreateCompatibleDC = nullptr;
  decltype(&::CreateCompatibleBitmap) CreateCompatibleBitmap = nullptr;
  decltype(&::BitBlt) BitBlt = nullptr;
  decltype(&::DeleteDC) DeleteDC = nullptr;
};

template <typename T>
bool bind(HMODULE module, const char* name, T& slot) noexcept {
  slot = reinterpret_cast<T>(GetProcAddress(module, name));
  return slot != nullptr;
}

bool bind(Api& api) noexcept {
  // The game loads both anyway; they stay loaded for the process lifetime, like the game's own copies.
  api.user32 = LoadLibraryExW(L"user32.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  api.gdi32 = LoadLibraryExW(L"gdi32.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!api.user32 || !api.gdi32) return false;
  const HMODULE u = api.user32;
  const HMODULE g = api.gdi32;
  bool ok = bind(u, "RegisterClassExW", api.RegisterClassExW) && bind(u, "UnregisterClassW", api.UnregisterClassW) &&
            bind(u, "CreateWindowExW", api.CreateWindowExW) && bind(u, "DestroyWindow", api.DestroyWindow) &&
            bind(u, "DefWindowProcW", api.DefWindowProcW) && bind(u, "ShowWindow", api.ShowWindow) &&
            bind(u, "UpdateWindow", api.UpdateWindow) && bind(u, "InvalidateRect", api.InvalidateRect) &&
            bind(u, "BeginPaint", api.BeginPaint) && bind(u, "EndPaint", api.EndPaint) &&
            bind(u, "GetClientRect", api.GetClientRect) && bind(u, "FillRect", api.FillRect) &&
            bind(u, "DrawTextW", api.DrawTextW) && bind(u, "PeekMessageW", api.PeekMessageW) &&
            bind(u, "TranslateMessage", api.TranslateMessage) && bind(u, "DispatchMessageW", api.DispatchMessageW) &&
            bind(u, "MsgWaitForMultipleObjects", api.MsgWaitForMultipleObjects) &&
            bind(u, "SystemParametersInfoW", api.SystemParametersInfoW) && bind(u, "LoadImageW", api.LoadImageW) &&
            bind(u, "LoadCursorW", api.LoadCursorW) && bind(u, "EnumWindows", api.EnumWindows) &&
            bind(u, "GetWindowThreadProcessId", api.GetWindowThreadProcessId) &&
            bind(u, "IsWindowVisible", api.IsWindowVisible) && bind(u, "GetDC", api.GetDC) &&
            bind(u, "ReleaseDC", api.ReleaseDC) && bind(u, "SetWindowPos", api.SetWindowPos) &&
            bind(u, "AdjustWindowRectEx", api.AdjustWindowRectEx) && bind(u, "DestroyIcon", api.DestroyIcon) &&
            bind(u, "SetTimer", api.SetTimer) && bind(u, "KillTimer", api.KillTimer) &&
            bind(g, "CreateFontW", api.CreateFontW) && bind(g, "DeleteObject", api.DeleteObject) &&
            bind(g, "SelectObject", api.SelectObject) && bind(g, "SetBkMode", api.SetBkMode) &&
            bind(g, "SetTextColor", api.SetTextColor) && bind(g, "CreateSolidBrush", api.CreateSolidBrush) &&
            bind(g, "CreateCompatibleDC", api.CreateCompatibleDC) &&
            bind(g, "CreateCompatibleBitmap", api.CreateCompatibleBitmap) && bind(g, "BitBlt", api.BitBlt) &&
            bind(g, "DeleteDC", api.DeleteDC);
  bind(u, "SetThreadDpiAwarenessContext", api.SetThreadDpiAwarenessContext);
  bind(u, "GetDpiForWindow", api.GetDpiForWindow);
  bind(u, "AdjustWindowRectExForDpi", api.AdjustWindowRectExForDpi);
  return ok;
}

// The shared state is plain data: the thread may outlive start-up, and nothing here has a destructor
// that could run while it does.
struct Shared {
  std::atomic<bool> started{false};
  HANDLE thread = nullptr;
  HANDLE finished = nullptr;  // manual-reset: start-up work is over
  const deploy::Progress* progress = nullptr;
  Mode mode = Mode::automatic;
  std::uint32_t game_wait_ms = kGameWaitMs;
  ULONGLONG began = 0;
  char language[16]{};
  std::atomic<bool> shown{false};
  std::atomic<std::uint64_t> shown_after_ms{0};
  std::atomic<int> ended{static_cast<int>(Ended::running)};
};
Shared g_shared;

std::wstring wide(const std::string& text) {
  if (text.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) return {};
  std::wstring out(static_cast<std::size_t>(size), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), out.data(), size);
  return out;
}

constexpr COLORREF kBackground = RGB(30, 32, 36);
constexpr COLORREF kHeading = RGB(240, 242, 245);
constexpr COLORREF kBody = RGB(196, 201, 208);
constexpr COLORREF kStatus = RGB(160, 166, 174);
constexpr COLORREF kTrack = RGB(58, 62, 68);
constexpr COLORREF kFill = RGB(118, 185, 0);  // NVIDIA green
constexpr int kWidthDip = 560;
constexpr DWORD kStyle = WS_POPUP | WS_CAPTION;  // a title bar without buttons: closing would not stop the work
// A taskbar button, so the game is seen to be starting; never active, so it takes no keyboard focus and
// hands no activation to the game's window (another thread, often busy) when it closes.
constexpr DWORD kExStyle = WS_EX_APPWINDOW | WS_EX_NOACTIVATE;

// The window's own state: one window per process, on one thread.
struct Window {
  Api api;
  Catalog text;
  std::wstring title, heading, body;
  HWND hwnd = nullptr;
  HFONT heading_font = nullptr, body_font = nullptr, status_font = nullptr;
  HICON big_icon = nullptr, small_icon = nullptr;
  HBRUSH background = nullptr, track = nullptr, fill = nullptr;
  UINT dpi = 96;
  int pad = 0, heading_height = 0, body_height = 0, bar_height = 0, status_height = 0;
  unsigned frame = 0;
};
Window* g_window = nullptr;

int scaled(int dip, UINT dpi) { return MulDiv(dip, static_cast<int>(dpi), 96); }

HFONT font(const Api& api, int pixels, int weight) {
  return api.CreateFontW(-pixels, 0, 0, 0, weight, FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                         CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
}

void free_fonts(Window& w) {
  for (HFONT* f : {&w.heading_font, &w.body_font, &w.status_font}) {
    if (*f) w.api.DeleteObject(*f);
    *f = nullptr;
  }
}

// Fonts and heights for the window's DPI; returns the client height for kWidthDip.
int layout(Window& w) {
  free_fonts(w);
  w.heading_font = font(w.api, scaled(22, w.dpi), FW_SEMIBOLD);
  w.body_font = font(w.api, scaled(15, w.dpi), FW_NORMAL);
  w.status_font = font(w.api, scaled(14, w.dpi), FW_NORMAL);
  w.pad = scaled(24, w.dpi);
  w.heading_height = scaled(32, w.dpi);
  w.bar_height = scaled(8, w.dpi);
  w.status_height = scaled(22, w.dpi);
  w.body_height = scaled(60, w.dpi);
  if (const HDC dc = w.api.GetDC(w.hwnd)) {
    const HGDIOBJ old = w.api.SelectObject(dc, w.body_font);
    RECT r{0, 0, scaled(kWidthDip, w.dpi) - 2 * w.pad, 0};
    w.api.DrawTextW(dc, w.body.c_str(), -1, &r, DT_CALCRECT | DT_WORDBREAK | DT_NOPREFIX);
    if (r.bottom > 0) w.body_height = r.bottom;
    w.api.SelectObject(dc, old);
    w.api.ReleaseDC(w.hwnd, dc);
  }
  return w.pad + w.heading_height + scaled(8, w.dpi) + w.body_height + scaled(20, w.dpi) + w.bar_height +
         scaled(10, w.dpi) + w.status_height + w.pad;
}

RECT outer(const Window& w, int client_width, int client_height) {
  RECT r{0, 0, client_width, client_height};
  if (w.api.AdjustWindowRectExForDpi) w.api.AdjustWindowRectExForDpi(&r, kStyle, FALSE, kExStyle, w.dpi);
  else w.api.AdjustWindowRectEx(&r, kStyle, FALSE, kExStyle);
  return r;
}

void paint(Window& w) {
  PAINTSTRUCT ps{};
  const HDC dc = w.api.BeginPaint(w.hwnd, &ps);
  if (!dc) return;
  RECT client{};
  w.api.GetClientRect(w.hwnd, &client);
  const int width = client.right - client.left;
  const int height = client.bottom - client.top;
  const HDC mem = w.api.CreateCompatibleDC(dc);
  const HBITMAP bitmap = mem ? w.api.CreateCompatibleBitmap(dc, width, height) : nullptr;
  if (!mem || !bitmap) {
    if (mem) w.api.DeleteDC(mem);
    w.api.EndPaint(w.hwnd, &ps);
    return;
  }
  const HGDIOBJ old_bitmap = w.api.SelectObject(mem, bitmap);
  w.api.FillRect(mem, &client, w.background);
  w.api.SetBkMode(mem, TRANSPARENT);
  const HGDIOBJ old_font = w.api.SelectObject(mem, w.heading_font);

  int y = w.pad;
  RECT r{w.pad, y, width - w.pad, y + w.heading_height};
  w.api.SetTextColor(mem, kHeading);
  w.api.DrawTextW(mem, w.heading.c_str(), -1, &r, DT_LEFT | DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);
  y += w.heading_height + scaled(8, w.dpi);

  w.api.SelectObject(mem, w.body_font);
  w.api.SetTextColor(mem, kBody);
  r = {w.pad, y, width - w.pad, y + w.body_height};
  w.api.DrawTextW(mem, w.body.c_str(), -1, &r, DT_LEFT | DT_WORDBREAK | DT_NOPREFIX);
  y += w.body_height + scaled(20, w.dpi);

  // The bar: how much is unpacked, or a moving segment while the amount is not known.
  const auto* progress = g_shared.progress;
  const std::uint32_t phase = progress ? progress->phase.load(std::memory_order_relaxed) : deploy::Progress::starting;
  const std::uint64_t total = progress ? progress->total.load(std::memory_order_relaxed) : 0;
  const std::uint64_t done = progress ? progress->done.load(std::memory_order_relaxed) : 0;
  RECT bar{w.pad, y, width - w.pad, y + w.bar_height};
  w.api.FillRect(mem, &bar, w.track);
  const int span = bar.right - bar.left;
  if (phase == deploy::Progress::unpacking && total) {
    RECT filled = bar;
    filled.right = bar.left + static_cast<int>(static_cast<long long>(span) * percent(done, total) / 100);
    if (filled.right > filled.left) w.api.FillRect(mem, &filled, w.fill);
  } else if (span > 0) {
    const int segment = span / 4;
    const int travel = span + segment;
    const int offset = static_cast<int>((w.frame * static_cast<unsigned>(scaled(6, w.dpi))) % static_cast<unsigned>(travel)) - segment;
    RECT moving{bar.left + (offset < 0 ? 0 : offset), bar.top, bar.left + offset + segment, bar.bottom};
    if (moving.right > bar.right) moving.right = bar.right;
    if (moving.right > moving.left) w.api.FillRect(mem, &moving, w.fill);
  }
  y += w.bar_height + scaled(10, w.dpi);

  std::wstring status;
  try {
    status = wide(status_text(w.text, phase, done, total));
  } catch (...) {
  }
  w.api.SelectObject(mem, w.status_font);
  w.api.SetTextColor(mem, kStatus);
  r = {w.pad, y, width - w.pad, y + w.status_height};
  w.api.DrawTextW(mem, status.c_str(), -1, &r, DT_LEFT | DT_SINGLELINE | DT_VCENTER | DT_END_ELLIPSIS | DT_NOPREFIX);

  w.api.BitBlt(dc, 0, 0, width, height, mem, 0, 0, SRCCOPY);
  w.api.SelectObject(mem, old_font);
  w.api.SelectObject(mem, old_bitmap);
  w.api.DeleteObject(bitmap);
  w.api.DeleteDC(mem);
  w.api.EndPaint(w.hwnd, &ps);
}

LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
  Window* w = g_window;
  if (!w) return 0;
  switch (message) {
    case WM_PAINT:
      paint(*w);
      return 0;
    case WM_ERASEBKGND:
      return 1;
    case WM_TIMER:
      ++w->frame;  // the bar's animation and the unpacked amount
      w->api.InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    case WM_CLOSE:
      return 0;  // Alt+F4 would not stop the work; the game opens by itself when it is done
    case WM_DPICHANGED: {
      w->dpi = HIWORD(wparam);
      const int height = layout(*w);
      const RECT size = outer(*w, scaled(kWidthDip, w->dpi), height);
      const auto* suggested = reinterpret_cast<const RECT*>(lparam);
      w->api.SetWindowPos(hwnd, nullptr, suggested->left, suggested->top, size.right - size.left, size.bottom - size.top,
                          SWP_NOZORDER | SWP_NOACTIVATE);
      w->api.InvalidateRect(hwnd, nullptr, FALSE);
      return 0;
    }
    default:
      return w->api.DefWindowProcW(hwnd, message, wparam, lparam);
  }
}

// The executable's own icon, for the taskbar button. A string name is valid only during the callback.
struct IconName {
  LPCWSTR id = nullptr;
  wchar_t text[64]{};
};
BOOL CALLBACK first_icon(HMODULE, LPCWSTR, LPWSTR name, LONG_PTR data) {
  auto& found = *reinterpret_cast<IconName*>(data);
  if (IS_INTRESOURCE(name)) {
    found.id = name;
  } else if (wcslen(name) < std::size(found.text)) {
    wcscpy_s(found.text, name);
    found.id = found.text;
  }
  return FALSE;
}
void load_icons(Window& w) {
  const HMODULE exe = GetModuleHandleW(nullptr);
  IconName name;
  EnumResourceNamesW(exe, RT_GROUP_ICON, first_icon, reinterpret_cast<LONG_PTR>(&name));
  if (!name.id) return;
  w.big_icon = static_cast<HICON>(w.api.LoadImageW(exe, name.id, IMAGE_ICON, scaled(32, w.dpi), scaled(32, w.dpi), LR_DEFAULTCOLOR));
  w.small_icon = static_cast<HICON>(w.api.LoadImageW(exe, name.id, IMAGE_ICON, scaled(16, w.dpi), scaled(16, w.dpi), LR_DEFAULTCOLOR));
}

struct Search {
  const Api* api;
  HWND self;
  DWORD process;
  bool found;
};
BOOL CALLBACK find_game_window(HWND hwnd, LPARAM data) {
  auto& search = *reinterpret_cast<Search*>(data);
  if (hwnd == search.self) return TRUE;
  DWORD process = 0;
  search.api->GetWindowThreadProcessId(hwnd, &process);
  if (process != search.process || !search.api->IsWindowVisible(hwnd)) return TRUE;
  search.found = true;
  return FALSE;
}

std::uint64_t elapsed_ms() { return GetTickCount64() - g_shared.began; }

// Opens the window and runs it until the game's window appears or game_wait_ms pass after finish().
Ended run_window() {
  static Window window;  // one per process; plain storage, never destroyed while the thread may run
  Window& w = window;
  if (!bind(w.api)) return Ended::unavailable;
  // Crisp text at any scaling: per-monitor DPI for this thread's windows only, never the game's.
  if (w.api.SetThreadDpiAwarenessContext) w.api.SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  try {
    w.text = catalog(g_shared.language);
  } catch (...) {
    w.text = Catalog{};
  }
  if (w.text.heading.empty()) w.text.heading = "RTX Remix";
  w.title = wide(w.text.title);
  w.heading = wide(w.text.heading);
  w.body = wide(w.text.body);
  w.background = w.api.CreateSolidBrush(kBackground);
  w.track = w.api.CreateSolidBrush(kTrack);
  w.fill = w.api.CreateSolidBrush(kFill);

  HMODULE self = nullptr;
  GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                     reinterpret_cast<LPCWSTR>(&window_proc), &self);
  load_icons(w);
  WNDCLASSEXW cls{};
  cls.cbSize = sizeof(cls);
  cls.lpfnWndProc = window_proc;
  cls.hInstance = self;
  cls.hCursor = w.api.LoadCursorW(nullptr, IDC_ARROW);
  cls.hIcon = w.big_icon;
  cls.hIconSm = w.small_icon;
  cls.lpszClassName = kClassName;
  g_window = &w;
  if (!w.api.RegisterClassExW(&cls) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return Ended::unavailable;
  w.hwnd = w.api.CreateWindowExW(kExStyle, kClassName, w.title.c_str(), kStyle, CW_USEDEFAULT, CW_USEDEFAULT,
                                 scaled(kWidthDip, 96), 200, nullptr, nullptr, self, nullptr);
  if (!w.hwnd) {
    w.api.UnregisterClassW(kClassName, self);
    return Ended::unavailable;
  }
  w.dpi = w.api.GetDpiForWindow ? w.api.GetDpiForWindow(w.hwnd) : 96;
  if (!w.dpi) w.dpi = 96;
  // A dark title bar to match the window (Windows 10 20H1 and later; elsewhere the light one stays).
  if (const HMODULE dwm = LoadLibraryExW(L"dwmapi.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32)) {
    using SetAttribute = HRESULT(WINAPI*)(HWND, DWORD, LPCVOID, DWORD);
    if (const auto set = reinterpret_cast<SetAttribute>(GetProcAddress(dwm, "DwmSetWindowAttribute"))) {
      const BOOL dark = TRUE;
      set(w.hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &dark, sizeof(dark));
    }
  }
  const int client_height = layout(w);
  const RECT size = outer(w, scaled(kWidthDip, w.dpi), client_height);
  RECT work{0, 0, 1280, 720};
  w.api.SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  const int width = size.right - size.left;
  const int height = size.bottom - size.top;
  w.api.SetWindowPos(w.hwnd, HWND_TOP, work.left + (work.right - work.left - width) / 2,
                     work.top + (work.bottom - work.top - height) / 2, width, height, SWP_NOACTIVATE);
  w.api.ShowWindow(w.hwnd, SW_SHOWNOACTIVATE);
  w.api.UpdateWindow(w.hwnd);
  g_shared.shown_after_ms.store(elapsed_ms());
  g_shared.shown.store(true);

  Ended result = Ended::timed_out;
  bool finished = false;
  ULONGLONG finished_at = 0;
  // Redraws come from a timer: invalidating on every pass would keep paint input pending, and the
  // wait below would return at once forever (R22 found it spinning and missing the end of start-up).
  w.api.SetTimer(w.hwnd, 1, 80, nullptr);
  for (;;) {
    // Sleep until a message or the end of start-up work arrives (after that, only messages and the
    // clock). Which of the two woke it is not trusted: the event is checked on every pass.
    if (finished) w.api.MsgWaitForMultipleObjects(0, nullptr, FALSE, 100, QS_ALLINPUT);
    else w.api.MsgWaitForMultipleObjects(1, &g_shared.finished, FALSE, 100, QS_ALLINPUT);
    MSG message{};
    bool quit = false;
    while (w.api.PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      if (message.message == WM_QUIT) quit = true;
      w.api.TranslateMessage(&message);
      w.api.DispatchMessageW(&message);
    }
    if (quit) break;
    if (!finished && WaitForSingleObject(g_shared.finished, 0) == WAIT_OBJECT_0) {
      finished = true;
      finished_at = GetTickCount64();
    }
    if (finished) {
      Search search{&w.api, w.hwnd, GetCurrentProcessId(), false};
      w.api.EnumWindows(find_game_window, reinterpret_cast<LPARAM>(&search));
      if (search.found) {
        result = Ended::game_window;
        break;
      }
      if (GetTickCount64() - finished_at >= g_shared.game_wait_ms) break;
    }
  }
  w.api.KillTimer(w.hwnd, 1);
  w.api.DestroyWindow(w.hwnd);
  w.hwnd = nullptr;
  w.api.UnregisterClassW(kClassName, self);
  free_fonts(w);
  for (HBRUSH* b : {&w.background, &w.track, &w.fill}) {
    if (*b) w.api.DeleteObject(*b);
    *b = nullptr;
  }
  if (w.big_icon) w.api.DestroyIcon(w.big_icon);
  if (w.small_icon) w.api.DestroyIcon(w.small_icon);
  w.big_icon = w.small_icon = nullptr;
  return result;
}

// Waits until the window is worth showing, then runs it. C++ failures end the thread quietly.
Ended run() noexcept {
  try {
    for (;;) {
      if (WaitForSingleObject(g_shared.finished, 0) == WAIT_OBJECT_0) return Ended::not_shown;
      const std::uint64_t unpack = g_shared.progress ? g_shared.progress->total.load(std::memory_order_relaxed) : 0;
      if (should_show(g_shared.mode, elapsed_ms(), unpack)) return run_window();
      if (WaitForSingleObject(g_shared.finished, 50) == WAIT_OBJECT_0) return Ended::not_shown;
    }
  } catch (...) {
    return Ended::unavailable;
  }
}

// No destructible locals in the SEH frame: a fault in the window ends only this thread.
DWORD WINAPI thread_main(void*) {
  Ended result = Ended::unavailable;
  __try {
    result = run();
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    result = Ended::unavailable;
  }
  g_shared.ended.store(static_cast<int>(result));
  return 0;
}
}  // namespace

void start(std::string_view language, const deploy::Progress* progress, Mode mode, std::uint32_t game_wait_ms) noexcept {
  if (mode == Mode::off || g_shared.started.exchange(true)) return;
  g_shared.progress = progress;
  g_shared.mode = mode;
  g_shared.game_wait_ms = game_wait_ms;
  g_shared.began = GetTickCount64();
  const std::size_t length = language.size() < sizeof(g_shared.language) - 1 ? language.size() : sizeof(g_shared.language) - 1;
  std::memcpy(g_shared.language, language.data(), length);
  g_shared.language[length] = '\0';
  g_shared.finished = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (!g_shared.finished) return;
  g_shared.thread = CreateThread(nullptr, 0, thread_main, nullptr, 0, nullptr);
  if (!g_shared.thread) g_shared.ended.store(static_cast<int>(Ended::unavailable));
}

void finish() noexcept {
  if (g_shared.finished) SetEvent(g_shared.finished);
}

std::string note() {
  if (!g_shared.started.load()) return "loading window off (NATIVE_LOADER_LOADING_WINDOW)";
  if (g_shared.ended.load() == static_cast<int>(Ended::unavailable)) return "loading window unavailable";
  if (!g_shared.shown.load()) return "loading window not needed: nothing large to unpack and start-up was quick";
  return "loading window shown " + std::to_string(g_shared.shown_after_ms.load()) +
         " ms into start-up; it closes when the game's window appears";
}

Ended ended() noexcept { return static_cast<Ended>(g_shared.ended.load()); }

bool wait(std::uint32_t milliseconds) noexcept {
  if (!g_shared.thread) return true;
  return WaitForSingleObject(g_shared.thread, milliseconds) == WAIT_OBJECT_0;
}

bool reset_for_tests() noexcept {
  if (g_shared.thread && WaitForSingleObject(g_shared.thread, 0) != WAIT_OBJECT_0) return false;
  if (g_shared.thread) CloseHandle(g_shared.thread);
  if (g_shared.finished) CloseHandle(g_shared.finished);
  g_shared.thread = nullptr;
  g_shared.finished = nullptr;
  g_shared.progress = nullptr;
  g_shared.shown.store(false);
  g_shared.shown_after_ms.store(0);
  g_shared.ended.store(static_cast<int>(Ended::running));
  g_shared.started.store(false);
  return true;
}

}  // namespace nl::proxy::loading
