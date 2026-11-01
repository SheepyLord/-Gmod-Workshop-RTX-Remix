#pragma once
#include "bsp.h"
#include <array>
#include <bit>
#include <cstring>

namespace nl::glass::fixture {
using Buffer=std::vector<std::uint8_t>;
inline void u32(Buffer& b,std::size_t at,std::uint32_t v) {
  if(b.size()<at+4)b.resize(at+4);for(unsigned i=0;i<4;++i)b[at+i]=static_cast<std::uint8_t>(v>>(i*8));
}
inline void u16(Buffer& b,std::size_t at,unsigned v) {
  if(b.size()<at+2)b.resize(at+2);b[at]=static_cast<std::uint8_t>(v);b[at+1]=static_cast<std::uint8_t>(v>>8);
}
inline void f32(Buffer& b,std::size_t at,float v) { u32(b,at,std::bit_cast<std::uint32_t>(v)); }
inline void vec(Buffer& b,std::size_t at,V3 v) { f32(b,at,v.x);f32(b,at+4,v.y);f32(b,at+8,v.z); }
inline Hull box(float x=2,float y=2,float z=.3f) {
  Hull h;for(float a:{-x,x})for(float b:{-y,y})for(float c:{-z,z})h.push_back({a,b,c});return h;
}
inline Buffer room(unsigned version=20,bool swapped=false) {
  std::array<Buffer,64> l;
  auto brush=[&](V3 min,V3 max,unsigned contents=1) {
    const auto index=l[18].size()/12, first=l[19].size()/8;
    u32(l[18],index*12,static_cast<unsigned>(first));u32(l[18],index*12+4,6);u32(l[18],index*12+8,contents);
    const std::array<Plane,6> planes{{{{1,0,0},max.x},{{-1,0,0},-min.x},{{0,1,0},max.y},
                                    {{0,-1,0},-min.y},{{0,0,1},max.z},{{0,0,-1},-min.z}}};
    for(const auto& p:planes) {
      const auto n=l[1].size()/20;vec(l[1],n*20,p.normal);f32(l[1],n*20+12,p.distance);u32(l[1],n*20+16,0);
      const auto s=l[19].size();l[19].resize(s+8);u16(l[19],s,static_cast<unsigned>(n));
    }
    u16(l[17],l[17].size(),static_cast<unsigned>(index));
  };
  brush({-1024,-1024,-64},{1024,1024,0});
  brush({-1056,-1056,0},{-1024,1056,512});brush({1024,-1056,0},{1056,1056,512});
  brush({-1024,-1056,0},{1024,-1024,512});brush({-1024,1024,0},{1024,1056,512});
  brush({-512,-512,0},{-500,-500,10},0x10000); // playerclip: deliberately excluded
  l[10].resize(version==19?56:32);u16(l[10],26,6);
  l[14].resize(48);u32(l[14],36,0xffffffffu);u32(l[14],44,1);
  // A sloped displacement over a quad, one grid corner lifted.
  l[7].resize(56);u16(l[7],8,4);
  const std::array<V3,4> corners{{{200,200,1},{240,200,1},{240,240,1},{200,240,1}}};
  for(unsigned i=0;i<4;++i) { vec(l[3],i*12,corners[i]);u16(l[12],i*4,i);u16(l[12],i*4+2,(i+1)%4);u32(l[13],i*4,i); }
  l[26].resize(176);vec(l[26],0,corners[0]);u32(l[26],20,2);u32(l[26],32,1);
  l[33].resize(25*20);for(unsigned i=0;i<25;++i) { vec(l[33],i*20,{0,0,1});f32(l[33],i*20+12,float(i%5)*.25f); }
  l[48].resize(32*2);for(unsigned i=0;i<32;++i)u16(l[48],i*2,1);
  // sprp v11 with one solid instance and one non-solid decoration.
  Buffer prop(4+128+4+4+80*2);u32(prop,0,1);
  const char model[]="models/fixture/block.mdl";std::memcpy(prop.data()+4,model,sizeof(model));
  u32(prop,136,2);
  for(unsigned i=0;i<2;++i) { const auto p=140+i*80;vec(prop,p,{0,500,32});vec(prop,p+12,{0,30,0});prop[p+30]=i==0?6:0;f32(prop,p+76,1.5f); }
  l[35].resize(20);u32(l[35],0,1);u32(l[35],4,0x73707270);u16(l[35],10,11);u32(l[35],16,static_cast<unsigned>(prop.size()));
  l[35].insert(l[35].end(),prop.begin(),prop.end());
  // Entity bytes make the v21 directory layout unambiguous.
  l[0]={'{','}','\n'};
  Buffer file(1036);u32(file,0,0x50534256);u32(file,4,version);
  for(unsigned i=0;i<64;++i) {
    const auto at=8+i*16,offset=static_cast<unsigned>(file.size());
    u32(file,at+(swapped?4:0),offset);u32(file,at+(swapped?8:4),static_cast<unsigned>(l[i].size()));
    u32(file,at+(swapped?0:8),i==10 && version!=19?1:0);
    if(i==35)u32(l[i],12,offset+20);
    file.insert(file.end(),l[i].begin(),l[i].end());
  }
  return file;
}
}
