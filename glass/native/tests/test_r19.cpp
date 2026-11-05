// R19 pre-release review: GL-01 (expansion charged before inflating), the 'sprp' total and the
// leaf walk's work budget, and a world that cancels its import instead of waiting for it.
#include "world.h"
#include "fixture.h"
#include "nl_test.h"
#include <chrono>
#include <cstring>
#include <iostream>
#include <memory>
#include <string>
#include <thread>

using namespace nl::glass;
namespace {
constexpr std::uint32_t MiB=1024*1024;
// The Error a parse ends with, or "" when it succeeds.
std::string refusal(const fixture::Buffer& file) {
  try { (void)read_bsp(file); } catch(const Error& e) { return e.what(); }
  return "";
}
// An LZMA header declaring `declared` bytes over sixteen undecodable bytes (the first byte of an
// LZMA range-coded stream must be zero), so the decoder fails after its buffer was allocated.
fixture::Buffer undecodable(std::uint32_t declared) {
  fixture::Buffer lump(17);fixture::u32(lump,0,0x414d5a4c);fixture::u32(lump,4,declared);fixture::u32(lump,8,16);
  lump[12]=0x5d;fixture::u32(lump,13,65536);lump.resize(33,0xff);
  return lump;
}
// `slices` collision lumps (1, 3, 5, ...) all cover one zero region of `region` bytes; lump 48
// is an undecodable LZMA lump declaring `declared` bytes. The reader charges lumps in index order.
fixture::Buffer collision_budget(unsigned slices,std::uint32_t region,std::uint32_t declared) {
  static constexpr unsigned order[]{1,3,5,7,10,12,13,14,17,18,19,26,33,35};
  fixture::Buffer file(1036+std::size_t(region));fixture::u32(file,0,0x50534256);fixture::u32(file,4,20);
  for(unsigned i=0;i<slices;++i) { const auto at=8+order[i]*16;fixture::u32(file,at,1036);fixture::u32(file,at+4,region); }
  const auto at=static_cast<unsigned>(file.size());const auto lump=undecodable(declared);
  file.insert(file.end(),lump.begin(),lump.end());
  fixture::u32(file,8+48*16,at);fixture::u32(file,8+48*16+4,static_cast<unsigned>(lump.size()));
  return file;
}
// A one-brush world whose six displacement lumps (unread: there is no displacement) cover one
// zero region of `region` bytes, and one compressed 'sprp' entry declaring `declared` bytes.
fixture::Buffer prop_budget(std::uint32_t region,std::uint32_t declared) {
  auto l=fixture::shared_leaves(1,1,fixture::box_planes());
  l[35].resize(20);fixture::u32(l[35],0,1);fixture::u32(l[35],4,0x73707270);
  fixture::u16(l[35],8,1);fixture::u16(l[35],10,11);
  auto file=fixture::assemble(l);
  const auto blob=static_cast<unsigned>(file.size());const auto lump=undecodable(declared);
  file.insert(file.end(),lump.begin(),lump.end());
  const auto directory=fixture::read_u32(file,8+35*16);
  fixture::u32(file,directory+12,blob);fixture::u32(file,directory+16,static_cast<unsigned>(lump.size()));
  const auto start=static_cast<unsigned>(file.size());file.resize(file.size()+region);
  for(unsigned i:{3u,7u,12u,13u,33u,48u}) { fixture::u32(file,8+i*16,start);fixture::u32(file,8+i*16+4,region); }
  return file;
}
// `entries` game-lump directory entries that all name one sprp v4 payload of `records` solid props.
fixture::Buffer aliased_props(unsigned entries,unsigned records) {
  auto l=fixture::shared_leaves(1,1,fixture::box_planes());
  fixture::Buffer payload(140+std::size_t(records)*56);fixture::u32(payload,0,1);
  const char model[]="models/fixture/block.mdl";std::memcpy(payload.data()+4,model,sizeof(model));
  fixture::u32(payload,136,records);
  for(unsigned p=0;p<records;++p)payload[140+std::size_t(p)*56+30]=6;
  l[35].resize(4+std::size_t(entries)*16);fixture::u32(l[35],0,entries);
  for(unsigned e=0;e<entries;++e) {
    fixture::u32(l[35],4+e*16,0x73707270);fixture::u16(l[35],4+e*16+6,4);
    fixture::u32(l[35],4+e*16+12,static_cast<unsigned>(payload.size()));
  }
  const auto at=static_cast<unsigned>(l[35].size());l[35].insert(l[35].end(),payload.begin(),payload.end());
  auto file=fixture::assemble(l);const auto lump=fixture::read_u32(file,8+35*16);
  for(unsigned e=0;e<entries;++e)fixture::u32(file,lump+4+e*16+8,lump+at);
  return file;
}
double ms_since(std::chrono::steady_clock::time_point t) {
  return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-t).count();
}
}
TEST_CASE("glass R19 leaf walk has a work budget for shared leaf-brush ranges") {
  // 128 leaves x 65,535 shared references = 8,388,480 visits: inside the 8,388,608 budget.
  CHECK(read_bsp(fixture::assemble(fixture::shared_leaves(128,65535,fixture::box_planes()))).brushes.size()==1);
  // One more leaf crosses it. Unbounded, 1,048,576 such leaves meant 2^36 visits on the worker.
  CHECK(refusal(fixture::assemble(fixture::shared_leaves(129,65535,fixture::box_planes())))=="BSP leaf brush reference work limit");
  // An ordinary map (each leaf its own range) is far inside the budget.
  CHECK(read_bsp(fixture::room()).brushes.size()==5);
}
TEST_CASE("glass R19 GL-01 a collision lump's declared expansion is charged before inflating") {
  // 8 x 31 MiB of collision slices leave exactly 8 MiB of the 256 MiB budget.
  CHECK(refusal(collision_budget(8,31*MiB,8*MiB))=="corrupt BSP LZMA"); // fits: allocated, then the decoder fails
  // One byte more is refused before any buffer exists; the decoder never runs.
  CHECK(refusal(collision_budget(8,31*MiB,8*MiB+1))=="expanded BSP collision data limit");
  CHECK(refusal(collision_budget(8,31*MiB,128*MiB))=="expanded BSP collision data limit");
  // Uncompressed slices alone still count, as before.
  CHECK(refusal(collision_budget(9,31*MiB,MiB))=="expanded BSP collision data limit");
}
TEST_CASE("glass R19 GL-01 an inflated static-prop lump counts against the same budget") {
  // 6 x 41 MiB of unread displacement lumps leave about 10 MiB.
  CHECK(refusal(prop_budget(41*MiB,8*MiB))=="corrupt BSP LZMA");
  CHECK(refusal(prop_budget(41*MiB,16*MiB))=="expanded BSP collision data limit");
  CHECK(refusal(prop_budget(MiB,16*MiB))=="corrupt BSP LZMA"); // the same entry within budget
}
TEST_CASE("glass R19 static props are capped across aliased sprp entries") {
  const auto one=read_bsp(aliased_props(1,32768));CHECK(one.props.size()==32768);
  const auto two=read_bsp(aliased_props(2,16384));CHECK(two.props.size()==32768);
  CHECK(two.props.front().model=="models/fixture/block.mdl");
  CHECK(refusal(aliased_props(2,16385))=="static-prop count");
  // The verifier's case: 128 entries naming one full payload were 4.2 million props for Lua.
  CHECK(refusal(aliased_props(128,32768))=="static-prop count");
}
TEST_CASE("glass R19 a requested stop ends a parse between units of work") {
  std::stop_source stop;stop.request_stop();
  CHECK_THROWS_AS(read_bsp(fixture::room(),stop.get_token()),Error);
  CHECK(read_bsp(fixture::room(),std::stop_source().get_token()).brushes.size()==5);
  CHECK(read_bsp(fixture::room(),{}).brushes.size()==5);
}
TEST_CASE("glass R19 destroying a world cancels its import instead of waiting for it") {
  // 7,000 shared 64-sided brushes: several seconds of clipping and cooking on one worker (the
  // brush clipping work limit is 8,192 of them). Cancelled, the worker stops at the next brush.
  const auto heavy=fixture::heavy_brushes(7000);
  auto w=std::make_unique<World>(1);std::vector<StaticProp> props;
  w->begin_load(heavy);
  std::this_thread::sleep_for(std::chrono::milliseconds(100));
  CHECK(!w->poll_load(props)); // still importing: there is work to cancel
  const auto start=std::chrono::steady_clock::now();
  w.reset(); // ~World requests the stop, then joins the worker
  const double waited=ms_since(start);
  std::cout<<"R19 cancelled heavy import: destructor waited "<<waited<<" ms\n";
  CHECK(waited<1000);
  // A fresh world imports an ordinary map as before.
  World again(1);again.begin_load(fixture::room());
  const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(10);
  while(!again.poll_load(props) && std::chrono::steady_clock::now()<deadline)std::this_thread::sleep_for(std::chrono::milliseconds(1));
  CHECK(props.size()==1);
}
