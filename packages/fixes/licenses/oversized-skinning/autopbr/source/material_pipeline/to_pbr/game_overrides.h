// GPL-2.0. Player choices keyed by live texture identity, never a character name.
#pragma once
#include "game_registry.h"
namespace MaterialPipeline { namespace ToPBR { namespace GameOverrides {
namespace fs=std::filesystem;
struct Choice {
    std::string mode,source,base,normal,packed,emission;unsigned layout=0;
    GameRegistry::Record record;
};
inline bool Text(const std::string& s,size_t limit=2048) {
    return s.size()<=limit && std::none_of(s.begin(),s.end(),[](unsigned char c){return c<32;});
}
class Store {
public:
    explicit Store(fs::path output):output_(std::move(output)),path_(output_.parent_path()/"game_overrides.registry"),validator_(output_){}
    bool Load() {
        choices_.clear();writable_=true;
        std::error_code ec;if(!fs::exists(path_,ec))return writable_=!ec;
        const auto size=fs::file_size(path_,ec);if(ec || size>GameRegistry::MaxBytes)return writable_=false;
        std::ifstream f(path_,std::ios::binary);std::string line;
        if(!std::getline(f,line) || line!="TOPBR_GAME_OVERRIDES 1")return writable_=false;
        while(std::getline(f,line)) {
            if(line.size()>16384 || choices_.size()>=GameRegistry::MaxRecords)return writable_=false;
            std::istringstream row(line);row.imbue(std::locale::classic());std::string id;Choice c;
            if(!(row>>id>>c.mode>>c.layout>>std::quoted(c.source)>>std::quoted(c.base)>>std::quoted(c.normal)>>std::quoted(c.packed)>>std::quoted(c.emission)))return writable_=false;
            c.record.identity=id;
            if(c.mode=="maps") {
                size_t count=0;
                if(!(row>>c.record.version>>c.record.generator>>count) || count>GameRegistry::MaxHashes)return writable_=false;
                c.record.hashes.resize(count);for(auto& h:c.record.hashes)row>>std::hex>>h>>std::dec;
                for(auto& t:c.record.textures){row>>std::quoted(t.file)>>t.bytes>>std::hex>>t.digest>>std::dec;}
                row>>c.record.roughness>>c.record.metallic>>c.record.emission;
                if(!row || !GameRegistry::ValidRecord(c.record))return writable_=false;
            }
            row>>std::ws;
            if(!row.eof() || !Valid(id,c) || !choices_.emplace(id,c).second)return writable_=false;
        }
        return writable_=!f.bad();
    }
    bool Readable() const{return writable_;}
    const Choice* Find(const std::string& id) const {if(!writable_)return nullptr;auto i=choices_.find(id);return i==choices_.end()?nullptr:&i->second;}
    // Commit is atomic: an unsuccessful save never changes the current choice.
    bool Set(const std::string& id,const Choice& choice) {
        if(!writable_ || GameRegistry::Identity(id)!=id || id.empty() || (choice.mode!="automatic" && !Valid(id,choice)))return false;
        auto next=choices_;
        if(choice.mode=="automatic")next.erase(id);else next[id]=choice;
        if(next.size()>GameRegistry::MaxRecords)return false;
        std::ostringstream out;out.imbue(std::locale::classic());out<<"TOPBR_GAME_OVERRIDES 1\n"<<std::setprecision(std::numeric_limits<float>::max_digits10);
        for(const auto& pair:next){const auto& c=pair.second;out<<pair.first<<' '<<c.mode<<' '<<c.layout<<' '<<std::quoted(c.source)<<' '<<std::quoted(c.base)<<' '<<std::quoted(c.normal)<<' '<<std::quoted(c.packed)<<' '<<std::quoted(c.emission);
            if(c.mode=="maps") {
                const auto& r=c.record;out<<' '<<r.version<<' '<<r.generator<<' '<<r.hashes.size();
                for(auto h:r.hashes)out<<' '<<std::hex<<h<<std::dec;
                for(const auto& t:r.textures)out<<' '<<std::quoted(t.file)<<' '<<t.bytes<<' '<<std::hex<<t.digest<<std::dec;
                out<<' '<<r.roughness<<' '<<r.metallic<<' '<<r.emission;
            }out<<'\n';
        }
        const auto bytes=out.str();if(bytes.size()>GameRegistry::MaxBytes || !GameRegistry::SaveText(path_,bytes,last_))return false;
        choices_=std::move(next);return true;
    }
    // R13-M: a saved manual choice's uncompressed maps move to their compact formats without a
    // source. The choice is replaced atomically through Set; any failure keeps the previous one.
    template<class Transcode>
    size_t Compact(const std::string& id,Transcode transcode) {
        const auto* c=Find(id);if(!c || c->mode!="maps")return 0;
        Choice next=*c;const size_t changed=validator_.CompactRecord(next.record,transcode);
        if(!changed)return 0;
        if(!Set(id,next))throw std::runtime_error("saved choice could not be updated; its maps stay uncompressed");
        return changed;
    }
    std::optional<GameRegistry::Record> Resolve(const std::string& id,const std::vector<uint64_t>& live) const {
        auto c=Find(id);if(!c || c->mode!="maps" || live.empty() || live.size()>GameRegistry::MaxHashes || !validator_.ValidateRecord(c->record))return {};
        for(auto h:live)if(!h)return {};
        auto r=c->record;r.hashes=live;return r;
    }
    template<class Automatic>
    std::optional<GameRegistry::Record> Select(const std::string& id,const std::vector<uint64_t>& live,bool enabled,Automatic automatic) const {
        if(!enabled || !writable_ || id.empty() || GameRegistry::Identity(id)!=id || live.empty() || live.size()>GameRegistry::MaxHashes)return {};
        for(auto h:live)if(!h)return {};
        if(Find(id))return Resolve(id,live); // Includes None and a damaged DDS: never revive automatic maps.
        return automatic();
    }
private:
    static bool Valid(const std::string& id,const Choice& c) {
        return !id.empty() && GameRegistry::Identity(id)==id && (c.mode=="none" || c.mode=="maps") && c.layout<=2 &&
            Text(c.source) && Text(c.base,1024) && Text(c.normal) && Text(c.packed) && Text(c.emission) &&
            (c.mode!="maps" || (c.record.identity==id && GameRegistry::ValidRecord(c.record)));
    }
    fs::path output_,path_;GameRegistry::Registry validator_;std::map<std::string,Choice> choices_;
    bool writable_=true;std::optional<std::string> last_;
};
}}}
