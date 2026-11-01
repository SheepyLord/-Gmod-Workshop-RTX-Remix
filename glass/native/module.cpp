#include "world.h"
#include <GarrysMod/Lua/Interface.h>
#include <functional>
#include <cstring>
#include <limits>

namespace {
using GarrysMod::Lua::ILuaBase;
namespace Type=GarrysMod::Lua::Type;
using namespace nl::glass;
std::unique_ptr<World> world;
ILuaBase* owner=nullptr;
void need(bool c,const char* message) { if(!c)throw Error(message); }
int absolute(ILuaBase* l,int index) { return index>0?index:l->Top()+index+1; }
void get(ILuaBase* l,int index,unsigned key) {
  index=absolute(l,index);l->PushNumber(key);l->RawGet(index);
}
void set(ILuaBase* l,int index,const char* key) {
  index=absolute(l,index);l->PushString(key);l->Insert(-2);l->RawSet(index);
}
void set(ILuaBase* l,int index,unsigned key) {
  index=absolute(l,index);l->PushNumber(key);l->Insert(-2);l->RawSet(index);
}
double number(ILuaBase* l,int index,double low,double high) {
  need(l->IsType(index,Type::Number),"expected number");const double n=l->GetNumber(index);
  need(std::isfinite(n) && n>=low && n<=high,"number outside allowed range");return n;
}
unsigned integer(ILuaBase* l,int index,unsigned low,unsigned high) {
  const double n=number(l,index,low,high);need(n==std::floor(n),"expected integer");return static_cast<unsigned>(n);
}
std::string string(ILuaBase* l,int index,unsigned limit) {
  need(l->IsType(index,Type::String),"expected string");unsigned len=0;const auto* text=l->GetString(index,&len);
  need(text && len>0 && len<=limit && !std::memchr(text,0,len),"invalid string length/NUL");return std::string(text,len);
}
V3 vector(ILuaBase* l,int index,float bound,bool angle=false) {
  V3 v;
  if(l->IsType(index,angle?Type::Angle:Type::Vector)) {
    const auto& source=angle?l->GetAngle(index):l->GetVector(index);v={source.x,source.y,source.z};
  } else {
    need(l->IsType(index,Type::Table),"expected Vector/Angle or three-number array");index=absolute(l,index);
    get(l,index,1);v.x=static_cast<float>(number(l,-1,-bound,bound));l->Pop();
    get(l,index,2);v.y=static_cast<float>(number(l,-1,-bound,bound));l->Pop();
    get(l,index,3);v.z=static_cast<float>(number(l,-1,-bound,bound));l->Pop();
  }
  need(v.valid(bound),"nonfinite/out-of-range vector");return v;
}
Hull hull(ILuaBase* l,int index,bool require_volume=true) {
  need(l->IsType(index,Type::Table),"expected hull point array");index=absolute(l,index);
  const int count=l->ObjLen(index);need(count>=4 && count<=static_cast<int>(kMaxHullPoints),"hull requires 4-256 points");
  Hull h;h.reserve(count);for(int i=1;i<=count;++i) { get(l,index,i);h.push_back(vector(l,-1,kCoordinateLimit));l->Pop(); }
  need(!require_volume || valid_hull(h),"flat/invalid hull");return h;
}
std::uint32_t id(ILuaBase* l) { return integer(l,1,1,std::numeric_limits<std::uint32_t>::max()); }
World& active(ILuaBase* l) { need(l==owner && world!=nullptr,"nlglass is not initialized in this client realm");return *world; }
template<class F> int guarded(ILuaBase* l,F&& f) noexcept {
  const int top=l->Top();
  try { need(l==owner,"nlglass is client-only");return f(); }
  catch(const std::exception& e) {
    if(l->Top()>top)l->Pop(l->Top()-top);l->PushNil();l->PushString(e.what());return 2;
  } catch(...) {
    if(l->Top()>top)l->Pop(l->Top()-top);l->PushNil();l->PushString("nlglass internal failure");return 2;
  }
}
int success(ILuaBase* l) { l->PushBool(true);return 1; }
int prop_table(ILuaBase* l,const std::vector<StaticProp>& props) {
  auto* LUA=l;LUA->CreateTable();unsigned index=0;
  for(const auto& p:props) {
    LUA->CreateTable();LUA->PushString(p.model.c_str());set(LUA,-2,"model");
    auto addvec=[&](V3 v,const char* field) {
      LUA->CreateTable();LUA->PushNumber(v.x);set(LUA,-2,1);LUA->PushNumber(v.y);set(LUA,-2,2);LUA->PushNumber(v.z);set(LUA,-2,3);set(LUA,-2,field);
    };
    addvec(p.position,"position");addvec(p.angles,"angles");LUA->PushNumber(p.solid);set(LUA,-2,"solid");
    LUA->PushNumber(p.scale);set(LUA,-2,"scale");set(LUA,-2,++index);
  }
  return 1;
}
std::span<const std::uint8_t> map_bytes(ILuaBase* l) {
  need(l->IsType(1,Type::String),"expected BSP byte string");unsigned len=0;
  const auto* data=l->GetString(1,&len);need(data && len<=kMaxMapBytes,"BSP input size limit");
  return {reinterpret_cast<const std::uint8_t*>(data),len};
}
LUA_FUNCTION_STATIC(Init) { return guarded(LUA,[&] {
  const auto budget=integer(LUA,1,1,kMaxBudget);const auto gravity=static_cast<float>(number(LUA,2,0,10000));
  world.reset();world=std::make_unique<World>(budget,gravity);return success(LUA);
}); }
LUA_FUNCTION_STATIC(LoadMap) { return guarded(LUA,[&] {
  auto& w=active(LUA);return prop_table(LUA,w.load_map(map_bytes(LUA)));
}); }
LUA_FUNCTION_STATIC(BeginLoadMap) { return guarded(LUA,[&] {
  auto& w=active(LUA);const auto bytes=map_bytes(LUA);w.begin_load({bytes.begin(),bytes.end()});return success(LUA);
}); }
LUA_FUNCTION_STATIC(PollLoadMap) { return guarded(LUA,[&] {
  std::vector<StaticProp> props;
  if(!active(LUA).poll_load(props)) { LUA->PushBool(false);return 1; }
  return prop_table(LUA,props);
}); }
LUA_FUNCTION_STATIC(AddModel) { return guarded(LUA,[&] {
  auto& w=active(LUA);const auto model=string(LUA,1,128);need(LUA->IsType(2,Type::Table),"expected convex array");
  const int count=LUA->ObjLen(2);need(count>0 && count<=128,"prop model requires 1-128 convexes");
  std::vector<Hull> convexes;convexes.reserve(count);
  for(int i=1;i<=count;++i) { get(LUA,2,i);convexes.push_back(hull(LUA,-1,false));LUA->Pop(); }
  LUA->PushBool(w.add_model(model,convexes));return 1;
}); }
LUA_FUNCTION_STATIC(AddProp) { return guarded(LUA,[&] {
  auto& w=active(LUA);const auto model=string(LUA,1,128);const auto p=vector(LUA,2,kCoordinateLimit),a=vector(LUA,3,36000,true);
  LUA->PushBool(w.add_prop(model,p,a,static_cast<float>(number(LUA,4,.001,16))));return 1;
}); }
LUA_FUNCTION_STATIC(FinishWorld) { return guarded(LUA,[&] { active(LUA).finish();return success(LUA); }); }
LUA_FUNCTION_STATIC(BeginFinishWorld) { return guarded(LUA,[&] { active(LUA).begin_finish();return success(LUA); }); }
LUA_FUNCTION_STATIC(PollFinishWorld) { return guarded(LUA,[&] { LUA->PushBool(active(LUA).poll_finish());return 1; }); }
LUA_FUNCTION_STATIC(Spawn) { return guarded(LUA,[&] {
  auto& w=active(LUA);const auto points=hull(LUA,1);const auto p=vector(LUA,2,kCoordinateLimit),a=vector(LUA,3,36000,true);
  const auto v=vector(LUA,4,100000),spin=vector(LUA,5,36000);
  LUA->PushNumber(w.spawn(points,p,a,v,spin));return 1;
}); }
LUA_FUNCTION_STATIC(Remove) { return guarded(LUA,[&] { LUA->PushBool(active(LUA).remove(id(LUA)));return 1; }); }
LUA_FUNCTION_STATIC(Impulse) { return guarded(LUA,[&] {
  auto& w=active(LUA);const auto origin=vector(LUA,1,kCoordinateLimit);
  const auto radius=static_cast<float>(number(LUA,2,.001,131072)),speed=static_cast<float>(number(LUA,3,0,100000));
  w.impulse(origin,radius,speed);return success(LUA);
}); }
LUA_FUNCTION_STATIC(SetCollide) { return guarded(LUA,[&] {
  need(LUA->IsType(1,Type::Bool),"expected collide boolean");active(LUA).set_collide(LUA->GetBool(1));return success(LUA);
}); }
LUA_FUNCTION_STATIC(SetGravity) { return guarded(LUA,[&] {
  active(LUA).set_gravity(static_cast<float>(number(LUA,1,0,10000)));return success(LUA);
}); }
LUA_FUNCTION_STATIC(Step) { return guarded(LUA,[&] { active(LUA).step(number(LUA,1,0,10));return success(LUA); }); }
LUA_FUNCTION_STATIC(BeginStep) { return guarded(LUA,[&] { active(LUA).begin_step(number(LUA,1,0,10));return success(LUA); }); }
LUA_FUNCTION_STATIC(PollStep) { return guarded(LUA,[&] { LUA->PushBool(active(LUA).poll_step());return 1; }); }
LUA_FUNCTION_STATIC(ReadPoses) { return guarded(LUA,[&] {
  auto& w=active(LUA);need(LUA->IsType(1,Type::Table) && LUA->IsType(2,Type::Table),"expected reusable poses and changed-id tables");
  const auto poses=w.poses();
  for(const auto& p:poses) {
    get(LUA,1,p.id);need(LUA->IsType(-1,Type::Table),"missing reusable pose row for live id");LUA->Pop();
  }
  unsigned count=0;
  for(const auto& p:poses) {
    get(LUA,1,p.id);
    const double fields[]{p.position.x,p.position.y,p.position.z,p.angles.x,p.angles.y,p.angles.z};
    for(unsigned i=0;i<6;++i) { LUA->PushNumber(fields[i]);set(LUA,-2,i+1); }
    LUA->PushBool(p.sleeping);set(LUA,-2,7);LUA->Pop();LUA->PushNumber(p.id);set(LUA,2,++count);
  }
  LUA->PushNumber(count);return 1;
}); }
LUA_FUNCTION_STATIC(IsSleeping) { return guarded(LUA,[&] { LUA->PushBool(active(LUA).sleeping(id(LUA)));return 1; }); }
LUA_FUNCTION_STATIC(ReadStats) { return guarded(LUA,[&] {
  need(LUA->IsType(1,Type::Table),"expected reusable statistics table");const auto s=active(LUA).stats();
  auto add=[&](const char* key,double v) { LUA->PushNumber(v);set(LUA,1,key); };
  add("live",s.live);add("awake",s.awake);add("statics",s.statics);add("models",s.models);add("workers",s.workers);
  add("substeps",s.substeps);add("step_ms",s.step_ms);add("dropped_seconds",s.dropped_seconds);
  add("brushes",s.brushes);add("skipped_brushes",s.skipped_brushes);
  add("refused_brushes",s.refused_brushes);add("refused_convexes",s.refused_convexes);
  add("refused_meshes",s.refused_meshes);add("skipped_props",s.skipped_props);
  add("contact_overflows",s.contact_overflows);add("manifold_overflows",s.manifold_overflows);
  add("pair_overflows",s.pair_overflows);add("constraint_overflows",s.constraint_overflows);
  add("temp_reserved_bytes",static_cast<double>(s.temp_reserved_bytes));add("temp_peak_bytes",static_cast<double>(s.temp_peak_bytes));
  add("pose_visits",s.pose_visits);
  LUA->PushBool(s.ready);set(LUA,1,"ready");LUA->PushBool(s.busy);set(LUA,1,"busy");return success(LUA);
}); }
LUA_FUNCTION_STATIC(Clear) { return guarded(LUA,[&] { active(LUA).clear();return success(LUA); }); }
LUA_FUNCTION_STATIC(Shutdown) { return guarded(LUA,[&] { world.reset();return success(LUA); }); }
}
GMOD_MODULE_OPEN() {
  // Raw realm lookup avoids any server-installed _G metamethods.
  LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);LUA->PushString("CLIENT");LUA->RawGet(-2);
  const bool client=LUA->IsType(-1,Type::Bool) && LUA->GetBool(-1);LUA->Pop(2);
  if(!client || (owner && owner!=LUA)) { LUA->PushNil();return 1; }
  owner=LUA;
  return guarded(LUA,[&] {
    LUA->CreateTable();
    const std::pair<const char*,GarrysMod::Lua::CFunc> functions[]{
      {"Init",Init},{"LoadMap",LoadMap},{"AddModel",AddModel},{"AddProp",AddProp},{"FinishWorld",FinishWorld},
      {"BeginLoadMap",BeginLoadMap},{"PollLoadMap",PollLoadMap},{"BeginFinishWorld",BeginFinishWorld},{"PollFinishWorld",PollFinishWorld},
      {"BeginStep",BeginStep},{"PollStep",PollStep},
      {"Spawn",Spawn},{"Remove",Remove},{"Impulse",Impulse},{"SetCollide",SetCollide},{"SetGravity",SetGravity},
      {"Step",Step},{"ReadPoses",ReadPoses},{"IsSleeping",IsSleeping},{"Stats",ReadStats},{"Clear",Clear},{"Shutdown",Shutdown}};
    for(const auto& [name,fn]:functions) { LUA->PushCFunction(fn);set(LUA,-2,name); }
    LUA->PushSpecial(GarrysMod::Lua::SPECIAL_GLOB);LUA->PushString("nlglass");LUA->Push(-3);LUA->RawSet(-3);LUA->Pop();
    return 1;
  });
}
GMOD_MODULE_CLOSE() {
  if(LUA==owner) { world.reset();owner=nullptr; }return 0;
}
