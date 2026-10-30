#include "nl/session.h"

#include "nl/fs.h"
#include "nl/json.h"
#include "nl/manifest.h"
#include "nl/paths.h"

#include <algorithm>

namespace nl::session {
namespace {

std::string lower(std::string_view text) { return paths::fold(text); }

bool has(const Values& values, std::string_view name) {
  return std::any_of(values.begin(), values.end(), [&](const auto& item) { return lower(item.first) == lower(name); });
}

const std::string* value_of(const Values& values, std::string_view name) {
  const auto found = std::find_if(values.begin(), values.end(), [&](const auto& item) { return lower(item.first) == lower(name); });
  return found == values.end() ? nullptr : &found->second;
}

std::string object(const Values& values) {
  std::string out = "{";
  for (std::size_t i = 0; i < values.size(); ++i) {
    out += (i ? ",\n    " : "\n    ") + json::quote(values[i].first) + ": " + json::quote(values[i].second);
  }
  return out + (values.empty() ? "}" : "\n  }");
}

// Recorded from config.cfg or a manifest: names are checked; values are restored inside quotes, so
// only quotes and line breaks would be a problem.
Values read_values(const json::Value& from, const char* what) {
  Values out;
  for (const auto& [name, value] : from.as_object(what)) {
    const std::string& text = value.as_string("session record value");
    if (!manifest::valid_cvar_name(name) || text.size() > 256 ||
        std::any_of(text.begin(), text.end(), [](char c) { return c == '"' || c == '\n' || c == '\r' || c == '\0'; })) {
      throw Error("session record: invalid entry \"" + name + "\"");
    }
    out.emplace_back(name, text);
  }
  return out;
}

}  // namespace

std::map<std::string, std::string> parse_config(std::string_view text) {
  std::map<std::string, std::string> out;
  std::size_t at = 0;
  while (at < text.size()) {
    std::size_t end = text.find('\n', at);
    if (end == std::string_view::npos) end = text.size();
    std::string_view line = text.substr(at, end - at);
    at = end + 1;
    while (!line.empty() && (line.back() == '\r' || line.back() == ' ' || line.back() == '\t')) line.remove_suffix(1);
    while (!line.empty() && (line.front() == ' ' || line.front() == '\t')) line.remove_prefix(1);
    if (line.empty() || line.substr(0, 2) == "//") continue;
    const std::size_t space = line.find_first_of(" \t");
    if (space == std::string_view::npos) continue;
    const std::string_view name = line.substr(0, space);
    std::string_view rest = line.substr(space + 1);
    while (!rest.empty() && (rest.front() == ' ' || rest.front() == '\t')) rest.remove_prefix(1);
    if (!manifest::valid_cvar_name(name)) continue;  // bind "x" "y" and the like are skipped by the caller's lookups
    std::string value;
    if (!rest.empty() && rest.front() == '"') {
      const std::size_t close = rest.find('"', 1);
      if (close == std::string_view::npos) continue;
      value = std::string(rest.substr(1, close - 1));
    } else {
      value = std::string(rest.substr(0, rest.find_first_of(" \t")));
    }
    out[lower(name)] = value;
  }
  return out;
}

std::string serialize(const Record& record) {
  std::string out = "{\n  \"schema\": 2,\n  \"restore_issued\": ";
  out += record.restore_issued ? "true" : "false";
  out += ",\n  \"values\": " + object(record.values);
  out += ",\n  \"session_values\": " + object(record.session_values) + "\n}\n";
  return out;
}

Record parse_record(std::string_view json_text) {
  try {
    const json::Value root = json::parse(json_text);
    const json::Value* schema = root.find("schema");
    const std::int64_t version = schema ? schema->as_int("schema") : 0;
    if (version != 1 && version != 2) throw Error("session record: schema must be 1 or 2");
    for (const auto& [key, value] : root.as_object("session record")) {
      (void)value;
      if (key != "schema" && key != "restore_issued" && key != "values" && (version == 1 || key != "session_values")) {
        throw Error("session record: unknown key \"" + key + "\"");
      }
    }
    Record record;
    if (const json::Value* issued = root.find("restore_issued")) record.restore_issued = issued->as_bool("restore_issued");
    if (const json::Value* values = root.find("values")) record.values = read_values(*values, "values");
    if (const json::Value* values = root.find("session_values")) record.session_values = read_values(*values, "session_values");
    return record;
  } catch (const json::Error& error) {
    throw Error(std::string("session record: ") + error.what());
  }
}

Plan plan(bool rtx_session, const Values& cvars, const std::optional<Record>& record,
          const std::map<std::string, std::string>& config) {
  Plan p;
  std::optional<Record> current = record;
  if (current && current->restore_issued) {
    // A start without RTX has put the recorded values back already; the game archived them when
    // it quit (or the user changed them since, which is theirs to keep). Start over.
    p.drop_record = true;
    current.reset();
  }
  if (rtx_session && !cvars.empty()) {
    p.record = current ? current->values : Values{};
    p.record_session = current ? current->session_values : Values{};
    for (const auto& [name, value] : cvars) {
      if (!has(p.record, name)) {  // else recorded before an earlier RTX session changed it
        if (const auto found = config.find(lower(name)); found != config.end() && !std::any_of(found->second.begin(), found->second.end(), [](char c) {
              return c == '"' || c == '\n' || c == '\r';
            })) {
          p.record.emplace_back(name, found->second);
        }
      }
      // What this session sets, so the restore can tell the user's later changes from ours.
      if (has(p.record, name)) {
        p.record_session.erase(std::remove_if(p.record_session.begin(), p.record_session.end(),
                                              [&](const auto& item) { return lower(item.first) == lower(name); }),
                               p.record_session.end());
        p.record_session.emplace_back(name, value);
      }
    }
    p.write_session = true;
    p.session = cvars;
    p.exec_args = {"+exec", "nativeloader_session.cfg"};
  } else if (!rtx_session && current && !current->values.empty()) {
    for (const auto& [name, recorded] : current->values) {
      const auto found = config.find(lower(name));
      if (found != config.end()) {
        if (found->second == recorded) continue;  // already the user's value
        const std::string* set = value_of(current->session_values, name);
        if (!set) set = value_of(cvars, name);
        if (set && found->second != *set) continue;  // changed since the RTX session: the user's own
      }
      p.restore.emplace_back(name, recorded);
    }
    if (!p.restore.empty()) {
      p.record = current->values;
      p.record_session = current->session_values;
      p.write_restore = true;
      p.exec_args = {"+exec", "nativeloader_restore.cfg"};
    }
    // Nothing left to put back: the record is done with (p.record stays empty).
  } else if (current) {
    p.record = current->values;
    p.record_session = current->session_values;
  }
  return p;
}

std::string cfg_text(const Values& values, std::string_view purpose) {
  std::string out(kHeader);
  out += " (";
  out += purpose;
  out += "). Do not edit: it is rewritten at every start that needs it.\n";
  for (const auto& [name, value] : values) out += name + " \"" + value + "\"\n";
  return out;
}

bool ours_or_absent(const std::filesystem::path& path) {
  const auto info = fs::stat(path);
  if (!info.exists) return true;
  if (info.directory || info.link) return false;
  const std::string head = fs::read_file(path, 4096).substr(0, kHeader.size());
  return head == kHeader;
}

std::vector<std::string> hidden_addons(const journal::Generation& generation) {
  constexpr std::string_view prefix = "garrysmod/addons/";
  std::vector<std::string> names;
  for (const auto& package : generation.packages) {
    if (!package.requires_remix) continue;
    for (const auto& file : generation.files) {
      if (file.package != package.id) continue;
      const std::string folded = paths::fold(file.path);
      if (folded.compare(0, prefix.size(), prefix) != 0) continue;
      const std::size_t slash = folded.find('/', prefix.size());
      if (slash == std::string::npos) continue;  // the area holds folders only
      names.push_back(folded.substr(prefix.size(), slash - prefix.size()));
    }
  }
  std::sort(names.begin(), names.end());
  names.erase(std::unique(names.begin(), names.end()), names.end());
  return names;
}

std::vector<manifest::ModuleDependency> module_dependencies(const journal::Generation& generation) {
  std::vector<manifest::ModuleDependency> out;
  for (const auto& package : generation.packages) {
    for (const auto& dependency : package.module_dependencies) {
      const std::string module = paths::fold(dependency.module);
      auto it = std::find_if(out.begin(), out.end(), [&](const manifest::ModuleDependency& d) { return paths::fold(d.module) == module; });
      if (it == out.end()) it = out.insert(out.end(), manifest::ModuleDependency{dependency.module, {}});
      for (const auto& first : dependency.load_first) {
        const bool listed = std::any_of(it->load_first.begin(), it->load_first.end(),
                                        [&](const std::string& f) { return paths::fold(f) == paths::fold(first); });
        if (!listed) it->load_first.push_back(first);
      }
    }
  }
  return out;
}

std::vector<std::string> deployed_files(const journal::Generation& generation, const std::filesystem::path& root,
                                        const std::vector<std::string>& files, std::vector<std::string>& notes) {
  std::vector<std::string> out;
  for (const std::string& file : files) {
    const std::string key = paths::fold(file);
    const auto record = std::find_if(generation.files.begin(), generation.files.end(),
                                     [&](const journal::File& f) { return paths::fold(f.path) == key; });
    bool as_deployed = false;
    if (record != generation.files.end()) {
      try {
        fs::refuse_links(root, record->path);
        const fs::Stat s = fs::stat(fs::join(root, record->path));
        as_deployed = s.exists && !s.directory && !s.link && s.size == record->size && s.mtime == record->mtime;
      } catch (const fs::Error&) {
        as_deployed = false;
      }
    }
    if (as_deployed) {
      out.push_back(file);
    } else {
      notes.push_back(file + ": not loaded before its module, because " +
                      (record == generation.files.end() ? std::string("the loader did not deploy it")
                                                        : std::string("it is missing or changed since the loader deployed it")));
    }
  }
  return out;
}

}  // namespace nl::session
