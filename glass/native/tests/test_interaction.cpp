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
TEST_CASE("glass collision flags default to objects and ragdolls and filter each target independently") {
  World w(8,0);ready(w);w.set_interaction(true);
  CHECK(w.stats().collision_flags==(Objects|Ragdolls));
  std::vector<SceneBody> rows;
  for(unsigned i=0;i<4;++i) { auto b=mirror(i+1,{float(i)*50,0,32});b.kind=1u<<i;rows.push_back(b); }
  w.sync_bodies(rows,1.0/60);CHECK(w.stats().scene_bodies==2);
  for(unsigned flags=0;flags<16;++flags) {
    w.set_collision_flags(flags);CHECK(w.stats().scene_bodies==0);
    w.sync_bodies(rows,1.0/60);
    unsigned expected=0;
    for(unsigned i=0;i<4;++i)if(flags&(1u<<i)) { ++expected;CHECK((w.scene_pose(i+1).position-rows[i].position).length()<.001f); }
    CHECK(w.stats().scene_bodies==expected);
  }
  CHECK_THROWS_AS(w.set_collision_flags(16),Error);
  rows[0].kind=3;CHECK_THROWS_AS(w.sync_bodies(rows,1.0/60),Error);
  w.set_interaction(false);CHECK(w.stats().scene_bodies==0);
}
TEST_CASE("glass melee wakes old piles fractures large pieces and bounds a crowded sweep") {
  World w(64,0);ready(w);w.set_interaction(true);
  const auto large=w.spawn(fixture::box(16,16,.5f),{0,0,32},{},{},{},8);
  const auto leaf=w.spawn(fixture::box(2,2,.5f),{0,28,32},{},{},{},8);
  for(unsigned i=0;i<7800;++i)w.step(1.0/60); // >120 seconds; age never disables a local hit.
  REQUIRE(w.sleeping(large));REQUIRE(w.sleeping(leaf));
  CHECK(w.melee({-50,0,32},{50,0,32},400000,500,6)==1);
  auto events=w.take_damage();REQUIRE(events.size()==1);CHECK(events[0].id==large && events[0].kinds==Melee);
  CHECK(w.split(large,8).size()==2);
  CHECK(w.melee({-50,28,32},{50,28,32},400000,500,6)==1);
  CHECK(w.take_damage().empty());CHECK(!w.sleeping(leaf)); // minimum size still moves.
  w.clear();
  for(unsigned i=0;i<32;++i)w.spawn(fixture::box(1,1,.5f),{float(i)*3,0,32},{},{},{},8);
  CHECK(w.melee({-20,0,32},{120,0,32},400000,500,8)<=8);
  CHECK(w.stats().melee_limited>0);
  const auto hits=w.stats().melee_hits;w.set_interaction(false);
  CHECK(w.melee({-20,0,32},{120,0,32},400000,500,8)==0);CHECK(w.stats().melee_hits==hits);
  CHECK_THROWS_AS(w.melee({},{300,0,0},1000,100,8),Error);
  CHECK_THROWS_AS(w.melee({},{100,0,0},1000,100,17),Error);
}
TEST_CASE("glass adaptive rigid groups keep exact sub hull gaps and only cosmetic motion") {
  World w(4,0);ready(w);w.set_interaction(true);
  auto left=fixture::box(2,4,.5f),right=left;
  for(auto& p:left)p.x-=8;for(auto& p:right)p.x+=8;
  const auto id=w.spawn_group({left,right},{0,0,32},{},{},{});
  CHECK(w.stats().live==1);CHECK(w.ray({0,0,50},{0,0,10},200000,400)==0); // never fill the gap.
  CHECK(w.ray({-8,0,50},{-8,0,10},200000,400)==id);
  CHECK(!w.can_split(id,4));CHECK(w.split(id,4).empty());CHECK(w.take_damage().empty());
  CHECK(w.melee({8,-20,32},{8,20,32},400000,400,6)==1);
  w.step(1.0/60);const auto poses=w.poses();REQUIRE(poses.size()==1);CHECK(!poses[0].sleeping);
  CHECK_THROWS_AS(w.spawn_group({left},{},{},{},{}),Error);
  CHECK_THROWS_AS(w.spawn_group(std::vector<Hull>(9,left),{},{},{},{}),Error);
  auto bad=left;bad[0].x=std::numeric_limits<float>::quiet_NaN();
  CHECK_THROWS_AS(w.spawn_group({bad,right},{},{},{},{}),Error);CHECK(w.stats().live==1);
  Hull dense;
  for(unsigned i=0;i<64;++i) {
    const auto a=float(i)*6.283185307f/64;
    dense.push_back({4*std::cos(a),4*std::sin(a),-.5f});dense.push_back({4*std::cos(a),4*std::sin(a),.5f});
  }
  CHECK_THROWS_AS(w.spawn_group(std::vector<Hull>(8,dense),{},{},{},{}),Error);CHECK(w.stats().live==1);
  w.clear();CHECK(w.stats().live==0);
}
TEST_CASE("glass adaptive load benchmark compares 2000 exact quads as bodies or eight hull groups") {
  for(bool grouped:{false,true}) {
    World w(2000);ready(w);const auto start=std::chrono::steady_clock::now();
    if(grouped) {
      std::vector<Hull> hulls;
      for(int y=0;y<2;++y)for(int x=0;x<4;++x) {
        auto hull=fixture::box(2,2,.3f);
        for(auto& p:hull) { p.x+=float(x)*5;p.y+=float(y)*5; }hulls.push_back(std::move(hull));
      }
      for(unsigned y=0;y<25;++y)for(unsigned x=0;x<10;++x)
        w.spawn_group(hulls,{float(x)*20-100,float(y)*10-125,64},{},{},{});
    } else for(unsigned y=0;y<50;++y)for(unsigned x=0;x<40;++x)
      w.spawn(fixture::box(2,2,.3f),{float(x)*5-100,float(y)*5-125,64},{},{},{},8);
    const auto spawn_ms=ms(start);double falling=0,max_step=0;unsigned frames=0;
    for(unsigned i=0;i<900;++i) {
      w.step(1.0/60);const auto s=w.stats();
      if(i<120) { falling+=s.step_ms;max_step=std::max(max_step,s.step_ms);++frames; }
      if(i>=120 && s.awake==0)break;
    }
    CHECK(w.stats().awake==0);CHECK(w.stats().live==(grouped?250u:2000u));
    std::cout<<"R8-G load grouped="<<grouped<<" fragments=2000 bodies="<<w.stats().live<<" spawn_ms="<<spawn_ms
      <<" falling_step_mean_ms="<<falling/frames<<" falling_step_max_ms="<<max_step<<'\n';
  }
}
TEST_CASE("glass Source mirrors push sleeping pieces but never yield to them") {
  World w(8,0);ready(w);w.set_interaction(true);w.set_collide(false);
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
TEST_CASE("glass fast box sweeps push a sleeping floor pile at one or two frame snapshot intervals") {
  // Pinned catch-up budgets, never this machine's speed: every substep runs (1000 ms), or a starved
  // client drops every catch-up step (0 ms). A 2-vCPU CI runner dropped some at the default 4 ms.
  for(float speed:{650.0f,3600.0f})for(double dt:{1.0/60,1.0/30})for(bool collide:{false,true})for(double budget:{1000.0,0.0}) {
    World w(16);ready(w);w.set_interaction(true);w.set_collide(collide);w.set_catch_up_budget(budget);
    for(int x=-1;x<=1;++x)for(int y=-1;y<=1;++y)
      w.spawn(fixture::box(16,16,.25f),{float(x)*34,float(y)*34,8},{},{},{},8);
    for(unsigned i=0;i<180;++i)w.step(1.0/60);
    const auto initial=w.poses();REQUIRE(initial.size()==9);for(const auto& p:initial)REQUIRE(p.sleeping);
    auto box=mirror(1,{-210,0,4});box.half={4,4,4};box.mass=30;box.velocity={speed,0,0};
    bool moved=false,damaged=false;double total=0,peak=0;
    for(unsigned i=0;i<36;++i) {
      box.position.x=-210+float(i*dt)*speed;
      const auto start=std::chrono::steady_clock::now();w.sync_bodies({box},dt);const auto elapsed=ms(start);
      total+=elapsed;peak=std::max(peak,elapsed);w.step(dt);
      CHECK((w.scene_pose(1).position-box.position).length()<.01f);
      for(const auto& p:w.poses())for(const auto& old:initial)if(p.id==old.id) {
        const auto d=p.position-old.position;if(d.x*d.x+d.y*d.y>4)moved=true;
      }
      for(const auto& e:w.take_damage())if(e.kinds&SourceBody)damaged=true;
    }
    CHECK(moved);CHECK(damaged);CHECK(w.stats().scene_sweep_hits>0);
    if(budget==0 && dt>1.0/60)CHECK(std::abs(w.stats().dropped_seconds-.6)<1e-6); // all 36 catch-up steps
    std::cout<<"R7-C fast box speed="<<speed<<" dt="<<dt<<" collide="<<collide<<" catch_up_ms="<<budget
      <<" sync_mean_ms="<<total/36<<" sync_max_ms="<<peak<<'\n';
  }
}
TEST_CASE("glass dropped catch-up steps keep Source mirrors on the snapshot clock") {
  World w(4,0);ready(w);w.set_interaction(true);w.set_catch_up_budget(0);
  auto body=mirror(3,{0,0,32});w.sync_bodies({body},1.0/60);w.step(1.0/60);
  for(unsigned i=1;i<=8;++i) { // 1/30 s snapshots: one substep runs, one is dropped, Source still wins.
    body.position.x=float(i)*20;w.sync_bodies({body},1.0/30);
    const auto dropped=w.stats().dropped_seconds;w.step(1.0/30);
    CHECK(w.stats().substeps==1);CHECK(std::abs(w.stats().dropped_seconds-dropped-1.0/60)<1e-9);
    CHECK((w.scene_pose(3).position-body.position).length()<.001f);
  }
  // .045 s: 1/60 runs and 1/60 drops, so the mirror covers 2/60 of 45 units; .0117 s stays queued.
  body.position.x+=45;w.sync_bodies({body},.045);w.step(.045);
  CHECK(std::abs(w.scene_pose(3).position.x-(160+45*float(2.0/60/.045)))<.01f);
  w.step(1.0/60);CHECK((w.scene_pose(3).position-body.position).length()<.001f);
  CHECK_THROWS_AS(w.set_catch_up_budget(-1),Error);CHECK_THROWS_AS(w.set_catch_up_budget(1001),Error);
  CHECK_THROWS_AS(w.set_catch_up_budget(std::numeric_limits<double>::quiet_NaN()),Error);
}
TEST_CASE("glass mirror sweeps cap casts hits and leaf damage without casting teleports or disabled scenes") {
  World w(128,0);ready(w);w.set_interaction(true);w.set_collide(false);
  for(unsigned line=0;line<16;++line)for(unsigned i=0;i<8;++i)
    w.spawn(fixture::box(2,2,.5f),{float(i)*8-28,float(line)*24,32},{},{},{},8);
  for(unsigned i=0;i<40;++i)w.step(1.0/60);(void)w.poses();
  std::vector<SceneBody> scene;
  for(unsigned i=0;i<96;++i) { auto b=mirror(i+1,{-90,float(i%16)*24,32});b.velocity={600,0,0};scene.push_back(b); }
  w.sync_bodies(scene,1.0/60);w.step(1.0/60);
  const auto before=w.stats();CHECK(before.scene_sweeps==16);CHECK(before.scene_sweep_limited==80);
  for(auto& b:scene)b.position.x=20;
  const auto start=std::chrono::steady_clock::now();w.sync_bodies(scene,1.0/60);const auto elapsed=ms(start);
  auto after=w.stats();CHECK(after.scene_sweeps-before.scene_sweeps<=16);
  CHECK(after.scene_sweep_hits==64);CHECK(after.scene_sweep_limited>before.scene_sweep_limited);
  CHECK(w.take_damage().empty());w.step(1.0/60);w.step(1.0/60); // Publish a non-initial interpolated leaf pose.
  bool leaf_moved=false;for(const auto& p:w.poses())if(p.position.x>32)leaf_moved=true;CHECK(leaf_moved);
  for(const auto& b:scene)CHECK((w.scene_pose(b.key).position-b.position).length()<.001f);
  for(auto& b:scene)b.position.x=1020;
  w.sync_bodies(scene,1.0/60);CHECK(w.stats().scene_sweeps==after.scene_sweeps);
  w.set_interaction(false);w.sync_bodies(scene,1.0/60);
  CHECK(w.stats().scene_sweeps==after.scene_sweeps);CHECK(w.stats().scene_bodies==0);
  std::cout<<"R7-C sweep cap bodies=96 pieces=128 hits="<<after.scene_sweep_hits<<" sync_ms="<<elapsed<<'\n';
}
TEST_CASE("glass walking hull moves a thin floor piece without lifting or slowing the Source mirror") {
  for(float half:{16.0f,4.0f}) {
    World w(8);ready(w);w.set_interaction(true);
    const auto id=w.spawn(fixture::box(half,half,.25f),{0,0,2},{},{},{},8);
    for(unsigned i=0;i<180;++i)w.step(1.0/60);REQUIRE(w.sleeping(id));(void)w.poses();
    // Same 8-unit sole skirt as capture: Source feet stay at z=0, mirror bottom at -8.
    auto actor=mirror(7,{-80,0,32});actor.half={16,16,40};actor.velocity={200,0,0};
    bool contact=false,moved=false;
    for(unsigned i=0;i<50;++i) {
      actor.position.x=-80+float(i)*200/60;w.sync_bodies({actor},1.0/60);w.step(1.0/60);
      CHECK((w.scene_pose(7).position-actor.position).length()<.001f);
      for(const auto& hit:w.take_damage())if(hit.id==id && (hit.kinds&SourceBody))contact=true;
      for(const auto& pose:w.poses())if(pose.id==id && std::abs(pose.position.x)>2)moved=true;
    }
    CHECK(moved);CHECK(contact==(half>4));CHECK(w.stats().live==1);
  }
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
  const auto nearby=w.regions({63000,0,32});bool last=false,first=false;
  for(const auto& r:nearby) { if(r.minimum.x<63000 && r.maximum.x>63000)last=true;if(r.minimum.x<0 && r.maximum.x>0)first=true; }
  CHECK(last);CHECK(!first); // Distant old glass cannot starve the player's current pile.
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
    const auto cold=std::chrono::steady_clock::now();w.sync_bodies(scene,1.0/60);const double cold_ms=ms(cold);
    const auto begin=std::chrono::steady_clock::now();
    for(unsigned i=0;i<120;++i) { (void)w.regions();w.sync_bodies(scene,1.0/60); }
    const double scene_ms=ms(begin)/120;
    const auto rays=std::chrono::steady_clock::now();
    for(unsigned i=0;i<640;++i)(void)w.ray({-600,float(i%25)*12-150,2},{600,float(i%25)*12-150,2},180000,300);
    const double ray_ms=ms(rays)/640;
    Hull rounded;
    for(unsigned i=0;i<64;++i) {
      const double a=i*6.283185307179586/64;
      rounded.push_back({float(4*std::cos(a)),float(4*std::sin(a)),i%2?4.0f:-4.0f});
    }
    scene[0].convexes=scene[1].convexes=std::vector<Hull>(8,rounded);
    const auto cook=std::chrono::steady_clock::now();w.sync_bodies(scene,1.0/60);const double cook_ms=ms(cook);
    std::cout<<"R7-C bounds bodies="<<scene.size()<<" cold_boxes_ms="<<cold_ms<<" regions_sync_mean_ms="<<scene_ms
      <<" ray_mean_ms="<<ray_ms<<" two_512_point_shapes_ms="<<cook_ms<<'\n';
    CHECK(w.stats().scene_bodies==kMaxSceneBodies);CHECK(w.stats().live==2000);
  }
  World w(8,0);ready(w);std::vector<double> times;double total=0;
  for(unsigned i=0;i<120;++i) {
    const auto id=w.spawn(fixture::box(16,12,.5f),{0,0,32},{},{400,0,0},{0,0,180},8);
    const auto begin=std::chrono::steady_clock::now();CHECK(w.can_split(id,8));const auto parts=w.split(id,8);
    const auto elapsed=ms(begin);total+=elapsed;times.push_back(elapsed);
    REQUIRE(parts.size()==2);for(const auto& child:parts)w.remove(child.id);
  }
  std::sort(times.begin(),times.end());
  std::cout<<"R7-C split can+replace mean_ms="<<total/times.size()<<" p99_ms="<<times[118]<<" max_ms="<<times.back()<<'\n';
}
