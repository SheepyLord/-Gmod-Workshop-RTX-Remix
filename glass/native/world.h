#pragma once
#include "bsp.h"
#include <memory>
#include <future>

namespace nl::glass {
struct Pose { std::uint32_t id; V3 position,angles; bool sleeping; };
struct Stats {
  unsigned live=0, awake=0, statics=0, models=0, workers=0, substeps=0, brushes=0, skipped_brushes=0;
  unsigned refused_brushes=0, refused_convexes=0, refused_meshes=0, skipped_props=0;
  unsigned contact_overflows=0, manifold_overflows=0, pair_overflows=0, constraint_overflows=0;
  std::size_t temp_reserved_bytes=0,temp_peak_bytes=0;
  unsigned pose_visits=0;
  double step_ms=0, dropped_seconds=0;
  bool ready=false,busy=false;
};
class World {
public:
  explicit World(unsigned budget,float gravity=600);
  ~World();
  World(const World&)=delete;
  World& operator=(const World&)=delete;
  // All positions, angles, speeds use Source units/degrees. Conversion occurs inside World.
  std::vector<StaticProp> load_map(std::span<const std::uint8_t> bytes);
  void begin_load(std::vector<std::uint8_t> bytes);
  bool poll_load(std::vector<StaticProp>& props);
  bool add_model(const std::string& name,const std::vector<Hull>& convexes);
  bool add_prop(const std::string& model,V3 position,V3 angles,float scale=1);
  void finish();
  void begin_finish();
  bool poll_finish();
  std::uint32_t spawn(const Hull& hull,V3 position,V3 angles,V3 velocity,V3 spin);
  bool remove(std::uint32_t id);
  void clear(); // pieces only; retain the imported map
  void impulse(V3 origin,float radius,float speed);
  void set_collide(bool enabled);
  void set_gravity(float gravity);
  void step(double dt);
  void begin_step(double dt);
  bool poll_step();
  std::span<const Pose> poses(); // awake pieces + one final pose per sleep transition, reused storage
  bool sleeping(std::uint32_t id) const;
  Stats stats() const;
private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
  std::future<std::vector<StaticProp>> loading_;
  std::future<void> finishing_,stepping_;
  Stats snapshot_;
  bool busy() const;
  Impl& idle() const;
  std::vector<StaticProp> load_impl(std::span<const std::uint8_t> bytes);
  void finish_impl();
  void step_impl(double dt);
};
}
