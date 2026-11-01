#include "world.h"
#include "fixture.h"
#include "nl_test.h"
#include <chrono>
#include <iostream>
#include <limits>

using namespace nl::glass;
namespace {
void ready(World& w) { w.load_map(fixture::room());w.finish(); }
SceneBody mirror(std::uint32_t key,V3 position) { return {key,position,{}, {4,4,8},{},85,{}}; }
double ms(std::chrono::steady_clock::time_point start) {
  return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
}
}
TEST_CASE("glass convex bisection preserves area thickness and minimum size over repeated cuts") {
  for(unsigned seed=1;seed<=80;++seed) {
    Hull points;for(unsigned i=0;i<11;++i) {
      const double a=(i*6.283185307179586/11)+seed*.001;
      points.push_back({float(std::cos(a)*(20+seed)),float(std::sin(a)*(16+seed*.5)),0});
    }
    const auto polygon=outline_xy(points);const auto expected=polygon_area(polygon);
    std::vector<Hull> leaves{polygon};
    for(unsigned generation=0;generation<7;++generation) {
      std::vector<Hull> next;
      for(const auto& p:leaves) {
        auto parts=split_polygon(p,4);
        if(parts[0].empty())next.push_back(p);else for(auto& child:parts)next.push_back(std::move(child));
      }
      leaves=std::move(next);
    }
    double area=0;
    for(const auto& p:leaves) {
      CHECK(polygon_area(p)>=15.999);CHECK(std::abs(polygon_area(outline_xy(p))-polygon_area(p))<.002);
      CHECK(valid_hull(extrude(p,.7f)));area+=polygon_area(p);
    }
    CHECK(std::abs(area-expected)<expected*.00001);
  }
  CHECK(split_polygon(outline_xy(fixture::box(4,4)),8)[0].empty());
  CHECK(split_polygon(outline_xy(fixture::box(32,1)),4)[0].empty());
}
TEST_CASE("glass Source mirrors push sleeping pieces but never yield to them") {
  World w(8,0);ready(w);w.set_interaction(true);
  const auto id=w.spawn(fixture::box(8,8,1),{0,0,32},{},{},{});
  for(unsigned i=0;i<40;++i)w.step(1.0/60);REQUIRE(w.sleeping(id));(void)w.poses();
  auto body=mirror(19,{-40,0,32});w.sync_bodies({body},1.0/60);
  for(unsigned i=0;i<30;++i) {
    body.position.x=-40+float(i)*3;w.sync_bodies({body},1.0/60);w.step(1.0/60);
    CHECK((w.scene_pose(19).position-body.position).length()<.001f);
  }
  const auto poses=w.poses();REQUIRE(!poses.empty());CHECK(poses[0].id==id);CHECK(poses[0].position.x>24);
  CHECK(w.stats().scene_bodies==1);CHECK(w.stats().live==1);
  // Incoming glass hits this stationary kinematic body; its Source-owned transform stays exact.
  body.position={100,0,32};w.sync_bodies({body},1.0/60);w.step(1.0/60);
  w.spawn(fixture::box(16,16,1),{70,0,32},{},{1200,0,0},{});
  for(unsigned i=0;i<20;++i) { w.sync_bodies({body},1.0/60);w.step(1.0/60); }
  CHECK((w.scene_pose(19).position-body.position).length()<.001f);
  w.sync_bodies({},1.0/60);CHECK(w.stats().scene_bodies==0);CHECK(w.stats().awake<=w.stats().live);
}
TEST_CASE("glass moving Source body generates follow-up damage and teleports do not fling glass") {
  World w(8,0);ready(w);w.set_interaction(true);
  w.spawn(fixture::box(16,16,.5f),{0,0,32},{},{},{});
  auto body=mirror(1,{-30,0,32});body.mass=40;body.velocity={600,0,0};
  w.sync_bodies({body},1.0/60);
  for(unsigned i=0;i<5;++i) { body.position.x+=10;w.sync_bodies({body},1.0/60);w.step(1.0/60); }
  const auto events=w.take_damage();REQUIRE(!events.empty());CHECK(events[0].kinds&SourceBody);CHECK(events[0].energy>=12000);
  body.position={800,0,32};CHECK(w.sync_bodies({body},1.0/60)==0);
  CHECK((w.scene_pose(1).position-body.position).length()<.001f);
}
TEST_CASE("glass falls blasts and bullets deliver bounded deduplicated damage events") {
  World w(128);ready(w);w.set_interaction(true);
  const auto falling=w.spawn(fixture::box(16,16,.5f),{0,0,220},{},{0,0,-400},{});
  bool damaged=false;
  for(unsigned i=0;i<90;++i) { w.step(1.0/60);for(const auto& e:w.take_damage())if(e.id==falling && (e.kinds&Fall))damaged=true; }
  CHECK(damaged);
  w.clear();
  for(unsigned i=0;i<100;++i)w.spawn(fixture::box(8,8,.5f),{float(i%10)*40,float(i/10)*40,32},{},{},{});
  w.impulse({-100,-100,32},10000,1200);w.impulse({-100,-100,32},10000,1200);
  const auto hits=w.take_damage();CHECK(hits.size()==kMaxDamageEvents);CHECK(w.take_damage().empty());CHECK(w.stats().damage_dropped>0);
  for(const auto& e:hits)CHECK(e.kinds&Blast);
  w.clear();const auto target=w.spawn(fixture::box(16,16,.5f),{0,0,32},{},{},{});
  CHECK(w.ray({-100,0,32},{100,0,32},200000,600)==target);
  CHECK(w.ray({-100,0,32},{100,0,32},300000,600)==target);
  const auto shot=w.take_damage();REQUIRE(shot.size()==1);CHECK(shot[0].energy==300000);CHECK(shot[0].kinds==Bullet);
  CHECK(w.ray({-100,40,32},{100,40,32},200000,600)==0);
  w.set_interaction(false);CHECK(w.ray({-100,0,32},{100,0,32},200000,600)==0);CHECK(w.take_damage().empty());
}
TEST_CASE("glass split replaces exactly one body preserves area and motion and respects capacity") {
  World w(3,0);ready(w);w.set_interaction(true);
  const auto id=w.spawn(fixture::box(16,12,.5f),{0,0,32},{13,27,39},{300,0,0},{0,0,180});
  const auto children=w.split(id,4);REQUIRE(children.size()==2);CHECK(w.stats().live==2);CHECK(!w.remove(id));
  double area=0;for(const auto& c:children) {
    CHECK(c.id!=id);CHECK(c.thickness>.999f && c.thickness<1.001f);CHECK(c.velocity.length()>200);
    CHECK(std::abs(c.spin.z-180)<.001f);area+=polygon_area(c.polygon);
  }
  CHECK(std::abs(area-32*24)<.05);
  const auto second=w.split(children[0].id,4);CHECK(second.size()==2);CHECK(w.stats().live==3);
  CHECK(w.split(children[1].id,4).empty());CHECK(w.stats().live==3);
  w.remove(children[1].id);const auto leaf=w.spawn(fixture::box(4,4,.5f),{0,0,40},{},{},{});
  CHECK(w.split(leaf,8).empty());CHECK(w.stats().live==3);
  CHECK_THROWS_AS(w.split(leaf,0),Error);CHECK(w.split(0,4).empty());
}
TEST_CASE("glass scene snapshots bound shapes rows keys and reject malformed input before mutation") {
  World w(2);ready(w);w.set_interaction(true);
  auto b=mirror(9,{0,0,32});b.convexes={fixture::box(4,4,8)};
  w.sync_bodies({b},1.0/60);CHECK(w.stats().scene_cooks==1);
  b.convexes.clear();w.sync_bodies({b},1.0/60);CHECK(w.stats().scene_cooks==1);
  CHECK_THROWS_AS(w.sync_bodies({b,b},1.0/60),Error);
  CHECK(w.stats().scene_bodies==1);
  auto bad=b;bad.mass=std::numeric_limits<float>::quiet_NaN();CHECK_THROWS_AS(w.sync_bodies({bad},1.0/60),Error);
  std::vector<SceneBody> excess(kMaxSceneBodies+1,b);CHECK_THROWS_AS(w.sync_bodies(excess,1.0/60),Error);
  auto c=b,d=b;c.key=10;d.key=11;b.convexes=c.convexes=d.convexes={fixture::box()};
  CHECK_THROWS_AS(w.sync_bodies({b,c,d},1.0/60),Error);
  w.set_interaction(false);CHECK(w.stats().scene_bodies==0);
  CHECK(w.sync_bodies({c},1.0/60)==0);CHECK(w.stats().scene_bodies==0);
  w.set_interaction(true);w.sync_bodies({c},1.0/60);w.clear();CHECK(w.stats().scene_bodies==0);
}
TEST_CASE("glass piece interest regions exclude an empty world and remain capped") {
  World w(64,0);ready(w);CHECK(w.regions().empty());
  for(unsigned i=0;i<64;++i)w.spawn(fixture::box(),{float(i)*1000,0,32},{},{},{});
  const auto regions=w.regions();CHECK(regions.size()==kMaxRegions);
  for(const auto& r:regions)CHECK(r.maximum.x-r.minimum.x<210);
}
TEST_CASE("glass interaction benchmark bounds scene capture raycasts and dormant floor contacts") {
  for(bool enabled:{false,true}) {
    World w(2000);ready(w);w.set_interaction(enabled);
    for(unsigned i=0;i<2000;++i)w.spawn(fixture::box(4,4,.5f),{float(i%40)*12-240,float((i/40)%25)*12-150,float(i/1000)*32+40},{},{},{},8);
    double total=0;
    for(unsigned i=0;i<180;++i) { w.step(1.0/60);total+=w.stats().step_ms;CHECK(w.take_damage().empty()); }
    std::cout<<"R7-C leaf benchmark interaction="<<enabled<<" live="<<w.stats().live<<" mean_step_ms="<<total/180<<'\n';
    if(!enabled)continue;
    std::vector<SceneBody> scene;
    for(unsigned i=0;i<kMaxSceneBodies;++i)scene.push_back(mirror(i+1,{float(i%16)*24-200,float(i/16)*40-120,64}));
    const auto begin=std::chrono::steady_clock::now();
    for(unsigned i=0;i<120;++i) { (void)w.regions();w.sync_bodies(scene,1.0/60); }
    const double scene_ms=ms(begin)/120;
    const auto rays=std::chrono::steady_clock::now();
    for(unsigned i=0;i<640;++i)(void)w.ray({-600,float(i%25)*12-150,2},{600,float(i%25)*12-150,2},180000,300);
    std::cout<<"R7-C bounds bodies="<<scene.size()<<" regions_sync_mean_ms="<<scene_ms<<" ray_mean_ms="<<ms(rays)/640<<'\n';
    CHECK(w.stats().scene_bodies==kMaxSceneBodies);CHECK(w.stats().live==2000);
  }
}
