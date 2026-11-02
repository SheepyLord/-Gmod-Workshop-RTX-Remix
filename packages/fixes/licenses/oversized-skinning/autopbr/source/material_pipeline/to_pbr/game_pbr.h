// GPL-2.0. Local authored game-map conversion, independent of Source material objects.
#pragma once
#include "to_pbr.h"
#include "pbr_policy.h"
#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <filesystem>
#include <fstream>
#include <map>
#include <stdexcept>
#include <array>
#include <cctype>
#include <cstring>
#include <functional>
#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")

namespace MaterialPipeline { namespace ToPBR { namespace GamePBR {
namespace fs = std::filesystem;
using Microsoft::WRL::ComPtr;
inline std::string Lower(std::string s) {
    for (auto& c:s) { if (c=='\\') c='/'; else if (uint8_t(c)<128) c=char(std::tolower(uint8_t(c))); }
    return s;
}
inline bool Has(const std::string& s, std::initializer_list<const char*> terms) {
    for (auto term:terms) if (s.find(term)!=std::string::npos) return true;
    return false;
}
enum Class : uint8_t { Original, Default, Cloth, Stocking, Leather, Hair, Metal, Rubber };
inline Class Classify(const std::string& native, const std::string& texture) {
    auto name=Lower(native);
    while(!name.empty() && std::isspace(uint8_t(name.back())))name.pop_back();
    while(!name.empty() && std::isspace(uint8_t(name.front())))name.erase(0,1);
    const auto tex=Lower(texture), both=name+" "+tex;
    if (Has(both,{"face","eye","iris","pupil","cornea","lash","brow","mouth","skin","cheek",
        u8"\u773c",u8"\u77b3",u8"\u767d\u76ee",u8"\u76ee\u767d",u8"\u776b",u8"\u7709",u8"\u989c",u8"\u9854",u8"\u9762",u8"\u53e3",u8"\u808c",u8"\u76ae\u80a4",u8"\u76ae\u819a"}) ||
        Has(name,{u8"\u4e0abody",u8"\u817f",u8"\u8eab\u4f53",u8"\u7d20\u4f53",u8"\u8155",u8"\u80f8"}) || (name=="body" || name=="body body")) return Original;
    if (Has(both,{"hair","bang",u8"\u9aea",u8"\u53d1",u8"\u9aee"})) return Hair;
    if (Has(name,{"metal","gold","silver",u8"\u91d1\u5c5e",u8"\u91d1\u5c6c"})) return Metal;
    if (Has(both,{"stock","sock","tight",u8"\u4e1d\u889c",u8"\u7d72\u896a"})) return Stocking;
    if (Has(both,{"leather",u8"\u76ae\u9769"})) return Leather;
    if (Has(both,{"rubber",u8"\u6a61\u80f6"})) return Rubber;
    if (Has(both,{"cloth","dress","coat","cape","fabric",u8"\u670d",u8"\u8863",u8"\u62ab\u98ce",u8"\u62ab\u98a8"})) return Cloth;
    return Default;
}
inline float Roughness(uint8_t c) {
    static constexpr float r[]={.7f,.45f,.55f,.30f,.20f,.28f,.12f,.08f};
    return r[(std::min)(unsigned(c),7u)];
}
inline float Strength(uint8_t c) {
    static constexpr float r[]={0,1.8f,2.6f,1.4f,2,1.2f,1.6f,.8f};
    return r[(std::min)(unsigned(c),7u)];
}
inline std::vector<uint8_t> Read(const fs::path& p, uint64_t limit=64*1024*1024) {
    std::ifstream f(p,std::ios::binary|std::ios::ate);
    if (!f) throw std::runtime_error("source is unavailable");
    const auto n=f.tellg(); if (n<0 || uint64_t(n)>limit) throw std::runtime_error("source exceeds bound");
    std::vector<uint8_t> b(size_t(n),0); f.seekg(0);
    if (!f.read(reinterpret_cast<char*>(b.data()),std::streamsize(b.size()))) throw std::runtime_error("short source read");
    return b;
}
inline uint64_t Hash(const std::vector<uint8_t>& b,uint64_t seed=14695981039346656037ull) {
    for (auto x:b) { seed^=x; seed*=1099511628211ull; } return seed;
}
struct Reader {
    const std::vector<uint8_t>& bytes; size_t at=0; bool utf8=true;
    void Skip(size_t n) { if (n>bytes.size()-at) throw std::runtime_error("truncated PMX"); at+=n; }
    template<class T> T Get() { T x; const auto pos=at; Skip(sizeof(T)); memcpy(&x,bytes.data()+pos,sizeof(T)); return x; }
    int Index(unsigned n,bool sign=true) {
        if(n==1) return sign?int(Get<int8_t>()):int(Get<uint8_t>());
        if(n==2) return sign?int(Get<int16_t>()):int(Get<uint16_t>());
        if(n==4) return Get<int32_t>();
        throw std::runtime_error("invalid PMX index width");
    }
    int Count(int max) { int n=Get<int32_t>(); if(n<0 || n>max) throw std::runtime_error("PMX count exceeds bound");return n; }
    std::string Text() {
        const int n=Count(1024*1024); const auto pos=at;Skip(size_t(n));
        if(utf8) return std::string(reinterpret_cast<const char*>(bytes.data()+pos),size_t(n));
        if(n%2) throw std::runtime_error("odd UTF16 text");
        std::wstring w(size_t(n/2),L'\0');memcpy(w.data(),bytes.data()+pos,size_t(n));
        int len=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,w.data(),int(w.size()),nullptr,0,nullptr,nullptr);
        if(!len && n) throw std::runtime_error("invalid PMX Unicode");
        std::string s(size_t(len),'\0');WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,w.data(),int(w.size()),s.data(),len,nullptr,nullptr);return s;
    }
};
struct UV { float u,v; };
struct Part { std::string name, texture; uint32_t first,count; uint8_t cls; };
struct Mesh { std::vector<UV> uv; std::vector<uint32_t> indices; std::vector<Part> parts; };
inline Mesh ParsePMX(const std::vector<uint8_t>& bytes) {
    Reader r{bytes}; if(r.Get<uint32_t>()!=0x20584d50) throw std::runtime_error("not PMX");
    float version=r.Get<float>(); if(version<1.99f || version>2.11f) throw std::runtime_error("unknown PMX version");
    const auto size=r.Get<uint8_t>(); if(size!=8) throw std::runtime_error("unknown PMX globals");
    std::array<uint8_t,8> g{};for(auto& c:g)c=r.Get<uint8_t>();
    for(size_t i=2;i<g.size();++i)if(g[i]!=1 && g[i]!=2 && g[i]!=4)throw std::runtime_error("invalid PMX index width");
    if(g[0]>1 || g[1]>4) throw std::runtime_error("unknown PMX encoding");r.utf8=g[0]==1;
    for(int i=0;i<4;++i)r.Text();
    Mesh m;const int vertices=r.Count(1000000);m.uv.reserve(vertices);
    for(int i=0;i<vertices;++i) {
        r.Skip(24);UV v{r.Get<float>(),r.Get<float>()};
        if(!std::isfinite(v.u)||!std::isfinite(v.v)||std::abs(v.u)>10000||std::abs(v.v)>10000) throw std::runtime_error("invalid UV");
        m.uv.push_back(v);r.Skip(size_t(g[1])*16);
        switch(r.Get<uint8_t>()) {
            case 0:r.Skip(g[5]);break;
            case 1:r.Skip(size_t(g[5])*2+4);break;
            case 2:case 4:r.Skip(size_t(g[5])*4+16);break;
            case 3:r.Skip(size_t(g[5])*2+40);break;
            default:throw std::runtime_error("unknown PMX deformation");
        }
        r.Skip(4);
    }
    const int count=r.Count(6000000);if(count%3)throw std::runtime_error("non-triangle PMX");m.indices.reserve(count);
    for(int i=0;i<count;++i){int v=r.Index(g[2],false);if(v<0||v>=vertices)throw std::runtime_error("bad vertex index");m.indices.push_back(uint32_t(v));}
    std::vector<std::string> textures;int n=r.Count(4096);for(int i=0;i<n;++i)textures.push_back(Lower(r.Text()));
    n=r.Count(4096);uint32_t first=0;
    for(int i=0;i<n;++i) {
        auto name=r.Text();auto english=r.Text();r.Skip(65);
        int texture=r.Index(g[3]);r.Index(g[3]);r.Skip(1);
        auto shared=r.Get<uint8_t>();if(shared==1)r.Skip(1);else if(shared==0)r.Index(g[3]);else throw std::runtime_error("bad toon index");
        r.Text();int faces=r.Count(count);if(faces%3 || uint64_t(first)+faces>m.indices.size())throw std::runtime_error("bad material span");
        std::string tex=texture>=0 && texture<int(textures.size())?textures[size_t(texture)]:"";
        m.parts.push_back({name+" "+english,tex,first,uint32_t(faces),uint8_t(Classify(name+" "+english,tex))});first+=uint32_t(faces);
    }
    if(first!=m.indices.size())throw std::runtime_error("incomplete material spans");return m;
}
inline std::vector<uint8_t> Mask(const Mesh& mesh,const std::string& base,uint32_t w,uint32_t h) {
    if(!Policy::ValidImage(w,h))throw std::runtime_error("mask exceeds bound");
    std::vector<uint8_t> mask(size_t(w)*h,255);
    uint64_t work=0;
    for(const auto& p:mesh.parts) {
        if(p.texture!=Lower(base))continue;
        for(uint32_t i=p.first;i<p.first+p.count;i+=3) {
            UV a=mesh.uv[mesh.indices[i]],b=mesh.uv[mesh.indices[i+1]],c=mesh.uv[mesh.indices[i+2]];
            a.u*=w;a.v*=h;b.u*=w;b.v*=h;c.u*=w;c.v*=h;
            float area=(b.u-a.u)*(c.v-a.v)-(b.v-a.v)*(c.u-a.u);
            if(std::abs(area)<1e-8f)continue;
            int x0=(std::max)(0,int(std::floor((std::min)({a.u,b.u,c.u})))),y0=(std::max)(0,int(std::floor((std::min)({a.v,b.v,c.v}))));
            int x1=(std::min)(int(w)-1,int(std::ceil((std::max)({a.u,b.u,c.u})))),y1=(std::min)(int(h)-1,int(std::ceil((std::max)({a.v,b.v,c.v}))));
            if (x1>=x0 && y1>=y0 && (work+=uint64_t(x1-x0+1)*uint64_t(y1-y0+1))>256*1024*1024)throw std::runtime_error("UV raster work exceeds bound");
            for(int y=y0;y<=y1;++y)for(int x=x0;x<=x1;++x) {
                float px=x+.5f,py=y+.5f;
                float u=((b.u-px)*(c.v-py)-(b.v-py)*(c.u-px))/area;
                float v=((c.u-px)*(a.v-py)-(c.v-py)*(a.u-px))/area;
                if(u>=-.001f && v>=-.001f && u+v<=1.001f) {
                    auto& out=mask[size_t(y)*w+x];if(out!=Original)out=p.cls==Original?Original:(out==255?p.cls:(std::max)(out,p.cls));
                }
            }
        }
    }
    // Extend island colour into its gutter; original skin always has priority.
    for(int pass=0;pass<4;++pass) {
        auto old=mask;
        for(uint32_t y=0;y<h;++y)for(uint32_t x=0;x<w;++x) {
            auto& dst=mask[size_t(y)*w+x];if(dst!=255)continue;
            for(int dy=-1;dy<=1;++dy)for(int dx=-1;dx<=1;++dx) {
                int xx=int(x)+dx,yy=int(y)+dy;if(xx<0||yy<0||xx>=int(w)||yy>=int(h))continue;
                auto c=old[size_t(yy)*w+xx];if(c==Original){dst=Original;break;}if(c!=255 && dst!=Original)dst=c;
            }
        }
    }
    for(auto& c:mask)if(c==255)c=Original;return mask;
}
struct Image { uint32_t w=0,h=0;std::vector<uint8_t> rgba; };
inline Image Decode(const fs::path& path,uint32_t w=0,uint32_t h=0) {
    auto bytes=Read(path); // Bound compressed input before WIC allocates.
    ComPtr<IWICImagingFactory> factory;ComPtr<IWICStream> stream;
    ComPtr<IWICBitmapDecoder> decoder;ComPtr<IWICBitmapFrameDecode> frame;
    ComPtr<IWICBitmapScaler> scaler;ComPtr<IWICFormatConverter> converter;
    auto check=[](HRESULT hr){if(FAILED(hr))throw std::runtime_error("unsupported/broken image");};
    check(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory)));
    check(factory->CreateStream(&stream));check(stream->InitializeFromMemory(bytes.data(),DWORD(bytes.size())));
    check(factory->CreateDecoderFromStream(stream.Get(),nullptr,WICDecodeMetadataCacheOnDemand,&decoder));
    UINT count=0;check(decoder->GetFrameCount(&count));if(count!=1)throw std::runtime_error("animated image");
    check(decoder->GetFrame(0,&frame));UINT sw=0,sh=0;check(frame->GetSize(&sw,&sh));
    if(!Policy::ValidImage(sw,sh))throw std::runtime_error("image dimensions exceed bound");
    if(!w || !h) { const float scale=(std::min)(1.0f,2048.0f/float((std::max)(sw,sh)));w=uint32_t(sw*scale);h=uint32_t(sh*scale); }
    if(!Policy::ValidImage(w,h) || uint64_t(sw)*h!=uint64_t(sh)*w)throw std::runtime_error("map aspect mismatch");
    check(factory->CreateBitmapScaler(&scaler));check(scaler->Initialize(frame.Get(),w,h,WICBitmapInterpolationModeFant));
    check(factory->CreateFormatConverter(&converter));check(converter->Initialize(scaler.Get(),GUID_WICPixelFormat32bppRGBA,WICBitmapDitherTypeNone,nullptr,0,WICBitmapPaletteTypeCustom));
    Image image{w,h,std::vector<uint8_t>(size_t(w)*h*4)};check(converter->CopyPixels(nullptr,w*4,UINT(image.rgba.size()),image.rgba.data()));return image;
}
struct Maps { bool recognized=false; fs::path normal,packed,emission;enum Layout{Wuwa,Endfield,Silver}layout=Wuwa; };
inline Maps Discover(const fs::path& root,const std::string& base) {
    const auto basePath=fs::u8path(base);if(basePath.has_root_path())throw std::runtime_error("rooted texture path");
    for(const auto& part:basePath)if(part=="..")throw std::runtime_error("texture traversal");
    auto stem=Lower(basePath.stem().u8string());if(stem.size()<3 || stem.substr(stem.size()-2)!="_d")return {};
    stem.resize(stem.size()-2);
    std::map<std::string,std::vector<fs::path>> files;size_t count=0;std::error_code ec;
    fs::recursive_directory_iterator it(root,ec),end;
    if(ec)throw std::runtime_error("cannot scan model folder");
    for(;it!=end;it.increment(ec)) {
        if(ec || ++count>4096)throw std::runtime_error("model folder scan exceeds bound");
        if(it.depth()>6 || (GetFileAttributesW(it->path().c_str())&FILE_ATTRIBUTE_REPARSE_POINT)){it.disable_recursion_pending();continue;}
        if(it->is_regular_file(ec)) {
            auto ext=Lower(it->path().extension().u8string());
            if(ext==".png"||ext==".bmp"||ext==".tga"||ext==".jpg")files[Lower(it->path().stem().u8string())].push_back(it->path());
        }
    }
    if(ec)throw std::runtime_error("model folder scan failed");
    auto find=[&](const char* suffix) {
        auto p=files.find(stem+suffix);if(p==files.end())return fs::path{};
        std::vector<fs::path> candidates;
        const auto beside=Lower((root/basePath.parent_path()).lexically_normal().u8string());
        for(const auto& candidate:p->second)
            if(Lower(candidate.parent_path().lexically_normal().u8string())==beside)candidates.push_back(candidate);
        if(candidates.empty())candidates=p->second;
        const auto bytes=Read(candidates[0]);
        for(size_t i=1;i<candidates.size();++i)
            if(Read(candidates[i])!=bytes)throw std::runtime_error("ambiguous companion texture");
        return candidates[0]; // Identical duplicate exports are the same authored input.
    };
    Maps m;m.normal=find("_n");m.packed=find("_mra");m.emission=find("_e");
    bool silverFamily=false;for(const auto& pair:files)if(pair.first.size()>4 && pair.first.substr(pair.first.size()-4)=="_mra")silverFamily=true;
    if(!m.packed.empty() || silverFamily)m.layout=Maps::Silver;
    else if(stem.find("t_actor_")==0) {m.layout=Maps::Endfield;m.packed=find("_p");if(m.normal.empty())m.normal=find("_hn");}
    else {
        // WuWa toon inputs need family evidence, not a generic suffix guess.
        if(find("_id").empty() && find("_hm").empty())return {};
        m.layout=Maps::Wuwa;m.emission.clear();
    }
    m.recognized=true;return m;
}
inline bool PlausibleNormal(const Image& n) {
    size_t valid=0,count=0;double sx=0,sy=0;
    const size_t pixels=n.rgba.size()/4,step=(std::max)(size_t(1),pixels/8192);
    for(size_t i=0;i<pixels;i+=step) {
        float x=n.rgba[i*4]/127.5f-1,y=n.rgba[i*4+1]/127.5f-1;
        valid+=x*x+y*y<1.15f;sx+=n.rgba[i*4]/255.0;sy+=n.rgba[i*4+1]/255.0;++count;
    }
    return count && valid>count*.90 && sx/count>.3 && sx/count<.7 && sy/count>.3 && sy/count<.7;
}
struct Output { std::string normal,roughness,metallic,emission,ao;size_t protectedPixels=0; };
using Writer=std::function<bool(const ConvertedTexture&,const std::string&)>;
inline Output Convert(const std::string& source,const std::string& base,const std::string& out,
                      const Writer& write,const std::function<void(ConvertedTexture&)>& oct) {
    const fs::path pmx=fs::u8path(source);if(!pmx.is_absolute() || Lower(pmx.extension().u8string())!=".pmx")throw std::runtime_error("not a local PMX");
    auto maps=Discover(pmx.parent_path(),base);if(!maps.recognized)return {};
    auto modelBytes=Read(pmx,256*1024*1024);
    uint64_t key=Hash(Read(pmx.parent_path()/fs::u8path(base)),Hash(modelBytes));
    // Every input byte participates, including a changed file with the same size/time.
    for(const auto& path:{maps.normal,maps.packed,maps.emission})if(!path.empty())key=Hash(Read(path),key);
    key=Hash(std::vector<uint8_t>(base.begin(),base.end()),key)^0x52313147414d4505ull;
    char id[32];snprintf(id,sizeof(id),"game_%016llX",static_cast<unsigned long long>(key));
    Output result;
    auto path=[&](const char* suffix){return (fs::u8path(out)/(std::string(id)+suffix+".dds")).u8string();};
    const fs::path marker=fs::u8path(out)/(std::string(id)+"_complete.txt");
    {
        std::ifstream cache(marker);std::string version;int glow=0;cache>>version>>glow;
        if(cache && version=="r11-game-v5" && Policy::ValidDDS(fs::u8path(path("_normal"))) &&
           Policy::ValidDDS(fs::u8path(path("_roughness"))) && Policy::ValidDDS(fs::u8path(path("_metallic"))) &&
           (!glow || Policy::ValidDDS(fs::u8path(path("_emission"))))) {
            result.normal=path("_normal");result.roughness=path("_roughness");result.metallic=path("_metallic");
            if(glow)result.emission=path("_emission");return result;
        }
    }
    auto mesh=ParsePMX(modelBytes);
    Image n=maps.normal.empty()?Image{}:Decode(maps.normal);
    Image packed=maps.packed.empty()?Image{}:Decode(maps.packed,n.w,n.h);
    uint32_t w=n.w?n.w:packed.w,h=n.h?n.h:packed.h;
    if(!w||!h) {auto diffuse=Decode(pmx.parent_path()/fs::u8path(base));w=diffuse.w;h=diffuse.h;}
    auto classes=Mask(mesh,base,w,h);size_t changed=0;for(auto c:classes)changed+=c!=Original;
    if(!changed)return {};
    if(n.w && !PlausibleNormal(n))throw std::runtime_error("normal channels fail sanity check");
    Image emission=maps.emission.empty()?Image{}:Decode(maps.emission,w,h);
    result.protectedPixels=classes.size()-changed;
    auto save=[&](ConvertedTexture& t,const char* suffix) {
        auto p=path(suffix);if(!Policy::ValidDDS(fs::u8path(p)) && !write(t,p))throw std::runtime_error("DDS publication failed");return p;
    };
    auto texture=[&](){ConvertedTexture t{};t.width=w;t.height=h;t.mipLevels=1;t.format=REMIXAPI_FORMAT_R8G8B8A8_UNORM;t.pixelData.resize(size_t(w)*h*4,255);return t;};
    auto rough=texture(),metal=texture(),ao=texture(),normal=texture(),glow=texture();
    bool anyGlow=false;
    for(size_t i=0;i<classes.size();++i) {
        const auto cls=classes[i];const size_t j=i*4;float r=Roughness(cls),m=cls==Metal?1.0f:0,a=1;
        if(cls!=Original && !packed.rgba.empty() && cls!=Hair) {
            m=packed.rgba[j]/255.0f;
            r=maps.layout==Maps::Endfield?1-packed.rgba[j+3]/255.0f:packed.rgba[j+1]/255.0f;
            a=packed.rgba[j+2]/255.0f;
        }
        r=std::clamp(r,.08f,.95f);
        for(int ch=0;ch<3;++ch) {
            rough.pixelData[j+ch]=uint8_t(r*255+.5f);metal.pixelData[j+ch]=uint8_t(m*255+.5f);ao.pixelData[j+ch]=uint8_t(a*255+.5f);
            glow.pixelData[j+ch]=cls!=Original && !emission.rgba.empty()?emission.rgba[j+ch]:0;
            anyGlow|=glow.pixelData[j+ch]>0;
        }
        float x=0,y=0,z=1;
        if(cls!=Original && n.w) {
            x=n.rgba[j]/127.5f-1;y=n.rgba[j+1]/127.5f-1;
            if(maps.layout==Maps::Endfield)y=-y;
            // UE families match DirectX; the sampled Endfield normals use OpenGL Y.
            // Rebuild Z: blue in WuWa/Endfield contains unrelated masks.
            z=maps.layout==Maps::Silver?(std::max)(.01f,n.rgba[j+2]/127.5f-1):std::sqrt((std::max)(.001f,1-x*x-y*y));
            x*=Strength(cls);y*=Strength(cls);
            float len=std::sqrt(x*x+y*y+z*z);x/=len;y/=len;z/=len;
        }
        normal.pixelData[j]=uint8_t((x*.5f+.5f)*255+.5f);normal.pixelData[j+1]=uint8_t((y*.5f+.5f)*255+.5f);normal.pixelData[j+2]=uint8_t((z*.5f+.5f)*255+.5f);
    }
    oct(normal);normal.isNormalMap=true;
    result.normal=save(normal,"_normal");result.roughness=save(rough,"_roughness");result.metallic=save(metal,"_metallic");
    if(!packed.rgba.empty())result.ao=save(ao,"_ao"); // Kept as data; do not bake occlusion into painted albedo under path tracing.
    if(anyGlow)result.emission=save(glow,"_emission");
    const fs::path staged=fs::path(marker.wstring()+L".tmp");
    { std::ofstream done(staged);done<<"r11-game-v5 "<<(anyGlow?1:0)<<"\n";if(!done)throw std::runtime_error("cache marker write failed"); }
    if(!MoveFileExW(staged.c_str(),marker.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))throw std::runtime_error("cache marker publication failed");
    return result;
}
}}}
