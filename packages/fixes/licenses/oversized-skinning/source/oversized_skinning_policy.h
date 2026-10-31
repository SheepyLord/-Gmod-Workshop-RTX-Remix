// SPDX-License-Identifier: GPL-2.0-only
#pragma once
#include <cstdint>

namespace OversizedSkinning {

// studiorender.dll's dynamic software path rejects this count inclusively.
constexpr int SoftwareVertexLimit = 32768;
constexpr unsigned int Flexed = 0x1;
constexpr unsigned int HardwareSkinned = 0x2;
constexpr unsigned int DeltaFlexed = 0x4;

constexpr bool IsNonFlexHardwareGroup(unsigned int flags, int flexes) {
    return (flags & HardwareSkinned) != 0 &&
        (flags & (Flexed | DeltaFlexed)) == 0 && flexes == 0;
}

constexpr bool NeedsHardwareProtection(int vertices, unsigned int flags, int flexes) {
    return vertices >= SoftwareVertexLimit && IsNonFlexHardwareGroup(flags, flexes);
}

constexpr bool NeedsHardwareScope(
    int vertices, unsigned int flags, int flexes, bool userForcedEligible, bool alreadyScoped)
{
    return !alreadyScoped && vertices > 0 && IsNonFlexHardwareGroup(flags, flexes) &&
        (userForcedEligible || vertices >= SoftwareVertexLimit);
}

constexpr bool HasUnsafeStaticFallback(unsigned char config38, bool oversized) {
    return oversized && (config38 & 0x08) != 0;
}

constexpr bool UserForcedUploadSelected(int bones, int mode) {
    return bones > 1 && bones <= 512 && (mode == 1 || mode == bones);
}

struct BoneSlotMask {
    std::uint64_t words[4] = {};

    bool Add(int slot) {
        if (slot < 0 || slot >= 256) return false;
        words[slot / 64] |= std::uint64_t(1) << (slot % 64);
        return true;
    }
};

// Only the strip's own assignments prove completeness. A mapping cached from
// an earlier mesh can be stale when the user has hardware skinning disabled.
inline bool StripProvidesUsedSlots(const BoneSlotMask& used, const BoneSlotMask& provided) {
    for (int i = 0; i < 4; ++i) {
        if ((used.words[i] & ~provided.words[i]) != 0) return false;
    }
    return true;
}

// Only the palette slots and blend states borrowed by the automatic draw are
// restored. A full D3D state block would also roll back Source's material state.
template<typename Matrix, int MaxMatrices>
struct BonePaletteSnapshot {
    Matrix matrices[MaxMatrices];
    unsigned int vertexBlend;
    unsigned int indexedBlend;
    int count;
    bool ready;

    template<typename Access>
    bool Capture(Access& access, int matrixCount) {
        ready = false;
        if (matrixCount <= 0 || matrixCount > MaxMatrices ||
            !access.ReadBlend(vertexBlend, indexedBlend)) return false;
        for (int i = 0; i < matrixCount; ++i) {
            if (!access.ReadMatrix(i, matrices[i])) return false;
        }
        count = matrixCount;
        ready = true;
        return true;
    }

    template<typename Access>
    bool Restore(Access& access) const {
        if (!ready) return true;
        bool restored = true;
        for (int i = 0; i < count; ++i) {
            if (!access.WriteMatrix(i, matrices[i])) restored = false;
        }
        if (!access.WriteBlend(vertexBlend, indexedBlend)) restored = false;
        return restored;
    }
};

} // namespace OversizedSkinning
