#include "bsp.h"
#include "LzmaDec.h"
#include <array>
#include <bit>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <set>

namespace nl::glass {
namespace {
using Bytes = std::span<const std::uint8_t>;
void need(bool condition, const char* text) { if (!condition) throw Error(text); }
Bytes slice(Bytes b, std::size_t at, std::size_t size) {
  need(at<=b.size() && size<=b.size()-at,"BSP range outside file/lump");
  return b.subspan(at,size);
}
std::uint32_t u32(Bytes b, std::size_t at) {
  const auto s=slice(b,at,4);
  return std::uint32_t(s[0]) | (std::uint32_t(s[1])<<8) | (std::uint32_t(s[2])<<16) | (std::uint32_t(s[3])<<24);
}
int i32(Bytes b, std::size_t at) { return std::bit_cast<std::int32_t>(u32(b,at)); }
unsigned u16(Bytes b, std::size_t at) { const auto s=slice(b,at,2); return s[0] | (unsigned(s[1])<<8); }
float f32(Bytes b, std::size_t at) {
  const auto v=std::bit_cast<float>(u32(b,at)); need(std::isfinite(v),"nonfinite BSP number"); return v;
}
V3 vec(Bytes b,std::size_t at) {
  V3 v{f32(b,at),f32(b,at+4),f32(b,at+8)}; need(v.valid(),"BSP vector out of bounds"); return v;
}
std::size_t count(Bytes b,std::size_t stride,std::size_t limit) {
  need(b.size()%stride==0 && b.size()/stride<=limit,"bad BSP record count/stride"); return b.size()/stride;
}
void* alloc(ISzAllocPtr,std::size_t n) { return std::malloc(n); }
void release(ISzAllocPtr,void* p) { std::free(p); }
const ISzAlloc allocator{alloc,release};
std::vector<std::uint8_t> decompress(Bytes b, std::size_t expected) {
  need(b.size()>=17 && u32(b,0)==0x414d5a4c,"invalid BSP LZMA header");
  const auto size=u32(b,4), packed=u32(b,8);
  need(size>0 && size<=128*1024*1024 && (!expected || expected==size) && packed==b.size()-17,
       "BSP LZMA size limit/mismatch");
  need(b[12]<9*5*5 && u32(b,13)<=64*1024*1024,"BSP LZMA property/dictionary limit");
  std::vector<std::uint8_t> out(size);
  SizeT dst=out.size(), src=packed;
  ELzmaStatus status=LZMA_STATUS_NOT_SPECIFIED;
  const auto result=LzmaDecode(out.data(),&dst,b.data()+17,&src,b.data()+12,5,LZMA_FINISH_END,&status,&allocator);
  need(result==SZ_OK && dst==size && src==packed &&
    (status==LZMA_STATUS_FINISHED_WITH_MARK || status==LZMA_STATUS_MAYBE_FINISHED_WITHOUT_MARK),"corrupt BSP LZMA");
  return out;
}
struct Lump { Bytes bytes; unsigned version=0; std::vector<std::uint8_t> owned; };
class Reader {
public:
  Bytes file;
  std::array<Lump,64> lumps;
  explicit Reader(Bytes input):file(input) {
    need(file.size()>=1036 && file.size()<=kMaxMapBytes && u32(file,0)==0x50534256,"invalid VBSP header/size");
    const auto version=u32(file,4); need(version>=19 && version<=21,"unsupported BSP version (expected 19-21)");
    // L4D2 v21 places lump version before offset and length. Detect using the entity lump.
    const bool swapped=version==21 && u32(file,8)<1036 && u32(file,12)>=1036;
    std::size_t expanded=0;
    for (unsigned i=0;i<64;++i) {
      const auto at=8+i*16;
      const auto offset=u32(file,at+(swapped?4:0)), length=u32(file,at+(swapped?8:4));
      auto& l=lumps[i]; l.version=u32(file,at+(swapped?0:8));
      need(!length || offset>=1036,"BSP lump overlaps header");
      l.bytes=slice(file,offset,length);
      // Only collision-related lumps are inflated: lighting/visibility can be enormous.
      if (i!=1 && i!=3 && i!=5 && i!=7 && i!=10 && i!=12 && i!=13 && i!=14 && i!=17 &&
          i!=18 && i!=19 && i!=26 && i!=33 && i!=35 && i!=48) continue;
      if (length>=4 && u32(l.bytes,0)==0x414d5a4c) {
        l.owned=decompress(l.bytes,u32(file,at+12)); l.bytes=l.owned;
      } else need(!u32(file,at+12),"BSP collision lump has unsupported compression");
      expanded+=l.bytes.size(); need(expanded<=kMaxMapBytes,"expanded BSP collision data limit");
    }
  }
  Bytes get(unsigned n) const { return lumps[n].bytes; }
};
void read_brushes(Reader& r, Map& out) {
  const auto planes=r.get(1), sides=r.get(19), brushes=r.get(18), nodes=r.get(5), leaves=r.get(10), refs=r.get(17), models=r.get(14);
  const auto np=count(planes,20,1048576), ns=count(sides,8,1048576), nb=count(brushes,12,262144), nn=count(nodes,32,1048576);
  const std::size_t leafstride=r.lumps[10].version==0?56:32;
  need(r.lumps[10].version<=1,"unsupported BSP leaf version");
  const auto nl=count(leaves,leafstride,1048576), nr=count(refs,2,2097152);
  need(count(models,48,65536)>0,"BSP has no world model");
  std::vector<int> stack{i32(models,36)};
  std::vector<bool> seen_nodes(nn),seen_leaves(nl),used(nb);
  while (!stack.empty()) {
    const int node=stack.back();stack.pop_back();
    if (node>=0) {
      need(static_cast<std::size_t>(node)<nn,"BSP world node index");
      need(!seen_nodes[node],"BSP world node cycle/shared child");seen_nodes[node]=true;
      stack.push_back(i32(nodes,std::size_t(node)*32+4)); stack.push_back(i32(nodes,std::size_t(node)*32+8));
    } else {
      const auto leaf=static_cast<std::size_t>(-std::int64_t(node)-1);
      need(leaf<nl,"BSP world leaf index");if(seen_leaves[leaf])continue;seen_leaves[leaf]=true;
      const auto first=u16(leaves,leaf*leafstride+24), number=u16(leaves,leaf*leafstride+26);
      need(first<=nr && number<=nr-first,"BSP leaf brush range");
      for(unsigned j=0;j<number;++j) { const auto index=u16(refs,(first+j)*2);need(index<nb,"BSP brush index");used[index]=true; }
    }
  }
  std::size_t total=0, work=0;
  for(std::size_t b=0;b<nb;++b) {
    // MASK_SOLID_BRUSHONLY: solid, window, grate, moveable; not player/monster clip or water.
    if(!used[b] || !(u32(brushes,b*12+8)&0x400b))continue;
    const auto first=u32(brushes,b*12), number=u32(brushes,b*12+4);
    need(first<=ns && number<=ns-first,"BSP brush side range");
    ++out.considered_brushes;
    // A brush that cannot become a hull (too few or many sides, a bad plane, a sliver) is skipped:
    // real maps carry a few (gm_construct does), and one lost brush costs less than the whole world.
    if(number<4 || number>64) { ++out.skipped_brushes;continue; }
    work+=std::size_t(number)*number;need(work<=32*1024*1024,"BSP brush clipping work limit");
    std::vector<Plane> p;bool usable=true;
    for(unsigned j=0;j<number;++j) {
      const auto index=u16(sides,(first+j)*8);need(index<np,"BSP brush plane index");
      const auto n=vec(planes,index*20); const auto d=f32(planes,index*20+12), len=n.length();
      if(!(len>.99f && len<1.01f && std::abs(d)<=kCoordinateLimit)) { usable=false;break; }
      p.push_back({n*(1/len),d/len});
    }
    auto hull=usable?brush_hull(p):Hull{};
    if(hull.empty()) { ++out.skipped_brushes;continue; }
    total+=hull.size();need(total<=kMaxMapPoints && out.brushes.size()<kMaxStaticBodies,"BSP brush geometry limit");
    out.brushes.push_back(std::move(hull));
  }
}
void read_displacements(Reader& r,Map& out) {
  const auto infos=r.get(26), dv=r.get(33), faces=r.get(7), edges=r.get(12), se=r.get(13), vertices=r.get(3), models=r.get(14), tags=r.get(48);
  const auto ni=count(infos,176,65536);if(!ni)return;
  const auto nv=count(dv,20,2097152), nf=count(faces,56,1048576), ne=count(edges,4,2097152), nse=count(se,4,4194304), nvert=count(vertices,12,2097152), nt=count(tags,2,4194304);
  const auto firstface=u32(models,40), numfaces=u32(models,44);
  need(firstface<=nf && numfaces<=nf-firstface,"BSP world face range");
  for(std::size_t i=0;i<ni;++i) {
    const auto at=i*176; if(!(u32(infos,at+32)&0x400b))continue;
    const auto face=u16(infos,at+36); if(face<firstface || face-firstface>=numfaces)continue;
    const auto power=u32(infos,at+20);need(power>=2 && power<=4,"unsupported displacement power");
    const unsigned side=(1u<<power)+1, size=side*side, tris=(side-1)*(side-1)*2;
    const auto start=u32(infos,at+12), tstart=u32(infos,at+16);
    need(start<=nv && size<=nv-start && (!nt || (tstart<=nt && tris<=nt-tstart)),"BSP displacement vertex/tag range");
    need(face<nf && u16(faces,face*56+8)==4,"displacement requires quad face");
    const auto first=u32(faces,face*56+4);need(first<=nse && 4<=nse-first,"displacement surfedge range");
    std::array<V3,4> quad;
    for(unsigned q=0;q<4;++q) {
      const int e=i32(se,(first+q)*4);const auto index=static_cast<std::size_t>(e<0?-std::int64_t(e):e);
      need(index<ne,"displacement edge index"); const auto v=u16(edges,index*4+(e<0?2:0));
      need(v<nvert,"displacement vertex index");quad[q]=vec(vertices,v*12);
    }
    const auto origin=vec(infos,at);unsigned nearest=0;
    for(unsigned q=1;q<4;++q)if((quad[q]-origin).length()<(quad[nearest]-origin).length())nearest=q;
    need((quad[nearest]-origin).length()<1,"displacement start position not a face corner");
    std::vector<V3> grid(size);
    for(unsigned y=0;y<side;++y)for(unsigned x=0;x<side;++x) {
      const float u=float(x)/float(side-1),v=float(y)/float(side-1);
      // Source's fast (column) index walks 0 -> 3; rows walk 0 -> 1.
      const auto base=quad[nearest]*((1-u)*(1-v))+quad[(nearest+3)%4]*(u*(1-v))+
        quad[(nearest+2)%4]*(u*v)+quad[(nearest+1)%4]*((1-u)*v);
      const auto atv=(start+y*side+x)*20;
      grid[y*side+x]=base+vec(dv,atv)*f32(dv,atv+12);
      need(grid[y*side+x].valid(),"displacement position out of bounds");
    }
    unsigned tri=0;
    auto add=[&](unsigned a,unsigned b,unsigned c) {
      // SURFACE is not set by all compilers (gm_construct has none). REMOVE is the hole flag.
      if(!nt || !(u16(tags,(tstart+tri)*2)&(1u<<5))) {
        if((grid[b]-grid[a]).cross(grid[c]-grid[a]).length()>1e-5f)out.triangles.push_back({grid[a],grid[b],grid[c]});
      }
      ++tri;
    };
    need(out.triangles.size()+tris<=kMaxMapPoints/3,"BSP displacement triangle limit");
    for(unsigned y=0;y+1<side;++y)for(unsigned x=0;x+1<side;++x) {
      const unsigned a=y*side+x,b=a+1,c=a+side,d=c+1;
      if((x+y)&1) { add(a,c,b);add(b,c,d); }else { add(a,c,d);add(a,d,b); }
    }
  }
}
void read_props(Reader& r,Map& out) {
  const auto game=r.get(35);if(game.empty())return;
  const auto num=u32(game,0);need(num<=128 && 4+std::size_t(num)*16<=game.size(),"BSP game-lump directory");
  for(unsigned i=0;i<num;++i) {
    const auto at=4+i*16; if(u32(game,at)!=0x73707270)continue; // 'sprp', Source's numeric fourcc.
    const auto flags=u16(game,at+4), version=u16(game,at+6);
    need(version>=4 && version<=11 && !(flags&~1u),"unsupported static-prop game lump");
    const auto offset=u32(game,at+8), length=u32(game,at+12);
    Bytes data;std::vector<std::uint8_t> expanded;
    if(flags&1) {
      const auto header=slice(r.file,offset,17);
      const auto packed=std::size_t(u32(header,8))+17;
      // Source variants store either packed or original length in the directory.
      need(length==packed || length==u32(header,4),"compressed static-prop directory size mismatch");
      expanded=decompress(slice(r.file,offset,packed),0);data=expanded;
    } else data=slice(r.file,offset,length);
    const auto models=u32(data,0);need(models<=4096,"static-prop model count");
    std::vector<std::string> names;
    for(unsigned m=0;m<models;++m) {
      const auto name=slice(data,4+m*128,128); const auto end=std::find(name.begin(),name.end(),0);
      need(end!=name.end(),"unterminated static-prop model name");
      std::string s(name.begin(),end);
      need(s.size()>11 && s.starts_with("models/") && s.ends_with(".mdl") && s.find("..") == s.npos &&
        s.find(':')==s.npos && s.find('\\')==s.npos,"unsafe static-prop model name");
      names.push_back(std::move(s));
    }
    auto cursor=4+std::size_t(models)*128;
    const auto leaves=u32(data,cursor);cursor+=4;need(leaves<=2097152,"static-prop leaf count");
    slice(data,cursor,std::size_t(leaves)*2);cursor+=std::size_t(leaves)*2;
    const auto props=u32(data,cursor);cursor+=4;need(props<=kMaxStaticBodies,"static-prop count");
    if(!props) { need(cursor==data.size(),"unexpected empty static-prop payload");continue; }
    const auto stride=(data.size()-cursor)/props;
    need((data.size()-cursor)%props==0 && stride>=56 && stride<=80 && stride%4==0 &&
      (version!=11 || stride==80),"unsupported static-prop record stride");
    for(unsigned p=0;p<props;++p) {
      const auto pos=cursor+p*stride;
      const auto model=u16(data,pos+24);need(model<names.size(),"static-prop model index");
      const auto origin=vec(data,pos),angles=vec(data,pos+12);const auto solid=data[pos+30];
      const float scale=version==11?f32(data,pos+76):1;
      need(scale>0 && scale<=16,"static-prop scale limit");
      if(solid)out.props.push_back({names[model],origin,angles,solid,scale});
    }
  }
}
}
bool valid_hull(const Hull& p) {
  if(p.size()<4 || p.size()>kMaxHullPoints)return false;
  for(auto v:p)if(!v.valid())return false;
  // Find a line, a plane, then a point off that plane. Avoid O(n^4) degenerate input.
  const auto a=p.front();V3 line{},normal{};
  for(auto v:p)if((v-a).length()>line.length())line=v-a;
  if(line.length()<.001f)return false;
  for(auto v:p)if(line.cross(v-a).length()>normal.length())normal=line.cross(v-a);
  if(normal.length()<.00001f)return false;
  for(auto v:p)if(std::abs(normal.dot(v-a))/normal.length()>.001f)return true;
  return false;
}
Hull brush_hull(const std::vector<Plane>& planes) {
  if(planes.size()<4 || planes.size()>64)return {};
  // Keep clipping and deduplication in double precision, including the very large seed faces.
  // Floats here amplify cancellation into extra near-vertices on bevelled/high-sided brushes.
  struct D3 {
    double x,y,z;
    D3 operator+(D3 b) const { return {x+b.x,y+b.y,z+b.z}; }
    D3 operator-(D3 b) const { return {x-b.x,y-b.y,z-b.z}; }
    D3 operator*(double s) const { return {x*s,y*s,z*s}; }
    double dot(D3 b) const { return x*b.x+y*b.y+z*b.z; }
    D3 cross(D3 b) const { return {y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x}; }
  };
  auto normal=[](const Plane& p) { return D3{p.normal.x,p.normal.y,p.normal.z}; };
  std::vector<D3> vertices;
  for(const auto& face:planes) {
    if(!face.normal.valid(1.01f) || !std::isfinite(face.distance) || std::abs(face.distance)>kCoordinateLimit ||
       face.normal.length()<.99f || face.normal.length()>1.01f)return {};
    const auto n=normal(face);const D3 axis=std::abs(n.z)<.8?D3{0,0,1}:D3{0,1,0};
    auto u=axis.cross(n);u=u*(1/std::sqrt(u.dot(u)));const auto v=n.cross(u);
    const auto center=n*(face.distance/n.dot(n));const double extent=kCoordinateLimit*4;
    std::vector<D3> poly{center+u*extent+v*extent,center-u*extent+v*extent,center-u*extent-v*extent,center+u*extent-v*extent};
    for(const auto& clip:planes) {
      std::vector<D3> next;
      for(std::size_t i=0;i<poly.size();++i) {
        const auto a=poly[i],b=poly[(i+1)%poly.size()];
        const double da=normal(clip).dot(a)-clip.distance,db=normal(clip).dot(b)-clip.distance;
        const bool ina=da<=1e-7,inb=db<=1e-7;
        if(ina)next.push_back(a);
        if(ina!=inb)next.push_back(a+(b-a)*std::clamp(da/(da-db),0.0,1.0));
      }
      poly=std::move(next);if(poly.empty())break;
    }
    for(auto p:poly) {
      if(std::abs(p.x)>kCoordinateLimit || std::abs(p.y)>kCoordinateLimit || std::abs(p.z)>kCoordinateLimit)return {};
      bool duplicate=false;for(auto q:vertices)if((p-q).dot(p-q)<1e-6) { duplicate=true;break; }
      if(!duplicate) { vertices.push_back(p);if(vertices.size()>kMaxHullPoints)return {}; }
    }
  }
  Hull hull;hull.reserve(vertices.size());
  for(auto p:vertices)hull.push_back({static_cast<float>(p.x),static_cast<float>(p.y),static_cast<float>(p.z)});
  return valid_hull(hull)?hull:Hull{};
}
Map read_bsp(std::span<const std::uint8_t> bytes) {
  Reader reader(bytes);Map map;
  read_brushes(reader,map);read_displacements(reader,map);read_props(reader,map);
  // Structural errors still refuse the map; individual shapes do not. Props may supply collision later.
  return map;
}
}
