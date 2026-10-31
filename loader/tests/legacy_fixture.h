#pragma once
#include "nl/legacy_detect.h"
#include "nl/legacy_migrate.h"
#include "nl/sha256.h"
#include <map>
#include <string>
namespace nl::test::legacy_fixture {
constexpr std::size_t kPe = 0x80, kCoff = kPe + 4, kOptional = kCoff + 20;
constexpr std::size_t kRaw = 0x200;
inline void put16(std::string& bytes, std::size_t at, unsigned value) {
  bytes.at(at) = static_cast<char>(value & 0xff);
  bytes.at(at + 1) = static_cast<char>((value >> 8) & 0xff);
}
inline void put32(std::string& bytes, std::size_t at, unsigned value) {
  put16(bytes, at, value & 0xffff); put16(bytes, at + 2, value >> 16);
}
inline void text(std::string& bytes, std::size_t at, const std::string& value) {
  bytes.replace(at, value.size(), value); bytes.at(at + value.size()) = '\0';
}
inline std::string fixture(bool x64 = true) {
  std::string bytes(0x800, '\0');
  put16(bytes, 0, 0x5a4d); put32(bytes, 0x3c, kPe); put32(bytes, kPe, 0x00004550);
  put16(bytes, kCoff, x64 ? 0x8664 : 0x014c); put16(bytes, kCoff + 2, 1);
  put16(bytes, kCoff + 16, x64 ? 0xf0 : 0xe0); put16(bytes, kCoff + 18, 0x2002);
  put16(bytes, kOptional, x64 ? 0x20b : 0x10b);
  put32(bytes, kOptional + 56, 0x3000); put32(bytes, kOptional + 60, 0x200);
  const auto directory = kOptional + (x64 ? 112 : 96);
  put32(bytes, directory - 4, 16); put32(bytes, directory, 0x1000); put32(bytes, directory + 4, 0x200);
  const auto section = kOptional + (x64 ? 0xf0 : 0xe0);
  text(bytes, section, ".text"); put32(bytes, section + 8, 0x1000); put32(bytes, section + 12, 0x1000);
  put32(bytes, section + 16, 0x600); put32(bytes, section + 20, kRaw); put32(bytes, section + 36, 0x60000020);
  put32(bytes, kRaw + 20, 1); put32(bytes, kRaw + 24, 1); put32(bytes, kRaw + 28, 0x1040);
  put32(bytes, kRaw + 32, 0x1050); put32(bytes, kRaw + 36, 0x1060);
  put32(bytes, kRaw + 0x40, 0x1400); put32(bytes, kRaw + 0x50, 0x1080); put16(bytes, kRaw + 0x60, 0);
  text(bytes, kRaw + 0x80, std::string(nl::legacy::kRemixExport));
  bytes[kRaw + 0x400] = static_cast<char>(0xc3);
  return bytes;
}

// A synthetic GMod build for stock-restoration tests: stock and launcher bytes for three paths of the
// built-in catalog (no game bytes), unmodified anchor files that confirm the build, and the catalog
// that trusts exactly them (nl::legacy::plan's test overload, deploy::Options::legacy_catalog).
struct Depot {
  nl::legacy::Catalog catalog;
  std::map<std::string, std::string> stock, legacy, anchors;  // path -> bytes
};
inline Depot depot() {
  Depot d;
  d.catalog.build = "test-build";
  for (const std::string path : {"bin/win64/engine.dll", "garrysmod/gamemodes/sandbox/logo.png", "garrysmod/html/loading.png"}) {
    d.stock[path] = "stock bytes of " + path;
    d.legacy[path] = "RTXLauncher's bytes of " + path;
    d.catalog.files.push_back({path, d.stock[path].size(), nl::sha256::of(d.stock[path]), nl::sha256::of(d.legacy[path])});
  }
  for (const std::string path : {"bin/win64/gmod.exe", "bin/win64/client.dll", "bin/win64/server.dll"}) {
    d.anchors[path] = "unmodified " + path;
    d.catalog.anchors.push_back({path, d.anchors[path].size(), nl::sha256::of(d.anchors[path]), {}});
  }
  return d;
}
}
