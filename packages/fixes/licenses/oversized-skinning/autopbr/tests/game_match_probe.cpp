// GPL-2.0. Read-only corpus probe using the production Discover implementation.
#include "game_pbr_types.h"
#include "../source/material_pipeline/to_pbr/game_pbr.h"
#include <iostream>
using namespace MaterialPipeline::ToPBR;
int wmain(int argc,wchar_t** argv) {
    if(argc!=3 && !(argc==4 && std::wstring(argv[3])==L"--blur"))return 2;
    const auto com=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    std::ifstream in(argv[1]);std::ofstream out(argv[2]);
    if(!in || !out)return 3;
    out<<"pmx\tbase\thidden\taccepted\tfamily\tscore\tmargin\tfeature\treason\tnormal\tpacked\tlayout\tevidence\twarnings\n";
    std::string pmx,base;GamePBR::DiscoveryCache cache(argc==4);
    while(std::getline(in,pmx) && std::getline(in,base))for(bool hidden:{false,true}) {
        GamePBR::Decision d;GamePBR::Maps maps;std::string warnings;
        try{maps=GamePBR::Discover(std::filesystem::u8path(pmx).parent_path(),base,hidden,[&](const auto& decision){
            if(decision.base.empty())warnings+=decision.family+": "+decision.reason+"; ";else d=decision;
        },&cache);}
        catch(const std::exception& e){d.reason=e.what();}
        out<<pmx<<'\t'<<base<<'\t'<<hidden<<'\t'<<maps.recognized<<'\t'<<d.family<<'\t'<<d.score<<'\t'<<d.margin<<'\t'<<d.feature<<'\t'<<d.reason<<'\t'<<maps.normal.u8string()<<'\t'<<maps.packed.u8string()<<'\t'<<int(maps.layout)<<'\t'<<d.evidence<<'\t'<<warnings<<'\n';out.flush();
    }
    if(SUCCEEDED(com))CoUninitialize();return 0;
}
