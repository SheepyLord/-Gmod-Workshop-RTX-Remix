#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace nl::glass {
constexpr float kMetres = 0.0254f;
constexpr std::uint32_t kMaxBudget = 8192;
constexpr std::size_t kMaxHullPoints = 256;
constexpr std::size_t kMaxMapBytes = 256 * 1024 * 1024;
constexpr std::size_t kMaxStaticBodies = 32768;
constexpr std::size_t kMaxMapPoints = 2 * 1024 * 1024;
constexpr float kCoordinateLimit = 131072;
struct Error : std::runtime_error { using std::runtime_error::runtime_error; };
struct V3 {
  float x = 0, y = 0, z = 0;
  V3 operator+(V3 b) const { return {x+b.x,y+b.y,z+b.z}; }
  V3 operator-(V3 b) const { return {x-b.x,y-b.y,z-b.z}; }
  V3 operator*(float s) const { return {x*s,y*s,z*s}; }
  float dot(V3 b) const { return x*b.x+y*b.y+z*b.z; }
  V3 cross(V3 b) const { return {y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x}; }
  float length() const { return std::sqrt(dot(*this)); }
  bool valid(float bound = kCoordinateLimit) const {
    return std::isfinite(x) && std::isfinite(y) && std::isfinite(z) &&
      std::abs(x)<=bound && std::abs(y)<=bound && std::abs(z)<=bound;
  }
};
using Hull = std::vector<V3>;
struct Triangle { V3 a,b,c; };
struct Plane { V3 normal; float distance; };
// Source halfspaces: normal.dot(point) <= distance. Empty/flat/unbounded brushes are refused.
Hull brush_hull(const std::vector<Plane>& planes);
// Validate before Jolt sees user-controlled geometry (also used for prop collision).
bool valid_hull(const Hull& points);
}
