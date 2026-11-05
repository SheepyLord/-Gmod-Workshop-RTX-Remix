#pragma once
#include "core.hpp"
#include "../dependency_scope.hpp"
#include <map>
namespace props {
// The files a model may name: its own folders only (dependency_scope.hpp, in the runtime
// so that every importer shares the worker's denylist).
using mmd::DependencyScope;
using mmd::setDependencyDenylist;
struct ResolvedTexture { fs::path path; bool repaired=false; };
class TextureResolver {
    fs::path root;
    DependencyScope scope;
    bool indexed=false;
    std::string indexFailure;
    std::vector<fs::path> folders;
    std::map<std::wstring,std::vector<fs::path>> names;
    void index();
public:
    // Static props follow the player's own links inside the model's import root
    // (DependencyScope::Reach::Local); characters in other formats pass Reach::Confined.
    explicit TextureResolver(fs::path directory,DependencyScope::Reach reach=DependencyScope::Reach::Local);
    ResolvedTexture resolve(const std::string& reference);
    // The reference names a file the model may not read as written: a denied place, a
    // network path or one outside the model's import root (for a confined resolver also
    // one through a link out of it). resolve() then looks for its file name instead.
    bool refuses(const std::string& reference) const;
    // Refused only for lying outside the import root (DependencyScope::outside).
    bool outside(const std::string& reference) const {return scope.outside(reference);}
};
}
