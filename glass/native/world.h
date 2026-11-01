#pragma once
#include "bsp.h"
#include <memory>

namespace nl::glass {
struct Pose { std::uint32_t id; V3 position,angles; bool sleeping; };
struct Stats {
  unsigned live=0, awake=0, statics=0, models=0, workers=0, substeps=0, brushes=0, skipped_brushes=0;
  double step_ms=0, dropped_seconds=0;
  bool ready=false;
};
class World {
public:
  explicit World(unsigned budget,float gravity=600);
  ~World();
  World(const World&)=delete;
  World& operator=(const World&)=delete;
  // All positions, angles, speeds use Source units/degrees. Conversion occurs inside World.
  std::vector<StaticProp> load_map(std::span<const std::uint8_t> bytes);
  void add_model(const std::string& name,const std::vector<Hull>& convexes);
  void add_prop(const std::string& model,V3 position,V3 angles,float scale=1);
  void finish();
  std::uint32_t spawn(const Hull& hull,V3 position,V3 angles,V3 velocity,V3 spin);
  bool remove(std::uint32_t id);
  void clear(); // pieces only; retain the imported map
  void impulse(V3 origin,float radius,float speed);
  void set_collide(bool enabled);
  void set_gravity(float gravity);
  void step(double dt);
  std::span<const Pose> poses(); // awake pieces + one final pose per sleep transition, reused storage
  bool sleeping(std::uint32_t id) const;
  Stats stats() const;
private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
}
