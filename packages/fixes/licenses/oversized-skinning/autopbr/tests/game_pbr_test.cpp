// GPL-2.0. Run against generated PMX/PNG fixtures, or a read-only corpus descriptor.
#include "../source/material_pipeline/to_pbr/game_pbr.h"
#include "../source/material_pipeline/to_pbr/vtf.h"
#include <cassert>
#include <iostream>
using namespace MaterialPipeline::ToPBR;
int main(int argc,char** argv) {
    assert(argc==2 || argc==3);
    auto com=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    const auto root=std::filesystem::u8path(argv[1]);
    std::filesystem::create_directories(root/"output");
    if(argc==3) {
        std::ifstream input(root/argv[2]);std::string pmx,base;
        while(std::getline(input,pmx) && std::getline(input,base)) {
            size_t count=0;
            try {
                auto output=GamePBR::Convert(pmx,base,(root/"output").u8string(),
                    [&](const ConvertedTexture& t,const std::string& path) {
                        ++count; uint64_t sums[4]{};
                        for(size_t i=0;i<t.pixelData.size();++i)sums[i%4]+=t.pixelData[i];
                        std::cout<<"MAP "<<path<<" "<<t.width<<"x"<<t.height<<" rgbmean="
                                 <<double(sums[0])/(t.pixelData.size()/4)<<","<<double(sums[1])/(t.pixelData.size()/4)<<","<<double(sums[2])/(t.pixelData.size()/4)<<"\n";
                        return true;
                    },[](ConvertedTexture& t){VTF::ConvertNormalMapToOctahedral(t);});
                std::cout<<"RESULT "<<base<<" maps="<<count<<" protected="<<output.protectedPixels<<"\n";
            } catch(const std::exception& e) { std::cout<<"REJECT "<<base<<" "<<e.what()<<"\n"; }
        }
    } else {
        using namespace GamePBR;
        assert(Classify(u8"\u808c", "T_actor_x_body_D.png")==Original);
        assert(Classify("MI_Skin01", "T_Skin01_D.png")==Original);
        assert(Classify(u8"\u773c\u767d", "atlas.png")==Original);
        assert(Classify("Body ", "atlas.png")==Original);
        assert(Classify("Body Body", "atlas.png")==Original);
        assert(Classify("Cloth", "atlas.png")==Cloth);
        assert(Classify(u8"\u91d1\u5c5e", "atlas.png")==Metal);
        auto bytes=Read(root/"test.pmx");auto mesh=ParsePMX(bytes);assert(mesh.parts.size()==2);
        auto classes=Mask(mesh,"tex/T_actor_test_cloth_D.png",8,8);
        assert(classes[2*8+1]==Original && classes[2*8+6]==Cloth);
        auto truncated=bytes;truncated.resize(30);bool rejected=false;
        try{ParsePMX(truncated);}catch(...){rejected=true;}assert(rejected);
        std::map<std::string,ConvertedTexture> written;
        auto output=Convert((root/"test.pmx").u8string(),"tex/T_actor_test_cloth_D.png",(root/"output").u8string(),
            [&](const ConvertedTexture& t,const std::string& path){written[path]=t;return true;},
            [](ConvertedTexture& t){VTF::ConvertNormalMapToOctahedral(t);});
        assert(!output.normal.empty() && !output.roughness.empty() && !output.metallic.empty() && !output.emission.empty());
        const auto& rough=written.at(output.roughness);const auto& metal=written.at(output.metallic);
        const auto& normal=written.at(output.normal);const auto& glow=written.at(output.emission);
        const size_t skin=(2*8+1)*4, cloth=(2*8+6)*4;
        assert(rough.pixelData[skin]==179 && metal.pixelData[skin]==0 && glow.pixelData[skin]==0);
        assert(std::abs(int(normal.pixelData[skin])-128)<=1 && std::abs(int(normal.pixelData[skin+1])-128)<=1);
        assert(normal.pixelData[cloth] > 128);
        assert(rough.pixelData[cloth]==55 && metal.pixelData[cloth]==220 && glow.pixelData[cloth]>0);
        // _P blue is AO, alpha is smoothness; green is deliberately unrelated.
        assert(written.at(output.ao).pixelData[cloth]==199);
        assert(!PlausibleNormal(Image{2,2,std::vector<uint8_t>(16,0)}));
        for(const auto& bad:{"../bad_D.png","C:bad_D.png","/bad_D.png"}) {
            rejected=false;try{Discover(root,bad);}catch(...){rejected=true;}assert(rejected);
        }
        std::filesystem::create_directories(root/"duplicate");
        std::filesystem::copy_file(root/"tex/T_actor_test_cloth_N.png",root/"duplicate/T_actor_test_cloth_N.png",std::filesystem::copy_options::overwrite_existing);
        assert(!Discover(root,"tex/T_actor_test_cloth_D.png").normal.empty());
        // A texture beside the base is authoritative; differing alternatives elsewhere are ambiguous.
        std::filesystem::create_directories(root/"duplicate2");
        std::filesystem::copy_file(root/"tex/T_actor_test_cloth_N.png",root/"duplicate2/T_actor_test_cloth_N.png",std::filesystem::copy_options::overwrite_existing);
        {std::ofstream f(root/"duplicate2/T_actor_test_cloth_N.png",std::ios::app|std::ios::binary);f<<"different";}
        std::filesystem::rename(root/"tex/T_actor_test_cloth_N.png",root/"tex/normal.saved");
        rejected=false;try{Discover(root,"tex/T_actor_test_cloth_D.png");}catch(...){rejected=true;}assert(rejected);
        std::filesystem::rename(root/"tex/normal.saved",root/"tex/T_actor_test_cloth_N.png");
        std::filesystem::remove(root/"duplicate/T_actor_test_cloth_N.png");
        std::filesystem::remove(root/"duplicate2/T_actor_test_cloth_N.png");
        std::cout<<"PASS game channels, PMX bounds, Unicode names, shared skin, aliases, discovery and image sanity\n";
    }
    if(SUCCEEDED(com))CoUninitialize();
}
