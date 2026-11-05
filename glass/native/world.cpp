#include "world.h"
#include <Jolt/Jolt.h>
#include <Jolt/RegisterTypes.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/Shape/ConvexHullShape.h>
#include <Jolt/Physics/Collision/Shape/MeshShape.h>
#include <Jolt/Physics/Collision/Shape/StaticCompoundShape.h>
#include <Jolt/Physics/Collision/Shape/ScaledShape.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/ContactListener.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/ShapeCast.h>
#include <atomic>
#include <array>
#include <bitset>
#include <limits>
#include <chrono>
#include <cstdarg>
#include <cstdio>
#include <mutex>
#include <thread>
#include <unordered_map>

namespace nl::glass {
namespace {
constexpr float kRadians=3.14159265358979323846f/180;
void need(bool c,const char* message) { if(!c)throw Error(message); }
JPH::Vec3 jvec(V3 v,float scale=kMetres) { return {v.x*scale,v.y*scale,v.z*scale}; }
V3 vec(JPH::Vec3Arg v,float scale=1/kMetres) { return {v.GetX()*scale,v.GetY()*scale,v.GetZ()*scale}; }
JPH::Quat rotation(V3 a) {
  return JPH::Quat::sRotation(JPH::Vec3::sAxisZ(),a.y*kRadians)*
    JPH::Quat::sRotation(JPH::Vec3::sAxisY(),a.x*kRadians)*JPH::Quat::sRotation(JPH::Vec3::sAxisX(),a.z*kRadians);
}
V3 angles(JPH::QuatArg q) {
  const auto m=JPH::Mat44::sRotation(q);
  const float pitch=std::asin(std::clamp(-m(2,0),-1.0f,1.0f));
  if(std::abs(std::cos(pitch))<1e-5f)return {pitch/kRadians,std::atan2(-m(0,1),m(1,1))/kRadians,0};
  return {pitch/kRadians,std::atan2(m(1,0),m(0,0))/kRadians,std::atan2(m(2,1),m(2,2))/kRadians};
}
void trace(const char* fmt,...) {
  char buffer[1024];va_list args;va_start(args,fmt);vsnprintf(buffer,sizeof(buffer),fmt,args);va_end(args);
  // No engine/Lua calls from worker threads.
}
// Factory and type registry are local to this statically linked module. Live worlds share them.
struct Runtime {
  Runtime() {
    JPH::RegisterDefaultAllocator();JPH::Trace=trace;
    JPH::Factory::sInstance=new JPH::Factory();JPH::RegisterTypes();
  }
  ~Runtime() { JPH::UnregisterTypes();delete JPH::Factory::sInstance;JPH::Factory::sInstance=nullptr; }
};
std::shared_ptr<Runtime> runtime() {
  // A world keeps the registry alive even during DLL static destruction (module close normally
  // releases it sooner). The registry must outlive every Jolt shape, body and worker.
  static auto r=std::make_shared<Runtime>();return r;
}
class BroadLayers final:public JPH::BroadPhaseLayerInterface {
public:
  JPH::uint GetNumBroadPhaseLayers() const override { return 2; }
  JPH::BroadPhaseLayer GetBroadPhaseLayer(JPH::ObjectLayer layer) const override { return JPH::BroadPhaseLayer(layer==0?0:1); }
#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
  const char* GetBroadPhaseLayerName(JPH::BroadPhaseLayer l) const override { return l.GetValue()==0?"map":"glass"; }
#endif
};
class ObjectBroadFilter final:public JPH::ObjectVsBroadPhaseLayerFilter {
public:
  bool ShouldCollide(JPH::ObjectLayer a,JPH::BroadPhaseLayer b) const override {
    return (a==1 || a==2) || b.GetValue()!=0;
  }
};
class PairFilter final:public JPH::ObjectLayerPairFilter {
public:
  bool ShouldCollide(JPH::ObjectLayer a,JPH::ObjectLayer b) const override {
    const bool glass_a=a==1 || a==2,glass_b=b==1 || b==2;
    return (glass_a && (b==0 || b==3))||(glass_b && (a==0 || a==3))||(a==1 && b==1);
  }
};
JPH::RefConst<JPH::Shape> hull_shape(const Hull& hull,bool glass) {
  need(valid_hull(hull),"invalid/flat hull (4-256 finite noncoplanar points required)");
  JPH::Array<JPH::Vec3> points;points.reserve(hull.size());for(auto p:hull)points.push_back(jvec(p));
  JPH::ConvexHullShapeSettings settings(points,glass?.0005f:.001f);
  settings.mHullTolerance=.00005f;settings.mDensity=2500; // ordinary soda-lime glass, kg/m^3
  const auto result=settings.Create();return result.HasError()?nullptr:result.Get();
}
class Scratch final:public JPH::TempAllocator {
public:
  explicit Scratch(unsigned bytes):allocator(bytes),reserved(bytes) {}
  void* Allocate(JPH::uint n) override {
    auto* result=allocator.Allocate(n);used+=n;peak=std::max(peak,used);return result;
  }
  void Free(void* p,JPH::uint n) override { allocator.Free(p,n);used-=n; }
  JPH::TempAllocatorImplWithMallocFallback allocator;
  std::size_t reserved=0,used=0,peak=0;
};
}
struct World::Impl {
  static constexpr unsigned no_queue=std::numeric_limits<unsigned>::max();
  struct Piece {
    std::uint32_t id=0;
    JPH::BodyID body;
    JPH::RVec3 previous=JPH::RVec3::sZero(),current=JPH::RVec3::sZero();
    JPH::Quat before=JPH::Quat::sIdentity(),after=JPH::Quat::sIdentity();
    bool asleep=false,dirty=true;
    unsigned queued=no_queue;
    std::uint64_t seen=0;
    float mass=0,thickness=1,threshold=0;
    bool splittable=false,grouped=false;
    std::atomic<float> damage{0};
    std::atomic<unsigned> kinds{0};
    std::atomic<bool> damage_queued{false};
    std::atomic<float> hit_x{0},hit_y{0},hit_z{0};
    std::atomic<unsigned> sound_tick{0};
    std::bitset<kMaxSceneBodies> overlaps;
    bool wet=false;
  };
  struct Mirror {
    std::uint32_t key=0;JPH::BodyID body;
    V3 half;float mass=85,remaining=0;
    JPH::RVec3 target=JPH::RVec3::sZero();JPH::Quat rotation=JPH::Quat::sIdentity();
    bool custom=false,seen=false;
  };
  struct SweepBudget { unsigned casts=0,count=0;std::array<JPH::uint32,64> kicked; };
  struct Contacts final:JPH::ContactListener {
    Impl& world;
    explicit Contacts(Impl& w):world(w) {}
    bool suppressed(const JPH::Body& a,const JPH::Body& b) const {
      const auto la=a.GetObjectLayer(),lb=b.GetObjectLayer();
      if(la!=3 && lb!=3)return false;
      const auto& p=la==3?b:a;const auto& mirror=la==3?a:b;
      if(p.GetObjectLayer()!=1 && p.GetObjectLayer()!=2)return false;
      return world.pieces[p.GetUserData()-1].overlaps.test(static_cast<std::size_t>(mirror.GetUserData()-1));
    }
    JPH::ValidateResult OnContactValidate(const JPH::Body& a,const JPH::Body& b,JPH::RVec3Arg,const JPH::CollideShapeResult&) override {
      return suppressed(a,b)?JPH::ValidateResult::RejectAllContactsForThisBodyPair:JPH::ValidateResult::AcceptAllContactsForThisBodyPair;
    }
    void contact(const JPH::Body& a,const JPH::Body& b,const JPH::ContactManifold& m,JPH::ContactSettings& settings) {
      if(suppressed(a,b)) { settings.mIsSensor=true;return; }
      const auto la=a.GetObjectLayer(),lb=b.GetObjectLayer();
      const bool first=la==1 || la==2;
      const auto& piece=first?a:b;const auto& obstacle=first?b:a;
      const auto slot=static_cast<unsigned>(piece.GetUserData()-1);
      if(slot>=world.pieces.size())return;
      const auto point=m.GetWorldSpaceContactPointOn1(0);
      const float speed=std::max(0.0f,(a.GetPointVelocity(point)-b.GetPointVelocity(point)).Dot(m.mWorldSpaceNormal))/kMetres;
      // Only one side emits a piece-piece impact. Tiny resting contacts never reach the buffer.
      if((la==0 || la==3 || lb==0 || lb==3) || a.GetUserData()<b.GetUserData())
        world.sound(slot,vec(point),speed,1);
      // Sound is independent of follow-up damage; no piece-piece damage cascade.
      if((la!=0 && la!=3) && (lb!=0 && lb!=3))return;
      if(!world.interaction || !world.pieces[slot].splittable)return;
      const bool source=obstacle.GetObjectLayer()==3;
      if(speed<(source?160.0f:220.0f))return;
      const auto& p=world.pieces[slot];
      const float mass=source?std::min(world.mirrors[obstacle.GetUserData()-1].mass,p.mass*8):p.mass;
      world.damage(slot,.5f*mass*speed*speed,source?SourceBody:Fall,vec(point));
    }
    void OnContactAdded(const JPH::Body& a,const JPH::Body& b,const JPH::ContactManifold& m,JPH::ContactSettings& s) override { contact(a,b,m,s); }
    void OnContactPersisted(const JPH::Body& a,const JPH::Body& b,const JPH::ContactManifold& m,JPH::ContactSettings& s) override { contact(a,b,m,s); }
  } contacts{*this};
  std::shared_ptr<Runtime> registry;
  BroadLayers broad;ObjectBroadFilter object_filter;PairFilter pair_filter;
  std::unique_ptr<JPH::PhysicsSystem> physics;
  std::unique_ptr<JPH::JobSystemThreadPool> jobs;
  std::unique_ptr<Scratch> temp;
  std::vector<Piece> pieces;
  unsigned capacity;
  std::array<Mirror,kMaxSceneBodies> mirrors;
  std::array<std::pair<unsigned,std::uint32_t>,kMaxDamageEvents> damage_slots{};
  std::atomic<unsigned> damage_count{0},damage_dropped{0};
  std::array<SoundEvent,kMaxSoundEvents> sound_slots{};
  std::atomic<unsigned> sound_count{0},sound_dropped{0},sound_events{0};
  bool sounds=true;
  unsigned simulation_tick=8,overlap_suppressed=0;
  std::vector<WaterVolume> water;
  struct WaterNode { V3 lo,hi;int left=-1,right=-1;unsigned volume=0; };
  std::vector<WaterNode> water_tree;
  unsigned water_tests=0,water_applied=0,water_entries=0;
  double water_ms=0;
  unsigned scene_moves=0,scene_cooks=0,ray_hits=0,splits=0;
  unsigned collision_flags=Objects|Ragdolls;
  unsigned melee_hits=0,melee_limited=0;
  unsigned scene_sweeps=0,scene_sweep_hits=0,scene_sweep_limited=0;
  bool interaction=false;
  std::vector<unsigned> free;
  std::unordered_map<std::uint32_t,unsigned> ids;
  std::vector<JPH::BodyID> statics;
  std::unordered_map<std::string,JPH::RefConst<JPH::Shape>> models;
  std::vector<Pose> output;
  std::vector<unsigned> pose_slots;
  JPH::BodyIDVector active_before;
  std::uint32_t next_id=1;
  bool collide=true,loaded=false,ready=false;
  unsigned workers=1,substeps=0,brushes=0,skipped_brushes=0;
  unsigned refused_brushes=0,refused_convexes=0,refused_meshes=0,skipped_props=0;
  unsigned contact_overflows=0,manifold_overflows=0,pair_overflows=0,constraint_overflows=0,pose_visits=0;
  std::uint64_t epoch=0;
  std::size_t model_points=0;
  float gravity=600;
  double accumulator=0,step_ms=0,dropped=0,last_fixed_ms=0,catch_up_ms=4;

  Impl(unsigned budget,float g):registry(runtime()),pieces(budget+6),capacity(budget),gravity(g) {
    const unsigned hw=std::thread::hardware_concurrency();
    workers=std::clamp(hw>2?hw-2:1u,1u,8u);
    jobs=std::make_unique<JPH::JobSystemThreadPool>(JPH::cMaxPhysicsJobs,JPH::cMaxPhysicsBarriers,static_cast<int>(workers));
    // Scratch is allocated lazily from live demand, not the maximum menu budget.
    physics=std::make_unique<JPH::PhysicsSystem>();
    physics->Init(static_cast<JPH::uint>(budget+6+kMaxStaticBodies+kMaxSceneBodies),0,std::max(1024u,budget*8),std::max(1024u,budget*4),broad,object_filter,pair_filter);
    JPH::PhysicsSettings settings;
    settings.mTimeBeforeSleep=.35f;settings.mPointVelocitySleepThreshold=.06f;
    settings.mPenetrationSlop=.001f;settings.mSpeculativeContactDistance=.003f;
    settings.mMaxPenetrationDistance=.03f;settings.mNumVelocitySteps=6;settings.mNumPositionSteps=2;
    settings.mMaxInFlightBodyPairs=static_cast<int>(std::max(1024u,budget*16));
    physics->SetPhysicsSettings(settings);physics->SetGravity({0,0,-g*kMetres});
    physics->SetContactListener(&contacts);
    ids.reserve(budget+6);output.reserve(budget);free.reserve(budget+6);statics.reserve(kMaxStaticBodies);
    pose_slots.reserve(budget+6);active_before.reserve(budget+kMaxSceneBodies);
    for(unsigned i=budget+6;i>0;--i)free.push_back(i-1);
  }
  ~Impl() { clear_all(); }
  void destroy(JPH::BodyID body) {
    auto& bi=physics->GetBodyInterfaceNoLock();bi.RemoveBody(body);bi.DestroyBody(body);
  }
  void queue(unsigned slot) {
    auto& p=pieces[slot];if(p.queued!=no_queue)return;
    p.queued=static_cast<unsigned>(pose_slots.size());pose_slots.push_back(slot);
  }
  void unqueue(unsigned slot) {
    auto& p=pieces[slot];if(p.queued==no_queue)return;
    const auto tail=pose_slots.back();pose_slots[p.queued]=tail;pieces[tail].queued=p.queued;
    pose_slots.pop_back();p.queued=no_queue;
  }
  void clear_pieces() {
    for(auto& p:pieces)if(p.id) { destroy(p.body);p.id=0;p.queued=no_queue;p.damage_queued=false;p.damage=0;p.kinds=0; }
    ids.clear();free.clear();for(unsigned i=static_cast<unsigned>(pieces.size());i>0;--i)free.push_back(i-1);
    accumulator=0;output.clear();pose_slots.clear();damage_count=0;sound_count=0;
    clear_scene();
  }
  void clear_scene() { for(auto& m:mirrors)if(m.key) { destroy(m.body);m=Mirror{}; }for(auto& p:pieces)p.overlaps.reset(); }
  void clear_all() {
    clear_pieces();for(auto id:statics)destroy(id);statics.clear();models.clear();water.clear();water_tree.clear();model_points=0;loaded=ready=false;
  }
  void add_static(JPH::RefConst<JPH::Shape> shape,V3 p={},V3 a={}) {
    need(statics.size()<kMaxStaticBodies,"static-world body limit");
    JPH::BodyCreationSettings s(shape,jvec(p),rotation(a),JPH::EMotionType::Static,0);
    s.mFriction=.65f;s.mRestitution=.02f;
    const auto id=physics->GetBodyInterfaceNoLock().CreateAndAddBody(s,JPH::EActivation::DontActivate);
    need(!id.IsInvalid(),"static-world allocation failed");statics.push_back(id);
  }
  Piece* find(std::uint32_t id) {
    const auto it=ids.find(id);return it==ids.end()?nullptr:&pieces[it->second];
  }
  void sound(unsigned slot,V3 position,float speed,unsigned kind) {
    if(!sounds || (kind==1 && speed<70))return;
    auto& p=pieces[slot];auto before=p.sound_tick.load(std::memory_order_relaxed);
    if(kind==1 && simulation_tick-before<8)return;
    if(kind==1 && !p.sound_tick.compare_exchange_strong(before,simulation_tick,std::memory_order_relaxed))return;
    const auto index=sound_count.fetch_add(1,std::memory_order_relaxed);
    if(index<kMaxSoundEvents) { sound_slots[index]={p.id,position,speed,p.mass,kind};++sound_events; }
    else ++sound_dropped;
  }
  void damage(unsigned slot,float energy,unsigned kind,V3 hit) {
    auto& p=pieces[slot];if(!interaction || !p.splittable || energy<p.threshold)return;
    auto previous=p.damage.load(std::memory_order_relaxed);
    while(previous<energy && !p.damage.compare_exchange_weak(previous,energy,std::memory_order_relaxed)) {}
    if(previous<energy) { p.hit_x=hit.x;p.hit_y=hit.y;p.hit_z=hit.z; }
    p.kinds.fetch_or(kind,std::memory_order_relaxed);
    if(p.damage_queued.exchange(true,std::memory_order_relaxed))return;
    const auto index=damage_count.fetch_add(1,std::memory_order_relaxed);
    if(index<kMaxDamageEvents)damage_slots[index]={slot,p.id};
    else { p.damage_queued=false;++damage_dropped; }
  }
  void mark_overlap(unsigned mirror,bool correction=false) {
    const auto* b=physics->GetBodyLockInterfaceNoLock().TryGetBody(mirrors[mirror].body);
    for(auto& p:pieces)if(p.id) {
      const auto* piece=physics->GetBodyLockInterfaceNoLock().TryGetBody(p.body);
      auto bounds=piece->GetWorldSpaceBounds();
      if(correction) { auto future=bounds;future.Translate(piece->GetLinearVelocity()*(1.0f/60));bounds.Encapsulate(future); }
      if(b->GetWorldSpaceBounds().Overlaps(bounds)) {
        if(!p.overlaps.test(mirror))++overlap_suppressed;
        p.overlaps.set(mirror);
      }
    }
  }
  void prune_overlaps() {
    for(auto& p:pieces)if(p.id && p.overlaps.any()) {
      const auto* b=physics->GetBodyLockInterfaceNoLock().TryGetBody(p.body);
      auto bounds=b->GetWorldSpaceBounds(),future=bounds;future.Translate(b->GetLinearVelocity()*(1.0f/60));bounds.Encapsulate(future);
      for(unsigned i=0;i<kMaxSceneBodies;++i)if(p.overlaps.test(i)) {
        const auto& m=mirrors[i];
        if(!m.key || !bounds.Overlaps(physics->GetBodyLockInterfaceNoLock().TryGetBody(m.body)->GetWorldSpaceBounds()))p.overlaps.reset(i);
      }
    }
  }
  int build_water(std::vector<unsigned>& order,unsigned first,unsigned end) {
    const int at=static_cast<int>(water_tree.size());water_tree.push_back({});
    auto lo=water[order[first]].minimum,hi=water[order[first]].maximum;
    for(unsigned i=first+1;i<end;++i) {
      const auto& v=water[order[i]];
      lo={std::min(lo.x,v.minimum.x),std::min(lo.y,v.minimum.y),std::min(lo.z,v.minimum.z)};
      hi={std::max(hi.x,v.maximum.x),std::max(hi.y,v.maximum.y),std::max(hi.z,v.maximum.z)};
    }
    water_tree[at].lo=lo;water_tree[at].hi=hi;
    if(end-first==1)water_tree[at].volume=order[first];
    else {
      const auto size=hi-lo;const unsigned axis=size.x>size.y?(size.x>size.z?0u:2u):(size.y>size.z?1u:2u);
      auto component=[&](V3 p) { return axis==0?p.x:axis==1?p.y:p.z; };
      const unsigned mid=(first+end)/2;
      std::nth_element(order.begin()+first,order.begin()+mid,order.begin()+end,[&](unsigned a,unsigned b) {
        return component(water[a].minimum+water[a].maximum)<component(water[b].minimum+water[b].maximum);
      });
      const auto left=build_water(order,first,mid),right=build_water(order,mid,end);
      water_tree[at].left=left;water_tree[at].right=right;
    }
    return at;
  }
  const WaterVolume* water_at(int index,V3 point,float height) {
    ++water_tests;const auto& n=water_tree[index];
    if(point.x<n.lo.x || point.x>n.hi.x || point.y<n.lo.y || point.y>n.hi.y || point.z<n.lo.z || point.z>n.hi.z+height)return nullptr;
    if(n.left>=0) { if(const auto* v=water_at(n.left,point,height))return v;return water_at(n.right,point,height); }
    const auto& v=water[n.volume];
    for(const auto& plane:v.planes)
      if(plane.normal.dot(point)>plane.distance+(plane.normal.z>.7f?height:0))return nullptr;
    return &v;
  }
  void buoyancy(float dt) {
    if(water_tree.empty())return;
    const auto start=std::chrono::steady_clock::now();
    // Sleeping bottom piles stay asleep. A blast wakes them through the ordinary impulse path.
    const auto n=physics->GetNumActiveBodies(JPH::EBodyType::RigidBody);
    const auto* active=physics->GetActiveBodiesUnsafe(JPH::EBodyType::RigidBody);
    for(unsigned i=0;i<n;++i) {
      auto* b=physics->GetBodyLockInterfaceNoLock().TryGetBody(active[i]);if(b->GetObjectLayer()==3)continue;
      auto& p=pieces[b->GetUserData()-1];
      const auto* v=water_at(0,vec(b->GetCenterOfMassPosition()),b->GetWorldSpaceBounds().GetExtent().GetZ()/kMetres);
      bool wet=false;
      if(v) {
        // Water/glass density = 1000/2500. Jolt integrates submerged volume, linear drag,
        // angular drag and the off-centre buoyancy torque on the actual (also compound) hull.
        wet=b->ApplyBuoyancyImpulse(jvec(v->surface.normal*v->surface.distance),jvec(v->surface.normal,1),.4f,1.4f,.08f,
          JPH::Vec3::sZero(),physics->GetGravity(),dt);
        if(wet)++water_applied;
      }
      if(wet && !p.wet) { ++water_entries;sound(static_cast<unsigned>(b->GetUserData()-1),vec(b->GetPosition()),b->GetLinearVelocity().Length()/kMetres,3); }
      p.wet=wet;
    }
    water_ms+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
  }
  // Jolt CCD deliberately excludes kinematics. Sampled poses alone can tunnel through sleeping
  // thin glass or pin it against the floor. Sweep only actual fast mirror translations, between
  // worker steps; transfer closing normal velocity to glass, never change the mirror trajectory.
  void sweep_mirror(const Mirror& m,JPH::Vec3Arg delta,float dt,SweepBudget& budget) {
    const auto velocity=delta/dt;
    if(velocity.LengthSq()<JPH::Square(160*kMetres))return;
    if(budget.casts==16 || budget.count==64) { ++scene_sweep_limited;return; }
    ++budget.casts;++scene_sweeps;
    struct Hit { JPH::BodyID body;JPH::Vec3 normal;bool overlap; };
    struct Collector final:JPH::CastShapeCollector {
      std::array<Hit,8> hits;unsigned count=0,visits=0,bodies=0;
      void OnBody(const JPH::Body&) override { if(++bodies==64)ForceEarlyOut(); }
      void AddHit(const JPH::ShapeCastResult& hit) override {
        if(count==hits.size() || visits==64)return;
        if(++visits==64)ForceEarlyOut();
        for(unsigned i=0;i<count;++i)if(hits[i].body==hit.mBodyID2)return;
        hits[count++]={hit.mBodyID2,hit.mPenetrationAxis,hit.mFraction<=0};
        if(count==hits.size())ForceEarlyOut();
      }
    } collector;
    class Pieces final:public JPH::ObjectLayerFilter {
      bool ShouldCollide(JPH::ObjectLayer layer) const override { return layer==1 || layer==2; }
    } filter;
    const auto* body=physics->GetBodyLockInterfaceNoLock().TryGetBody(m.body);
    const JPH::RShapeCast cast(body->GetShape(),JPH::Vec3::sReplicate(1),body->GetCenterOfMassTransform(),delta);
    JPH::ShapeCastSettings settings;settings.mUseShrunkenShapeAndConvexRadius=true;
    const JPH::SpecifiedBroadPhaseLayerFilter moving_layer(JPH::BroadPhaseLayer(1));
    physics->GetNarrowPhaseQueryNoLock().CastShape(cast,settings,JPH::RVec3::sZero(),collector,moving_layer,filter);
    if(collector.ShouldEarlyOut())++scene_sweep_limited;
    auto& bi=physics->GetBodyInterfaceNoLock();
    for(unsigned i=0;i<collector.count && budget.count<64;++i) {
      const auto& hit=collector.hits[i];
      const auto id=hit.body.GetIndexAndSequenceNumber();
      if(std::find(budget.kicked.begin(),budget.kicked.begin()+budget.count,id)!=budget.kicked.begin()+budget.count)continue;
      const auto normal=hit.overlap?velocity.NormalizedOr(JPH::Vec3::sZero()):hit.normal.NormalizedOr(JPH::Vec3::sZero());
      const auto before=bi.GetLinearVelocity(hit.body);
      const float closing=(velocity-before).Dot(normal);
      if(closing<160*kMetres)continue;
      const auto* piece=physics->GetBodyLockInterfaceNoLock().TryGetBody(hit.body);
      const auto slot=static_cast<unsigned>(piece->GetUserData()-1);auto& p=pieces[slot];
      bi.ActivateBody(hit.body);bi.SetLinearVelocity(hit.body,before+normal*std::min(closing,2000*kMetres));
      p.asleep=false;p.dirty=true;queue(slot);budget.kicked[budget.count++]=id;++scene_sweep_hits;
      const float speed=closing/kMetres,mass=std::min(m.mass,p.mass*8);
      // Swept transfer already resolved this contact. Do not let a subsequent deep
      // kinematic overlap solve the same sample again in the opposite direction.
      p.overlaps.set(static_cast<std::size_t>(&m-mirrors.data()));++overlap_suppressed;
      damage(slot,.5f*mass*speed*speed,SourceBody,vec(piece->GetPosition()));
    }
  }
  // Discarded catch-up time never reaches Jolt, but Source still moved. Finish that part of each
  // mirror's sampled motion as a pose correction (the sync sweep already covered the path). A mirror
  // left behind would carry the backlog into the next snapshot as extra speed for its sweep and push.
  void skip_mirrors(float seconds) {
    auto& bi=physics->GetBodyInterfaceNoLock();
    for(auto& m:mirrors)if(m.key && m.remaining>0) {
      if(seconds>=m.remaining)bi.SetPositionAndRotation(m.body,m.target,m.rotation,JPH::EActivation::DontActivate);
      else {
        const float t=seconds/m.remaining;const auto p=bi.GetPosition(m.body);
        bi.SetPositionAndRotation(m.body,p+(m.target-p)*t,bi.GetRotation(m.body).SLERP(m.rotation,t),JPH::EActivation::DontActivate);
      }
      m.remaining=std::max(0.0f,m.remaining-seconds);
      mark_overlap(static_cast<unsigned>(&m-mirrors.data()),true);
    }
  }
  std::uint32_t create(JPH::RefConst<JPH::Shape> shape,V3 position,V3 a,V3 velocity,V3 spin,float minimum_size=4) {
    need(!free.empty() && next_id!=0,"piece budget/identifier exhausted");
    JPH::BodyCreationSettings settings(shape,jvec(position),rotation(a),JPH::EMotionType::Dynamic,collide?1:2);
    settings.mFriction=.65f;settings.mRestitution=.025f;settings.mLinearDamping=.15f;settings.mAngularDamping=.35f;
    settings.mMaxLinearVelocity=200;settings.mMaxAngularVelocity=100;
    settings.mMotionQuality=JPH::EMotionQuality::LinearCast;
    settings.mLinearVelocity=jvec(velocity);settings.mAngularVelocity=jvec(spin,kRadians);
    settings.mUserData=free.back()+1;
    const auto id=physics->GetBodyInterfaceNoLock().CreateAndAddBody(settings,JPH::EActivation::Activate);
    need(!id.IsInvalid(),"piece allocation failed");const auto index=free.back();const auto token=next_id++;
    try { ids.emplace(token,index); }catch(...) { destroy(id);throw; }
    free.pop_back();auto& p=pieces[index];p.id=token;p.body=id;p.previous=p.current=jvec(position);p.grouped=false;
    p.before=p.after=rotation(a);p.asleep=false;p.dirty=true;p.damage=0;p.kinds=0;p.damage_queued=false;
    p.hit_x=position.x;p.hit_y=position.y;p.hit_z=position.z;p.sound_tick=simulation_tick-8;p.overlaps.reset();p.wet=false;
    const auto size=shape->GetLocalBounds().GetSize()/kMetres;
    p.thickness=size.GetZ();p.mass=shape->GetMassProperties().mMass;
    const float area=shape->GetVolume()/(kMetres*kMetres*kMetres*p.thickness);
    p.threshold=std::max(12000.0f,36000*std::sqrt(area/64)*p.thickness*p.thickness);
    p.splittable=area>=2*minimum_size*minimum_size && std::max(size.GetX(),size.GetY())>=2*minimum_size &&
      std::min(size.GetX(),size.GetY())>=minimum_size;
    // Tiny fragments keep map/Source contact, but need no mutual pile constraints.
    if(area<4)physics->GetBodyInterfaceNoLock().SetObjectLayer(id,2);
    const auto* created=physics->GetBodyLockInterfaceNoLock().TryGetBody(id);
    for(unsigned i=0;i<kMaxSceneBodies;++i)if(mirrors[i].key &&
      created->GetWorldSpaceBounds().Overlaps(physics->GetBodyLockInterfaceNoLock().TryGetBody(mirrors[i].body)->GetWorldSpaceBounds())) {
      p.overlaps.set(i);++overlap_suppressed;
    }
    queue(index);return token;
  }
};
World::World(unsigned budget,float gravity) {
  need(budget>=1 && budget<=kMaxBudget,"body budget must be 1-8192");
  need(std::isfinite(gravity) && gravity>=0 && gravity<=10000,"gravity must be 0-10000 Source units/s^2");
  impl_=std::make_unique<Impl>(budget,gravity);
}
World::~World() {
  // Only lifecycle teardown may wait. Normal polling and a busy mutation never wait on a worker.
  // A running import is cancelled first and ends at its next bounded unit of work (R19); a finish
  // or a step is short and always completes.
  stop_.request_stop();
  if(loading_.valid())loading_.wait();if(finishing_.valid())finishing_.wait();if(stepping_.valid())stepping_.wait();
}
bool World::busy() const { return loading_.valid() || finishing_.valid() || stepping_.valid(); }
World::Impl& World::idle() const { need(!busy(),"world worker is busy; poll before access");return *impl_; }
std::vector<StaticProp> World::load_map(std::span<const std::uint8_t> bytes) {
  (void)idle();return load_impl(bytes,stop_.get_token());
}
void World::begin_load(std::vector<std::uint8_t> bytes) {
  (void)idle();need(bytes.size()<=kMaxMapBytes,"BSP input size limit");snapshot_=stats();
  // The token is taken here, on the caller's thread: the worker never touches stop_ itself.
  loading_=std::async(std::launch::async,[this,stop=stop_.get_token(),bytes=std::move(bytes)]() mutable {
    // Release the large byte buffer on this worker, before publishing readiness to the client.
    auto owned=std::move(bytes);return load_impl(owned,std::move(stop));
  });
}
bool World::poll_load(std::vector<StaticProp>& props) {
  need(loading_.valid(),"no pending map import");
  if(loading_.wait_for(std::chrono::seconds(0))!=std::future_status::ready)return false;
  props=loading_.get();return true;
}
std::vector<StaticProp> World::load_impl(std::span<const std::uint8_t> bytes,std::stop_token stop) {
  auto& w=*impl_;w.clear_all();
  w.brushes=w.skipped_brushes=w.refused_brushes=w.refused_convexes=w.refused_meshes=w.skipped_props=0;
  // Cooking is checked between shapes and batches, as read_bsp is between its own units.
  auto live=[&stop] { need(!stop.stop_requested(),"BSP import cancelled"); };
  try {
    auto map=read_bsp(bytes,stop);
    w.water=std::move(map.water);w.water_tree.clear();
    if(!w.water.empty()) {
      std::vector<unsigned> order(w.water.size());for(unsigned i=0;i<order.size();++i)order[i]=i;
      w.water_tree.reserve(w.water.size()*2);w.build_water(order,0,static_cast<unsigned>(order.size()));
    }
    w.brushes=map.considered_brushes;w.skipped_brushes=map.skipped_brushes;
    for(const auto& hull:map.brushes) {
      live();
      const auto shape=hull_shape(hull,false);
      if(shape)w.add_static(shape);else ++w.refused_brushes;
    }
    // Split displacement meshes into bounded batches. Make both sides solid for cosmetic debris.
    for(std::size_t first=0;first<map.triangles.size();first+=8192) {
      live();
      JPH::TriangleList triangles;
      const auto end=std::min(first+8192,map.triangles.size());triangles.reserve((end-first)*2);
      for(std::size_t i=first;i<end;++i) {
        const auto& t=map.triangles[i];const auto a=jvec(t.a),b=jvec(t.b),c=jvec(t.c);
        triangles.emplace_back(a,b,c);triangles.emplace_back(a,c,b);
      }
      JPH::MeshShapeSettings settings(triangles);const auto result=settings.Create();
      if(result.HasError())++w.refused_meshes;else w.add_static(result.Get());
    }
    w.loaded=true;return std::move(map.props);
  } catch(...) { w.clear_all();throw; }
}
bool World::add_model(const std::string& name,const std::vector<Hull>& convexes) {
  auto& w=idle();need(w.loaded && !w.ready,"map must be loaded and unfinished");
  need(!name.empty() && name.size()<=128 && convexes.size()>0 && convexes.size()<=128,"invalid prop model/convex count");
  need(!w.models.contains(name) && w.models.size()<2048,"duplicate/too many collision models");
  JPH::StaticCompoundShapeSettings settings;std::size_t points=0;
  for(const auto& hull:convexes) {
    points+=hull.size();need(w.model_points+points<=kMaxMapPoints,"prop collision point limit");
    if(!valid_hull(hull)) { ++w.refused_convexes;continue; }
    const auto shape=hull_shape(hull,false);
    if(shape)settings.AddShape(JPH::Vec3::sZero(),JPH::Quat::sIdentity(),shape);else ++w.refused_convexes;
  }
  w.model_points+=points;
  if(settings.mSubShapes.empty())return false;
  const auto result=settings.Create();if(result.HasError())return false;
  w.models.emplace(name,result.Get());return true;
}
bool World::add_prop(const std::string& model,V3 position,V3 a,float scale) {
  auto& w=idle();need(w.loaded && !w.ready,"map must be loaded and unfinished");
  need(position.valid() && a.valid(36000) && std::isfinite(scale) && scale>0 && scale<=16,"invalid prop transform");
  const auto it=w.models.find(model);if(it==w.models.end()) { ++w.skipped_props;return false; }
  if(scale==1)w.add_static(it->second,position,a);
  else {
    const auto result=JPH::ScaledShapeSettings(it->second,JPH::Vec3::sReplicate(scale)).Create();
    if(result.HasError()) { ++w.skipped_props;return false; }w.add_static(result.Get(),position,a);
  }
  return true;
}
void World::finish() {
  (void)idle();finish_impl();
}
void World::begin_finish() {
  (void)idle();snapshot_=stats();finishing_=std::async(std::launch::async,[this] { finish_impl(); });
}
bool World::poll_finish() {
  need(finishing_.valid(),"no pending world finish");
  if(finishing_.wait_for(std::chrono::seconds(0))!=std::future_status::ready)return false;
  finishing_.get();return true;
}
void World::finish_impl() {
  auto& w=*impl_;need(w.loaded && !w.statics.empty(),"BSP has no usable world collision");w.physics->OptimizeBroadPhase();w.ready=true;
}
std::uint32_t World::spawn(const Hull& hull,V3 position,V3 a,V3 velocity,V3 spin,float minimum_size) {
  auto& w=idle();need(w.ready,"world is not ready");
  need(position.valid() && a.valid(36000) && velocity.valid(100000) && spin.valid(36000),"invalid piece transform/velocity");
  need(std::isfinite(minimum_size) && minimum_size>=1 && minimum_size<=64,"invalid minimum piece size");
  need(w.ids.size()<w.capacity && w.next_id!=0,"piece budget/identifier exhausted");
  // A hull must remain close to its local origin; huge off-centre inputs are not debris.
  for(auto p:hull)need(p.valid(1024),"piece hull exceeds 1024 local units");
  const auto shape=hull_shape(hull,true);
  need(shape!=nullptr,"Jolt refused piece hull");
  return w.create(shape,position,a,velocity,spin,minimum_size);
}
std::uint32_t World::spawn_group(const std::vector<Hull>& hulls,V3 position,V3 a,V3 velocity,V3 spin) {
  auto& w=idle();need(w.ready,"world is not ready");
  need(hulls.size()>=2 && hulls.size()<=8,"group hull count limit");
  need(position.valid() && a.valid(36000) && velocity.valid(100000) && spin.valid(36000),"invalid group transform/velocity");
  need(w.ids.size()<w.capacity && w.next_id!=0,"piece budget/identifier exhausted");
  std::size_t points=0;
  for(const auto& hull:hulls) {
    need(valid_hull(hull),"invalid group hull");points+=hull.size();
    for(auto p:hull)need(p.valid(1024),"group hull exceeds local bounds");
  }
  need(points<=512,"group point limit");
  JPH::StaticCompoundShapeSettings settings;
  for(const auto& hull:hulls) {
    const auto shape=hull_shape(hull,true);need(shape!=nullptr,"Jolt refused group hull");
    settings.AddShape(JPH::Vec3::sZero(),JPH::Quat::sIdentity(),shape);
  }
  const auto result=settings.Create();need(!result.HasError(),"Jolt refused group");
  const auto id=w.create(result.Get(),position,a,velocity,spin);
  auto* p=w.find(id);p->grouped=true;p->splittable=false;
  return id;
}
bool World::remove(std::uint32_t id) {
  auto& w=idle();auto* p=w.find(id);if(!p)return false;
  const auto index=w.ids.at(id);w.unqueue(index);w.destroy(p->body);p->id=0;p->damage_queued=false;p->damage=0;p->kinds=0;
  w.ids.erase(id);w.free.push_back(index);return true;
}
void World::clear() {
  if(stepping_.valid()) { stepping_.wait();stepping_.get(); }
  idle().clear_pieces();
}
void World::impulse(V3 origin,float radius,float speed) {
  need(origin.valid() && std::isfinite(radius) && radius>0 && radius<=131072 &&
    std::isfinite(speed) && speed>=0 && speed<=100000,"invalid impulse");
  auto& w=idle();auto& bi=w.physics->GetBodyInterfaceNoLock();
  for(auto& p:w.pieces)if(p.id) {
    const auto delta=vec(bi.GetPosition(p.body))-origin;const auto distance=delta.length();
    if(distance>=radius)continue;
    const auto direction=distance>.001f?delta*(1/distance):V3{0,0,1};
    // A bounded radial velocity kick: independent of each shard's mass.
    const auto kick=jvec(direction*(speed*(1-distance/radius)));
    bi.ActivateBody(p.body);bi.SetLinearVelocity(p.body,bi.GetLinearVelocity(p.body)+kick);p.asleep=false;p.dirty=true;
    if(w.interaction) { const float v=speed*(1-distance/radius);if(v>=220)w.damage(static_cast<unsigned>(&p-w.pieces.data()),.5f*p.mass*v*v,Blast,origin); }
    w.queue(static_cast<unsigned>(&p-w.pieces.data()));
  }
}
void World::set_collide(bool enabled) {
  auto& w=idle();if(w.collide==enabled)return;w.collide=enabled;auto& bi=w.physics->GetBodyInterfaceNoLock();
  for(auto& p:w.pieces)if(p.id) {
    const auto* body=w.physics->GetBodyLockInterfaceNoLock().TryGetBody(p.body);
    const bool tiny=body->GetShape()->GetVolume()/(kMetres*kMetres*kMetres*p.thickness)<4;
    bi.SetObjectLayer(p.body,enabled && !tiny?1:2);bi.InvalidateContactCache(p.body);bi.ActivateBody(p.body);p.asleep=false;p.dirty=true;
    w.queue(static_cast<unsigned>(&p-w.pieces.data()));
  }
}
void World::set_gravity(float gravity) {
  need(std::isfinite(gravity) && gravity>=0 && gravity<=10000,"invalid gravity");
  auto& w=idle();if(w.gravity==gravity)return;w.gravity=gravity;w.physics->SetGravity({0,0,-gravity*kMetres});
  for(auto& p:w.pieces)if(p.id) {
    w.physics->GetBodyInterfaceNoLock().ActivateBody(p.body);p.asleep=false;p.dirty=true;
    w.queue(static_cast<unsigned>(&p-w.pieces.data()));
  }
}
void World::set_interaction(bool enabled) {
  auto& w=idle();if(w.interaction==enabled)return;w.interaction=enabled;
  if(!enabled) { w.clear_scene();(void)take_damage(); }
}
void World::set_collision_flags(unsigned flags) {
  need(flags<=15,"invalid collision flags");auto& w=idle();
  if(w.collision_flags!=flags) { w.collision_flags=flags;w.clear_scene(); }
}
unsigned World::sync_bodies(const std::vector<SceneBody>& bodies,double sample_dt) {
  auto& w=idle();need(w.ready,"world is not ready");
  need(bodies.size()<=kMaxSceneBodies && std::isfinite(sample_dt) && sample_dt>=.001 && sample_dt<=.25,"invalid scene count/timestep");
  unsigned cooks=0;
  for(std::size_t i=0;i<bodies.size();++i) {
    const auto& s=bodies[i];
    need(s.kind==Objects || s.kind==Ragdolls || s.kind==Players || s.kind==NPCs,"invalid scene kind");
    need(s.key && s.position.valid() && s.angles.valid(36000) && s.velocity.valid(100000) && s.half.valid(1024) &&
      s.half.x>=.05f && s.half.y>=.05f && s.half.z>=.05f && std::isfinite(s.mass) && s.mass>=.01f && s.mass<=50000,"invalid scene body");
    for(std::size_t j=0;j<i;++j)need(bodies[j].key!=s.key,"duplicate scene key");
    if(!s.convexes.empty()) {
      need(++cooks<=2 && s.convexes.size()<=8,"scene cooking budget exceeded");
      std::size_t points=0;for(const auto& h:s.convexes) {
        need(valid_hull(h),"invalid scene convex");points+=h.size();
        for(auto p:h)need(p.valid(1024),"scene hull exceeds local bounds");
      }
      need(points<=512,"scene shape point budget exceeded");
    }
  }
  if(!w.interaction) { w.clear_scene();return 0; }
  auto& bi=w.physics->GetBodyInterfaceNoLock();w.scene_moves=0;
  Impl::SweepBudget sweep_budget;
  for(auto& m:w.mirrors)if(m.key) {
    m.seen=false;
    if(std::none_of(bodies.begin(),bodies.end(),[&](const SceneBody& s) { return s.key==m.key && (s.kind&w.collision_flags); })) { w.destroy(m.body);m=Impl::Mirror{}; }
  }
  for(const auto& s:bodies) {
    if(!(s.kind&w.collision_flags))continue;
    auto it=std::find_if(w.mirrors.begin(),w.mirrors.end(),[&](const auto& m) { return m.key==s.key; });
    const bool fresh=it==w.mirrors.end();
    if(fresh)it=std::find_if(w.mirrors.begin(),w.mirrors.end(),[](const auto& m) { return !m.key; });
    need(it!=w.mirrors.end(),"scene body allocation limit");auto& m=*it;
    JPH::RefConst<JPH::Shape> shape;
    const bool box_changed=!m.custom && (s.half-m.half).length()>.01f;
    if(!s.convexes.empty()) {
      JPH::StaticCompoundShapeSettings settings;
      for(const auto& h:s.convexes) { const auto sub=hull_shape(h,false);if(sub)settings.AddShape(JPH::Vec3::sZero(),JPH::Quat::sIdentity(),sub); }
      if(!settings.mSubShapes.empty()) { const auto result=settings.Create();if(!result.HasError())shape=result.Get(); }
      if(shape) { m.custom=true;++w.scene_cooks; }
    }
    if(!shape && (fresh || box_changed))shape=new JPH::BoxShape(jvec(s.half),.0005f);
    const auto target=jvec(s.position);const auto q=rotation(s.angles);
    if(fresh) {
      // One sample of incoming motion lets a newly discovered fast body actually sweep into glass.
      auto history=jvec(s.velocity)*(1.0f/60);if(history.Length()>128*kMetres)history=JPH::Vec3::sZero();
      JPH::BodyCreationSettings settings(shape,target-history,q,JPH::EMotionType::Kinematic,3);
      settings.mUserData=static_cast<JPH::uint64>(it-w.mirrors.begin()+1);
      settings.mFriction=.65f;settings.mRestitution=.025f;
      m.body=bi.CreateAndAddBody(settings,JPH::EActivation::Activate);need(!m.body.IsInvalid(),"scene body allocation failed");m.key=s.key;
    } else if(shape)bi.SetShape(m.body,shape,false,JPH::EActivation::Activate);
    m.half=s.half;m.mass=s.mass;m.target=target;m.rotation=q;m.seen=true;
    const auto delta=target-bi.GetPosition(m.body);
    if(delta.Length()>128*kMetres) { // Teleports are pose corrections, never a giant impact.
      bi.SetPositionAndRotation(m.body,target,q,JPH::EActivation::DontActivate);
      bi.SetLinearAndAngularVelocity(m.body,JPH::Vec3::sZero(),JPH::Vec3::sZero());m.remaining=0;
      w.mark_overlap(static_cast<unsigned>(it-w.mirrors.begin()),true);
    } else if(fresh || delta.LengthSq()>1e-10f || std::abs(bi.GetRotation(m.body).Dot(q))<.999999f) {
      m.remaining=static_cast<float>(std::clamp(sample_dt,1.0/60,4.0/60));++w.scene_moves;
      w.sweep_mirror(m,delta,m.remaining,sweep_budget);
    }
    if(fresh)w.mark_overlap(static_cast<unsigned>(it-w.mirrors.begin()));
  }
  return w.scene_moves;
}
Pose World::scene_pose(std::uint32_t key) const {
  const auto& w=idle();for(const auto& m:w.mirrors)if(m.key==key) {
    const auto& bi=w.physics->GetBodyInterfaceNoLock();return {key,vec(bi.GetPosition(m.body)),angles(bi.GetRotation(m.body)),!bi.IsActive(m.body)};
  }
  throw Error("unknown scene key");
}
std::vector<Region> World::regions(V3 focus) const {
  need(focus.valid(),"invalid scene focus");
  const auto& w=idle();std::vector<Region> out;out.reserve(kMaxRegions);
  std::array<std::array<int,3>,kMaxRegions> cells{};
  std::array<float,kMaxRegions> scores{};
  for(const auto& p:w.pieces)if(p.id) {
    const auto* b=w.physics->GetBodyLockInterfaceNoLock().TryGetBody(p.body);
    const auto c=vec(b->GetPosition());const std::array<int,3> key{int(std::floor(c.x/512)),int(std::floor(c.y/512)),int(std::floor(c.z/512))};
    std::size_t index=0;while(index<out.size() && cells[index]!=key)++index;
    const V3 delta{(key[0]+.5f)*512-focus.x,(key[1]+.5f)*512-focus.y,(key[2]+.5f)*512-focus.z};
    const auto score=delta.dot(delta);bool replace=false;
    if(index==kMaxRegions) {
      const auto furthest=std::max_element(scores.begin(),scores.end());
      if(score>=*furthest)continue;
      index=static_cast<std::size_t>(furthest-scores.begin());replace=true;
    }
    const auto bounds=b->GetWorldSpaceBounds();const auto lo=vec(bounds.mMin)-V3{96,96,96},hi=vec(bounds.mMax)+V3{96,96,96};
    if(replace) { cells[index]=key;scores[index]=score;out[index]={lo,hi}; }
    else if(index==out.size()) { cells[index]=key;scores[index]=score;out.push_back({lo,hi}); }
    else {
      auto& r=out[index];r.minimum={std::min(r.minimum.x,lo.x),std::min(r.minimum.y,lo.y),std::min(r.minimum.z,lo.z)};
      r.maximum={std::max(r.maximum.x,hi.x),std::max(r.maximum.y,hi.y),std::max(r.maximum.z,hi.z)};
    }
  }
  std::sort(out.begin(),out.end(),[focus](const Region& a,const Region& b) {
    const auto da=(a.minimum+a.maximum)*.5f-focus,db=(b.minimum+b.maximum)*.5f-focus;
    return da.dot(da)<db.dot(db);
  });
  return out;
}
std::vector<DamageEvent> World::take_damage() {
  auto& w=idle();const auto n=std::min(w.damage_count.exchange(0),kMaxDamageEvents);
  std::vector<DamageEvent> out;out.reserve(n);
  for(unsigned i=0;i<n;++i) {
    const auto [slot,id]=w.damage_slots[i];auto& p=w.pieces[slot];if(p.id!=id)continue;
    const auto energy=p.damage.exchange(0);const auto kinds=p.kinds.exchange(0);p.damage_queued=false;
    if(energy>0)out.push_back({id,energy,kinds});
  }
  return out;
}
void World::set_sounds(bool enabled) { auto& w=idle();w.sounds=enabled;if(!enabled)w.sound_count=0; }
std::vector<SoundEvent> World::take_sounds() {
  auto& w=idle();const auto n=std::min(w.sound_count.exchange(0),kMaxSoundEvents);
  return {w.sound_slots.begin(),w.sound_slots.begin()+n};
}
Motion World::motion(std::uint32_t id) const {
  auto& w=idle();const auto* p=w.find(id);need(p!=nullptr,"unknown piece id");
  const auto& bi=w.physics->GetBodyInterfaceNoLock();
  return {vec(bi.GetPosition(p->body)),vec(bi.GetLinearVelocity(p->body)),vec(bi.GetAngularVelocity(p->body),1/kRadians)};
}
std::uint32_t World::ray(V3 from,V3 to,float energy,float speed) {
  need(from.valid() && to.valid() && (to-from).length()<=131072 && std::isfinite(energy) && energy>=0 && energy<=1e9 &&
    std::isfinite(speed) && speed>=0 && speed<=2000,"invalid debris ray");
  auto& w=idle();if(!w.interaction || (to-from).length()<.001f)return 0;
  class Pieces final:public JPH::ObjectLayerFilter { bool ShouldCollide(JPH::ObjectLayer l) const override { return l==1 || l==2; } } filter;
  JPH::RayCastResult hit;
  if(!w.physics->GetNarrowPhaseQueryNoLock().CastRay(JPH::RRayCast(jvec(from),jvec(to-from)),hit,{},filter))return 0;
  const auto* body=w.physics->GetBodyLockInterfaceNoLock().TryGetBody(hit.mBodyID);
  const auto slot=static_cast<unsigned>(body->GetUserData()-1);auto& p=w.pieces[slot];
  auto& bi=w.physics->GetBodyInterfaceNoLock();const auto kick=jvec((to-from)*(speed/(to-from).length()));
  bi.ActivateBody(p.body);bi.SetLinearVelocity(p.body,bi.GetLinearVelocity(p.body)+kick);p.asleep=false;p.dirty=true;w.queue(slot);
  w.damage(slot,energy,Bullet,from+(to-from)*hit.mFraction);++w.ray_hits;return p.id;
}
unsigned World::melee(V3 from,V3 to,float energy,float speed,float radius) {
  need(from.valid() && to.valid() && (to-from).length()<=256 && std::isfinite(energy) && energy>=0 && energy<=1e9 &&
    std::isfinite(speed) && speed>=0 && speed<=2000 && std::isfinite(radius) && radius>=1 && radius<=16,"invalid debris melee");
  auto& w=idle();if(!w.interaction || (to-from).length()<.001f)return 0;
  struct Collector final:JPH::CastShapeCollector {
    std::array<JPH::BodyID,8> hits;unsigned count=0,visits=0,bodies=0;bool limited=false;
    void OnBody(const JPH::Body&) override { if(++bodies==64) { limited=true;ForceEarlyOut(); } }
    void AddHit(const JPH::ShapeCastResult& hit) override {
      if(count==8 || visits==64)return;
      if(++visits==64) { limited=true;ForceEarlyOut(); }
      for(unsigned i=0;i<count;++i)if(hits[i]==hit.mBodyID2)return;
      hits[count++]=hit.mBodyID2;
      if(count==8) { limited=true;ForceEarlyOut(); }
    }
  } collector;
  class Pieces final:public JPH::ObjectLayerFilter { bool ShouldCollide(JPH::ObjectLayer l) const override { return l==1 || l==2; } } filter;
  const JPH::SphereShape shape(radius*kMetres);
  const JPH::RShapeCast cast(&shape,JPH::Vec3::sReplicate(1),JPH::RMat44::sTranslation(jvec(from)),jvec(to-from));
  JPH::ShapeCastSettings settings;
  w.physics->GetNarrowPhaseQueryNoLock().CastShape(cast,settings,JPH::RVec3::sZero(),collector,{},filter);
  auto& bi=w.physics->GetBodyInterfaceNoLock();const auto kick=jvec((to-from)*(speed/(to-from).length()));
  for(unsigned i=0;i<collector.count;++i) {
    const auto id=collector.hits[i];const auto* body=w.physics->GetBodyLockInterfaceNoLock().TryGetBody(id);
    const auto slot=static_cast<unsigned>(body->GetUserData()-1);auto& p=w.pieces[slot];
    bi.ActivateBody(id);bi.SetLinearVelocity(id,bi.GetLinearVelocity(id)+kick);p.asleep=false;p.dirty=true;w.queue(slot);
    w.damage(slot,energy,Melee,vec(body->GetPosition()));
  }
  w.melee_hits+=collector.count;if(collector.limited)++w.melee_limited;
  return collector.count;
}
bool World::can_split(std::uint32_t id,float minimum_size) const {
  auto& w=idle();auto* p=w.find(id);if(!p)return false;
  if(p->grouped)return false; // adaptive rigid groups keep exact sub-hulls and respond by moving.
  const auto* body=w.physics->GetBodyLockInterfaceNoLock().TryGetBody(p->body);
  const auto* shape=static_cast<const JPH::ConvexHullShape*>(body->GetShape());
  Hull points;points.reserve(shape->GetNumPoints());
  for(unsigned i=0;i<shape->GetNumPoints();++i)points.push_back(vec(shape->GetPoint(i)+shape->GetCenterOfMass()));
  return !split_polygon(outline_xy(points),minimum_size).empty();
}
std::vector<Fragment> World::split(std::uint32_t id,float minimum_size,unsigned maximum) {
  auto& w=idle();need(std::isfinite(minimum_size) && minimum_size>=1 && minimum_size<=64 && maximum>=2 && maximum<=6,"invalid minimum piece size/count");
  auto* p=w.find(id);if(!p || p->grouped || w.ids.size()>=w.capacity)return {};
  auto& bi=w.physics->GetBodyInterfaceNoLock();const auto* body=w.physics->GetBodyLockInterfaceNoLock().TryGetBody(p->body);
  const auto* shape=static_cast<const JPH::ConvexHullShape*>(body->GetShape());
  Hull points;points.reserve(shape->GetNumPoints());
  for(unsigned i=0;i<shape->GetNumPoints();++i)points.push_back(vec(shape->GetPoint(i)+shape->GetCenterOfMass()));
  const auto position=bi.GetPosition(p->body);const auto q=bi.GetRotation(p->body);
  const auto hit=vec(q.Conjugated()*(jvec({p->hit_x.load(),p->hit_y.load(),p->hit_z.load()})-position));
  maximum=std::min(maximum,static_cast<unsigned>(w.capacity-w.ids.size()+1));
  const auto polygons=split_polygon(outline_xy(points),minimum_size,hit,id*7919u+w.splits,maximum);if(polygons.empty())return {};
  const auto velocity=bi.GetLinearVelocity(p->body),spin=bi.GetAngularVelocity(p->body);
  const auto thick=p->thickness;
  std::vector<Fragment> out;out.reserve(polygons.size());std::array<JPH::RefConst<JPH::Shape>,6> shapes;
  const auto overlaps=p->overlaps;
  for(unsigned i=0;i<polygons.size();++i) {
    auto poly=polygons[i];const auto center=polygon_center(poly);for(auto& v:poly)v=v-center;
    shapes[i]=hull_shape(extrude(poly,thick),true);if(!shapes[i])return {};
    const auto delta=q*jvec(center);
    out.push_back({0,std::move(poly),thick,vec(position+delta),angles(q),vec(velocity+spin.Cross(delta)),vec(spin,1/kRadians)});
  }
  // Six private slots permit transactional replacement; completed live counts respect capacity.
  // Public Spawn and completed Split never exceed the configured capacity.
  try {
    for(unsigned i=0;i<polygons.size();++i) {
      out[i].id=w.create(shapes[i],out[i].position,out[i].angles,out[i].velocity,out[i].spin,minimum_size);
      w.find(out[i].id)->overlaps|=overlaps;
    }
  } catch(...) { for(const auto& f:out)if(f.id)remove(f.id);throw; }
  w.sound(w.ids.at(id),vec(position),0,2);remove(id);++w.splits;return out;
}
void World::step(double dt) {
  (void)idle();step_impl(dt);
}
void World::set_catch_up_budget(double milliseconds) {
  need(std::isfinite(milliseconds) && milliseconds>=0 && milliseconds<=1000,"catch-up budget must be 0-1000 ms");
  idle().catch_up_ms=milliseconds;
}
void World::begin_step(double dt) {
  auto& w=idle();need(w.ready,"world is not ready");need(std::isfinite(dt) && dt>=0 && dt<=10,"invalid timestep");
  snapshot_=stats();stepping_=std::async(std::launch::async,[this,dt] { step_impl(dt); });
}
bool World::poll_step() {
  need(stepping_.valid(),"no pending step");
  if(stepping_.wait_for(std::chrono::seconds(0))!=std::future_status::ready)return false;
  stepping_.get();return true;
}
void World::step_impl(double dt) {
  need(std::isfinite(dt) && dt>=0 && dt<=10,"invalid timestep");
  auto& w=*impl_;need(w.ready,"world is not ready");
  constexpr double fixed=1.0/60;
  w.dropped+=std::max(0.0,dt-fixed*4);w.accumulator+=std::min(dt,fixed*4);w.substeps=0;
  const auto start=std::chrono::steady_clock::now();
  while(w.accumulator+1e-9>=fixed && w.substeps<4) {
    const auto tick=std::chrono::steady_clock::now();
    const double elapsed=std::chrono::duration<double,std::milli>(tick-start).count();
    // Always permit one fixed update; additional catch-up steps must fit a measured 4 ms budget
    // (C++ tests pin it, so their results never depend on how fast the machine steps).
    if(w.substeps && elapsed+w.last_fixed_ms>=w.catch_up_ms)break;
    ++w.simulation_tick;w.prune_overlaps();w.buoyancy(static_cast<float>(fixed));
    if(w.interaction) {
      auto& bi=w.physics->GetBodyInterfaceNoLock();
      for(auto& m:w.mirrors)if(m.key) {
        if(m.remaining>0) {
          const auto p=bi.GetPosition(m.body);const auto q=bi.GetRotation(m.body);
          const float t=std::min(1.0f,static_cast<float>(fixed)/m.remaining);
          bi.MoveKinematic(m.body,p+(m.target-p)*t,q.SLERP(m.rotation,t),static_cast<float>(fixed));
          m.remaining=std::max(0.0f,m.remaining-static_cast<float>(fixed));
        } else if(bi.IsActive(m.body)) {
          bi.SetLinearAndAngularVelocity(m.body,JPH::Vec3::sZero(),JPH::Vec3::sZero());bi.DeactivateBody(m.body);
        }
      }
    }
    const auto n=w.physics->GetNumActiveBodies(JPH::EBodyType::RigidBody);
    if(n) {
      const unsigned scratch=2*1024*1024+((static_cast<unsigned>(w.ids.size())+255)/256)*256*8192;
      if(!w.temp || w.temp->reserved<scratch)w.temp=std::make_unique<Scratch>(scratch);
      const auto* active=w.physics->GetActiveBodiesUnsafe(JPH::EBodyType::RigidBody);
      w.active_before.assign(active,active+n);
      auto body=[&](JPH::BodyID id) { return w.physics->GetBodyLockInterfaceNoLock().TryGetBody(id); };
      for(auto id:w.active_before) {
        const auto* b=body(id);if(b->GetObjectLayer()==3)continue;
        auto& p=w.pieces[b->GetUserData()-1];p.previous=p.current;p.before=p.after;
      }
      const auto error=w.physics->Update(static_cast<float>(fixed),1,w.temp.get(),w.jobs.get());
      // A small first population can still need capacity-sized solver scratch. Learn that demand
      // once; retain non-aborting fallback for any later peak rather than malloc/free every frame.
      if(w.temp->peak>w.temp->reserved) {
        const auto bytes=static_cast<unsigned>((w.temp->peak+1048575)/1048576*1048576);
        const auto peak=w.temp->peak;w.temp=std::make_unique<Scratch>(bytes);w.temp->peak=peak;
      }
      if(error!=JPH::EPhysicsUpdateError::None)++w.contact_overflows;
      if((error&JPH::EPhysicsUpdateError::ManifoldCacheFull)!=JPH::EPhysicsUpdateError::None)++w.manifold_overflows;
      if((error&JPH::EPhysicsUpdateError::BodyPairCacheFull)!=JPH::EPhysicsUpdateError::None)++w.pair_overflows;
      if((error&JPH::EPhysicsUpdateError::ContactConstraintsFull)!=JPH::EPhysicsUpdateError::None)++w.constraint_overflows;
      ++w.epoch;
      auto capture=[&](JPH::BodyID id) {
        const auto* b=body(id);if(b->GetObjectLayer()==3)return;
        const auto slot=static_cast<unsigned>(b->GetUserData()-1);auto& p=w.pieces[slot];
        if(p.seen==w.epoch)return;
        p.seen=w.epoch;p.current=b->GetPosition();p.after=b->GetRotation();p.asleep=!b->IsActive();p.dirty=true;w.queue(slot);
      };
      // The old active set includes bodies that just fell asleep. The new one includes pile wakes.
      for(auto id:w.active_before)capture(id);
      active=w.physics->GetActiveBodiesUnsafe(JPH::EBodyType::RigidBody);
      const auto after=w.physics->GetNumActiveBodies(JPH::EBodyType::RigidBody);
      for(unsigned i=0;i<after;++i)capture(active[i]);
    }
    w.accumulator=std::max(0.0,w.accumulator-fixed);++w.substeps;
    w.last_fixed_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-tick).count();
  }
  // Only a missed budget leaves a whole step due (same tolerance as the loop): drop it, never queue it.
  if(w.accumulator+1e-9>=fixed) {
    const auto discard=std::floor((w.accumulator+1e-9)/fixed)*fixed;
    w.accumulator=std::max(0.0,w.accumulator-discard);w.dropped+=discard;w.skip_mirrors(static_cast<float>(discard));
  }
  w.step_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
}
std::span<const Pose> World::poses() {
  auto& w=idle();w.output.clear();const auto alpha=static_cast<float>(w.accumulator*60);
  w.pose_visits=static_cast<unsigned>(w.pose_slots.size());
  for(std::size_t i=0;i<w.pose_slots.size();) {
    const auto slot=w.pose_slots[i];auto& p=w.pieces[slot];
    const auto position=p.asleep?p.current:p.previous+(p.current-p.previous)*alpha;
    const auto q=p.asleep?p.after:p.before.SLERP(p.after,alpha);
    w.output.push_back({p.id,vec(position),angles(q),p.asleep});p.dirty=false;
    if(p.asleep)w.unqueue(slot);else ++i;
  }
  return w.output;
}
bool World::sleeping(std::uint32_t id) const {
  auto& w=idle();auto* p=w.find(id);need(p!=nullptr,"unknown piece id");return !w.physics->GetBodyInterfaceNoLock().IsActive(p->body);
}
Stats World::stats() const {
  if(busy()) { auto s=snapshot_;s.busy=true;return s; }
  const auto& w=*impl_;Stats s;
  s.live=static_cast<unsigned>(w.ids.size());s.awake=w.physics->GetNumActiveBodies(JPH::EBodyType::RigidBody);
  for(const auto& m:w.mirrors)if(m.key) { ++s.scene_bodies;if(w.physics->GetBodyInterfaceNoLock().IsActive(m.body))--s.awake; }
  s.scene_moves=w.scene_moves;s.scene_cooks=w.scene_cooks;s.damage_dropped=w.damage_dropped.load();
  s.scene_sweeps=w.scene_sweeps;s.scene_sweep_hits=w.scene_sweep_hits;s.scene_sweep_limited=w.scene_sweep_limited;
  s.ray_hits=w.ray_hits;s.splits=w.splits;s.interaction=w.interaction;s.collision_flags=w.collision_flags;
  s.melee_hits=w.melee_hits;s.melee_limited=w.melee_limited;
  s.sound_events=w.sound_events;s.sound_dropped=w.sound_dropped;
  s.water_volumes=static_cast<unsigned>(w.water.size());s.water_tests=w.water_tests;s.water_applied=w.water_applied;
  s.water_entries=w.water_entries;s.water_ms=w.water_ms;s.overlap_suppressed=w.overlap_suppressed;
  s.statics=static_cast<unsigned>(w.statics.size());s.models=static_cast<unsigned>(w.models.size());
  s.workers=w.workers;s.substeps=w.substeps;s.step_ms=w.step_ms;s.dropped_seconds=w.dropped;s.ready=w.ready;
  s.brushes=w.brushes;s.skipped_brushes=w.skipped_brushes;
  s.refused_brushes=w.refused_brushes;s.refused_convexes=w.refused_convexes;s.refused_meshes=w.refused_meshes;s.skipped_props=w.skipped_props;
  s.contact_overflows=w.contact_overflows;s.manifold_overflows=w.manifold_overflows;
  s.pair_overflows=w.pair_overflows;s.constraint_overflows=w.constraint_overflows;s.pose_visits=w.pose_visits;
  if(w.temp) { s.temp_reserved_bytes=w.temp->reserved;s.temp_peak_bytes=w.temp->peak; }
  return s;
}
}
