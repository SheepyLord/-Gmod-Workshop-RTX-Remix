// The loading window (ADR 0128): when it shows, what it says in each catalog language, and its lifecycle.
#include "exit_report.h"
#include "loading.h"
#include "nl_test.h"
#include <windows.h>
#include <array>
#include <string>

namespace l = nl::proxy::loading;
namespace {
constexpr std::uint64_t kMiB = std::uint64_t{1} << 20;
constexpr std::uint64_t kGiB = std::uint64_t{1} << 30;

// This process's loading window, if one is open (never another process's).
HWND loading_window() {
  HWND found = nullptr;
  while ((found = FindWindowExW(nullptr, found, l::kClassName, nullptr)) != nullptr) {
    DWORD process = 0;
    GetWindowThreadProcessId(found, &process);
    if (process == GetCurrentProcessId()) return found;
  }
  return nullptr;
}

HWND wait_for_window(DWORD milliseconds) {
  const ULONGLONG until = GetTickCount64() + milliseconds;
  while (GetTickCount64() < until) {
    if (HWND window = loading_window()) return window;
    Sleep(20);
  }
  return nullptr;
}

// Waits for the window thread while this thread pumps its own messages, as the game's thread does.
bool wait_pumping(DWORD milliseconds) {
  const ULONGLONG until = GetTickCount64() + milliseconds;
  while (GetTickCount64() < until) {
    if (l::wait(10)) return true;
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
  }
  return l::wait(0);
}

// CPU time this process used, in milliseconds.
std::uint64_t process_cpu_ms() {
  FILETIME created{}, exited{}, kernel{}, user{};
  GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user);
  const auto ticks = [](const FILETIME& f) { return (std::uint64_t{f.dwHighDateTime} << 32) | f.dwLowDateTime; };
  return (ticks(kernel) + ticks(user)) / 10000;
}

// A visible window of this process, standing in for the game's.
HWND game_window() {
  WNDCLASSEXW cls{};
  cls.cbSize = sizeof(cls);
  cls.lpfnWndProc = DefWindowProcW;
  cls.hInstance = GetModuleHandleW(nullptr);
  cls.lpszClassName = L"NativeLoaderTestGameWindow";
  RegisterClassExW(&cls);
  HWND window = CreateWindowExW(0, cls.lpszClassName, L"game", WS_OVERLAPPEDWINDOW, 0, 0, 200, 120, nullptr, nullptr,
                                cls.hInstance, nullptr);
  // A test runner can start this process hidden, and Windows then applies that to its first ordinary
  // window's first ShowWindow; SetWindowPos is not subject to it.
  if (window) SetWindowPos(window, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
  return window;
}
}  // namespace

TEST_CASE("loading window: the environment chooses never, always or automatic") {
  for (const char* off : {"0", "off", "OFF", "false", "no"}) CHECK(l::mode(off) == l::Mode::off);
  CHECK(l::mode("always") == l::Mode::always);
  CHECK(l::mode("Always") == l::Mode::always);
  for (const char* automatic : {"", "1", "on", "yes", "sometimes"}) CHECK(l::mode(automatic) == l::Mode::automatic);
}

TEST_CASE("loading window: shows for a large unpack or a slow start, never for an ordinary start") {
  CHECK(!l::should_show(l::Mode::off, 600000, 4 * kGiB));
  CHECK(l::should_show(l::Mode::always, 0, 0));
  // Ordinary starts take well under a second with nothing to unpack (R22: 34-590 ms in the PoC).
  CHECK(!l::should_show(l::Mode::automatic, 600, 0));
  CHECK(!l::should_show(l::Mode::automatic, 2999, 0));
  CHECK(l::should_show(l::Mode::automatic, 3000, 0));
  CHECK(!l::should_show(l::Mode::automatic, 399, 2 * kGiB));
  CHECK(l::should_show(l::Mode::automatic, 400, 2 * kGiB));
  CHECK(l::should_show(l::Mode::automatic, 400, 64 * kMiB));
  CHECK(!l::should_show(l::Mode::automatic, 1000, 64 * kMiB - 1));
}

TEST_CASE("loading window: percent reaches 100 only at the end and never overflows") {
  CHECK(l::percent(0, 0) == 0);
  CHECK(l::percent(5, 0) == 0);
  CHECK(l::percent(0, 100) == 0);
  CHECK(l::percent(50, 100) == 50);
  CHECK(l::percent(999, 1000) == 99);
  CHECK(l::percent(1000, 1000) == 100);
  CHECK(l::percent(2000, 1000) == 100);
  CHECK(l::percent(std::uint64_t{1} << 62, std::uint64_t{1} << 63) == 50);
  CHECK(l::percent(~std::uint64_t{0} - 1, ~std::uint64_t{0}) == 99);
}

TEST_CASE("loading window: every catalog language has every label, with the placeholders intact") {
  for (const char* language : {"en", "zh-CN", "zh-TW", "ja", "ko", "fr", "ru"}) {
    const auto text = l::catalog(language);
    for (const auto* value : {&text.title, &text.heading, &text.body, &text.checking, &text.unpacking, &text.placing,
                              &text.starting, &text.megabytes, &text.gigabytes, &text.decimal})
      CHECK(!value->empty());
    CHECK(text.unpacking.find("{done}") != std::string::npos);
    CHECK(text.unpacking.find("{total}") != std::string::npos);
    CHECK(text.unpacking.find("{percent}") != std::string::npos);
  }
  CHECK(l::catalog("de").heading == l::catalog("en").heading);
  CHECK(l::catalog("zh-CN").heading != l::catalog("en").heading);
}

TEST_CASE("loading window: sizes in binary units, rounded down, with the language's units and decimal mark") {
  const auto en = l::catalog("en");
  CHECK(l::size_text(en, 0) == "0 MB");
  CHECK(l::size_text(en, 850 * kMiB + 1000) == "850 MB");
  CHECK(l::size_text(en, kGiB - 1) == "1023 MB");
  CHECK(l::size_text(en, kGiB) == "1.0 GB");
  CHECK(l::size_text(en, kGiB + kGiB / 4) == "1.2 GB");
  CHECK(l::size_text(en, 2 * kGiB + kGiB / 10 * 9 + 5) == "2.9 GB");
  CHECK(l::size_text(l::catalog("fr"), kGiB + kGiB / 4) == "1,2 Go");
  CHECK(l::size_text(l::catalog("ru"), 300 * kMiB) == "300 \xD0\x9C\xD0\x91");  // "300 МБ"
}

TEST_CASE("loading window: the status line follows the deployer's phase") {
  using P = nl::deploy::Progress;
  const auto en = l::catalog("en");
  CHECK(l::status_text(en, P::idle, 0, 0) == en.checking);
  CHECK(l::status_text(en, P::checking, 0, 0) == en.checking);
  CHECK(l::status_text(en, P::unpacking, 0, 0) == en.checking);  // nothing known to unpack yet
  CHECK(l::status_text(en, P::unpacking, 512 * kMiB, 2 * kGiB) == "Unpacking files: 512 MB of 2.0 GB (25%)");
  CHECK(l::status_text(en, P::unpacking, 3 * kGiB, 2 * kGiB) == "Unpacking files: 2.0 GB of 2.0 GB (100%)");
  CHECK(l::status_text(en, P::placing, 2 * kGiB, 2 * kGiB) == en.placing);
  CHECK(l::status_text(en, P::starting, 2 * kGiB, 2 * kGiB) == en.starting);
  const auto zh = l::catalog("zh-CN");
  const auto line = l::status_text(zh, P::unpacking, kGiB, 2 * kGiB);
  CHECK(line.find("1.0 GB") != std::string::npos);
  CHECK(line.find("50%") != std::string::npos);
}

TEST_CASE("loading window: Steam's language for the game comes between gmod_language and Windows") {
  namespace r = nl::proxy::exit_report;
  const char* manifest =
      "\"AppState\"\n{\n\t\"appid\"\t\t\"4000\"\n\t\"UserConfig\"\n\t{\n\t\t\"language\"\t\t\"schinese\"\n\t}\n"
      "\t\"MountedConfig\"\n\t{\n\t\t\"language\"\t\t\"english\"\n\t}\n}\n";
  CHECK(r::app_language(manifest) == "schinese");
  CHECK(r::app_language("\"AppState\"\n{\n\t\"appid\"\t\"4000\"\n}\n").empty());
  CHECK(r::app_language("{ unbalanced").empty());
  CHECK(r::app_language("").empty());
  // observer::language passes Steam's language in Windows' place when it has one.
  CHECK(r::language({}, {}, r::app_language(manifest)) == "zh-CN");
  CHECK(r::language("gmod_language \"ko\"\n", {}, r::app_language(manifest)) == "ko");
  CHECK(r::language({}, "ja", r::app_language(manifest)) == "ja");
}

TEST_CASE("loading window: opens, then closes when the game's window appears") {
  REQUIRE(l::reset_for_tests());
  nl::deploy::Progress progress;
  progress.phase.store(nl::deploy::Progress::unpacking);
  progress.total.store(2 * kGiB);
  progress.done.store(kGiB);
  l::start("en", &progress, l::Mode::always, 20000);
  HWND window = wait_for_window(5000);
  REQUIRE(window != nullptr);
  CHECK(IsWindowVisible(window));
  CHECK((GetWindowLongPtrW(window, GWL_EXSTYLE) & WS_EX_NOACTIVATE) != 0);
  CHECK(GetForegroundWindow() != window);
  wchar_t title[128]{};
  GetWindowTextW(window, title, 128);
  // Not "Garry's Mod": tools find the game's window by that title (R22 QA).
  CHECK(std::wstring(title) == L"RTX Remix");
  CHECK(l::ended() == l::Ended::running);
  CHECK(l::note().find("loading window shown") == 0);
  // An open window sleeps between redraws: a second of it costs a few milliseconds, not a core
  // (R22: redrawing on every pass kept paint input pending and the loop spinning).
  const auto cpu = process_cpu_ms();
  Sleep(1000);
  CHECK(process_cpu_ms() - cpu < 250);
  progress.phase.store(nl::deploy::Progress::starting);
  l::finish();
  Sleep(300);
  CHECK(loading_window() != nullptr);  // start-up is over, but the game has no window yet
  HWND game = game_window();
  REQUIRE(game != nullptr);
  REQUIRE(IsWindowVisible(game));
  CHECK(wait_pumping(5000));
  CHECK(l::ended() == l::Ended::game_window);
  CHECK(loading_window() == nullptr);
  DestroyWindow(game);
  CHECK(l::reset_for_tests());
}

TEST_CASE("loading window: an open window gives up after the wait when the game shows none") {
  REQUIRE(l::reset_for_tests());
  nl::deploy::Progress progress;
  l::start("zh-CN", &progress, l::Mode::always, 600);
  REQUIRE(wait_for_window(5000) != nullptr);
  l::finish();
  CHECK(l::wait(5000));
  CHECK(l::ended() == l::Ended::timed_out);
  CHECK(loading_window() == nullptr);
  CHECK(l::reset_for_tests());
}

TEST_CASE("loading window: a quick start with nothing to unpack never opens it") {
  REQUIRE(l::reset_for_tests());
  nl::deploy::Progress progress;
  progress.phase.store(nl::deploy::Progress::checking);
  progress.total.store(10 * kMiB);
  l::start("en", &progress, l::Mode::automatic);
  Sleep(600);  // past the grace period, but far below the threshold and the slow-start time
  CHECK(loading_window() == nullptr);
  l::finish();
  CHECK(l::wait(5000));
  CHECK(l::ended() == l::Ended::not_shown);
  CHECK(l::note().find("not needed") != std::string::npos);
  CHECK(l::reset_for_tests());
  l::start("en", &progress, l::Mode::off);
  CHECK(l::note().find("off") != std::string::npos);
  CHECK(l::reset_for_tests());
}
