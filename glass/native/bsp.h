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
  unsigned considered_brushes = 0; // solid world brushes looked at
  unsigned skipped_brushes = 0;    // of those, the ones that could not become a hull
};
// Parses only little-endian Source VBSP 19-21; never reads a path or any engine memory.
// A bad/unsupported file throws Error and callers discard the whole map. Single brushes that cannot
// become a hull are skipped and counted; World::finish refuses maps with no usable collision.
Map read_bsp(std::span<const std::uint8_t> bytes);
}
