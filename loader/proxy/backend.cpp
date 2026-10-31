#include "backend.h"
#include "nl/cmdline.h"
#include <vector>

namespace nl::proxy::backend {
namespace {
bool equal(std::wstring_view a, std::wstring_view b) {
  if (a.size() != b.size()) return false;
  for (std::size_t i = 0; i < a.size(); ++i) {
    const auto lower = [](wchar_t c) { return c >= L'A' && c <= L'Z' ? c + (L'a' - L'A') : c; };
    if (lower(a[i]) != lower(b[i])) return false;
  }
  return true;
}
struct Edit { std::size_t begin, end; std::wstring replacement; };
}  // namespace

Selection select(std::wstring_view command_line, bool rtx_active) {
  Selection result{std::wstring(command_line)};
  if (!rtx_active) return result;
  const auto args = cmdline::argument_spans(command_line);
  std::vector<Edit> edits;
  constexpr std::wstring_view option = L"-shaderapi";
  for (std::size_t i = 1; i < args.size(); ++i) {
    const auto& arg = args[i];
    if (arg.value.size() > option.size() && arg.value[option.size()] == L'=' &&
        equal(std::wstring_view(arg.value).substr(0, option.size()), option)) {
      ++result.explicit_choices;
      edits.push_back({arg.begin, arg.end, L"-shaderapi shaderapidx9"});
    } else if (equal(arg.value, option)) {
      ++result.explicit_choices;
      edits.push_back({arg.begin, arg.end, std::wstring(option)});
      if (i + 1 < args.size() && (args[i + 1].value.empty() ||
          (args[i + 1].value.front() != L'-' && args[i + 1].value.front() != L'+'))) {
        const auto& value = args[++i];
        edits.push_back({value.begin, value.end, L"shaderapidx9"});
      } else {
        // A missing operand must not consume the next launch switch or console command.
        edits.push_back({arg.end, arg.end, L" shaderapidx9"});
      }
    }
  }
  // Reverse order retains the original offsets. Insertions at an option's end precede its rewrite.
  for (auto it = edits.rbegin(); it != edits.rend(); ++it)
    result.line.replace(it->begin, it->end - it->begin, it->replacement);
  result.changed = result.line != command_line;
  return result;
}

}  // namespace nl::proxy::backend
