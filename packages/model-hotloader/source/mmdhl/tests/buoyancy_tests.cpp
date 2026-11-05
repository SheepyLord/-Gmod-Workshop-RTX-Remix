// Gravity and buoyancy of hair and clothing physics. The gravity scale the addon derives
// from sv_gravity (Secondary::setTuning: up to 16, negative too) reaches every dynamic
// body, sleeping ones as well. With buoyancy on, a chain under the water surface
// (Instance::waterPlane) floats up; with buoyancy off, or the surface below the chain,
// the chain hangs exactly as a dry one.
#include "runtime.hpp"
#include "secondary.hpp"
#include "jobs.hpp"
#include <cmath>
#include <functional>
#include <iostream>
#include <limits>
using namespace mmd;
namespace {
int checks=0;
void check(bool ok,const std::string& name){if(!ok)throw std::runtime_error("FAIL "+name);++checks;std::cout<<"PASS "<<name<<"\n";}
Json options(const std::string& backend){return {{"backend","source"},{"presentationDriven",true},{"secondaryCollision",0},{"secondaryBackend",backend}};}
std::vector<btTransform> restPose(const Instance& p){std::vector<btTransform> pose;for(auto& b:p.sourceRig->bones)pose.push_back(b.rest);return pose;}
void play(Instance& p,const std::vector<btTransform>& pose,int from,int to){
 for(int f=from;f<to;f++){p.submitPresentationPose(pose,(f+1)/60.,uint64_t(f+1));p.secondary->waitAsyncIdle();p.stepSource();}
}
// The dynamic bodies' positions (PMX units, y up) and their mean height.
struct Hang {double height=0;std::vector<btVector3> bodies;unsigned submerged=0,sleeping=0;};
Hang measure(Instance& p){
 auto d=p.secondary->diagnostics();Hang h;
 for(auto& b:d["bodyList"])if(!b["follower"].get<bool>()){btVector3 v(b["position"][0].get<float>(),b["position"][1].get<float>(),b["position"][2].get<float>());h.bodies.push_back(v);h.height+=v.y();}
 if(h.bodies.empty())throw std::runtime_error("The fixture has no dynamic bodies");
 h.height/=double(h.bodies.size());h.submerged=d.value("submergedBodies",0u);h.sleeping=d.value("sleepingBodies",0u);return h;
}
// The fixture's chain hanging from its resting skeleton for four seconds.
Hang hang(const std::shared_ptr<Model>& model,const std::string& backend,float water){
 World host;auto& p=host.get(host.create(model,options(backend)));p.waterHeight=water;
 play(p,restPose(p),0,240);return measure(p);
}
bool same(const Hang& a,const Hang& b){
 if(a.bodies.size()!=b.bodies.size())return false;
 for(size_t i=0;i<a.bodies.size();i++)if(a.bodies[i]!=b.bodies[i])return false;
 return true;
}
bool refused(const std::function<void()>& call){try{call();}catch(const std::exception&){return true;}return false;}
}
int main(int argc,char** argv){try{
 if(argc<2)throw std::runtime_error("Pass native-chain.pmx");
 auto model=parse(readFile(argv[1]));const float none=std::numeric_limits<float>::quiet_NaN();
 check(!refused([]{Secondary::setTuning(10,16,1,false,1);})&&!refused([]{Secondary::setTuning(10,-16,1,false,1);}),"gravity scales from -16 to 16 are accepted");
 check(refused([]{Secondary::setTuning(10,16.5f,1,false,1);})&&refused([]{Secondary::setTuning(10,NAN,1,false,1);}),"a gravity scale beyond 16 or not a number is refused");
 check(refused([]{Secondary::setBuoyancy(true,4.5f,1);})&&refused([]{Secondary::setBuoyancy(true,1,-1);})&&refused([]{Secondary::setBuoyancy(true,1,21);}),"buoyancy outside 0-4 or drag outside 0-20 is refused");
 Secondary::setTuning(10,1,1,false,1);Secondary::setBuoyancy(false,1.2f,2);Secondary::setSleepPolicy(false,.5f,.35f,1.5f);

 // The water surface in simulation space: the poses' transform (submitPresentationPose),
 // for a placed and turned character.
 {World host;auto o=options("cpu_mt_v2");o["position"]={100,200,300};o["angles"]={30,90,10};auto& p=host.get(host.create(model,o));
  auto simulation=[&](btVector3 source){return fromSource(p.placement.inverse()*(source*Inch))/p.scale;};
  btVector3 normal;float offset=0;
  check(!p.waterPlane(normal,offset),"no water surface without a water height");
  p.waterHeight=350;check(p.waterPlane(normal,offset),"a water height gives a surface");
  float on=normal.dot(simulation({140,180,350}))-offset,under=normal.dot(simulation({60,230,340}))-offset,over=normal.dot(simulation({60,230,360}))-offset;
  check(std::abs(normal.length()-1)<1e-5f&&std::abs(on)<1e-3f&&under<0&&over>0,"the surface matches the poses' transform: points under it lie below the plane");}

 for(std::string backend:{"reference","cpu_mt","cpu_mt_v2"}){
  auto dry=hang(model,backend,none);
  check(same(dry,hang(model,backend,100000)),backend+": with buoyancy off a submerged chain hangs as a dry one");
  Secondary::setBuoyancy(true,1.5f,2);
  auto below=hang(model,backend,-100000),under=hang(model,backend,100000);
  Secondary::setBuoyancy(false,1.2f,2);
  check(same(dry,below)&&below.submerged==0,backend+": a water surface below the chain changes nothing");
  check(under.submerged==under.bodies.size()&&under.height>dry.height+.5,backend+": a submerged chain floats up with buoyancy above 1");
  Secondary::setTuning(10,-1,1,false,1);auto inverted=hang(model,backend,none);
  Secondary::setTuning(10,0,1,false,1);auto weightless=hang(model,backend,none);
  Secondary::setTuning(10,1,1,false,1);
  check(inverted.height>dry.height+.5&&weightless.height>=dry.height-1e-3,backend+": the gravity scale reaches the chain, a negative one lifts it");
  std::cout<<backend<<": dry "<<dry.height<<", submerged "<<under.height<<", inverted "<<inverted.height<<", weightless "<<weightless.height<<" PMX\n";
 }

 // Bullet's world gravity skips sleeping bodies: a chain asleep when the gravity
 // turns over must rise all the same.
 {Secondary::setSleepPolicy(true,.5f,.35f,1.5f);
  World host;auto& p=host.get(host.create(model,options("cpu_mt_v2")));auto pose=restPose(p);
  play(p,pose,0,600);auto asleep=measure(p);
  Secondary::setTuning(10,-1,1,false,1);play(p,pose,600,900);auto turned=measure(p);
  Secondary::setTuning(10,1,1,false,1);Secondary::setSleepPolicy(false,.5f,.35f,1.5f);
  check(asleep.sleeping>0,"the resting chain fell asleep");
  check(turned.height>asleep.height+.5,"a chain asleep when the gravity turns over rises too");}
 std::cout<<checks<<" checks passed\n";shutdownJobs();return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<std::endl;shutdownJobs();return 1;}}
