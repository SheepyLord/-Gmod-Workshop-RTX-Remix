// GPL-2.0. Included inside GamePBR, after Image/Decode/Maps.
// Spatial edges are compared at identical normalized UV coordinates. No rotations,
// translations or best-fit warps: a similar object with a different atlas must abstain.
struct Features {
    uint32_t w=0,h=0; std::vector<float> edges; double mean=0,energy=0;
};
inline Features Describe(const Image& image,bool blur=false) {
    Features f;f.w=image.w;f.h=image.h;f.edges.resize(size_t(f.w)*f.h);
    for(uint32_t y=0;y<f.h;++y)for(uint32_t x=0;x<f.w;++x) {
        const size_t i=size_t(y)*f.w+x;float dx=0,dy=0;
        for(size_t c=0;c<3;++c) {
            if(x)dx=(std::max)(dx,float(std::abs(int(image.rgba[i*4+c])-int(image.rgba[(i-1)*4+c])))/255);
            if(y)dy=(std::max)(dy,float(std::abs(int(image.rgba[i*4+c])-int(image.rgba[(i-f.w)*4+c])))/255);
        }
        f.edges[i]=dx+dy;
    }
    auto sorted=f.edges;std::sort(sorted.begin(),sorted.end());
    const float scale=sorted[sorted.size()*9/10]+.0001f;
    for(auto& e:f.edges)e=std::sqrt((std::min)(2.f,e/scale));
    // A single 3x3 pass tolerates one descriptor pixel of filtering variation.
    // Clamp at the atlas boundary; UV coordinates are never moved or searched.
    if(blur) {
        const auto old=f.edges;
        for(uint32_t y=0;y<f.h;++y)for(uint32_t x=0;x<f.w;++x) {
            float sum=0;
            for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx) {
                const auto xx=std::clamp(int(x)+dx,0,int(f.w)-1),yy=std::clamp(int(y)+dy,0,int(f.h)-1);
                sum+=old[size_t(yy)*f.w+size_t(xx)];
            }
            f.edges[size_t(y)*f.w+x]=sum/9;
        }
    }
    for(auto e:f.edges)f.mean+=e;
    f.mean/=double(f.edges.size());
    for(auto e:f.edges)f.energy+=(e-f.mean)*(e-f.mean);
    return f;
}
inline double Similarity(const Features& a,const Features& b) {
    if(a.w!=b.w || a.h!=b.h || a.energy<.01 || b.energy<.01)return -1;
    double sum=0;for(size_t i=0;i<a.edges.size();++i)sum+=(a.edges[i]-a.mean)*(b.edges[i]-b.mean);
    return sum/std::sqrt(a.energy*b.energy);
}
inline int Vocabulary(const std::string& value) {
    const auto s=Lower(value);
    if(Has(s,{"hair","bang",u8"头发",u8"頭髮"}))return 1;
    if(Has(s,{"sock","stock","tight",u8"丝袜",u8"絲襪"}))return 2;
    if(Has(s,{"hat","head",u8"头饰",u8"頭飾"}))return 3;
    if(Has(s,{"skin",u8"皮肤",u8"皮膚"}))return 4;
    if(Has(s,{"pupil","eye",u8"眼睛"}))return 5;
    if(Has(s,{"face",u8"脸",u8"臉"}))return 6;
    if(Has(s,{"lava","reactor",u8"熔岩"}))return 7;
    if(Has(s,{"cloth","body","dress","coat",u8"衣服",u8"衣饰"}))return 8;
    return 0;
}
struct Decision { std::string base,family,reason,evidence;double score=0,margin=0,feature=0;bool accepted=false; };
using DecisionLog=std::function<void(const Decision&)>;
struct Evidence { fs::path path;Features features; };
struct Family { std::string stem;Maps maps;std::vector<Evidence> features; };
inline bool AuxiliarySuffix(const std::string& suffix) {
    // Only data-map roles, never diffuse/emission variants or arbitrary siblings.
    for(const auto prefix:{"_lbmask","_anisomask","_prommask","_specular","_dynao","_expmask","_caustic"})
        if(suffix.compare(0,std::strlen(prefix),prefix)==0)return true;
    return false;
}
inline fs::path RelativeTexture(const fs::path& root,const std::string& value) {
    const auto p=fs::u8path(Lower(value));
    if(p.empty() || p.has_root_path())throw std::runtime_error("rooted/empty texture path");
    for(const auto& part:p)if(part==".." || part.u8string().find(':')!=std::string::npos)throw std::runtime_error("texture traversal");
    auto cursor=root;
    for(const auto& part:p){cursor/=part;auto a=GetFileAttributesW(cursor.c_str());
        if(a!=INVALID_FILE_ATTRIBUTES && (a&FILE_ATTRIBUTE_REPARSE_POINT))throw std::runtime_error("linked texture path");}
    return p;
}
class Discovery {
public:
    explicit Discovery(fs::path root,bool blur=false):root_(std::move(root)),blur_(blur) {
        const auto attrs=GetFileAttributesW(root_.c_str());
        if(attrs==INVALID_FILE_ATTRIBUTES || (attrs&FILE_ATTRIBUTE_REPARSE_POINT))throw std::runtime_error("invalid model folder");
        size_t count=0;std::error_code ec;fs::recursive_directory_iterator it(root_,ec),end;
        if(ec)throw std::runtime_error("cannot scan model folder");
        for(;it!=end;it.increment(ec)) {
            if(ec || ++count>4096)throw std::runtime_error("model folder scan exceeds bound");
            if(it.depth()>6 || (GetFileAttributesW(it->path().c_str())&FILE_ATTRIBUTE_REPARSE_POINT)){it.disable_recursion_pending();continue;}
            if(it->is_regular_file(ec)) {
                const auto ext=Lower(it->path().extension().u8string());
                if(ext==".png"||ext==".bmp"||ext==".tga"||ext==".jpg")files_[Lower(it->path().stem().u8string())].push_back(it->path());
            }
        }
        if(ec)throw std::runtime_error("model folder scan failed");
    }
    // Whether any scanned image stem ends with `suffix` (lower case), e.g. "_mra".
    bool HasStemSuffix(const std::string& suffix) const {
        for(const auto& p:files_)if(p.first.size()>suffix.size() && p.first.compare(p.first.size()-suffix.size(),suffix.size(),suffix)==0)return true;
        return false;
    }
    fs::path Find(const std::string& stem,const fs::path& beside) const {
        auto p=files_.find(stem);if(p==files_.end())return {};
        std::vector<fs::path> candidates;
        for(const auto& c:p->second)if(Lower(c.parent_path().lexically_normal().u8string())==Lower(beside.lexically_normal().u8string()))candidates.push_back(c);
        if(candidates.empty())candidates=p->second;
        const auto bytes=Read(candidates[0]);
        for(size_t i=1;i<candidates.size();++i)if(Read(candidates[i])!=bytes)throw std::runtime_error("ambiguous companion texture");
        return candidates[0];
    }
    Maps Named(const std::string& stem,const fs::path& beside) const {
        Maps m;m.normal=Find(stem+"_n",beside);m.packed=Find(stem+"_mra",beside);m.emission=Find(stem+"_e",beside);
        if(!m.packed.empty()) {
            if(stem.find("t_actor_")==0)throw std::runtime_error("conflicting packed game layouts");
            m.layout=Maps::Silver;
        }
        else if(stem.find("t_actor_")==0){m.layout=Maps::Endfield;m.packed=Find(stem+"_p",beside);if(m.normal.empty())m.normal=Find(stem+"_hn",beside);}
        else if(!Find(stem+"_id",beside).empty() || !Find(stem+"_hm",beside).empty()){m.layout=Maps::Wuwa;m.emission.clear();}
        else {
            // Silver families without an MRA (e.g. hair) need explicit game-family evidence.
            bool silver=false;
            const auto split=stem.find('_',2);
            const auto prefix=split==std::string::npos?std::string{}:stem.substr(0,split+1);
            if(stem.find("t_")==0 && !prefix.empty())for(const auto& p:files_)
                if(p.first.compare(0,prefix.size(),prefix)==0 && p.first.size()>4 && p.first.substr(p.first.size()-4)=="_mra")silver=true;
            if(!silver)return {};
            m.layout=Maps::Silver;
        }
        m.recognized=!m.normal.empty() || !m.packed.empty();return m;
    }
    const std::vector<Family>& Families(const DecisionLog& log={}) {
        if(ready_)return families_;
        families_.clear();
        std::map<std::string,bool> stems;
        for(const auto& p:files_)for(const auto suffix:{"_n","_hn","_mra","_p"}) {
            const size_t n=std::strlen(suffix);if(p.first.size()>n && p.first.substr(p.first.size()-n)==suffix)stems[p.first.substr(0,p.first.size()-n)]=true;
        }
        if(stems.size()>64)throw std::runtime_error("family count exceeds bound");
        for(const auto& stem:stems) {
            try {
                auto m=Named(stem.first,root_);if(!m.recognized)continue;
                Family family{stem.first,m,{}};
                for(const auto& path:{m.normal,m.packed})if(!path.empty())family.features.push_back({path,Feature(path)});
                families_.push_back(std::move(family));
            }catch(const std::exception& e) {
                // Resource exhaustion still fails closed: it is not evidence that a
                // candidate is bad. A broken/ambiguous family must not poison others.
                if(std::string(e.what()).find("budget")!=std::string::npos)throw;
                LogSkip(log,stem.first,"skipped family: "+std::string(e.what()));
            }
        }
        ready_=true;
        return families_;
    }
    const std::vector<Evidence>& Auxiliary(const Family& family,const DecisionLog& log={}) {
        // Reserve all core maps and possible bases before spending leftover work on
        // masks. Known data-map roles are maps; every other image is a possible
        // base. Cache failures too, so bad files cannot consume retries.
        if(!auxiliaryReady_) {
            auxiliaryReady_=true;
            for(const auto& entry:files_) {
                bool map=false;
                for(const auto& f:families_)if(entry.first.compare(0,f.stem.size()+1,f.stem+"_")==0) {
                    const auto role=entry.first.substr(f.stem.size());
                    if(AuxiliarySuffix(role) || role=="_n" || role=="_hn" || role=="_mra" || role=="_p" || role=="_e"){map=true;break;}
                }
                if(map)continue;
                for(const auto& path:entry.second)try{Feature(path);}catch(const std::exception& e) {
                    if(std::string(e.what()).find("budget")!=std::string::npos)auxiliaryAllowed_=false;
                }
            }
        }
        auto found=auxiliary_.find(family.stem);if(found!=auxiliary_.end())return found->second;
        auto& result=auxiliary_[family.stem];
        if(!auxiliaryAllowed_){LogSkip(log,family.stem,"skipped auxiliary: core/base budget reserved");return result;}
        const auto prefix=family.stem+"_";
        for(const auto& entry:files_) {
            if(entry.first.compare(0,prefix.size(),prefix)!=0)continue;
            const auto suffix=entry.first.substr(family.stem.size());
            if(!AuxiliarySuffix(suffix))continue;
            try{const auto path=Find(entry.first,root_);result.push_back({path,Feature(path)});}
            catch(const std::exception& e){LogSkip(log,family.stem,"skipped auxiliary: "+std::string(e.what()));}
        }
        return result;
    }
    Features Feature(const fs::path& path) {
        const auto found=features_.find(path);if(found!=features_.end())return found->second;
        const auto failed=failures_.find(path);if(failed!=failures_.end())throw std::runtime_error(failed->second);
        // Bound cumulative compressed input and original decode pixels, including bases.
        try {
            const auto bytes=fs::file_size(path);if(decodes_>=96 || bytes>64*1024*1024 || compressed_+bytes>256*1024*1024)throw std::runtime_error("feature decode budget exhausted");
            ++decodes_;compressed_+=bytes;
            auto image=Decode(path,0,0,128,&pixels_);
            auto result=Describe(image,blur_);features_[path]=result;return result;
        }catch(const std::exception& e){failures_[path]=e.what();throw;}
    }
    const fs::path& Root() const{return root_;}
    std::vector<std::string> Files() const {
        std::vector<std::string> result;
        for(const auto& entry:files_)for(const auto& p:entry.second) {
            if(result.size()>=256)return result;
            result.push_back(p.lexically_relative(root_).u8string());
        }
        return result;
    }
private:
    static void LogSkip(const DecisionLog& log,const std::string& family,const std::string& reason) {
        if(log){Decision d;d.family=family;d.reason=reason;log(d);}
    }
    fs::path root_;std::map<std::string,std::vector<fs::path>> files_;std::vector<Family> families_;
    std::map<fs::path,Features> features_;
    std::map<fs::path,std::string> failures_;
    std::map<std::string,std::vector<Evidence>> auxiliary_;
    bool ready_=false,blur_=false,auxiliaryReady_=false,auxiliaryAllowed_=true;
    size_t decodes_=0;uint64_t compressed_=0,pixels_=256ull*1024*1024;
};
class DiscoveryCache {
public:
    explicit DiscoveryCache(bool blur=false):blur_(blur){}
    Discovery& Get(const fs::path& root) {
        auto found=folders_.find(root);if(found!=folders_.end())return *found->second;
        if(folders_.size()>=8)folders_.erase(folders_.begin());
        auto folder=std::make_unique<Discovery>(root,blur_);auto& result=*folder;folders_[root]=std::move(folder);return result;
    }
private:std::map<fs::path,std::unique_ptr<Discovery>> folders_;bool blur_=false;
};
inline Maps Discover(const fs::path& root,const std::string& base,bool hideNames=false,const DecisionLog& log={},DiscoveryCache* cache=nullptr) {
    Decision d;d.base=base;
    auto done=[&](const Maps& m){d.accepted=m.recognized;if(log)log(d);return m;};
    const auto p=RelativeTexture(root,base);const auto stem=Lower(p.stem().u8string());
    std::unique_ptr<Discovery> owned;if(!cache)owned=std::make_unique<Discovery>(root);
    Discovery& folder=cache?cache->Get(root):*owned;
    if(!hideNames && stem.size()>2 && stem.substr(stem.size()-2)=="_d") {
        auto m=folder.Named(stem.substr(0,stem.size()-2),root/p.parent_path());
        if(m.recognized){d.family=stem.substr(0,stem.size()-2);d.score=1;d.margin=1;d.reason="exact stem";d.evidence=(m.normal.empty()?m.packed:m.normal).u8string();return done(m);}
    }
    const auto baseFeatures=folder.Feature(root/p);
    double best=-1,runner=-1;const Family* chosen=nullptr;
    for(const auto& family:folder.Families(log)) {
        double feature=-1;std::string evidence;
        auto compare=[&](const Evidence& e){const auto s=Similarity(baseFeatures,e.features);if(s>feature){feature=s;evidence=e.path.u8string();}};
        for(const auto& f:family.features)compare(f);
        // Names only add support after spatial evidence; they never rescue a mismatched layout.
        const int group=hideNames?0:Vocabulary(stem);
        const bool sameGroup=group && group==Vocabulary(family.stem);
        // An explicit exported family is negative name evidence too: EyeTrans and
        // Pupil, or Hair_02 and Hair_01, are not interchangeable because both are eyes/hair.
        const bool conflictingStem=stem.compare(0,2,"t_")==0 && stem.size()>2 && stem.substr(stem.size()-2)=="_d" && stem.substr(0,stem.size()-2)!=family.stem;
        if(sameGroup && !conflictingStem)for(const auto& f:folder.Auxiliary(family,log))
            if(Lower(f.path.lexically_normal().u8string())!=Lower((root/p).lexically_normal().u8string()))compare(f);
        const double score=feature+(sameGroup?.08:0);
        if(score>best){runner=best;best=score;chosen=&family;d.feature=feature;d.evidence=evidence;}else runner=(std::max)(runner,score);
    }
    d.score=best;d.margin=best-runner;if(chosen)d.family=chosen->stem;
    if(!hideNames && chosen && stem.compare(0,2,"t_")==0 && stem.size()>2 && stem.substr(stem.size()-2)=="_d" && stem.substr(0,stem.size()-2)!=chosen->stem) {
        d.reason="conflicting exported family";return done({});
    }
    if(!chosen || d.feature<.28 || best<.36){d.reason="insufficient UV edge evidence";return done({});}
    if(d.margin<.12){d.reason="ambiguous UV layout";return done({});}
    d.reason=hideNames?"UV edges (names hidden)":"UV edges with name support";
    return done(chosen->maps);
}
