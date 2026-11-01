#include "fracture.h"

namespace nl::glass {
namespace {
double cross(V3 a,V3 b,V3 c) { return double(b.x-a.x)*(c.y-a.y)-double(b.y-a.y)*(c.x-a.x); }
Hull clip(const Hull& polygon,bool x_axis,double cut,bool positive) {
  Hull out;out.reserve(polygon.size()+1);
  auto distance=[&](V3 v) { return ((x_axis?v.x:v.y)-cut)*(positive?1:-1); };
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
std::array<Hull,2> split_polygon(const Hull& polygon,float minimum_size) {
  if(polygon.size()<3 || polygon.size()>64 || !std::isfinite(minimum_size) || minimum_size<4 || minimum_size>64)return {};
  V3 lo=polygon.front(),hi=lo;
  for(auto p:polygon) {
    if(!p.valid(1024))return {};
    lo.x=std::min(lo.x,p.x);lo.y=std::min(lo.y,p.y);hi.x=std::max(hi.x,p.x);hi.y=std::max(hi.y,p.y);
  }
  const double area=polygon_area(polygon),min_area=double(minimum_size)*minimum_size;
  if(area<2*min_area)return {};
  const bool x_axis=hi.x-lo.x>=hi.y-lo.y;
  double low=x_axis?lo.x:lo.y,high=x_axis?hi.x:hi.y;
  for(unsigned i=0;i<24;++i) {
    const double cut=(low+high)*.5;
    if(polygon_area(clip(polygon,x_axis,cut,false))<area*.5)low=cut;else high=cut;
  }
  std::array<Hull,2> out{clip(polygon,x_axis,(low+high)*.5,false),clip(polygon,x_axis,(low+high)*.5,true)};
  for(const auto& child:out) {
    if(child.size()<3 || child.size()>64 || polygon_area(child)<min_area*.99999)return {};
    V3 a=child.front(),b=a;
    for(auto p:child) { a.x=std::min(a.x,p.x);a.y=std::min(a.y,p.y);b.x=std::max(b.x,p.x);b.y=std::max(b.y,p.y); }
    if(b.x-a.x<minimum_size-.0001f || b.y-a.y<minimum_size-.0001f)return {};
  }
  return out;
}
Hull extrude(const Hull& polygon,float thickness) {
  Hull out;out.reserve(polygon.size()*2);
  for(auto p:polygon) { out.push_back({p.x,p.y,-thickness*.5f});out.push_back({p.x,p.y,thickness*.5f}); }
  return out;
}
}
