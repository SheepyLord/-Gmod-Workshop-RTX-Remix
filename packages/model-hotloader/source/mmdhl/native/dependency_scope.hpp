#pragma once
#include <filesystem>
#include <functional>
#include <string>
#include <string_view>
#include <vector>
// The files a model may name (external buffers, material libraries, textures). A model
// file is untrusted: what it reads goes into the cache and to other players with the
// model, so a network path, a drive- or root-relative one, an alternate data stream and
// anything the process's denylist names (the worker's FilePolicy), wherever a link
// leads, are never opened. Every model reads only inside its import root (R19, review
// MH-01): its own folder and below it, the tex and textures folders the static prop
// resolver also searches one and two levels up (when textureFolders) and, for a model in
// a Steam Workshop item's folder, that whole item. A reference may use ".." as long as
// it stays there (2.2's references within a model's folders keep working); one that
// climbs out of it, or an absolute path elsewhere, is never opened. A confined scope
// (FBX, glTF and DAE characters, character_import.cpp) also checks where a file really
// is: a link or junction cannot lead out of the root. PMX and PMD characters (assets.cpp)
// and static props (props/import.cpp, props/texture_resolver.cpp) follow a link the
// player made inside the root, as in 2.2 (a downloaded model brings no junction).
// It lives in the runtime so that one denylist serves them all.
namespace mmd {
class DependencyScope {
public:
    using path = std::filesystem::path;
    // Confined: inside the root as written and where the file really is (FBX, glTF and DAE
    // characters, new in 2.3).
    // Local: inside the root as written (PMX and PMD textures, static props); links inside it
    // are followed, but never to a network path, an alternate data stream or, through any
    // link, a place the denylist names. Until R19 Local read anywhere (2.2's reach).
    enum class Reach {Confined,Local};
    DependencyScope(path modelFolder,bool textureFolders,Reach reach=Reach::Confined);
    // The path `reference` (UTF-8, absolute or relative to the model's folder) names,
    // normalized, when that lies in the scope as written; empty otherwise (also for
    // network paths and parts Windows would rewrite, such as a trailing dot).
    path locate(std::string_view reference) const;
    // Whether `reference` is refused only because it lies outside the import root: a plain
    // local path that names somewhere else (for the warning that says so).
    bool outside(std::string_view reference) const;
    // An existing regular file that really lies in the scope and is not denied. Where it
    // really is: the opened file's final path, links resolved, or, where Windows cannot
    // say (some RAM disks, FUSE and cloud drives), a path as written with no link or
    // junction between the scope's folder and the file.
    bool allows(const path& file) const;
    const path& folder() const {return root;}
    // The Steam Workshop item folder (...\workshop\content\<app>\<item>) `folder` lies in, or empty.
    static path workshopItem(const path& folder);
private:
    path root;
    Reach reach;
    std::vector<path> trees;                        // as written (lexical)
    size_t itemTree=0;                              // the Workshop item's index in trees (0: none)
    mutable std::vector<std::wstring> finals;       // where they really are
    mutable bool resolved=false;
    const std::vector<std::wstring>& finalTrees() const;
    // locate's answer, and whether a well-formed reference was refused for lying outside the root.
    path find(std::string_view reference,bool& outsideRoot) const;
    // The model's folder and the Workshop item count as themselves where a link leads to
    // them; a tex or textures folder near the model must not be a link itself.
    bool linkMayLead(size_t tree) const {return tree==0||tree==itemTree;}
};
// Places no model dependency is read from, by final path (the worker sets its FilePolicy).
void setDependencyDenylist(std::function<bool(const std::filesystem::path&)> denied);
// Tests only: act as if Windows could not say where any open file really is.
void simulateUnknownFinalPaths(bool unknown);
}
