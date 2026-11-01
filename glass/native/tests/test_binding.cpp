#include "fake_lua.h"
#include "fixture.h"
#include "nl_test.h"
#include <limits>
#include <chrono>
#include <thread>

extern "C" int gmod13_open(lua_State*);
extern "C" int gmod13_close(lua_State*);
using namespace nl::glass::test;
namespace {
struct Module {
  Lua lua;lua_State state{};Value api;
  Module() {
    state.luabase=&lua;(*lua.globals.table)["sCLIENT"]=Value::boolean(true);
    if(gmod13_open(&state)!=1 || lua.at(-1).type!=Type::Table)throw std::runtime_error("module open failed");
    api=lua.at(-1);lua.stack.clear();
  }
  ~Module() { gmod13_close(&state); }
  std::vector<Value> call(const char* name,std::initializer_list<Value> args={}) {
    lua.stack=args;const auto fn=api.table->at(std::string("s")+name).f;const int returns=fn(&state);
    if(lua.Top()!=static_cast<int>(args.size())+returns)throw std::runtime_error("binding stack imbalance");
    return {lua.stack.end()-returns,lua.stack.end()};
  }
};
Value num(double n) { return Value::num(n); }
Value vector(double x=0,double y=0,double z=0) { return Value::array({num(x),num(y),num(z)}); }
Value hull() {
  auto v=Value::object();unsigned i=0;for(auto p:nl::glass::fixture::box())(*v.table)["n"+std::to_string(++i)]=vector(p.x,p.y,p.z);return v;
}
bool failure(const std::vector<Value>& v) { return v.size()==2 && v[0].type==Type::Nil && v[1].type==Type::String; }
}
TEST_CASE("glass binding validates every boundary without Lua errors or metamethods") {
  Module m;
  CHECK(failure(m.call("Init",{num(0),num(600)})));
  CHECK(failure(m.call("Init",{num(2.5),num(600)})));
  CHECK(failure(m.call("Init",{num(8193),num(600)})));
  CHECK(failure(m.call("Init",{num(2),num(std::numeric_limits<double>::quiet_NaN())})));
  CHECK(m.call("Init",{num(2),num(600)})[0].b);
  for(const auto* name:{"LoadMap","AddModel","AddProp","Spawn","Remove","Impulse","SetCollide","SetGravity","Step","ReadPoses","IsSleeping","Stats"})
    CHECK(failure(m.call(name,{Value::text("wrong type")})));
  CHECK(failure(m.call("Spawn",{hull(),vector(),vector(),vector(),vector()})));
  const auto bsp=nl::glass::fixture::room();const Value bytes=Value::text(std::string(bsp.begin(),bsp.end()));
  auto result=m.call("LoadMap",{bytes});REQUIRE(result.size()==1);CHECK(result[0].type==Type::Table);
  CHECK(failure(m.call("AddModel",{Value::text("model"),Value::object()})));
  const auto flat=Value::array({vector(0,0,0),vector(1,0,0),vector(1,1,0),vector(0,1,0)});
  CHECK(m.call("AddModel",{Value::text("mixed"),Value::array({flat,hull()})})[0].b);
  const auto cooking=Value::object();m.call("Stats",{cooking});CHECK(cooking.table->at("srefused_convexes").n==1);
  CHECK(m.call("FinishWorld")[0].b);
  CHECK(failure(m.call("Step",{num(-1)})));CHECK(failure(m.call("Step",{num(std::numeric_limits<double>::infinity())})));
  CHECK(failure(m.call("SetCollide",{num(1)})));CHECK(failure(m.call("IsSleeping",{num(1.2)})));
  CHECK(failure(m.call("Impulse",{vector(),num(0),num(20)})));
  CHECK(failure(m.call("Spawn",{Value::array({num(0),num(1),num(2),num(3)}),vector(),vector(),vector(),vector()})));
  CHECK(failure(m.call("Spawn",{hull(),vector(1e20),vector(),vector(),vector()})));
  const auto spawned=m.call("Spawn",{hull(),vector(0,0,32),vector(),vector(),vector()});
  REQUIRE(spawned.size()==1);const auto id=spawned[0];CHECK(id.n>0);
  CHECK(failure(m.call("ReadPoses",{num(0),Value::object()})));
  auto rows=Value::object(),changed=Value::object();
  const auto row=Value::array({num(0),num(0),num(0),num(0),num(0),num(0),Value::boolean(false)});
  (*rows.table)["n"+std::to_string(static_cast<unsigned>(id.n))]=row;
  const auto before=m.lua.tables;
  CHECK(m.call("ReadPoses",{rows,changed})[0].n==1);
  CHECK(m.lua.tables==before);CHECK(row.table->at("n3").n==32);
  CHECK(m.call("Remove",{id})[0].b);CHECK(!m.call("Remove",{id})[0].b);
  CHECK(failure(m.call("IsSleeping",{id})));CHECK(m.call("Clear")[0].b);
  CHECK(failure(m.call("LoadMap",{Value::text("broken")})));
  const auto stats=Value::object();CHECK(m.call("Stats",{stats})[0].b);CHECK(!stats.table->at("sready").b);
  CHECK(m.call("Shutdown")[0].b);CHECK(failure(m.call("Step",{num(0)})));
}
TEST_CASE("glass module refuses nonclient and foreign realms") {
  Lua server;lua_State s{};s.luabase=&server;
  CHECK(gmod13_open(&s)==1);CHECK(server.at(-1).type==Type::Nil);
  Module client;
  Lua foreign;lua_State f{};f.luabase=&foreign;(*foreign.globals.table)["sCLIENT"]=Value::boolean(true);
  CHECK(gmod13_open(&f)==1);CHECK(foreign.at(-1).type==Type::Nil);
  const auto fn=client.api.table->at("sInit").f;foreign.stack={num(2),num(600)};
  CHECK(fn(&f)==2);CHECK(foreign.at(-2).type==Type::Nil);
}
TEST_CASE("glass binding background operations return pending results and propagate worker errors") {
  Module m;CHECK(m.call("Init",{num(16),num(600)})[0].b);
  CHECK(failure(m.call("PollLoadMap")));CHECK(failure(m.call("PollStep")));CHECK(failure(m.call("PollFinishWorld")));
  CHECK(failure(m.call("BeginLoadMap",{num(1)})));CHECK(failure(m.call("BeginStep",{num(-1)})));
  const auto bsp=nl::glass::fixture::room();const Value bytes=Value::text(std::string(bsp.begin(),bsp.end()));
  CHECK(m.call("BeginLoadMap",{bytes})[0].b);
  CHECK(failure(m.call("BeginLoadMap",{bytes}))); // no second worker may mutate the world
  const auto stats=Value::object();m.call("Stats",{stats});CHECK(stats.table->at("sbusy").b);
  auto poll=[&](const char* name) {
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(10);
    for(;;) {
      auto v=m.call(name);
      if(v[0].type!=Type::Bool || v[0].b)return v;
      if(std::chrono::steady_clock::now()>deadline)throw std::runtime_error("binding worker timeout");
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
  };
  CHECK(poll("PollLoadMap")[0].type==Type::Table);
  CHECK(m.call("BeginFinishWorld")[0].b);CHECK(poll("PollFinishWorld")[0].b);
  CHECK(m.call("BeginStep",{num(1.0/60)})[0].b);CHECK(failure(m.call("SetGravity",{num(600)})));
  CHECK(poll("PollStep")[0].b);
  CHECK(m.call("BeginLoadMap",{Value::text("bad map")})[0].b);CHECK(failure(poll("PollLoadMap")));
  CHECK(m.call("BeginLoadMap",{bytes})[0].b);CHECK(m.call("Shutdown")[0].b); // joins safely
}
TEST_CASE("glass binding validates scene ray damage and split APIs with balanced raw tables") {
  Module m;m.call("Init",{num(4),num(0)});
  const auto bsp=nl::glass::fixture::room();m.call("LoadMap",{Value::text(std::string(bsp.begin(),bsp.end()))});m.call("FinishWorld");
  CHECK(failure(m.call("SetInteraction",{num(1)})));CHECK(m.call("SetInteraction",{Value::boolean(true)})[0].b);
  CHECK(failure(m.call("SyncBodies",{num(1),num(.016)})));
  auto row=Value::array({num(1),vector(40,0,32),vector(),vector(4,4,8),num(85),Value{},vector()});
  auto rows=Value::array({row});CHECK(m.call("SyncBodies",{rows,num(.016)})[0].n==1);
  CHECK(failure(m.call("SyncBodies",{Value::array({row,row}),num(.016)})));
  CHECK(failure(m.call("SetCollisionFlags",{num(16)})));
  CHECK(failure(m.call("SetCollisionFlags",{num(1.5)})));
  (*row.table)["n8"]=num(3);CHECK(failure(m.call("SyncBodies",{rows,num(.016)})));
  (*row.table)["n8"]=num(4);CHECK(m.call("SyncBodies",{rows,num(.016)})[0].n==0);
  CHECK(m.call("SetCollisionFlags",{num(4)})[0].b);
  CHECK(m.call("SyncBodies",{rows,num(.016)})[0].n==1);
  CHECK(m.call("SetCollisionFlags",{num(3)})[0].b);(*row.table)["n8"]=num(1);
  (*row.table)["n6"]=Value::array({hull()});CHECK(m.call("SyncBodies",{rows,num(.016)})[0].type==Type::Number);
  (*row.table)["n7"]=num(0);CHECK(failure(m.call("SyncBodies",{rows,num(.016)})));
  CHECK(m.call("ReadRegions")[0].type==Type::Table);CHECK(m.call("ReadDamage")[0].type==Type::Bool);
  const auto large=Value::object();unsigned n=0;
  for(auto p:nl::glass::fixture::box(16,12,.5f))(*large.table)["n"+std::to_string(++n)]=vector(p.x,p.y,p.z);
  CHECK(failure(m.call("Spawn",{large,vector(0,0,32),vector(),vector(),vector(),num(0)})));
  const auto id=m.call("Spawn",{large,vector(0,0,32),vector(),vector(),vector(),num(4)})[0];
  CHECK(failure(m.call("Ray",{vector(),vector(),num(-1),num(10)})));
  CHECK(failure(m.call("Melee",{vector(),vector(100,0,0),num(1000),num(100),num(17)})));
  CHECK(m.call("Melee",{vector(-100,0,32),vector(100,0,32),num(180000),num(600),num(6)})[0].n==1);
  CHECK(m.call("Ray",{vector(-100,0,32),vector(100,0,32),num(180000),num(600)})[0].n==id.n);
  CHECK(m.call("ReadDamage")[0].type==Type::Table);CHECK(m.call("ReadDamage")[0].type==Type::Bool);
  CHECK(m.call("CanSplit",{id,num(4)})[0].b);
  CHECK(failure(m.call("Split",{id,num(3)})));
  const auto parts=m.call("Split",{id,num(4)})[0];CHECK(parts.type==Type::Table);
  CHECK(parts.table->at("n1").table->at("sid").n!=id.n);
  CHECK(parts.table->at("n1").table->at("spoly").type==Type::Table);
  CHECK(!m.call("CanSplit",{id,num(4)})[0].b);CHECK(!m.call("Remove",{id})[0].b);
  m.call("BeginStep",{num(.016)});CHECK(failure(m.call("SyncBodies",{Value::object(),num(.016)})));
  CHECK(failure(m.call("ReadDamage")));CHECK(failure(m.call("ReadRegions")));m.call("Clear");
}
