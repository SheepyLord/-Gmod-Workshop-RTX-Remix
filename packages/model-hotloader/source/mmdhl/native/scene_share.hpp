#pragma once
#include "scene.hpp"
namespace mmd {
struct SceneShare {
 struct Cached {std::weak_ptr<const SceneGeometry> source;std::string key;Bytes bytes;};
 // A shape received from the server: kept while frames name it (R19, review MH-05).
 struct Imported {std::shared_ptr<const SceneGeometry> geometry;size_t bytes=0;double used=0;};
 std::map<const SceneGeometry*,Cached> exported;
 std::map<std::string,Imported> imported;
 size_t importedBytes=0;
 // A shape no frame has named for IdleSeconds goes: its entity went away or out of reach.
 // Past ImportBudget bytes or ImportLimit shapes, the ones unused the longest go first; a
 // shape that cannot fit even then is refused.
 static constexpr double IdleSeconds=60;
 static constexpr size_t ImportBudget=size_t(256)<<20,ImportLimit=4096;
 // Seconds on a steady clock (tests set it).
 std::function<double()> clock;
 // consumer identifies the subscriber whose interest region this refreshes;
 // kinds (Collide:: flags) are the objects it asked for: map geometry, objects,
 // living players, living NPCs.
 Json describe(const btVector3& center,float radius,uint64_t consumer=0,unsigned kinds=Collide::All);
 Bytes chunk(const std::string&,size_t offset,size_t count)const;
 void accept(const std::string&,std::span<const unsigned char>);
 // Returns the shapes the client should forget (and ask for again when a frame names them):
 // those dropped since the last publication and those this frame names but which are not held.
 std::vector<std::string> publish(World&,const Json&);
 void clear();
private:
 std::vector<std::string> dropped;
 double now() const;
 void drop(std::map<std::string,Imported>::iterator);
};
}
