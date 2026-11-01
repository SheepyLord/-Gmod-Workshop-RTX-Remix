#pragma once
#include "geometry.h"
#include <array>

namespace nl::glass {
// A convex, CCW polygon in the piece's XY plane (z is zero).
Hull outline_xy(const Hull& points);
double polygon_area(const Hull& polygon);
// Bisect the longest axis by area. Empty children mean this is already a minimum-size piece.
std::array<Hull,2> split_polygon(const Hull& polygon,float minimum_size);
Hull extrude(const Hull& polygon,float thickness);
V3 polygon_center(const Hull& polygon);
}
