#pragma once
#include "geometry.h"
#include <array>

namespace nl::glass {
// A convex, CCW polygon in the piece's XY plane (z is zero).
Hull outline_xy(const Hull& points);
double polygon_area(const Hull& polygon);
// Seeded crack lines near the local hit, 2-6 convex children. Empty means minimum size.
std::vector<Hull> split_polygon(const Hull& polygon,float minimum_size,V3 hit={},std::uint32_t seed=1,unsigned maximum=6);
Hull extrude(const Hull& polygon,float thickness);
V3 polygon_center(const Hull& polygon);
}
