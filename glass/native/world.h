#pragma once
#include "bsp.h"
#include "fracture.h"
#include <memory>
#include <future>

namespace nl::glass {
struct Pose { std::uint32_t id; V3 position,angles; bool sleeping; };
constexpr unsigned kMaxSceneBodies=96,kMaxDamageEvents=64,kMaxRegions=32;
constexpr unsigned kMaxSoundEvents=128;
struct SoundEvent { std::uint32_t id; V3 position; float speed,mass; unsigned kind; }; // impact=1, split=2, water=3
struct Motion { V3 position,velocity,spin; };
enum DamageKind : unsigned { Bullet=1,Blast=2,SourceBody=4,Fall=8,Melee=16 };
enum CollisionTarget : unsigned { Objects=1,Ragdolls=2,Players=4,NPCs=8 };
struct DamageEvent { std::uint32_t id; float energy; unsigned kinds; };
struct SceneBody {
  std::uint32_t key=0;
  V3 position,angles,half,velocity;
  float mass=85;
  std::vector<Hull> convexes; // optional: supplied only on creation/physics-shape replacement
  unsigned kind=Objects;
};
struct Region { V3 minimum,maximum; };
struct Fragment { std::uint32_t id=0; Hull polygon; float thickness=1; V3 position,angles,velocity,spin; };
struct Stats {
  unsigned live=0, awake=0, statics=0, models=0, workers=0, substeps=0, brushes=0, skipped_brushes=0;
  unsigned refused_brushes=0, refused_convexes=0, refused_meshes=0, skipped_props=0;
  unsigned contact_overflows=0, manifold_overflows=0, pair_overflows=0, constraint_overflows=0;
  std::size_t temp_reserved_bytes=0,temp_peak_bytes=0;
  unsigned pose_visits=0;
  unsigned scene_bodies=0,scene_moves=0,scene_cooks=0,damage_dropped=0,ray_hits=0,splits=0;
  unsigned scene_sweeps=0,scene_sweep_hits=0,scene_sweep_limited=0;
  unsigned melee_hits=0,melee_limited=0;
  unsigned sound_events=0,sound_dropped=0,water_volumes=0,water_tests=0,water_applied=0,water_entries=0;
  unsigned overlap_suppressed=0;
  double water_ms=0;
  bool interaction=false;
  unsigned collision_flags=Objects|Ragdolls;
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
  std::uint32_t spawn(const Hull& hull,V3 position,V3 angles,V3 velocity,V3 spin,float minimum_size=4);
  std::uint32_t spawn_group(const std::vector<Hull>& hulls,V3 position,V3 angles,V3 velocity,V3 spin);
  bool remove(std::uint32_t id);
  void clear(); // pieces only; retain the imported map
  void impulse(V3 origin,float radius,float speed);
  void set_collide(bool enabled);
  void set_gravity(float gravity);
  void set_interaction(bool enabled);
  void set_collision_flags(unsigned flags);
  unsigned sync_bodies(const std::vector<SceneBody>& bodies,double sample_dt);
  std::vector<Region> regions(V3 focus={}) const;
  std::vector<DamageEvent> take_damage();
  void set_sounds(bool enabled);
  std::vector<SoundEvent> take_sounds();
  Motion motion(std::uint32_t id) const;
  std::uint32_t ray(V3 from,V3 to,float energy,float speed);
  unsigned melee(V3 from,V3 to,float energy,float speed,float radius);
  std::vector<Fragment> split(std::uint32_t id,float minimum_size,unsigned maximum=6);
  bool can_split(std::uint32_t id,float minimum_size) const;
  Pose scene_pose(std::uint32_t key) const; // read-only; also proves one-way motion in tests
  void step(double dt);
  // C++ tests only (never exposed to the game Lua API): the wall-clock limit for catch-up substeps,
  // 4 ms by default. 0 drops every catch-up step and 1000 runs them all, so tests never race the clock.
  void set_catch_up_budget(double milliseconds);
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
