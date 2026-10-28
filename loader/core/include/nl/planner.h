#pragma once
// Turning discovered candidates into a plan: which packages are active, and why each other one is
// not. make_plan() is a pure function of its inputs; the rules are in docs/decisions/0006.

#include "nl/config.h"
#include "nl/discovery.h"
#include "nl/manifest.h"
#include "nl/package.h"

#include <memory>
#include <optional>
#include <string>
#include <vector>

namespace nl::planner {

// A candidate after its package was loaded (or failed to load).
struct Considered {
  discovery::Candidate candidate;
  std::shared_ptr<const package::Package> package;  // null if the candidate has a problem
  std::string problem;                              // discovery or load problem; empty if loaded
};

// Loads every usable candidate's package; load failures become problems, never exceptions.
std::vector<Considered> consider(const std::vector<discovery::Candidate>& candidates);

struct Decision {
  Considered item;
  bool active = false;
  std::string reason;             // why it is not active; for an active package, an optional note
  bool activate_runtime = false;  // active remix-runtime package that should be preloaded (M4)
};

struct Plan {
  std::vector<Decision> decisions;  // same order as the candidates
  const Decision* runtime() const;  // the active remix-runtime package, if any
};

// Rules, in order: loader disabled -> nothing; a candidate problem skips it; requires_loader newer
// than `loader` skips it; a package id already active (from a higher-precedence source) is shadowed;
// only the first remix-runtime package is active; a package whose root files overlap an active
// package's is skipped. Runtime activation also needs remix.enabled.
Plan make_plan(const std::vector<Considered>& considered, const config::Config& config, const manifest::Version& loader);

}  // namespace nl::planner
