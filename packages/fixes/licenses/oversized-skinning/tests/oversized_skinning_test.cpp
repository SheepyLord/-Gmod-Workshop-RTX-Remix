// SPDX-License-Identifier: GPL-2.0-only
#include "../source/oversized_skinning_policy.h"
#include <cassert>
#include <iostream>

struct FakePalette {
    int matrices[8] = {10, 11, 12, 13, 14, 15, 16, 17};
    unsigned int blend = 2;
    unsigned int indexed = 1;
    int failRead = -1;
    int writes = 0;
    bool ReadBlend(unsigned int& b, unsigned int& i) { b = blend; i = indexed; return true; }
    bool WriteBlend(unsigned int b, unsigned int i) { blend = b; indexed = i; ++writes; return true; }
    bool ReadMatrix(int i, int& value) { value = matrices[i]; return i != failRead; }
    bool WriteMatrix(int i, int value) { matrices[i] = value; ++writes; return true; }
};

int main() {
    using OversizedSkinning::NeedsHardwareProtection;
    for (int count : {-1, 0, 1, 32767}) assert(!NeedsHardwareProtection(count, 2, 0));
    for (int count : {32768, 40509, 62049}) assert(NeedsHardwareProtection(count, 2, 0));
    assert(!NeedsHardwareProtection(40509, 0, 0));
    assert(!NeedsHardwareProtection(40509, 1, 0));
    assert(!NeedsHardwareProtection(40509, 3, 0));
    assert(!NeedsHardwareProtection(40509, 6, 0));
    assert(!NeedsHardwareProtection(40509, 2, 1));
    assert(!NeedsHardwareProtection(40509, 2, -1));

    using OversizedSkinning::NeedsHardwareScope;
    assert(!NeedsHardwareScope(7015, 2, 0, false, false));
    assert(NeedsHardwareScope(7015, 2, 0, true, false));
    assert(NeedsHardwareScope(40509, 2, 0, false, false));
    assert(!NeedsHardwareScope(40509, 2, 0, true, true));
    assert(!NeedsHardwareScope(7015, 0, 0, true, false));
    assert(!NeedsHardwareScope(7015, 3, 1, true, false));
    assert(!NeedsHardwareScope(0, 2, 0, true, false));
    assert(OversizedSkinning::HasUnsafeStaticFallback(0x08, true));
    assert(!OversizedSkinning::HasUnsafeStaticFallback(0x08, false));
    assert(!OversizedSkinning::HasUnsafeStaticFallback(0x00, true));
    assert(OversizedSkinning::UserForcedUploadSelected(233, 1));
    assert(OversizedSkinning::UserForcedUploadSelected(43, 43));
    assert(!OversizedSkinning::UserForcedUploadSelected(233, 0));
    assert(!OversizedSkinning::UserForcedUploadSelected(233, -1));
    assert(!OversizedSkinning::UserForcedUploadSelected(233, 43));
    assert(!OversizedSkinning::UserForcedUploadSelected(1, 1));
    assert(!OversizedSkinning::UserForcedUploadSelected(513, 1));

    OversizedSkinning::BoneSlotMask used, provided, staleCache;
    assert(used.Add(0) && used.Add(52) && used.Add(255));
    assert(provided.Add(0) && provided.Add(52));
    assert(staleCache.Add(255));
    assert(!OversizedSkinning::StripProvidesUsedSlots(used, provided));
    // A stale cache containing the missing slot cannot approve this strip.
    assert(staleCache.words[3] != 0 &&
        !OversizedSkinning::StripProvidesUsedSlots(used, provided));
    assert(provided.Add(255));
    assert(OversizedSkinning::StripProvidesUsedSlots(used, provided));
    assert(!provided.Add(-1) && !provided.Add(256));

    FakePalette device;
    OversizedSkinning::BonePaletteSnapshot<int, 8> snapshot = {};
    assert(snapshot.Capture(device, 4));
    for (int i = 0; i < 4; ++i) device.matrices[i] = 100 + i;
    device.blend = 0; device.indexed = 0;
    assert(snapshot.Restore(device));
    for (int i = 0; i < 8; ++i) assert(device.matrices[i] == 10 + i);
    assert(device.blend == 2 && device.indexed == 1);
    assert(snapshot.Capture(device, 4));
    try {
        device.matrices[0] = 900;
        device.blend = 7;
        throw 1;
    } catch (...) {
        assert(snapshot.Restore(device));
    }
    assert(device.matrices[0] == 10 && device.blend == 2);
    const int priorWrites = device.writes;
    device.failRead = 2;
    assert(!snapshot.Capture(device, 4));
    assert(snapshot.Restore(device) && device.writes == priorWrites);
    assert(!snapshot.Capture(device, -1));
    assert(!snapshot.Capture(device, 9));
    std::cout << "PASS: oversized HW policy, complete per-strip palettes and borrowed state restoration\n";
}
