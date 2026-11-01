#include "world.h"
#include "fixture.h"
#include "nl_test.h"
#include <chrono>
#include <iostream>
#include <limits>
#include <thread>
#include <windows.h>

using namespace nl::glass;
namespace {
double cpu_seconds() {
  FILETIME created{},exited{},kernel{},user{};
  if(!GetProcessTimes(GetCurrentProcess(),&created,&exited,&kernel,&user))throw Error("GetProcessTimes failed");
  auto seconds=[](FILETIME t) { return (double(t.dwHighDateTime)*4294967296.0+t.dwLowDateTime)/10000000.0; };
  return seconds(kernel)+seconds(user);
}
}
TEST_CASE("glass hulls refuse flat nonfinite and unbounded input") {
  CHECK(valid_hull(fixture::box()));CHECK(!valid_hull({{0,0,0},{1,0,0},{1,1,0},{0,1,0}}));
  auto h=fixture::box();h[0].x=std::numeric_limits<float>::infinity();CHECK(!valid_hull(h));
  std::vector<Plane> p{{{1,0,0},1},{{-1,0,0},1},{{0,1,0},1},{{0,-1,0},1},{{0,0,1},1},{{0,0,-1},1}};
  CHECK(brush_hull(p).size()==8);p.pop_back();CHECK(brush_hull(p).empty());
}
TEST_CASE("glass high-sided brush clips and deduplicates in double precision") {
  std::vector<Plane> p{{{0,0,1},64},{{0,0,-1},64}};
  for(unsigned i=0;i<62;++i) {
    const double a=i*6.283185307179586/62;
    const V3 n{static_cast<float>(std::cos(a)),static_cast<float>(std::sin(a)),0};
    p.push_back({n,128+n.dot({12000,-3000,0})});
  }
  const auto h=brush_hull(p);REQUIRE(h.size()==124);CHECK(valid_hull(h));
  World w(1);w.load_map(fixture::room());CHECK(w.add_model("prism",{h}));w.finish();
  CHECK(w.stats().refused_convexes==0);
}
TEST_CASE("glass BSP imports only world brushes displacements and solid sprp instances") {
  for(auto v:{19u,20u,21u}) {
    const auto map=read_bsp(fixture::room(v));CHECK(map.brushes.size()==5);CHECK(map.triangles.size()==32);
    REQUIRE(map.props.size()==1);CHECK(map.props[0].model=="models/fixture/block.mdl");CHECK(map.props[0].scale==1.5f);
  }
  CHECK(read_bsp(fixture::room(21,true)).brushes.size()==5);
  auto file=fixture::room();fixture::u32(file,4,99);CHECK_THROWS_AS(read_bsp(file),Error);
  file=fixture::room();fixture::u32(file,8+18*16,0xfffffff0u);CHECK_THROWS_AS(read_bsp(file),Error);
  file.resize(100);CHECK_THROWS_AS(read_bsp(file),Error);
  // World nodes never pull in a brush belonging only to an entity model.
  file=fixture::room();const auto leaf_offset=fixture::read_u32(file,8+10*16);
  fixture::u16(file,leaf_offset+26,1);CHECK(read_bsp(file).brushes.size()==1);
  file=fixture::room();fixture::u16(file,fixture::read_u32(file,8+48*16),1u<<5);
  CHECK(read_bsp(file).triangles.size()==31); // An authored displacement hole remains a hole.
}
TEST_CASE("glass displacement fast index goes to corner three and ordinary tags need no surface bit") {
  auto file=fixture::room();const auto tags=fixture::read_u32(file,8+48*16);
  for(unsigned i=0;i<32;++i)fixture::u16(file,tags+i*2,i%3==0?0:i%3==1?2:6);
  const auto map=read_bsp(file);CHECK(map.triangles.size()==32);
  bool raised=false,mirrored=false;
  for(const auto& t:map.triangles)for(auto p:{t.a,t.b,t.c}) {
    if((p-V3{200,210,1.25f}).length()<.001f)raised=true;
    if((p-V3{210,200,1.25f}).length()<.001f)mirrored=true;
  }
  CHECK(raised);CHECK(!mirrored);
}
TEST_CASE("glass BSP skips a brush that cannot become a hull, not the map") {
  auto file=fixture::room();const auto brushes=fixture::read_u32(file,8+18*16);
  fixture::u32(file,brushes+4,3); // brush 0 keeps a valid side range but has only three sides
  const auto map=read_bsp(file);CHECK(map.brushes.size()==4);CHECK(map.skipped_brushes==1);CHECK(map.considered_brushes==5);
  for(unsigned i=1;i<5;++i)fixture::u32(file,brushes+i*12+4,3);
  CHECK(read_bsp(file).brushes.empty()); // displacement/props can still supply collision
  World w(1);w.load_map(file);w.finish();CHECK(w.stats().ready);
  fixture::u32(file,12+26*16,0);fixture::u32(file,12+35*16,0);
  w.load_map(file);CHECK_THROWS_AS(w.finish(),Error); // genuinely no collision: fallback
}
TEST_CASE("glass Jolt-refused brush and prop convex are counted without disabling usable collision") {
  // Small enough to fail Jolt's initial-triangle area threshold, but a finite 3D hull in Source units.
  const auto tiny=fixture::box(.002f,.002f,.002f);REQUIRE(valid_hull(tiny));
  auto file=fixture::room();const auto planes=fixture::read_u32(file,8+1*16);
  for(unsigned i=0;i<6;++i)fixture::f32(file,planes+i*20+12,.002f);
  World w(4);w.load_map(file);
  CHECK(w.stats().skipped_brushes==0);CHECK(w.stats().refused_brushes==1);
  CHECK(w.add_model("mixed",{tiny,fixture::box()}));CHECK(!w.add_model("tiny",{tiny}));
  CHECK(w.stats().refused_convexes==2);CHECK(w.add_prop("mixed",{},{}));CHECK(!w.add_prop("tiny",{},{}));
  w.finish();CHECK(w.stats().ready);CHECK(w.stats().statics==6);CHECK(w.stats().skipped_props==1);
}
TEST_CASE("glass BSP decodes Source LZMA collision lumps and refuses bad compression") {
  auto file=fixture::room();
  // Generated from the same 32-byte v1 leaf (first brush=0, count=6), with Python's raw
  // LZMA1 encoder, lc=3/lp=0/pb=2 and a 64 KiB dictionary. No external fixture file.
  const fixture::Buffer packed{0x00,0x00,0x6e,0x0c,0x4e,0x54,0x31,0xef,0xce,0xff,0xff,0xfd,0xf0,0x10,0x00};
  fixture::Buffer lump(17);fixture::u32(lump,0,0x414d5a4c);fixture::u32(lump,4,32);
  fixture::u32(lump,8,static_cast<unsigned>(packed.size()));lump[12]=0x5d;fixture::u32(lump,13,65536);
  lump.insert(lump.end(),packed.begin(),packed.end());const auto offset=static_cast<unsigned>(file.size());
  fixture::u32(file,8+10*16,offset);fixture::u32(file,12+10*16,static_cast<unsigned>(lump.size()));fixture::u32(file,20+10*16,32);
  file.insert(file.end(),lump.begin(),lump.end());CHECK(read_bsp(file).brushes.size()==5);
  fixture::u32(file,offset+13,128*1024*1024);CHECK_THROWS_AS(read_bsp(file),Error);
  fixture::u32(file,offset+13,65536);file.pop_back();CHECK_THROWS_AS(read_bsp(file),Error);
  // Same raw-encoder settings, generated from fixture::room's 300-byte sprp payload.
  const fixture::Buffer prop_packed{0x00,0x00,0x80,0x3c,0x8a,0x42,0xe3,0x86,0xa4,0xd3,0xcd,0x1a,0xc8,0x16,0x7a,0x8d,
    0x78,0x9f,0xf1,0x8a,0xae,0x23,0x9c,0x9c,0xb3,0xb5,0x56,0x69,0xe5,0xb6,0x9e,0x69,0xbf,0x55,0xdd,0xa4,0x4d,0x66,
    0xdf,0xe1,0x82,0x51,0xcd,0xc6,0x2b,0x8a,0xe5,0x5a,0x5f,0x3b,0x99,0x7c,0xca,0x47,0x24,0xc7,0x3a,0x03,0x86,0xff,
    0xff,0xf3,0xb2,0x00,0x00};
  for(bool original_length:{false,true}) {
    file=fixture::room();const auto directory=fixture::read_u32(file,8+35*16), at=static_cast<unsigned>(file.size());
    fixture::Buffer compressed(17);fixture::u32(compressed,0,0x414d5a4c);fixture::u32(compressed,4,300);
    fixture::u32(compressed,8,static_cast<unsigned>(prop_packed.size()));compressed[12]=0x5d;fixture::u32(compressed,13,65536);
    compressed.insert(compressed.end(),prop_packed.begin(),prop_packed.end());file.insert(file.end(),compressed.begin(),compressed.end());
    fixture::u16(file,directory+8,1);fixture::u32(file,directory+12,at);
    fixture::u32(file,directory+16,original_length?300:static_cast<unsigned>(compressed.size()));
    const auto map=read_bsp(file);REQUIRE(map.props.size()==1);CHECK(map.props[0].scale==1.5f);
  }
}
TEST_CASE("glass BSP deterministic damaged-fixture sweep remains bounded") {
  const auto seed=fixture::room();std::uint32_t rng=78394;
  for(unsigned i=0;i<128;++i) {
    auto file=seed;rng=rng*1664525+1013904223;const auto offset=std::size_t(rng)%file.size();
    file[offset]^=static_cast<std::uint8_t>(1u<<(rng%8));
    try { const auto map=read_bsp(file);for(const auto& hull:map.brushes)CHECK(valid_hull(hull)); }
    catch(const Error&) {} // Refusal is the expected outcome for damaged geometry/header fields.
  }
}
TEST_CASE("glass world validates bounds and map failure clears static collision") {
  CHECK_THROWS_AS(World(0),Error);CHECK_THROWS_AS(World(kMaxBudget+1),Error);
  World w(2);const auto room=fixture::room();auto props=w.load_map(room);
  CHECK(w.stats().temp_reserved_bytes==0); // neither Init nor map import reserves simulation scratch
  w.add_model(props[0].model,{fixture::box(16,16,32)});
  w.add_prop(props[0].model,props[0].position,props[0].angles,props[0].scale);w.finish();
  CHECK(w.stats().statics==7);CHECK(w.stats().workers>=1 && w.stats().workers<=8);
  auto h=fixture::box();const auto a=w.spawn(h,{0,0,16},{13,27,39},{},{0,0,10});
  const auto b=w.spawn(h,{16,0,16},{},{},{});CHECK(a!=b);
  CHECK_THROWS_AS(w.spawn(h,{},{},{},{}),Error);CHECK_THROWS_AS(w.step(-1),Error);
  CHECK_THROWS_AS(w.impulse({},-1,10),Error);CHECK_THROWS_AS(w.set_gravity(-1),Error);
  CHECK_THROWS_AS(w.sleeping(0),Error);CHECK(!w.remove(0));CHECK(w.remove(a));CHECK(!w.remove(a));
  const auto c=w.spawn(h,{0,0,32},{},{},{});CHECK(c!=a);w.set_collide(false);
  w.set_catch_up_budget(1000);w.step(1); // the four-substep cap, not this machine's 4 ms budget
  CHECK(w.stats().substeps==4);CHECK(w.stats().dropped_seconds>.9);
  w.clear();CHECK(w.stats().live==0 && w.stats().ready);
  CHECK_THROWS_AS(w.load_map({}),Error);CHECK(!w.stats().ready && w.stats().statics==0);
}
TEST_CASE("glass poses interpolate source angles sleep once and wake on impulse") {
  World w(4,0);w.load_map(fixture::room());w.finish();
  const auto id=w.spawn(fixture::box(),{0,0,32},{13,27,39},{60,0,0},{});
  auto poses=w.poses();REQUIRE(poses.size()==1);CHECK(std::abs(poses[0].angles.x-13)<.01f);
  CHECK(std::abs(poses[0].angles.y-27)<.01f);CHECK(std::abs(poses[0].angles.z-39)<.01f);
  w.step(1.0/60);w.step(1.0/120);poses=w.poses();CHECK(poses[0].position.x>.4f && poses[0].position.x<.6f);
  w.set_gravity(600);
  for(unsigned i=0;i<600 && !w.sleeping(id);++i)w.step(1.0/60);
  CHECK(w.sleeping(id));poses=w.poses();REQUIRE(poses.size()==1);CHECK(poses[0].sleeping);
  CHECK(poses[0].position.z>-.5f && poses[0].position.z<4);
  CHECK(w.poses().empty());w.impulse({0,0,0},1000,100);w.step(1.0/60);CHECK(!w.sleeping(id));CHECK(w.poses().size()==1);
}
TEST_CASE("glass pose queue visits only changed bodies and safely reuses removed slots") {
  World w(kMaxBudget);w.load_map(fixture::room());w.finish();
  auto id=w.spawn(fixture::box(),{0,0,32},{},{},{});
  CHECK(w.poses().size()==1);CHECK(w.stats().pose_visits==1);
  CHECK(w.remove(id));CHECK(w.poses().empty());CHECK(w.stats().pose_visits==0);
  id=w.spawn(fixture::box(),{0,0,32},{},{},{});
  for(unsigned i=0;i<600 && !w.sleeping(id);++i)w.step(1.0/60);
  REQUIRE(w.sleeping(id));CHECK(w.poses().size()==1);CHECK(w.poses().empty());CHECK(w.stats().pose_visits==0);
  w.set_gravity(100);CHECK(w.poses().size()==1);w.set_collide(false);CHECK(w.poses().size()==1);
  CHECK(w.stats().temp_reserved_bytes<48*1024*1024);
}
TEST_CASE("glass asynchronous import finish and steps poll safely and exclude concurrent mutation") {
  World w(8);w.begin_load(fixture::room());CHECK(w.stats().busy);
  CHECK_THROWS_AS(w.spawn(fixture::box(),{},{},{},{}),Error);
  std::vector<StaticProp> props;
  auto poll=[&](auto fn) {
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(10);
    while(!fn()) {
      if(std::chrono::steady_clock::now()>deadline)throw Error("worker poll timeout");
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
  };
  poll([&] { return w.poll_load(props); });CHECK(props.size()==1);CHECK(!w.stats().busy);
  w.begin_finish();poll([&] { return w.poll_finish(); });CHECK(w.stats().ready);
  const auto id=w.spawn(fixture::box(),{0,0,32},{},{},{});
  w.begin_step(1.0/60);CHECK(w.stats().busy);CHECK_THROWS_AS(w.remove(id),Error);
  poll([&] { return w.poll_step(); });CHECK(!w.stats().busy);CHECK(w.poses().size()==1);
  w.begin_step(1.0/60);w.clear();CHECK(w.stats().live==0); // lifecycle joins pending work
  w.begin_load({});CHECK_THROWS_AS(poll([&] { return w.poll_load(props); }),Error);
  CHECK(!w.stats().ready);CHECK(!w.stats().busy);
  w.begin_load(fixture::room()); // destructor joins even if caller never polls
}
TEST_CASE("glass displacement and scaled static prop actually support falling shards") {
  World w(4);const auto props=w.load_map(fixture::room());
  w.add_model(props[0].model,{fixture::box(16,16,32)});w.add_prop(props[0].model,props[0].position,props[0].angles,props[0].scale);w.finish();
  const auto terrain=w.spawn(fixture::box(),{220,220,40},{},{},{}), prop=w.spawn(fixture::box(),{0,500,128},{},{},{});
  for(unsigned i=0;i<600;++i)w.step(1.0/60);
  CHECK(w.sleeping(terrain));CHECK(w.sleeping(prop));
  const auto poses=w.poses();REQUIRE(poses.size()==2);
  for(const auto& p:poses) {
    if(p.id==prop)CHECK(p.position.z>79 && p.position.z<85);
    else CHECK(p.position.z>1.1f && p.position.z<3);
  }
}
TEST_CASE("glass overfull contact tables count saturation and keep the world running") {
  World w(128);w.load_map(fixture::room());w.finish();
  for(unsigned i=0;i<128;++i)w.spawn(fixture::box(),{0,0,32},{},{},{});
  w.step(1.0/60);CHECK(w.stats().contact_overflows>0);CHECK(w.stats().ready);
  CHECK(w.stats().manifold_overflows+w.stats().pair_overflows+w.stats().constraint_overflows>0);
  CHECK(w.poses().size()==128);w.step(1.0/60);CHECK(w.stats().live==128);
  w.clear();CHECK(w.stats().live==0);
  w.set_collide(false);
  for(unsigned i=0;i<128;++i)w.spawn(fixture::box(),{0,0,32},{},{},{});
  w.step(1.0/60);CHECK(w.stats().live==128); // Same overlap cannot create any piece-piece pairs.
}
TEST_CASE("glass benchmark 4000 colliding pieces settle within 15 simulated seconds 30 wall and 120 CPU seconds") {
  constexpr unsigned number=4000,steps=900;
  World w(kMaxBudget);w.load_map(fixture::room());w.finish();
  const auto hull=fixture::box(2,2,.3f);const auto begin=std::chrono::steady_clock::now();
  for(unsigned i=0;i<number;++i)w.spawn(hull,{float(i%40)*5-100,float((i/40)%25)*5-62,float(i/1000)*16+32},{},{},{});
  const auto spawned=std::chrono::steady_clock::now();const double cpu=cpu_seconds();double worst=0,total=0;unsigned settled_at=steps;
  for(unsigned i=0;i<steps;++i) {
    w.step(1.0/60);const auto s=w.stats();worst=std::max(worst,s.step_ms);total+=s.step_ms;
    if(s.awake==0) { settled_at=i+1;break; }
  }
  const auto wall=std::chrono::duration<double>(std::chrono::steady_clock::now()-spawned).count();
  std::cout<<"G1-B benchmark: pieces="<<number<<" capacity="<<kMaxBudget<<" workers="<<w.stats().workers<<" settled_sim_s="<<settled_at/60.0
    <<" awake="<<w.stats().awake<<" spawn_s="<<std::chrono::duration<double>(spawned-begin).count()
    <<" simulation_wall_s="<<wall<<" simulation_cpu_s="<<cpu_seconds()-cpu<<" mean_step_ms="<<total/settled_at<<" max_step_ms="<<worst
    <<" scratch_reserved="<<w.stats().temp_reserved_bytes<<" scratch_peak="<<w.stats().temp_peak_bytes
    <<" contact_overflows="<<w.stats().contact_overflows<<'\n';
  CHECK(w.stats().live==number);CHECK(w.stats().awake==0);CHECK(wall<30);CHECK(cpu_seconds()-cpu<120);
  const auto idle=std::chrono::steady_clock::now();for(unsigned i=0;i<120;++i) { w.step(1.0/60);(void)w.poses(); }
  std::cout<<"G1-B settled step+poses mean_ms="<<std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-idle).count()/120<<'\n';
}
TEST_CASE("glass asynchronous step dispatch and polling at 4000 bodies leave the caller free") {
  World w(kMaxBudget);w.load_map(fixture::room());w.finish();
  const auto hull=fixture::box(2,2,.3f);
  for(unsigned i=0;i<4000;++i)w.spawn(hull,{float(i%40)*5-100,float((i/40)%25)*5-62,float(i/1000)*16+32},{},{},{});
  double dispatch=0,poll=0,max_dispatch=0,max_poll=0,worker=0;unsigned calls=0;
  for(unsigned frame=0;frame<120;++frame) {
    const auto a=std::chrono::steady_clock::now();w.begin_step(1.0/60);const auto b=std::chrono::steady_clock::now();
    const auto ms=std::chrono::duration<double,std::milli>(b-a).count();dispatch+=ms;max_dispatch=std::max(max_dispatch,ms);
    for(;;) {
      const auto c=std::chrono::steady_clock::now();const bool done=w.poll_step();const auto d=std::chrono::steady_clock::now();
      const auto elapsed=std::chrono::duration<double,std::milli>(d-c).count();poll+=elapsed;max_poll=std::max(max_poll,elapsed);++calls;
      if(done)break;
      std::this_thread::sleep_for(std::chrono::milliseconds(1)); // stand in for unrelated game work
    }
    (void)w.poses();worker+=w.stats().step_ms;
  }
  CHECK(w.stats().live==4000);CHECK(w.stats().ready);
  // Exercise catch-up limiting under a measured load; it always runs at least one fixed update.
  w.step(.25);CHECK(w.stats().substeps>=1 && w.stats().substeps<=4);CHECK(w.stats().dropped_seconds>0);
  std::cout<<"G1-B asynchronous 4000: dispatch_mean_ms="<<dispatch/120<<" dispatch_max_ms="<<max_dispatch
    <<" poll_mean_ms="<<poll/calls<<" poll_max_ms="<<max_poll<<" worker_step_mean_ms="<<worker/120
    <<" capped_substeps="<<w.stats().substeps<<" dropped_s="<<w.stats().dropped_seconds<<'\n';
}
