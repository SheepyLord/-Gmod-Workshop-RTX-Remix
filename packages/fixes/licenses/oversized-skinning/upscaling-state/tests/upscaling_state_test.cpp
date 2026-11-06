// GPL-2.0. SDK-free tests of the production readback parser and bounded API read.
#include "../source/remixapi/upscaling_state.h"
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>

using namespace RemixAPI::UpscalingReadback;
static void check(bool value) { if (!value) std::abort(); }

int main() {
    State s;
    check(Parse("1 0 0 0 0 0 0", s) && !s.ready && !s.dlss && !s.dlfg && !s.fsrfg);
    for (unsigned up = 0; up <= 5; ++up) {
        for (unsigned fg = 0; fg <= 2; ++fg) {
            for (unsigned caps = 0; caps < 8; ++caps) {
                std::string wire = "1 1 " + std::to_string(up) + " " + std::to_string(fg)
                    + " " + std::to_string(caps & 1) + " " + std::to_string((caps >> 1) & 1)
                    + " " + std::to_string((caps >> 2) & 1);
                check(Parse(wire, s) && s.ready && s.upscaler == up && s.frameGeneration == fg
                    && s.dlss == bool(caps & 1) && s.dlfg == bool(caps & 2) && s.fsrfg == bool(caps & 4));
            }
        }
    }
    for (const char* bad : {"", "2 1 0 0 1 1 1", "1 2 0 0 1 1 1", "1 1 6 0 1 1 1", "1 1 0 3 1 1 1",
            "1 1 0 0 2 1 1", "1 1 0 0 1 2 1", "1 1 0 0 1 1 2", "1 1 0 0 1 1 1 ",
            "1 1 0 0 1 1 1\n", "1\t1 0 0 1 1 1", "1 1 -1 0 1 1 1", "1 1 0 0 true true true"}) {
        s = {true, 4, 2, true, false, true};
        check(!Parse(bad, s) && s.ready && s.upscaler == 4 && s.frameGeneration == 2);
    }
    for (unsigned i = 0; i < 13; ++i) {
        std::string wire = "1 1 1 1 1 1 1";
        wire[i] = '\0';
        check(!Parse(wire, s));
    }
    check(ReadState([](const char* key, char* out, uint32_t size, uint32_t* actual) {
        check(std::strcmp(key, Key) == 0 && size >= 14);
        std::memcpy(out, "1 1 5 2 1 0 1", 14); *actual = 14; return true;
    }, s) && s.ready && s.upscaler == 5 && s.frameGeneration == 2 && !s.dlfg);
    for (uint32_t size : {0u, 1u, 13u, 15u, 64u, 65u, 0xffffffffu}) {
        check(!ReadState([size](const char*, char*, uint32_t, uint32_t* actual) {
            *actual = size; return true;
        }, s));
    }
    check(!ReadState([](const char*, char*, uint32_t, uint32_t*) { return false; }, s));
    check(!ReadState([](const char*, char* out, uint32_t size, uint32_t* actual) {
        std::memset(out, '1', size); *actual = 14; return true;
    }, s));
    std::cout << "PASS upscaling readback: all enums/capabilities, malformed/missing/oversized/error/unterminated\n";
}
