#include "world.h"
#include "fixture.h"
#include "nl_test.h"
#include <iostream>
#include <chrono>
using namespace nl::glass;
namespace {
void ready(World& w,bool water=false) { w.load_map(fixture::room(20,false,water));w.finish(); }
double ms(std::chrono::steady_clock::time_point t) { return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-t).count(); }
}
TEST_CASE("glass R9 irregular hit centred fracture conserves area down to one unit") {
  unsigned tiny=0,multi=0,diagonal=0;
  for(unsigned seed=1;seed<=80;++seed) {
    const auto p=outline_xy(fixture::box(32,24,.5f));
    const auto parts=split_polygon(p,1,{17,-5,0},seed);
    REQUIRE(parts.size()>=2);CHECK(parts.size()<=6);if(parts.size()>2)++multi;
    const auto repeat=split_polygon(p,1,{17,-5,0},seed);
    REQUIRE(parts.size()==repeat.size());double area=0;
    std::vector<Hull> leaves=parts;
    for(unsigned g=0;g<9;++g) {
      std::vector<Hull> next;
      for(const auto& a:leaves) {
        const auto child=split_polygon(a,1,polygon_center(a),seed+g);
        if(child.empty())next.push_back(a);else next.insert(next.end(),child.begin(),child.end());
      }
      leaves=std::move(next);
    }
    for(const auto& a:leaves) {
      const auto ar=polygon_area(a);CHECK(ar>=.9999);if(ar<4)++tiny;area+=ar;
      CHECK(valid_hull(extrude(a,1)));
    }
    CHECK(std::abs(area-polygon_area(p))<.02);
    for(std::size_t i=0;i<parts.size();++i)for(std::size_t j=0;j<parts[i].size();++j) {
      CHECK((parts[i][j]-repeat[i][j]).length()==0);
      const auto d=parts[i][j]-parts[i][(j+1)%parts[i].size()];if(std::abs(d.x)>.01f && std::abs(d.y)>.01f)++diagonal;
    }
  }
  CHECK(tiny>100);CHECK(multi>40);CHECK(diagonal>100);
  std::cout<<"R9 fracture tiny="<<tiny<<" multi="<<multi<<" diagonal="<<diagonal<<'\n';
}
TEST_CASE("glass R9 secondary replacement respects six child budget and inherited point velocity") {
  World w(6,0);ready(w);w.set_interaction(true);
  const auto id=w.spawn(fixture::box(32,24,.5f),{0,0,64},{},{500,0,0},{0,0,0},1);
  w.ray({20,-10,90},{20,-10,40},1e8f,0);REQUIRE(w.take_damage().size()==1);
  const auto children=w.split(id,1);REQUIRE(children.size()>=2);CHECK(w.stats().live==children.size());
  double area=0;for(const auto& f:children) { area+=polygon_area(f.polygon);CHECK(f.velocity.x>499.9f); }
  CHECK(std::abs(area-3072)<.01);CHECK(!w.remove(id));
  while(w.stats().live<6) {
    bool split=false;for(auto f:children)if(w.can_split(f.id,1)) { auto next=w.split(f.id,1,2);if(!next.empty()) { split=true;break; } }
    if(!split)break;
  }
  CHECK(w.stats().live<=6);
}
TEST_CASE("glass R9 sound events are bounded independent of interaction and quiet at rest") {
  World w(256);ready(w);w.set_interaction(false);
  for(int i=0;i<256;++i)w.spawn(fixture::box(1,1,.2f),{float(i%16)*5-40,float(i/16)*5-40,40},{},{0,0,-400},{},1);
  for(unsigned i=0;i<120;++i)w.step(1.0/60);
  const auto events=w.take_sounds();CHECK(!events.empty());CHECK(events.size()<=kMaxSoundEvents);
  CHECK(w.stats().sound_dropped>0);
  for(const auto& e:events) { CHECK(e.speed>=70);CHECK(e.position.valid());CHECK(e.mass>0); }
  for(unsigned i=0;i<180;++i)w.step(1.0/60);
  CHECK(w.take_sounds().empty());
  w.set_sounds(false);w.impulse({0,0,0},1000,800);for(unsigned i=0;i<120;++i)w.step(1.0/60);
  CHECK(w.take_sounds().empty());w.clear();CHECK(w.take_sounds().empty());
}
TEST_CASE("glass R9 water brushes apply buoyancy drag and entry events without becoming solid") {
  CHECK(read_bsp(fixture::room(20,false,true)).water.size()==1);
  World wet(16),dry(16);ready(wet,true);ready(dry);
  const auto a=wet.spawn(fixture::box(12,12,.5f),{0,0,150},{15,20,10},{0,0,-300},{70,40,20},1);
  const auto b=dry.spawn(fixture::box(12,12,.5f),{0,0,150},{15,20,10},{0,0,-300},{70,40,20},1);
  for(unsigned i=0;i<12;++i) { wet.step(1.0/60);dry.step(1.0/60); }
  const auto wm=wet.motion(a),dm=dry.motion(b);
  CHECK(wm.position.z>dm.position.z);CHECK(wm.velocity.z<0);CHECK(wm.velocity.z>dm.velocity.z);
  CHECK(wet.stats().water_volumes==1);CHECK(wet.stats().water_applied>0);CHECK(wet.stats().water_entries==1);
  CHECK(wet.stats().statics==dry.stats().statics);
  auto events=wet.take_sounds();bool entry=false;for(const auto& e:events)entry|=e.kind==3;CHECK(entry);
  for(unsigned i=0;i<360;++i)wet.step(1.0/60);
  CHECK(wet.motion(a).position.z<150);CHECK(wet.motion(a).position.z>-.5f);
  const auto id=wet.spawn_group({fixture::box(2,2,.3f),fixture::box(3,3,.3f)},{0,0,100},{},{},{0,10,0});
  wet.step(1.0/60);CHECK(wet.motion(id).velocity.z<0);
}
TEST_CASE("glass R9 initial overlaps fast sweeps and teleports never reverse transferred flight") {
  unsigned backwards=0,total=0;
  for(float speed:{250.f,700.f,3600.f})for(bool fresh:{false,true})for(bool teleported:{false,true}) {
    World w(32,0);ready(w);w.set_interaction(true);
    SceneBody source{1,{-40,0,64},{},{8,40,40},{speed,0,0},85,{}};
    if(!fresh)w.sync_bodies({source},1.0/60);
    for(int y=-3;y<=3;++y)w.spawn(fixture::box(.5f,3,.5f),{0,float(y)*8,64},{},{speed*.7f,0,0},{},1);
    source.position={teleported?500.f:0.f,0,64};w.sync_bodies({source},1.0/60);
    if(teleported) { source.position={0,0,64};w.sync_bodies({source},1.0/60); }
    for(unsigned frame=0;frame<8;++frame) {
      source.position.x+=speed/60;w.sync_bodies({source},1.0/60);w.step(1.0/60);
      for(const auto& p:w.poses()) { const auto m=w.motion(p.id);++total;if(m.velocity.x<-.1f) {
        ++backwards;std::cout<<"R9 reverse speed="<<speed<<" fresh="<<fresh<<" teleport="<<teleported<<" frame="<<frame<<" vx="<<m.velocity.x<<" x="<<m.position.x<<'\n';
      } }
      CHECK((w.scene_pose(1).position-source.position).length()<.002f);
    }
  }
  std::cout<<"R9 velocity samples="<<total<<" backwards="<<backwards<<'\n';CHECK(backwards==0);
}
TEST_CASE("glass R9 environment benchmark separates sound and buoyancy worker costs") {
  for(bool water:{false,true})for(bool sound:{false,true}) {
    World w(1000);ready(w,water);w.set_sounds(sound);double total=0;unsigned sounds=0;
    for(int i=0;i<1000;++i)w.spawn(fixture::box(1,1,.2f),{float(i%32)*6-96,float(i/32)*6-96,120+float(i%4)*8},{},{},{0,30,0},1);
    for(unsigned i=0;i<120;++i) { w.step(1.0/60);total+=w.stats().step_ms;sounds+=static_cast<unsigned>(w.take_sounds().size()); }
    std::cout<<"R9 environment water="<<water<<" sound="<<sound<<" pieces=1000 step_mean_ms="<<total/120
      <<" water_mean_ms="<<w.stats().water_ms/120<<" tests="<<w.stats().water_tests<<" applied="<<w.stats().water_applied<<" sound_events="<<sounds<<'\n';
  }
}
