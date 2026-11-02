#include "fracture.h"

namespace nl::glass {
namespace {
double cross(V3 a,V3 b,V3 c) { return double(b.x-a.x)*(c.y-a.y)-double(b.y-a.y)*(c.x-a.x); }
Hull clip(const Hull& polygon,V3 normal,double cut,bool positive) {
  Hull out;out.reserve(polygon.size()+1);
  auto distance=[&](V3 v) { return (double(v.x)*normal.x+double(v.y)*normal.y-cut)*(positive?1:-1); };
  for(std::size_t i=0;i<polygon.size();++i) {
    const auto a=polygon[i],b=polygon[(i+1)%polygon.size()];const double da=distance(a),db=distance(b);
    if(da>=0)out.push_back(a);
    if((da<0 && db>0)||(da>0 && db<0)) {
      const double t=da/(da-db);
      out.push_back({float(a.x+(b.x-a.x)*t),float(a.y+(b.y-a.y)*t),0});
    }
  }
  return out;
}
}
Hull outline_xy(const Hull& points) {
  Hull sorted=points;
  for(auto& p:sorted)p.z=0;
  std::sort(sorted.begin(),sorted.end(),[](V3 a,V3 b) { return a.x<b.x || (a.x==b.x && a.y<b.y); });
  sorted.erase(std::unique(sorted.begin(),sorted.end(),[](V3 a,V3 b) { return a.x==b.x && a.y==b.y; }),sorted.end());
  if(sorted.size()<3)return {};
  Hull out;out.reserve(sorted.size()*2);
  for(auto p:sorted) {
    while(out.size()>1 && cross(out[out.size()-2],out.back(),p)<=1e-9)out.pop_back();out.push_back(p);
  }
  const auto lower=out.size();
  for(auto it=sorted.rbegin()+1;it!=sorted.rend();++it) {
    while(out.size()>lower && cross(out[out.size()-2],out.back(),*it)<=1e-9)out.pop_back();out.push_back(*it);
  }
  out.pop_back();return out;
}
double polygon_area(const Hull& polygon) {
  double area=0;for(std::size_t i=0;i<polygon.size();++i) {
    const auto a=polygon[i],b=polygon[(i+1)%polygon.size()];area+=double(a.x)*b.y-double(a.y)*b.x;
  }
  return area*.5;
}
V3 polygon_center(const Hull& polygon) {
  double x=0,y=0,area=0;
  for(std::size_t i=0;i<polygon.size();++i) {
    const auto a=polygon[i],b=polygon[(i+1)%polygon.size()];const double c=double(a.x)*b.y-double(a.y)*b.x;
    x+=(a.x+b.x)*c;y+=(a.y+b.y)*c;area+=c;
  }
  return area>1e-9?V3{float(x/(3*area)),float(y/(3*area)),0}:V3{};
}
std::vector<Hull> split_polygon(const Hull& polygon,float minimum_size,V3 hit,std::uint32_t seed,unsigned maximum) {
  if(polygon.size()<3 || polygon.size()>64 || !std::isfinite(minimum_size) || minimum_size<1 || minimum_size>64 ||
    !hit.valid(2048) || maximum<2 || maximum>6)return {};
  V3 lo=polygon.front(),hi=lo;
  for(auto p:polygon) {
    if(!p.valid(1024))return {};
    lo.x=std::min(lo.x,p.x);lo.y=std::min(lo.y,p.y);hi.x=std::max(hi.x,p.x);hi.y=std::max(hi.y,p.y);
  }
  const double area=polygon_area(polygon),min_area=double(minimum_size)*minimum_size;
  if(area<2*min_area)return {};
  if(std::min(hi.x-lo.x,hi.y-lo.y)<minimum_size)return {};
  // The hit may lie just outside a face after a sweep. Pull it into this convex polygon
  // toward the centroid, rather than cutting at an arbitrary bounding-box midpoint.
  const auto center=polygon_center(polygon);
  for(unsigned i=0;i<12;++i) {
    bool inside=true;for(std::size_t j=0;j<polygon.size();++j)
      if(cross(polygon[j],polygon[(j+1)%polygon.size()],hit)<0) { inside=false;break; }
    if(inside)break;hit=(hit+center)*.5f;
  }
  auto random=[&]() { seed=seed*1664525u+1013904223u;return seed; };
  // Deliberately oblique, bounded integer normals. Follow-up cosmetic fracture is local;
  // initial authoritative pane subdivision uses the shared integer Lua generator instead.
  const std::array<V3,12> normals{{{13,5,0},{7,17,0},{-11,9,0},{3,19,0},{-17,4,0},{9,11,0},
    {19,-7,0},{5,-13,0},{-7,-19,0},{17,11,0},{-3,17,0},{11,-17,0}}};
  std::vector<Hull> out{polygon};
  const unsigned wanted=std::min(maximum,2u+(random()>>16)%5);
  for(unsigned attempt=0;attempt<24 && out.size()<wanted;++attempt) {
    auto it=std::max_element(out.begin(),out.end(),[](const Hull& a,const Hull& b) { return polygon_area(a)<polygon_area(b); });
    auto n=normals[(random()>>16)%normals.size()];
    const auto c=polygon_center(*it);
    const auto target=attempt<3?hit*.7f+c*.3f:c;
    const double d=double(n.x)*target.x+double(n.y)*target.y;
    auto a=clip(*it,n,d,false),b=clip(*it,n,d,true);
    if(a.size()<3 || b.size()<3 || a.size()>64 || b.size()>64 ||
      polygon_area(a)<min_area || polygon_area(b)<min_area)continue;
    *it=std::move(a);out.push_back(std::move(b));
  }
  return out.size()>1?out:std::vector<Hull>{};
}
Hull extrude(const Hull& polygon,float thickness) {
  Hull out;out.reserve(polygon.size()*2);
  for(auto p:polygon) { out.push_back({p.x,p.y,-thickness*.5f});out.push_back({p.x,p.y,thickness*.5f}); }
  return out;
}
}
