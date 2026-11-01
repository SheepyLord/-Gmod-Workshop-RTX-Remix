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
  bool ShouldCollide(JPH::ObjectLayer a,JPH::BroadPhaseLayer b) const override { return a!=0 || b.GetValue()!=0; }
};
class PairFilter final:public JPH::ObjectLayerPairFilter {
public:
  bool ShouldCollide(JPH::ObjectLayer a,JPH::ObjectLayer b) const override {
    return (a==0 && b!=0)||(b==0 && a!=0)||(a==1 && b==1);
  }
};
JPH::RefConst<JPH::Shape> hull_shape(const Hull& hull,bool glass) {
  need(valid_hull(hull),"invalid/flat hull (4-256 finite noncoplanar points required)");
  JPH::Array<JPH::Vec3> points;points.reserve(hull.size());for(auto p:hull)points.push_back(jvec(p));
  JPH::ConvexHullShapeSettings settings(points,glass?.0005f:.001f);
  settings.mHullTolerance=.00005f;settings.mDensity=2500; // ordinary soda-lime glass, kg/m^3
  const auto result=settings.Create();return result.HasError()?nullptr:result.Get();
}
}
struct World::Impl {
  struct Piece {
    std::uint32_t id=0;
    JPH::BodyID body;
    JPH::RVec3 previous=JPH::RVec3::sZero(),current=JPH::RVec3::sZero();
    JPH::Quat before=JPH::Quat::sIdentity(),after=JPH::Quat::sIdentity();
    bool asleep=false,dirty=true;
  };
  std::shared_ptr<Runtime> registry;
  BroadLayers broad;ObjectBroadFilter object_filter;PairFilter pair_filter;
  std::unique_ptr<JPH::PhysicsSystem> physics;
  std::unique_ptr<JPH::JobSystemThreadPool> jobs;
  std::unique_ptr<JPH::TempAllocatorImplWithMallocFallback> temp;
  std::vector<Piece> pieces;
  std::vector<unsigned> free;
  std::unordered_map<std::uint32_t,unsigned> ids;
  std::vector<JPH::BodyID> statics;
  std::unordered_map<std::string,JPH::RefConst<JPH::Shape>> models;
  std::vector<Pose> output;
  std::uint32_t next_id=1;
  bool collide=true,loaded=false,ready=false;
  unsigned workers=1,substeps=0,brushes=0,skipped_brushes=0;
  unsigned refused_brushes=0,refused_convexes=0,refused_meshes=0,skipped_props=0;
  std::size_t model_points=0;
  float gravity=600;
  double accumulator=0,step_ms=0,dropped=0;

  Impl(unsigned budget,float g):registry(runtime()),pieces(budget),gravity(g) {
    const unsigned hw=std::thread::hardware_concurrency();
    workers=std::clamp(hw>2?hw-2:1u,1u,8u);
    jobs=std::make_unique<JPH::JobSystemThreadPool>(JPH::cMaxPhysicsJobs,JPH::cMaxPhysicsBarriers,static_cast<int>(workers));
    // Bounded scratch, sized above the worst case for our bounded body/contact/pair tables.
    // The fixed-only upstream allocator aborts on overflow. Keep its non-aborting heap fallback;
    // work remains bounded by the body, pair and contact tables.
    temp=std::make_unique<JPH::TempAllocatorImplWithMallocFallback>(16*1024*1024+budget*16384);
    physics=std::make_unique<JPH::PhysicsSystem>();
    physics->Init(static_cast<JPH::uint>(budget+kMaxStaticBodies),0,budget*32,budget*16,broad,object_filter,pair_filter);
    JPH::PhysicsSettings settings;
    settings.mTimeBeforeSleep=.35f;settings.mPointVelocitySleepThreshold=.06f;
    settings.mPenetrationSlop=.001f;settings.mSpeculativeContactDistance=.003f;
    settings.mMaxPenetrationDistance=.03f;settings.mNumVelocitySteps=6;settings.mNumPositionSteps=2;
    settings.mMaxInFlightBodyPairs=static_cast<int>(budget*16);
    physics->SetPhysicsSettings(settings);physics->SetGravity({0,0,-g*kMetres});
    ids.reserve(budget);output.reserve(budget);free.reserve(budget);statics.reserve(kMaxStaticBodies);
    for(unsigned i=budget;i>0;--i)free.push_back(i-1);
  }
  ~Impl() { clear_all(); }
  void destroy(JPH::BodyID body) {
    auto& bi=physics->GetBodyInterface();bi.RemoveBody(body);bi.DestroyBody(body);
  }
  void clear_pieces() {
    for(auto& p:pieces)if(p.id) { destroy(p.body);p.id=0; }
    ids.clear();free.clear();for(unsigned i=static_cast<unsigned>(pieces.size());i>0;--i)free.push_back(i-1);
    accumulator=0;output.clear();
  }
  void clear_all() {
    clear_pieces();for(auto id:statics)destroy(id);statics.clear();models.clear();model_points=0;loaded=ready=false;
  }
  void add_static(JPH::RefConst<JPH::Shape> shape,V3 p={},V3 a={}) {
    need(statics.size()<kMaxStaticBodies,"static-world body limit");
    JPH::BodyCreationSettings s(shape,jvec(p),rotation(a),JPH::EMotionType::Static,0);
    s.mFriction=.65f;s.mRestitution=.02f;
    const auto id=physics->GetBodyInterface().CreateAndAddBody(s,JPH::EActivation::DontActivate);
    need(!id.IsInvalid(),"static-world allocation failed");statics.push_back(id);
  }
  Piece* find(std::uint32_t id) {
    const auto it=ids.find(id);return it==ids.end()?nullptr:&pieces[it->second];
  }
};
World::World(unsigned budget,float gravity) {
  need(budget>=1 && budget<=kMaxBudget,"body budget must be 1-8192");
  need(std::isfinite(gravity) && gravity>=0 && gravity<=10000,"gravity must be 0-10000 Source units/s^2");
  impl_=std::make_unique<Impl>(budget,gravity);
}
World::~World()=default;
std::vector<StaticProp> World::load_map(std::span<const std::uint8_t> bytes) {
  auto& w=*impl_;w.clear_all();
  w.brushes=w.skipped_brushes=w.refused_brushes=w.refused_convexes=w.refused_meshes=w.skipped_props=0;
  try {
    auto map=read_bsp(bytes);
    w.brushes=map.considered_brushes;w.skipped_brushes=map.skipped_brushes;
    for(const auto& hull:map.brushes) {
      const auto shape=hull_shape(hull,false);
      if(shape)w.add_static(shape);else ++w.refused_brushes;
    }
    // Split displacement meshes into bounded batches. Make both sides solid for cosmetic debris.
    for(std::size_t first=0;first<map.triangles.size();first+=8192) {
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
  auto& w=*impl_;need(w.loaded && !w.ready,"map must be loaded and unfinished");
  need(!name.empty() && name.size()<=128 && convexes.size()>0 && convexes.size()<=128,"invalid prop model/convex count");
  need(!w.models.contains(name) && w.models.size()<2048,"duplicate/too many collision models");
  JPH::StaticCompoundShapeSettings settings;std::size_t points=0;
  for(const auto& hull:convexes) {
    points+=hull.size();need(w.model_points+points<=kMaxMapPoints,"prop collision point limit");
    const auto shape=hull_shape(hull,false);
    if(shape)settings.AddShape(JPH::Vec3::sZero(),JPH::Quat::sIdentity(),shape);else ++w.refused_convexes;
  }
  w.model_points+=points;
  if(settings.mSubShapes.empty())return false;
  const auto result=settings.Create();if(result.HasError())return false;
  w.models.emplace(name,result.Get());return true;
}
bool World::add_prop(const std::string& model,V3 position,V3 a,float scale) {
  auto& w=*impl_;need(w.loaded && !w.ready,"map must be loaded and unfinished");
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
  auto& w=*impl_;need(w.loaded && !w.statics.empty(),"BSP has no usable world collision");w.physics->OptimizeBroadPhase();w.ready=true;
}
std::uint32_t World::spawn(const Hull& hull,V3 position,V3 a,V3 velocity,V3 spin) {
  auto& w=*impl_;need(w.ready,"world is not ready");
  need(position.valid() && a.valid(36000) && velocity.valid(100000) && spin.valid(36000),"invalid piece transform/velocity");
  need(!w.free.empty() && w.next_id!=0,"piece budget/identifier exhausted");
  // A hull must remain close to its local origin; huge off-centre inputs are not debris.
  for(auto p:hull)need(p.valid(1024),"piece hull exceeds 1024 local units");
  const auto shape=hull_shape(hull,true);
  need(shape!=nullptr,"Jolt refused piece hull");
  JPH::BodyCreationSettings settings(shape,jvec(position),rotation(a),JPH::EMotionType::Dynamic,w.collide?1:2);
  settings.mFriction=.65f;settings.mRestitution=.025f;settings.mLinearDamping=.15f;settings.mAngularDamping=.35f;
  settings.mMaxLinearVelocity=200;settings.mMaxAngularVelocity=100;
  settings.mMotionQuality=JPH::EMotionQuality::LinearCast;
  settings.mLinearVelocity=jvec(velocity);settings.mAngularVelocity=jvec(spin,kRadians);
  settings.mUserData=w.free.back()+1;
  const auto id=w.physics->GetBodyInterface().CreateAndAddBody(settings,JPH::EActivation::Activate);
  need(!id.IsInvalid(),"piece allocation failed");
  const auto index=w.free.back();
  // Map insertion can allocate; roll back the Jolt body if the host allocator refuses it.
  const auto token=w.next_id++;
  try { w.ids.emplace(token,index); }catch(...) { w.destroy(id);throw; }
  w.free.pop_back();auto& p=w.pieces[index];p.id=token;p.body=id;p.previous=p.current=jvec(position);
  p.before=p.after=rotation(a);p.asleep=false;p.dirty=true;return token;
}
bool World::remove(std::uint32_t id) {
  auto& w=*impl_;auto* p=w.find(id);if(!p)return false;
  w.destroy(p->body);p->id=0;const auto index=w.ids.at(id);w.ids.erase(id);w.free.push_back(index);return true;
}
void World::clear() { impl_->clear_pieces(); }
void World::impulse(V3 origin,float radius,float speed) {
  need(origin.valid() && std::isfinite(radius) && radius>0 && radius<=131072 &&
    std::isfinite(speed) && speed>=0 && speed<=100000,"invalid impulse");
  auto& w=*impl_;auto& bi=w.physics->GetBodyInterface();
  for(auto& p:w.pieces)if(p.id) {
    const auto delta=vec(bi.GetPosition(p.body))-origin;const auto distance=delta.length();
    if(distance>=radius)continue;
    const auto direction=distance>.001f?delta*(1/distance):V3{0,0,1};
    // A bounded radial velocity kick: independent of each shard's mass.
    const auto kick=jvec(direction*(speed*(1-distance/radius)));
    bi.ActivateBody(p.body);bi.SetLinearVelocity(p.body,bi.GetLinearVelocity(p.body)+kick);p.asleep=false;p.dirty=true;
  }
}
void World::set_collide(bool enabled) {
  auto& w=*impl_;if(w.collide==enabled)return;w.collide=enabled;auto& bi=w.physics->GetBodyInterface();
  for(auto& p:w.pieces)if(p.id) {
    bi.SetObjectLayer(p.body,enabled?1:2);bi.InvalidateContactCache(p.body);bi.ActivateBody(p.body);p.asleep=false;p.dirty=true;
  }
}
void World::set_gravity(float gravity) {
  need(std::isfinite(gravity) && gravity>=0 && gravity<=10000,"invalid gravity");
  auto& w=*impl_;if(w.gravity==gravity)return;w.gravity=gravity;w.physics->SetGravity({0,0,-gravity*kMetres});
  for(auto& p:w.pieces)if(p.id) { w.physics->GetBodyInterface().ActivateBody(p.body);p.asleep=false;p.dirty=true; }
}
void World::step(double dt) {
  need(std::isfinite(dt) && dt>=0 && dt<=10,"invalid timestep");
  auto& w=*impl_;need(w.ready,"world is not ready");
  constexpr double fixed=1.0/60;
  w.dropped+=std::max(0.0,dt-fixed*4);w.accumulator+=std::min(dt,fixed*4);w.substeps=0;
  auto& bi=w.physics->GetBodyInterface();const auto start=std::chrono::steady_clock::now();
  while(w.accumulator+1e-9>=fixed && w.substeps<4) {
    for(auto& p:w.pieces)if(p.id) { p.previous=p.current;p.before=p.after; }
    const auto error=w.physics->Update(static_cast<float>(fixed),1,w.temp.get(),w.jobs.get());
    need(error==JPH::EPhysicsUpdateError::None,"Jolt contact/pair capacity exceeded");
    for(auto& p:w.pieces)if(p.id) {
      const bool asleep=!bi.IsActive(p.body);
      if(!p.asleep || !asleep) { bi.GetPositionAndRotation(p.body,p.current,p.after);p.dirty=true; }
      if(p.asleep!=asleep)p.dirty=true;p.asleep=asleep;
    }
    w.accumulator=std::max(0.0,w.accumulator-fixed);++w.substeps;
  }
  w.step_ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
}
std::span<const Pose> World::poses() {
  auto& w=*impl_;w.output.clear();const auto alpha=static_cast<float>(w.accumulator*60);
  for(auto& p:w.pieces)if(p.id && (!p.asleep || p.dirty)) {
    const auto position=p.asleep?p.current:p.previous+(p.current-p.previous)*alpha;
    const auto q=p.asleep?p.after:p.before.SLERP(p.after,alpha);
    w.output.push_back({p.id,vec(position),angles(q),p.asleep});p.dirty=false;
  }
  return w.output;
}
bool World::sleeping(std::uint32_t id) const {
  auto* p=impl_->find(id);need(p!=nullptr,"unknown piece id");return !impl_->physics->GetBodyInterface().IsActive(p->body);
}
Stats World::stats() const {
  const auto& w=*impl_;Stats s;
  s.live=static_cast<unsigned>(w.ids.size());s.awake=w.physics->GetNumActiveBodies(JPH::EBodyType::RigidBody);
  s.statics=static_cast<unsigned>(w.statics.size());s.models=static_cast<unsigned>(w.models.size());
  s.workers=w.workers;s.substeps=w.substeps;s.step_ms=w.step_ms;s.dropped_seconds=w.dropped;s.ready=w.ready;
  s.brushes=w.brushes;s.skipped_brushes=w.skipped_brushes;
  s.refused_brushes=w.refused_brushes;s.refused_convexes=w.refused_convexes;s.refused_meshes=w.refused_meshes;s.skipped_props=w.skipped_props;
  return s;
}
}
