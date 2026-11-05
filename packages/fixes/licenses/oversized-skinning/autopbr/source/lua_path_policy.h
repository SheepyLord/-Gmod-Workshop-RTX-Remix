// GPL-2.0, like the rest of the RTX fixes. R19 (the native loader's ADR 0112): paths that come
// from Lua. Any server's client Lua reaches this module's Lua functions. A path it names must not
// reach another computer (a UNC or "\\?\" path makes Windows open an SMB session and offer the
// player's Windows login to that host), nor leave the folder the function works in. No SDK and no
// Windows header: the regression test in tests/ compiles this file alone.
#pragma once

#include <cctype>
#include <cwctype>
#include <filesystem>
#include <optional>
#include <string>
#include <string_view>

namespace LuaPathPolicy {

inline bool Refuse(std::string* reason, const char* why) {
    if (reason) *reason = why;
    return false;
}

// A path segment that Win32 reads as a device whatever its folder or extension: CON, PRN, AUX,
// NUL, CONIN$, CONOUT$, COM0-9 and LPT0-9 (also with the superscripts 1-3).
inline bool DeviceName(std::string_view segment) {
    std::string base;
    for (char c : segment) {
        if (c == '.') break;
        base += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    while (!base.empty() && base.back() == ' ') base.pop_back();
    if (base == "con" || base == "prn" || base == "aux" || base == "nul" || base == "conin$" || base == "conout$")
        return true;
    if (base.size() < 4 || (base.compare(0, 3, "com") != 0 && base.compare(0, 3, "lpt") != 0)) return false;
    const std::string_view digit(base.data() + 3, base.size() - 3);
    return (digit.size() == 1 && std::isdigit(static_cast<unsigned char>(digit[0]))) ||
           digit == "\xC2\xB9" || digit == "\xC2\xB2" || digit == "\xC2\xB3";
}

// A path that the game's file system, Remix or this module resolves against a folder of the
// game's own: not empty, at most 1024 bytes, no control character, no ':' (a drive, a stream or a
// device), no leading '/' or '\' (a root, a UNC or a "\\?\" path), no ".." segment, no segment
// that Windows would shorten (a trailing '.' or space) or read as a device.
inline bool RelativePath(std::string_view path, std::string* reason = nullptr) {
    if (path.empty()) return Refuse(reason, "the path is empty");
    if (path.size() > 1024) return Refuse(reason, "the path is longer than 1024 bytes");
    if (path.front() == '/' || path.front() == '\\')
        return Refuse(reason, "the path starts at a root (an absolute, UNC or \\\\?\\ path)");
    for (char c : path) {
        const auto byte = static_cast<unsigned char>(c);
        if (byte < 0x20 || byte == 0x7F) return Refuse(reason, "the path holds a control character");
        if (c == ':') return Refuse(reason, "the path holds ':' (a drive, a stream or a device)");
    }
    size_t start = 0;
    while (start <= path.size()) {
        const size_t end = path.find_first_of("/\\", start);
        const std::string_view segment = path.substr(start, end == std::string_view::npos ? std::string_view::npos : end - start);
        if (segment == "..") return Refuse(reason, "the path holds a \"..\" segment");
        if (!segment.empty() && segment != ".") {
            if (segment.back() == '.' || segment.back() == ' ')
                return Refuse(reason, "a path segment ends with '.' or a space");
            if (DeviceName(segment)) return Refuse(reason, "a path segment names a device");
        }
        if (end == std::string_view::npos) break;
        start = end + 1;
    }
    return true;
}

// A file on a local drive: "X:\" or "X:/", then a relative path by the rule above.
inline bool LocalDrivePath(std::string_view path, std::string* reason = nullptr) {
    if (path.size() < 4 || !std::isalpha(static_cast<unsigned char>(path[0])) || path[1] != ':' ||
        (path[2] != '\\' && path[2] != '/'))
        return Refuse(reason, "not a path on a local drive (X:\\...)");
    return RelativePath(path.substr(3), reason);
}

// A value that names a root, a drive or a network path ("\\host", "//host", "/x", "C:", "C:\x"),
// whatever its key.
inline bool AbsolutePathValue(std::string_view value) {
    if (!value.empty() && (value.front() == '/' || value.front() == '\\')) return true;
    return value.size() >= 2 && std::isalpha(static_cast<unsigned char>(value[0])) && value[1] == ':' &&
           (value.size() == 2 || value[2] == '\\' || value[2] == '/');
}

// The Remix options whose value is a file or a folder that the runtime opens, loads code from or
// writes to (rtx_atmosphere.h, rtx_camera.h, rtx_nrc_context.h, rtx_nsight_capture.h,
// rtx_options.h of the runtime fork). Lua leaves them to rtx.conf and the Remix menu.
inline bool RemixPathOption(std::string_view key) {
    static constexpr const char* kPaths[] = {
        "rtx.atmosphere.moonalbedotexture", "rtx.atmosphere.moonnormaltexture",
        "rtx.atmosphere.starmaptexture", "rtx.atmosphere.starmapgalaxytexture",
        "rtx.atmosphere.starmapnebulatexture", "rtx.basegamemodpathregex", "rtx.basegamemodregex",
        "rtx.camerasequence.filepath", "rtx.captureinstancestagename", "rtx.capturetimestampreplacement",
        "rtx.neuralradiancecache.cudadlldepsdirectorypath", "rtx.nsight.graphicscaptureinstallpath",
        "rtx.nsight.graphicscaptureoutputdir", "rtx.nsight.graphicscaptureoutputfile",
    };
    std::string lower;
    for (char c : key) {
        if (c == ' ' || c == '\t') continue;
        lower += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    for (const char* path : kPaths)
        if (lower == path) return true;
    return false;
}

// `requested`, relative to `root` ("" or "." for the root itself), as a folder that is still the
// root or below it once lexically normal; components compare without case, as on Windows.
inline std::optional<std::filesystem::path> Inside(const std::filesystem::path& root, std::string_view requested,
                                                    std::string* reason = nullptr) {
    namespace fs = std::filesystem;
    fs::path folder = root;
    if (!requested.empty() && requested != ".") {
        if (!RelativePath(requested, reason)) return std::nullopt;
        size_t start = 0;
        while (start <= requested.size()) {
            const size_t end = requested.find_first_of("/\\", start);
            const std::string segment(requested.substr(start, end == std::string_view::npos ? std::string_view::npos : end - start));
            if (!segment.empty() && segment != ".") folder /= fs::u8path(segment);
            if (end == std::string_view::npos) break;
            start = end + 1;
        }
    }
    const fs::path normalRoot = root.lexically_normal(), normal = folder.lexically_normal();
    auto lower = [](const fs::path& part) {
        std::wstring text = part.wstring();
        for (auto& c : text) c = static_cast<wchar_t>(std::towlower(c));
        return text;
    };
    auto it = normal.begin();
    for (const auto& part : normalRoot) {
        if (part.empty()) continue;
        while (it != normal.end() && it->empty()) ++it;
        if (it == normal.end() || lower(*it) != lower(part)) {
            Refuse(reason, "the resolved folder is outside the allowed one");
            return std::nullopt;
        }
        ++it;
    }
    return normal;
}

}  // namespace LuaPathPolicy
