// MIT. Replay actual Lua capture rows against a generated sleeping pile, without a game.
#include "world.h"
#include "fixture.h"
#include <chrono>
#include <iostream>
#include <map>
#include <string>

using namespace nl::glass;
int main(int argc,char** argv) {
  try {
    const bool enabled=argc==1;
    if(argc>2 || (!enabled && std::string(argv[1])!="--off"))throw Error("usage: nl_glass_scene_replay [--off] < snapshots");
    World w(16);w.load_map(fixture::room());w.finish();w.set_interaction(enabled);
    for(int x=-1;x<=1;++x)for(int y=-1;y<=1;++y)
      w.spawn(fixture::box(16,16,.25f),{float(x)*34,float(y)*34,8},{},{},{},8);
    for(unsigned i=0;i<180;++i)w.step(1.0/60);
    std::map<std::uint32_t,V3> original;
    for(const auto& p:w.poses()) {
      if(!p.sleeping)throw Error("fixture did not settle");
      original[p.id]=p.position;
    }
    if(original.size()!=9)throw Error("fixture lost pieces");
    unsigned frames=0,mirrored=0,hits=0;std::map<std::uint32_t,bool> moved;
    std::string marker;double dt,total_ms=0;
    while(std::cin>>marker) {
      unsigned n=0;
      if(marker!="frame" || !(std::cin>>dt>>n) || ++frames>120 || n>kMaxSceneBodies)throw Error("invalid replay frame");
      std::vector<SceneBody> rows(n);
      for(auto& b:rows) {
        if(!(std::cin>>b.key>>b.position.x>>b.position.y>>b.position.z>>b.angles.x>>b.angles.y>>b.angles.z
          >>b.half.x>>b.half.y>>b.half.z>>b.mass>>b.velocity.x>>b.velocity.y>>b.velocity.z))throw Error("invalid replay body");
      }
      const auto start=std::chrono::steady_clock::now();
      w.sync_bodies(rows,dt);
      total_ms+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
      mirrored+=w.stats().scene_bodies>0;w.step(dt);
      if(enabled)for(const auto& b:rows)
        if((w.scene_pose(b.key).position-b.position).length()>.01f)throw Error("glass changed a Source mirror trajectory");
      for(const auto& p:w.poses()) {
        const auto d=p.position-original.at(p.id);
        if(d.x*d.x+d.y*d.y>4)moved[p.id]=true;
      }
      for(const auto& hit:w.take_damage())if(hit.kinds&SourceBody)++hits;
    }
    std::cout<<"scene replay enabled="<<enabled<<" frames="<<frames<<" mirrored="<<mirrored<<" moved="<<moved.size()
      <<" body_hits="<<hits<<" sweep_hits="<<w.stats().scene_sweep_hits<<" sync_mean_ms="<<(frames?total_ms/frames:0)<<'\n';
    if(!frames || (enabled?moved.empty() || !hits:!moved.empty() || hits))return 1;
    return 0;
  } catch(const std::exception& e) { std::cerr<<e.what()<<'\n';return 1; }
}
