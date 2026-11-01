// Read-only offline import probe. No engine, installed assets or generated fixtures are modified.
#include "world.h"
#include <chrono>
#include <fstream>
#include <iostream>
#include <iterator>

int main(int argc,char** argv) {
  using namespace nl::glass;
  if(argc!=2) { std::cerr<<"usage: nl_glass_import_probe <map.bsp>\n";return 2; }
  try {
    std::ifstream file(argv[1],std::ios::binary|std::ios::ate);
    if(!file || file.tellg()<0 || file.tellg()>static_cast<std::streamoff>(kMaxMapBytes))throw Error("map missing/too large");
    file.seekg(0);std::vector<std::uint8_t> bytes((std::istreambuf_iterator<char>(file)),{});
    const auto start=std::chrono::steady_clock::now();const auto map=read_bsp(bytes);
    const auto parsed=std::chrono::steady_clock::now();World w(kMaxBudget);
    const auto created=std::chrono::steady_clock::now();(void)w.load_map(bytes);w.finish();
    const auto end=std::chrono::steady_clock::now();const auto s=w.stats();
    auto ms=[](auto a,auto b) { return std::chrono::duration<double,std::milli>(b-a).count(); };
    std::cout<<"brushes="<<s.brushes<<" hulls="<<map.brushes.size()<<" skipped="<<s.skipped_brushes
      <<" refused="<<s.refused_brushes<<" triangles="<<map.triangles.size()<<" refused_meshes="<<s.refused_meshes
      <<" props="<<map.props.size()<<" statics="<<s.statics<<" parse_ms="<<ms(start,parsed)
      <<" init_ms="<<ms(parsed,created)<<" parse_and_build_ms="<<ms(created,end)<<'\n';
    return 0;
  }catch(const std::exception& e) { std::cerr<<e.what()<<'\n';return 1; }
}
