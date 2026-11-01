#include "fake_lua.h"
#include "fixture.h"
#include "nl_test.h"
#include <limits>

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
