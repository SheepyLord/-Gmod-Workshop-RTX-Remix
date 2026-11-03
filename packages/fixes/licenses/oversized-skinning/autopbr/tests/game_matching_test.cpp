// GPL-2.0. Production discovery/override/queue-order regressions without game or SDK.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <memory>
#include <vector>
#include <cassert>
#include <iostream>
#include <stdexcept>
#include "game_pbr_types.h"
#include "../source/material_pipeline/to_pbr/game_pbr.h"
#include "../source/material_pipeline/to_pbr/game_overrides.h"
#include "../source/material_pipeline/to_pbr/fallback_guard.h"
using namespace MaterialPipeline::ToPBR;
namespace fs=std::filesystem;
static void BMP(const fs::path& path,int variant,bool colour=false) {
    const int w=128,h=128;uint8_t header[54]{};header[0]='B';header[1]='M';
    auto value=[&](size_t at,uint32_t v){memcpy(header+at,&v,4);};
    value(2,54+w*h*4);value(10,54);value(14,40);value(18,w);value(22,h);header[26]=1;header[28]=32;
    std::ofstream f(path,std::ios::binary);f.write(reinterpret_cast<char*>(header),54);
    for(int y=0;y<h;++y)for(int x=0;x<w;++x){
        const bool island=variant==0?((x>12 && x<60 && y>8 && y<90) || (x>80 && y>60 && y<110)):
            ((x>50 && y<40) || (x<25 && y>80));
        const uint8_t v=island?200:30;
        const uint8_t pixel[4]={uint8_t(colour?255-v:v),uint8_t(colour?v/2:v),v,255};
        f.write(reinterpret_cast<const char*>(pixel),4);
    }
}
static void DDS(const fs::path& p) {
    uint32_t h[32]{};h[0]=0x20534444;h[1]=124;h[3]=h[4]=h[7]=1;h[19]=32;h[20]=0x41;h[22]=32;
    h[23]=0xff0000;h[24]=0xff00;h[25]=0xff;h[26]=0xff000000;
    std::ofstream f(p,std::ios::binary);f.write(reinterpret_cast<char*>(h),128);f<<"abcd";
}
static std::string Bytes(const fs::path& p){std::ifstream f(p,std::ios::binary);return {std::istreambuf_iterator<char>(f),{}};}
int wmain(int argc,wchar_t** argv) {
    assert(argc==2);const auto com=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    const fs::path root=argv[1];fs::create_directories(root/"maps");fs::create_directories(root/"textures");
    BMP(root/"renamed.bmp",0,true);BMP(root/"maps/One_MRA.bmp",0);BMP(root/"maps/Two_MRA.bmp",1);
    GamePBR::Decision d;
    auto discover=[&](){return GamePBR::Discover(root,"renamed.bmp",true,[&](const auto& v){d=v;});};
    assert(discover().recognized && d.family=="one" && d.score>.99 && d.margin>.12);
    // Equal UV layouts must abstain, even if one has an attractive filename.
    BMP(root/"maps/Three_MRA.bmp",0);
    assert(!discover().recognized && d.reason=="ambiguous UV layout");
    fs::remove(root/"maps/Three_MRA.bmp");
    GamePBR::Image blank{128,128,std::vector<uint8_t>(128*128*4,128)};
    const auto flat=GamePBR::Describe(blank);assert(GamePBR::Similarity(flat,flat)<0);
    auto stretched=flat;stretched.w=64;stretched.h=256;assert(GamePBR::Similarity(flat,stretched)<0);
    // Name hints can never revive a spatial mismatch or a missing supported family.
    BMP(root/"hair.bmp",0);fs::remove(root/"maps/One_MRA.bmp");
    assert(!GamePBR::Discover(root,"hair.bmp").recognized);
    for(const auto& bad:{"../x.bmp","C:x.bmp","/x.bmp"}){bool threw=false;try{GamePBR::Discover(root,bad);}catch(...){threw=true;}assert(threw);}
    const auto silver=root/"silver";fs::create_directory(silver);
    BMP(silver/"T_OtherDefault_Cloth_MRA.bmp",0);BMP(silver/"T_OtherDefault_Hair_N.bmp",1);BMP(silver/"T_OtherDefault_Hair_D.bmp",1,true);
    auto silverHair=GamePBR::Discover(silver,"T_OtherDefault_Hair_D.bmp");
    assert(silverHair.recognized && silverHair.layout==GamePBR::Maps::Silver && silverHair.packed.empty());
    const auto conflicting=root/"conflicting";fs::create_directory(conflicting);
    BMP(conflicting/"T_actor_wrong_D.bmp",0);BMP(conflicting/"T_actor_wrong_MRA.bmp",0);
    bool conflict=false;try{GamePBR::Discover(conflicting,"T_actor_wrong_D.bmp");}catch(...){conflict=true;}assert(conflict);
    const auto bounded=root/"bounded";fs::create_directory(bounded);BMP(bounded/"base.bmp",0);
    for(int i=0;i<65;++i){std::ofstream f(bounded/(std::to_string(i)+"_MRA.bmp"));}
    bool over=false;try{GamePBR::Discover(bounded,"base.bmp");}catch(...){over=true;}assert(over);
    // Drawn-hash evidence precedes material loading, including invalid/over-budget jobs.
    int loads=0;auto load=[&](){++loads;return "mmd/t/0123456789abcdef";};
    assert(GameRegistry::DrawnIdentity({},load).empty());assert(GameRegistry::DrawnIdentity({0},load).empty());
    assert(GameRegistry::DrawnIdentity(std::vector<uint64_t>(65,1),load).empty() && loads==0);
    assert(!GameRegistry::DrawnIdentity({7},load).empty() && loads==1);
    const std::string id="mmd/t/0123456789abcdef";
    const auto output=root/"textures";DDS(output/"manual.dds");
    GameRegistry::Registry registry(output);assert(registry.Load());
    GameOverrides::Choice c;c.mode="maps";c.source="E:/source/角色.pmx";c.base="衣服.bmp";c.normal="maps/One_N.bmp";c.layout=2;
    c.record.identity=id;c.record.hashes={7};c.record.generator=6;
    assert(registry.Capture(c.record,{(output/"manual.dds").u8string(),{},{},{}}));
    GameOverrides::Store store(output);assert(store.Load() && store.Set(id,c));
    GameOverrides::Store restart(output);assert(restart.Load());
    // No original source exists: only recorded DDS are required. New material hashes are used.
    assert(restart.Find(id)->source==c.source);
    auto restored=restart.Resolve(id,{9,11});assert(restored && restored->hashes==std::vector<uint64_t>({9,11}));
    int autoCalls=0;
    auto automatic=[&]()->std::optional<GameRegistry::Record>{++autoCalls;return {};};
    assert(restart.Select(id,{9},true,automatic) && autoCalls==0);
    assert(!restart.Select(id,{9},false,automatic) && autoCalls==0);
    c.mode="none";assert(restart.Set(id,c) && restart.Find(id)->mode=="none" && !restart.Resolve(id,{12}));
    assert(!restart.Select(id,{9},true,automatic) && autoCalls==0);
    GameOverrides::Store noneReload(output);assert(noneReload.Load() && noneReload.Find(id)->mode=="none");
    c.mode="automatic";assert(noneReload.Set(id,c) && !noneReload.Find(id));
    assert(!noneReload.Select(id,{9},true,automatic) && autoCalls==1);
    c.mode="maps";assert(noneReload.Set(id,c));
    // Changed DDS suppress the override rather than silently restoring automatic maps.
    {std::fstream f(output/"manual.dds",std::ios::in|std::ios::out|std::ios::binary);f.seekp(128);f.put('z');}
    assert(noneReload.Find(id) && !noneReload.Resolve(id,{8}));
    assert(!noneReload.Select(id,{9},true,automatic) && autoCalls==1);
    // Failed durable replacement preserves both disk choice and in-memory choice.
    const auto path=root/"game_overrides.registry";const auto before=Bytes(path);
    HANDLE held=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,0,nullptr);assert(held!=INVALID_HANDLE_VALUE);
    c.mode="none";assert(!noneReload.Set(id,c) && noneReload.Find(id)->mode=="maps" && Bytes(path)==before);CloseHandle(held);
    assert(!fs::exists(path.wstring()+L".tmp"));
    {std::ofstream f(path,std::ios::binary);f<<"TOPBR_GAME_OVERRIDES 999\n";}
    GameOverrides::Store unknown(output);assert(!unknown.Load() && !unknown.Readable() && !unknown.Set(id,c));
    assert(!unknown.Select(id,{9},true,automatic) && autoCalls==1);
    assert(Bytes(path)=="TOPBR_GAME_OVERRIDES 999\n");
    std::cout<<"PASS R12 matching: spatial selection/abstention/layouts/bounds; drawn-before-load; texture override persistence/none/automatic/restore/integrity/atomic failure\n";
    if(SUCCEEDED(com))CoUninitialize();return 0;
}
