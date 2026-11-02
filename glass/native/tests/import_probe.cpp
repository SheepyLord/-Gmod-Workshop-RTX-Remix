// Read-only offline import probe. No engine, installed assets or generated fixtures are modified.
#include "world.h"
#include <chrono>
#include <fstream>
#include <iostream>
#include <iterator>
#include <thread>

int main(int argc,char** argv) {
  using namespace nl::glass;
  if(argc!=2 && (argc!=3 || std::string(argv[2])!="--water")) { std::cerr<<"usage: nl_glass_import_probe <map.bsp> [--water]\n";return 2; }
  try {
    std::ifstream file(argv[1],std::ios::binary|std::ios::ate);
    if(!file || file.tellg()<0 || file.tellg()>static_cast<std::streamoff>(kMaxMapBytes))throw Error("map missing/too large");
    file.seekg(0);std::vector<std::uint8_t> bytes((std::istreambuf_iterator<char>(file)),{});
    const auto start=std::chrono::steady_clock::now();const auto map=read_bsp(bytes);
    if(argc==3) {
      std::cout<<"water_volumes="<<map.water.size()<<'\n';
      for(const auto& v:map.water)std::cout<<"water min="<<v.minimum.x<<','<<v.minimum.y<<','<<v.minimum.z
        <<" max="<<v.maximum.x<<','<<v.maximum.y<<','<<v.maximum.z<<" surface="<<v.surface.distance<<'\n';
      return 0;
    }
    const auto parsed=std::chrono::steady_clock::now();World w(kMaxBudget);
    const auto created=std::chrono::steady_clock::now();(void)w.load_map(bytes);w.finish();
    const auto end=std::chrono::steady_clock::now();const auto s=w.stats();
    auto ms=[](auto a,auto b) { return std::chrono::duration<double,std::milli>(b-a).count(); };
    std::cout<<"brushes="<<s.brushes<<" hulls="<<map.brushes.size()<<" skipped="<<s.skipped_brushes
      <<" refused="<<s.refused_brushes<<" triangles="<<map.triangles.size()<<" refused_meshes="<<s.refused_meshes
      <<" props="<<map.props.size()<<" statics="<<s.statics<<" parse_ms="<<ms(start,parsed)
      <<" init_ms="<<ms(parsed,created)<<" parse_and_build_ms="<<ms(created,end)<<'\n';
    World background(kMaxBudget);std::vector<StaticProp> props;
    const auto enqueue=std::chrono::steady_clock::now();background.begin_load(bytes);
    const auto enqueued=std::chrono::steady_clock::now();double worst_poll=0;
    auto poll=[&](auto fn) {
      const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(60);
      for(;;) {
        const auto a=std::chrono::steady_clock::now();const bool done=fn();
        worst_poll=std::max(worst_poll,ms(a,std::chrono::steady_clock::now()));
        if(done)return;
        if(std::chrono::steady_clock::now()>deadline)throw Error("import poll timeout");
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
      }
    };
    poll([&] { return background.poll_load(props); });background.begin_finish();
    poll([&] { return background.poll_finish(); });
    std::cout<<"async_enqueue_copy_ms="<<ms(enqueue,enqueued)<<" async_poll_max_ms="<<worst_poll
      <<" async_total_ms="<<ms(enqueue,std::chrono::steady_clock::now())
      <<" init_scratch_bytes="<<background.stats().temp_reserved_bytes<<'\n';
    return 0;
  }catch(const std::exception& e) { std::cerr<<e.what()<<'\n';return 1; }
}
