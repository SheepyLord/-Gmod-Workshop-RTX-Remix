#include "nl/planner.h"

#include "nl/content.h"
#include "nl/paths.h"

#include <exception>

namespace nl::planner {

namespace {

std::string describe(const discovery::Candidate& c) {
  return std::string(discovery::source_name(c.source)) + " \"" + c.label + "\"";
}

}  // namespace

std::vector<Considered> consider(const std::vector<discovery::Candidate>& candidates) {
  std::vector<Considered> out;
  for (const discovery::Candidate& c : candidates) {
    Considered item{c, nullptr, c.problem};
    if (item.problem.empty()) {
      try {
        auto contents = c.source == discovery::Source::dev_folder ? package::open_folder(c.location)
                                                                  : package::open_archive(c.location);
        item.package = std::make_shared<const package::Package>(package::load(std::move(contents)));
      } catch (const std::exception& e) {
        item.problem = e.what();
      }
    }
    out.push_back(std::move(item));
  }
  return out;
}

const Decision* Plan::runtime() const {
  for (const Decision& d : decisions) {
    if (d.active && d.item.package && d.item.package->manifest.has(manifest::Kind::remix_runtime)) return &d;
  }
  return nullptr;
}

Plan make_plan(const std::vector<Considered>& considered, const config::Config& config, const manifest::Version& loader) {
  Plan plan;
  for (const Considered& item : considered) {
    Decision d{item, false, {}, false};
    const auto skip = [&](std::string reason) {
      d.reason = std::move(reason);
      plan.decisions.push_back(std::move(d));
    };
    if (!config.enabled) {
      skip("the loader is disabled in native-loader/config.json");
      continue;
    }
    if (!item.problem.empty() || !item.package) {
      skip(item.problem.empty() ? "not loaded" : item.problem);
      continue;
    }
    const manifest::Manifest& m = item.package->manifest;
    if (item.candidate.content_only) {
      // Found among the subscribed items, not through the allowlist: content only (ADR 0027).
      if (const std::string why = content::problem(m); !why.empty()) {
        skip("not in the allowlist, so it may hold only Remix mods and Lua add-ons, but " + why +
             "; to deploy it, add Workshop item " + item.candidate.label + " to allow.workshop in native-loader/config.json");
        continue;
      }
    }
    if (m.requires_loader && manifest::compare(loader, *m.requires_loader) < 0) {
      skip("needs loader >=" + m.requires_loader->text + "; this is " + loader.text);
      continue;
    }
    const Decision* same_id = nullptr;
    const Decision* other_runtime = nullptr;
    std::string overlap;
    for (const Decision& earlier : plan.decisions) {
      if (!earlier.active) continue;
      const manifest::Manifest& e = earlier.item.package->manifest;
      if (e.id == m.id && !same_id) same_id = &earlier;
      if (e.has(manifest::Kind::remix_runtime) && m.has(manifest::Kind::remix_runtime) && !other_runtime) other_runtime = &earlier;
      for (const manifest::RootFile& mine : m.root_files) {
        for (const manifest::RootFile& theirs : e.root_files) {
          if (overlap.empty() && (paths::within(mine.path, theirs.path) || paths::within(theirs.path, mine.path))) {
            overlap = "root file \"" + mine.path + "\" overlaps \"" + theirs.path + "\" of active package " + e.id;
          }
        }
      }
    }
    if (same_id) {
      skip("shadowed by " + describe(same_id->item.candidate) + ", which provides the same id \"" + m.id + "\"");
      continue;
    }
    if (other_runtime) {
      skip("only one remix-runtime package can be active; " + other_runtime->item.package->manifest.id + " from " +
           describe(other_runtime->item.candidate) + " is");
      continue;
    }
    if (!overlap.empty()) {
      skip(overlap);
      continue;
    }
    d.active = true;
    d.activate_runtime = m.has(manifest::Kind::remix_runtime) && config.remix_enabled;
    if (m.has(manifest::Kind::remix_runtime) && !config.remix_enabled) {
      d.reason = "active, but the runtime is not loaded: remix.enabled is false";
    }
    plan.decisions.push_back(std::move(d));
  }
  return plan;
}

}  // namespace nl::planner
