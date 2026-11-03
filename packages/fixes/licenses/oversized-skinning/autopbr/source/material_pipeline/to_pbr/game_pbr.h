// GPL-2.0. Local authored game-map conversion, independent of Source material objects.
#pragma once
#ifndef GAME_PBR_TYPES_PROVIDED
#include "to_pbr.h"
#endif
#include "pbr_policy.h"
#include "dds_publish.h"
#include <Windows.h>
#include <wincodec.h>
#include <wrl/client.h>
#include <filesystem>
#include <fstream>
#include <locale>
#include <map>
#include <memory>
#include <optional>
#include <sstream>
#include <stdexcept>
#include <array>
#include <cctype>
#include <cstring>
#include <functional>
#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")

namespace MaterialPipeline { namespace ToPBR { namespace GamePBR {
namespace fs = std::filesystem;
#ifndef TOPBR_GAME_GENERATOR_VERSION
#define TOPBR_GAME_GENERATOR_VERSION 8
#endif
// Registry provenance only (R13-M). Cached maps are keyed by their inputs and Recipe(), never by
// this number, so a release that changes no conversion reuses every map. Tests override it.
constexpr unsigned GeneratorVersion = TOPBR_GAME_GENERATOR_VERSION;
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
    const auto n=f.tellg();
    if (n<0) throw std::runtime_error("source is unreadable");
    if (uint64_t(n)>limit) throw std::runtime_error("source file exceeds bound: "+p.filename().u8string()+" is "+
        std::to_string(uint64_t(n))+" bytes; the limit is "+std::to_string(limit)+" bytes");
    std::vector<uint8_t> b(size_t(n),0); f.seekg(0);
    if (!f.read(reinterpret_cast<char*>(b.data()),std::streamsize(b.size()))) throw std::runtime_error("short source read");
    return b;
}
inline uint64_t Hash(const uint8_t* data,size_t size,uint64_t seed=14695981039346656037ull) {
    for (size_t i=0;i<size;++i) { seed^=data[i]; seed*=1099511628211ull; } return seed;
}
inline uint64_t Hash(const std::vector<uint8_t>& b,uint64_t seed=14695981039346656037ull) {
    return Hash(b.data(),b.size(),seed);
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
inline Image Decode(const fs::path& path,uint32_t w=0,uint32_t h=0,uint32_t limit=2048,uint64_t* pixelBudget=nullptr) {
    auto bytes=Read(path); // Bound compressed input before WIC allocates.
    ComPtr<IWICImagingFactory> factory;ComPtr<IWICStream> stream;
    ComPtr<IWICBitmapDecoder> decoder;ComPtr<IWICBitmapFrameDecode> frame;
    ComPtr<IWICFormatConverter> converter;
    auto check=[](HRESULT hr){if(FAILED(hr))throw std::runtime_error("unsupported/broken image");};
    check(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory)));
    check(factory->CreateStream(&stream));check(stream->InitializeFromMemory(bytes.data(),DWORD(bytes.size())));
    check(factory->CreateDecoderFromStream(stream.Get(),nullptr,WICDecodeMetadataCacheOnDemand,&decoder));
    UINT count=0;check(decoder->GetFrameCount(&count));if(count!=1)throw std::runtime_error("animated image");
    check(decoder->GetFrame(0,&frame));UINT sw=0,sh=0;check(frame->GetSize(&sw,&sh));
    if(!Policy::ValidImage(sw,sh))throw std::runtime_error(Policy::ImageRefusal(sw,sh,path.filename().u8string()));
    if(pixelBudget){const uint64_t pixels=uint64_t(sw)*sh;if(pixels>*pixelBudget)throw std::runtime_error("feature pixel budget exhausted");*pixelBudget-=pixels;}
    if(!w || !h) { const float scale=(std::min)(1.0f,float(limit)/float((std::max)(sw,sh)));w=uint32_t(sw*scale);h=uint32_t(sh*scale); }
    if(!Policy::ValidImage(w,h) || uint64_t(sw)*h!=uint64_t(sh)*w)throw std::runtime_error("map aspect mismatch");
    // WIC's Fant scaler premultiplies transparent PNG colour. These channels hold
    // packed game data, so decode straight RGBA first and average each independently.
    check(factory->CreateFormatConverter(&converter));check(converter->Initialize(frame.Get(),GUID_WICPixelFormat32bppRGBA,WICBitmapDitherTypeNone,nullptr,0,WICBitmapPaletteTypeCustom));
    Image source{sw,sh,std::vector<uint8_t>(size_t(sw)*sh*4)};
    check(converter->CopyPixels(nullptr,sw*4,UINT(source.rgba.size()),source.rgba.data()));
    if(w==sw && h==sh)return source;
    Image image{w,h,std::vector<uint8_t>(size_t(w)*h*4)};
    const uint64_t area=uint64_t(sw)*sh;
    for(uint32_t y=0;y<h;++y)for(uint32_t x=0;x<w;++x) {
        const uint32_t x0=x*sw,x1=(x+1)*sw,y0=y*sh,y1=(y+1)*sh;
        uint64_t sum[4]{};
        for(uint32_t sy=y0/h;sy<(y1+h-1)/h;++sy)for(uint32_t sx=x0/w;sx<(x1+w-1)/w;++sx) {
            const auto wx=(std::min)(x1,(sx+1)*w)-(std::max)(x0,sx*w);
            const auto wy=(std::min)(y1,(sy+1)*h)-(std::max)(y0,sy*h);
            const uint64_t weight=uint64_t(wx)*wy;
            for(size_t c=0;c<4;++c)sum[c]+=source.rgba[(size_t(sy)*sw+sx)*4+c]*weight;
        }
        for(size_t c=0;c<4;++c)image.rgba[(size_t(y)*w+x)*4+c]=uint8_t((sum[c]+area/2)/area);
    }
    return image;
}
struct Maps { bool recognized=false; fs::path normal,packed,emission;enum Layout{Wuwa,Endfield,Silver}layout=Wuwa; };
#include "game_matching.inl"
inline bool PlausibleNormal(const Image& n) {
    size_t valid=0,count=0;double sx=0,sy=0;
    const size_t pixels=n.rgba.size()/4,step=(std::max)(size_t(1),pixels/8192);
    for(size_t i=0;i<pixels;i+=step) {
        float x=n.rgba[i*4]/127.5f-1,y=n.rgba[i*4+1]/127.5f-1;
        valid+=x*x+y*y<1.15f;sx+=n.rgba[i*4]/255.0;sy+=n.rgba[i*4+1]/255.0;++count;
    }
    return count && valid>count*.90 && sx/count>.3 && sx/count<.7 && sy/count>.3 && sy/count<.7;
}
// Everything that changes converted bytes (R13-M): decoding, masks, class tables, channel math,
// octahedral encoding, mips, stored formats and the block encoder. Content keys and completion
// markers carry it, so a release that changes none of it reuses every cached map. Change the tag
// of whatever step a code change touches; the tables are printed from the values in use.
inline const std::string& Recipe() {
    static const std::string recipe=[] {
        std::ostringstream s;s.imbue(std::locale::classic());
        s<<"game-maps-1;decode=wic-straight-rgba8+area-integer,limit2048;mask=pmx-uv-raster,gutter4,original-first;classes=";
        for(unsigned c=0;c<8;++c)s<<(c?",":"")<<Roughness(uint8_t(c))<<"/"<<Strength(uint8_t(c));
        s<<";roughness=clamp0.08-0.95,metal-r,rough-g|endfield-1-a,hair-and-original-class"
         <<";normal=rebuild-z(wuwa,endfield),endfield-flip-y,silver-blue-z-min0.01,class-strength,octahedral-hemi-8bit"
         <<";emission=rgb-outside-original;mips=box2x2-floor"
         <<";formats=normal-BC5,roughness-BC4,metallic-BC4,emission-RGBA8,unaligned-RGBA8;encoder="<<DDS::EncoderId;
        return s.str();
    }();
    return recipe;
}
inline std::string Id(uint64_t key) {
    char id[32];snprintf(id,sizeof(id),"game_%016llX",static_cast<unsigned long long>(key));return id;
}
// The current key and the keys earlier generators gave the same inputs (their formulas, exactly).
struct Keys { uint64_t current=0,v7=0,v6=0,v5=0; };
inline Keys ContentKeys(const std::vector<uint8_t>& model,const std::vector<uint8_t>& baseBytes,
                        const std::array<std::vector<uint8_t>,3>& inputs,const std::array<bool,3>& present,
                        const std::string& base,Maps::Layout layout) {
    const uint64_t seed=Hash(baseBytes,Hash(model));
    uint64_t roles=seed,v5=seed;
    for(size_t i=0;i<3;++i) {
        const uint8_t tag[2]{uint8_t(i+1),uint8_t(present[i])};roles=Hash(tag,2,roles);
        if(present[i]){roles=Hash(inputs[i],roles);v5=Hash(inputs[i],v5);}
    }
    const auto name=reinterpret_cast<const uint8_t*>(base.data());
    const uint64_t named=Hash(name,base.size(),roles);
    Keys keys;
    keys.v7=named^0x52313247414d4507ull^uint64_t(layout);
    keys.v6=named^0x52313247414d4506ull^uint64_t(layout);
    keys.v5=Hash(name,base.size(),v5)^0x52313147414d4505ull;
    const uint8_t layoutTag=uint8_t(layout);
    keys.current=Hash(reinterpret_cast<const uint8_t*>(Recipe().data()),Recipe().size(),Hash(&layoutTag,1,named));
    return keys;
}
// Image dimensions from the encoded header, without decoding pixels.
inline std::pair<uint32_t,uint32_t> ImageSize(const std::vector<uint8_t>& bytes) {
    ComPtr<IWICImagingFactory> factory;ComPtr<IWICStream> stream;ComPtr<IWICBitmapDecoder> decoder;ComPtr<IWICBitmapFrameDecode> frame;
    auto check=[](HRESULT hr){if(FAILED(hr))throw std::runtime_error("unsupported/broken image");};
    check(CoCreateInstance(CLSID_WICImagingFactory,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory)));
    check(factory->CreateStream(&stream));check(stream->InitializeFromMemory(const_cast<BYTE*>(bytes.data()),DWORD(bytes.size())));
    check(factory->CreateDecoderFromStream(stream.Get(),nullptr,WICDecodeMetadataCacheOnDemand,&decoder));
    check(decoder->GetFrame(0,&frame));UINT w=0,h=0;check(frame->GetSize(&w,&h));return {w,h};
}
// via: "cached", "converted" or "transcoded from <marker>"; written counts the maps stored now.
struct Output { std::string normal,roughness,metallic,emission,via;size_t protectedPixels=0;unsigned written=0; };
// Stores a complete mip chain as `format` at a path. Production publishes atomically and throws
// one clear line on a refusal; returning false reports a generic publication failure.
using Writer=std::function<bool(const std::vector<DDS::Level>&,const std::string&,DDS::Format)>;
inline Output Convert(const std::string& source,const std::string& base,const std::string& out,
                      const Writer& write,const std::function<void(ConvertedTexture&)>& oct,
                      DiscoveryCache* discovery=nullptr,const Maps* selected=nullptr,const DecisionLog& log={}) {
    const fs::path pmx=fs::u8path(source);if(!pmx.is_absolute() || Lower(pmx.extension().u8string())!=".pmx")throw std::runtime_error("not a local PMX");
    auto maps=selected?*selected:Discover(pmx.parent_path(),base,false,log,discovery);if(!maps.recognized)return {};
    const auto modelBytes=Read(pmx,256*1024*1024);
    const auto baseBytes=Read(pmx.parent_path()/fs::u8path(base));
    // Every input byte participates, including a changed file with the same size/time.
    std::array<std::vector<uint8_t>,3> inputs;std::array<bool,3> present{};
    {size_t i=0;for(const auto& path:{maps.normal,maps.packed,maps.emission}){present[i]=!path.empty();if(present[i])inputs[i]=Read(path);++i;}}
    const auto keys=ContentKeys(modelBytes,baseBytes,inputs,present,base,maps.layout);
    const fs::path folder=fs::u8path(out);
    static constexpr const char* suffix[4]={"_normal","_roughness","_metallic","_emission"};
    auto file=[&](uint64_t key,size_t role){return folder/(Id(key)+suffix[role]+".dds");};
    const fs::path marker=folder/(Id(keys.current)+"_complete.txt");
    Output result;
    auto finish=[&](bool glow,const std::string& via) {
        result.normal=file(keys.current,0).u8string();result.roughness=file(keys.current,1).u8string();
        result.metallic=file(keys.current,2).u8string();if(glow)result.emission=file(keys.current,3).u8string();
        result.via=via;return result;
    };
    auto mark=[&](bool glow,const std::string& origin) {
        const fs::path staged(marker.wstring()+L".tmp");
        {std::ofstream done(staged,std::ios::binary|std::ios::trunc);done<<Recipe()<<' '<<(glow?1:0)<<"\norigin "<<origin<<"\n";done.close();
         if(!done)throw std::runtime_error("cache marker write failed");}
        if(!MoveFileExW(staged.c_str(),marker.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH))throw std::runtime_error("cache marker publication failed");
    };
    // A map is current when it is complete, bounded and in its role's format for its own size.
    auto current=[&](const fs::path& path,size_t role) {
        DDS::Info info;
        return DDS::Probe(path,info) && Policy::ValidImage(info.width,info.height) && info.format==DDS::GameFormat(role,info.width,info.height);
    };
    {
        std::ifstream cache(marker,std::ios::binary);std::string recipe;int glow=-1;cache>>recipe>>glow;
        if(cache && recipe==Recipe() && (glow==0 || glow==1) && current(file(keys.current,0),0) && current(file(keys.current,1),1) &&
           current(file(keys.current,2),2) && (!glow || current(file(keys.current,3),3)))return finish(glow!=0,"cached");
    }
    // A finished family from an earlier generator with these inputs is re-encoded, not converted
    // again (the uncompressed RGBA8 maps before R13). Half-finished families convert normally.
    struct Earlier { unsigned version;uint64_t key;const char* marker; };
    const Earlier earlier[]{{7,keys.v7,"r12-game-v7"},{6,keys.v6,"r12-game-v6"},{5,keys.v5,"r11-game-v5"}};
    std::optional<bool> mraInFolder;
    for(const auto& legacy:earlier) {
        // v5 keys carry neither roles nor layout, and manual choices did not exist then.
        if(legacy.version==5 && selected)continue;
        std::ifstream cache(folder/(Id(legacy.key)+"_complete.txt"),std::ios::binary);std::string version;int glow=-1;cache>>version>>glow;
        if(!cache || version!=legacy.marker || (glow!=0 && glow!=1))continue;
        DDS::Info info;bool complete=true;
        for(size_t role=0;role<(glow?4u:3u) && complete;++role) {
            DDS::Info map;
            complete=DDS::Probe(file(legacy.key,role),map) && Policy::ValidImage(map.width,map.height) && map.format==DDS::Format::RGBA8 &&
                (!role || (map.width==info.width && map.height==info.height));
            if(!role)info=map;
        }
        if(!complete)continue;
        if(legacy.version<7) {
            // v5/v6 decoded through WIC's premultiplying Fant scaler whenever a map was resized
            // (R12-B2): such outputs are converted again from their readable source.
            bool resized=false;
            for(size_t i=0;i<3;++i)if(present[i]){const auto size=ImageSize(inputs[i]);resized|=size.first!=info.width || size.second!=info.height;}
            if(resized)continue;
        }
        if(legacy.version==5 && maps.layout!=Maps::Silver) {
            // v5 chose Silver for every family in a folder holding any *_MRA map; otherwise its
            // canonical layout rules are today's.
            if(!mraInFolder) {
                std::unique_ptr<Discovery> owned;
                Discovery& scan=discovery?discovery->Get(pmx.parent_path()):*(owned=std::make_unique<Discovery>(pmx.parent_path()));
                mraInFolder=scan.HasStemSuffix("_mra");
            }
            if(*mraInFolder)continue;
        }
        for(size_t role=0;role<(glow?4u:3u);++role) {
            const auto target=file(keys.current,role);
            if(current(target,role))continue;
            DDS::Info stored;auto chain=DDS::Read(file(legacy.key,role),stored);
            if(!write(chain,target.u8string(),DDS::GameFormat(role,stored.width,stored.height)))throw std::runtime_error("DDS publication failed");
            ++result.written;
        }
        mark(glow!=0,std::string("transcoded ")+legacy.marker+" "+Id(legacy.key));
        return finish(glow!=0,std::string("transcoded from ")+legacy.marker);
    }
    auto mesh=ParsePMX(modelBytes);
    Image n=maps.normal.empty()?Image{}:Decode(maps.normal);
    Image packed=maps.packed.empty()?Image{}:Decode(maps.packed,n.w,n.h);
    uint32_t w=n.w?n.w:packed.w,h=n.h?n.h:packed.h;
    if(!w||!h) {auto diffuse=Decode(pmx.parent_path()/fs::u8path(base));w=diffuse.w;h=diffuse.h;}
    const auto diffuseSize=Decode(pmx.parent_path()/RelativeTexture(pmx.parent_path(),base),0,0,128);
    if(uint64_t(diffuseSize.w)*h!=uint64_t(diffuseSize.h)*w)throw std::runtime_error("base/map aspect mismatch");
    auto classes=Mask(mesh,base,w,h);size_t changed=0;for(auto c:classes)changed+=c!=Original;
    if(!changed)return {};
    if(n.w && !PlausibleNormal(n))throw std::runtime_error("normal channels fail sanity check");
    Image emission=maps.emission.empty()?Image{}:Decode(maps.emission,w,h);
    result.protectedPixels=classes.size()-changed;
    // A map already stored in its format survives an interrupted pass: the family completes.
    auto save=[&](ConvertedTexture& t,size_t role) {
        const auto p=file(keys.current,role);
        if(!current(p,role)) {
            if(!write(DDS::Chain(t.width,t.height,std::move(t.pixelData)),p.u8string(),DDS::GameFormat(role,t.width,t.height)))
                throw std::runtime_error("DDS publication failed");
            ++result.written;
        }
    };
    auto texture=[&](){ConvertedTexture t{};t.width=w;t.height=h;t.mipLevels=1;t.format=REMIXAPI_FORMAT_R8G8B8A8_UNORM;t.pixelData.resize(size_t(w)*h*4,255);return t;};
    auto rough=texture(),metal=texture(),normal=texture(),glow=texture();
    bool anyGlow=false;
    for(size_t i=0;i<classes.size();++i) {
        const auto cls=classes[i];const size_t j=i*4;float r=Roughness(cls),m=cls==Metal?1.0f:0;
        // Packed blue (Endfield P / Silver MRA occlusion) has no Remix input and is not stored.
        if(cls!=Original && !packed.rgba.empty() && cls!=Hair) {
            m=packed.rgba[j]/255.0f;
            r=maps.layout==Maps::Endfield?1-packed.rgba[j+3]/255.0f:packed.rgba[j+1]/255.0f;
        }
        r=std::clamp(r,.08f,.95f);
        for(int ch=0;ch<3;++ch) {
            rough.pixelData[j+ch]=uint8_t(r*255+.5f);metal.pixelData[j+ch]=uint8_t(m*255+.5f);
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
    save(normal,0);save(rough,1);save(metal,2);
    if(anyGlow)save(glow,3);
    mark(anyGlow,"converted");
    return finish(anyGlow,"converted");
}
}}}
