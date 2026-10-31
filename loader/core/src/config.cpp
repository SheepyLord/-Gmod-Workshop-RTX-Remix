#include "nl/config.h"

#include "nl/json.h"

#include <algorithm>
#include <fstream>
#include <initializer_list>
#include <set>
#include <system_error>

namespace nl::config {

namespace {

using json::Value;

[[noreturn]] void fail(const std::string& message) {
  throw Error(std::string(kConfigPath) + ": " + message);
}

void only_keys(const Value& object, std::string_view where, std::initializer_list<std::string_view> allowed) {
  for (const auto& [key, value] : object.as_object(where)) {
    if (std::find(allowed.begin(), allowed.end(), key) == allowed.end()) {
      fail("unknown key \"" + key + "\" in " + std::string(where));
    }
  }
}

std::vector<std::string> unique_strings(const Value& list, std::string_view what) {
  std::vector<std::string> out;
  std::set<std::string> seen;
  for (const Value& item : list.as_array(what)) {
    const std::string& text = item.as_string(std::string(what) + " entries");
    if (text.empty()) fail(std::string(what) + " has an empty entry");
    if (!seen.insert(text).second) fail(std::string(what) + " lists \"" + text + "\" twice");
    out.push_back(text);
  }
  return out;
}

}  // namespace

Config parse(std::string_view json_text) {
  Value root;
  try {
    root = json::parse(json_text);
  } catch (const json::Error& e) {
    fail(e.what());
  }
  try {
    if (!root.is_object()) fail("the document must be a JSON object");
    only_keys(root, "the config", {"schema", "enabled", "allow", "remix", "patch_sets", "diagnostics"});
    const Value* schema = root.find("schema");
    if (!schema) fail("missing \"schema\"");
    if (schema->as_int("schema") != kSchema) fail("schema " + std::to_string(schema->as_int()) + " is not supported (expected 1)");

    Config c;
    c.from_file = true;
    if (const Value* enabled = root.find("enabled")) c.enabled = enabled->as_bool("enabled");
    if (const Value* allow = root.find("allow")) {
      only_keys(*allow, "allow", {"workshop", "local", "dev_folders", "subscribed_content"});
      if (const Value* content = allow->find("subscribed_content")) c.subscribed_content = content->as_bool("allow.subscribed_content");
      if (const Value* ids = allow->find("workshop")) {
        for (const Value& id : ids->as_array("allow.workshop")) {
          if (!id.is_string()) fail("allow.workshop ids must be strings, for example \"3600000000\" (large numbers lose digits)");
        }
        c.workshop = unique_strings(*ids, "allow.workshop");
        for (const std::string& id : c.workshop) {
          if (id.size() > 20 || id[0] == '0' || !std::all_of(id.begin(), id.end(), [](char ch) { return ch >= '0' && ch <= '9'; })) {
            fail("allow.workshop id \"" + id + "\" is not a Workshop item id");
          }
        }
      }
      if (const Value* local = allow->find("local")) c.local = unique_strings(*local, "allow.local");
      if (const Value* dev = allow->find("dev_folders")) c.dev_folders = unique_strings(*dev, "allow.dev_folders");
    }
    if (const Value* remix = root.find("remix")) {
      only_keys(*remix, "remix", {"enabled", "reshade", "performance_tier"});
      if (const Value* enabled = remix->find("enabled")) c.remix_enabled = enabled->as_bool("remix.enabled");
      if (const Value* tier = remix->find("performance_tier")) {
        const std::string mode = tier->is_string() ? tier->as_string() : std::string{};
        if (mode == "auto") c.performance_tier = PerformanceTier::automatic;
        else if (mode == "high") c.performance_tier = PerformanceTier::high;
        else if (mode == "medium") c.performance_tier = PerformanceTier::medium;
        else if (mode == "low") c.performance_tier = PerformanceTier::low;
        else c.notes.push_back("remix.performance_tier must be auto, high, medium or low; using auto");
      }
      if (const Value* reshade = remix->find("reshade")) {
        const std::string& mode = reshade->as_string("remix.reshade");
        if (mode == "auto") c.reshade = Reshade::automatic;
        else if (mode == "on") c.reshade = Reshade::on;
        else if (mode == "off") c.reshade = Reshade::off;
        else fail("remix.reshade must be \"auto\", \"on\" or \"off\"");
      }
    }
    if (const Value* diagnostics = root.find("diagnostics")) {
      only_keys(*diagnostics, "diagnostics", {"gpu_crash_dumps"});
      if (const Value* dumps = diagnostics->find("gpu_crash_dumps")) {
        const auto& mode = dumps->as_string("diagnostics.gpu_crash_dumps");
        if (mode == "off") c.gpu_crash_dumps = GpuCrashDumps::off;
        else if (mode == "next_start") c.gpu_crash_dumps = GpuCrashDumps::next_start;
        else if (mode == "always") c.gpu_crash_dumps = GpuCrashDumps::always;
        else fail("diagnostics.gpu_crash_dumps must be \"off\", \"next_start\" or \"always\"");
      }
    }
    if (const Value* patches = root.find("patch_sets")) {
      only_keys(*patches, "patch_sets", {"require_insecure", "allow_rtx_render_patches"});
      if (const Value* insecure = patches->find("require_insecure")) {
        c.patch_sets_require_insecure = insecure->as_bool("patch_sets.require_insecure");
      }
      if (const Value* render = patches->find("allow_rtx_render_patches"))
        c.allow_secure_rtx_render_patches = render->as_bool("patch_sets.allow_rtx_render_patches");
    }
    return c;
  } catch (const json::Error& e) {
    fail(e.what());
  }
}

Config load(const std::filesystem::path& game_root) {
  const std::filesystem::path file = game_root / std::filesystem::path(kConfigPath);
  std::error_code ec;
  if (!std::filesystem::exists(file, ec)) {
    if (ec) fail("cannot check whether it exists: " + ec.message());
    return Config{};
  }
  const auto size = std::filesystem::file_size(file, ec);
  if (ec) fail("cannot read: " + ec.message());
  if (size > (std::uintmax_t{1} << 20)) fail("larger than 1 MiB");
  std::ifstream in(file, std::ios::binary);
  std::string text(static_cast<std::size_t>(size), '\0');
  if (!in.read(text.data(), static_cast<std::streamsize>(text.size()))) fail("cannot read");
  return parse(text);
}

}  // namespace nl::config
