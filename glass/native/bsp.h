#pragma once
#include "geometry.h"
#include <span>
#include <string>

namespace nl::glass {
struct StaticProp {
  std::string model;
  V3 position, angles;
  unsigned solid = 0;
  float scale = 1;
};
struct Map {
  std::vector<Hull> brushes;
  std::vector<Triangle> triangles;
  std::vector<StaticProp> props;
  unsigned skipped_brushes = 0;
};
// Parses only little-endian Source VBSP 19-21; never reads a path or any engine memory.
// A bad/unsupported file throws Error. Callers discard the whole map, never a partial world.
Map read_bsp(std::span<const std::uint8_t> bytes);
}
