#pragma once

#include <cstddef>
#include <string>
#include <vector>

// The adapter validates the live memory range before passing the offset table.
// Keep ownership separate from engine addresses so malformed/replaced maps and
// another patch's edits cannot cause stale PVS offsets to be restored.
namespace VisPAS {
constexpr int MaxClusters = 65536;
constexpr int MaxVisibilityBytes = 0x1000000; // Source SDK MAX_MAP_VISIBILITY

enum class Result { Unchanged, Widened, Restored, Invalid, OwnershipLost };

class State {
public:
    bool Active() const { return !original.empty(); }

    void Forget() {
        table = nullptr;
        map.clear();
        bytes = 0;
        original.clear();
    }

    Result Sync(void* identity, const std::string& mapName, int byteCount,
        int clusters, int* offsets, bool want)
    {
        if (!identity || mapName.empty() || !offsets || clusters <= 0 ||
            clusters > MaxClusters || byteCount < 4 + clusters * 8 || byteCount > MaxVisibilityBytes) {
            Forget();
            return Result::Invalid;
        }
        const int headerBytes = 4 + clusters * 8;
        for (int i = 0; i < clusters * 2; ++i) {
            if (offsets[i] < headerBytes || offsets[i] >= byteCount) {
                Forget();
                return Result::Invalid;
            }
        }

        if (Active()) {
            if (table != identity || map != mapName || bytes != byteCount ||
                original.size() != static_cast<std::size_t>(clusters) * 2) {
                Forget(); // a new map, including reuse of an old allocation
            } else {
                for (int c = 0; c < clusters; ++c) {
                    if (offsets[c * 2] != original[c * 2 + 1] ||
                        offsets[c * 2 + 1] != original[c * 2 + 1]) {
                        Forget(); // do not overwrite an intervening patch
                        return Result::OwnershipLost;
                    }
                }
                if (want) return Result::Unchanged;
                for (int c = 0; c < clusters; ++c) {
                    offsets[c * 2] = original[c * 2];
                }
                Forget();
                return Result::Restored;
            }
        }

        if (!want) return Result::Unchanged;
        bool different = false;
        for (int c = 0; c < clusters; ++c) {
            different |= offsets[c * 2] != offsets[c * 2 + 1];
        }
        if (!different) return Result::Unchanged;
        // Allocate and capture everything before changing the engine's table.
        original.assign(offsets, offsets + clusters * 2);
        map = mapName;
        table = identity;
        bytes = byteCount;
        for (int c = 0; c < clusters; ++c) {
            offsets[c * 2] = offsets[c * 2 + 1];
        }
        return Result::Widened;
    }

private:
    void* table = nullptr;
    std::string map;
    int bytes = 0;
    std::vector<int> original;
};
} // namespace VisPAS
