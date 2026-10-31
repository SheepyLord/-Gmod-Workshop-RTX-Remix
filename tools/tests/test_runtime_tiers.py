"""Check packaged performance tiers against source-pinned RTX option names, types and bounds."""
import hashlib
from pathlib import Path
import re
import unittest


REPO = Path(__file__).resolve().parents[2]

# Pinned on 2026-10-31 from the PM's read-only, patched T4 runtime-src, HEAD
# 29546f3566a676a1318b799fb8ddd01b2a110058 (base c6b48ed1 + this project's patches).
# Paths below are relative to src/dxvk/rtx_render/. RtxOptions.md is a useful cross-check:
# SHA256 4a457a8d1e3bb6dbf00efe05720fd9c8c4ea8621509fa72c6621313eb685cc57.
# Refresh these entries from RTX_OPTION declarations/enums when runtime/base.json changes;
# never infer types/ranges from the conf values or require an external runtime checkout in CI.
# Bounds are inclusive declared limits, or the C++ type's limits when no bound is declared.
# The two OMM memory values use the nonnegative 0..256*1024 MiB range of their runtime UI
# (rtx_opacity_micromap_manager.cpp:602-603), rather than allowing negative signed-int budgets.
# Sky probes use the six supported UI extents (src/dxvk/imgui/dxvk_imgui.cpp:3390-3399),
# rather than allowing a zero extent or arbitrary uint32_t sizes into image creation.
# Entry: (C++ type, range or enum values, source declaration).
OPTIONS = {
    'rtx.pathMaxBounces': ('uint8_t', (0, 15), 'rtx_options.h:868-874'),
    'rtx.neuralRadianceCache.qualityPreset': (
        'QualityPreset', frozenset((0, 1, 2)), 'rtx_neural_radiance_cache.h:45-49,142-150'),
    'rtx.lowMemoryGpu': ('bool', frozenset(('True', 'False')), 'rtx_options.h:401'),
    'rtx.opacityMicromap.cache.maxBudgetSizeMB': (
        'int', (0, 262144), 'rtx_opacity_micromap_manager.h:67'),
    'rtx.opacityMicromap.cache.minFreeVidmemMBToNotAllocate': (
        'int', (0, 262144), 'rtx_opacity_micromap_manager.h:56'),
    'rtx.skyProbeSide': (
        'uint32_t', frozenset((256, 512, 1024, 2048, 4096, 8192)), 'rtx_options.h:1307'),
    'rtx.volumetrics.froxelGridResolutionScale': (
        'uint32_t', (1, 4294967295), 'rtx_global_volumetrics.h:97-98'),
    'rtx.terrainBaker.cascadeMap.levelResolution': (
        'uint32_t', (1, 32768), 'rtx_terrain_baker.h:140-143'),
    'rtx.atmosphere.starMapTexture': ('std::string', None, 'rtx_atmosphere.h:534-536'),
    'rtx.atmosphere.starMapGalaxyTexture': ('std::string', None, 'rtx_atmosphere.h:537-539'),
    'rtx.atmosphere.starMapNebulaTexture': ('std::string', None, 'rtx_atmosphere.h:540-542'),
}

# These are baseline layers, not R6 tiers. Classic contains 15 obsolete keys absent from the
# patched source (old exposure/localtonemap/bloom options, occluderTextures, finalizeWithACES).
# Preserve its accepted high-tier bytes instead of pretending those keys are runtime options.
# Every *.conf is scanned; any other layer must pass OPTIONS, so a new file cannot bypass it.
BASELINE_HASHES = {
    'classic_remix_defaults.conf': '72cc5317ecbc4d77ac63e22683f0075b34eff1674a3e0f39b23ed7ccbeb06f86',
    'compiler_threads.conf': 'fdb168ee65505699c13d8f8396825dc22e38666cf9f2864c5026677ce9f1ebb0',
}


def assignments(text):
    seen = set()
    for number, line in enumerate(text.splitlines(), 1):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        key, sep, value = line.partition('=')
        key, value = key.strip(), value.strip()
        if not sep or not key or key in seen:
            raise ValueError('line %d: malformed or duplicate assignment: %s' % (number, key))
        seen.add(key)
        yield number, key, value


def validate_tier(text):
    keys = set()
    for number, key, value in assignments(text):
        if key not in OPTIONS:
            raise ValueError('line %d: unknown option %s; refresh OPTIONS from runtime source' % (number, key))
        kind, bounds, source = OPTIONS[key]
        if kind == 'std::string':
            valid = bool(value) and '\0' not in value
        elif kind == 'bool':
            valid = value in bounds
        elif re.fullmatch(r'-?[0-9]+', value):
            parsed = int(value)
            valid = parsed in bounds if isinstance(bounds, frozenset) else bounds[0] <= parsed <= bounds[1]
        else:
            valid = False
        if not valid:
            raise ValueError('line %d: %s = %r outside %s %s (%s)' %
                             (number, key, value, kind, bounds, source))
        keys.add(key)
    if not keys:
        raise ValueError('empty tier')
    return keys


class RuntimeTierTests(unittest.TestCase):
    def test_every_packaged_layer_is_validated_or_pinned_baseline(self):
        paths = sorted((REPO / 'packages/runtime/layers').glob('*.conf'))
        self.assertLessEqual({'low.conf', 'medium.conf', *BASELINE_HASHES}, {p.name for p in paths})
        used = set()
        for path in paths:
            with self.subTest(layer=path.name):
                data = path.read_bytes()
                pairs = list(assignments(data.decode('utf-8')))
                self.assertTrue(pairs)
                if path.name in BASELINE_HASHES:
                    self.assertEqual(hashlib.sha256(data).hexdigest(), BASELINE_HASHES[path.name],
                                     'baseline changed; review its options rather than silently exempting new keys')
                else:
                    used.update(validate_tier(data.decode('utf-8')))
        self.assertEqual(used, set(OPTIONS))

    def test_typos_malformed_assignments_and_wrong_types_fail(self):
        cases = (
            'rtx.pathMaxBouces = 4', 'dxvk.hud = 0', 'rtx.pathMaxBounces 4',
            'rtx.pathMaxBounces = 4\nrtx.pathMaxBounces = 8', '# no values',
            'rtx.pathMaxBounces = 4.0', 'rtx.pathMaxBounces = True',
            'rtx.skyProbeSide = 768',
            'rtx.lowMemoryGpu = 1', 'rtx.lowMemoryGpu = maybe',
            'rtx.atmosphere.starMapTexture = ', 'rtx.atmosphere.starMapTexture = a\0b',
        )
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ValueError):
                validate_tier(text)

    def test_numeric_bounds_and_enum_values(self):
        for key, (kind, bounds, _) in OPTIONS.items():
            if kind in ('std::string', 'bool'):
                continue
            low, high = (min(bounds), max(bounds)) if isinstance(bounds, frozenset) else bounds
            for value in (low - 1, high + 1):
                with self.subTest(key=key, invalid=value), self.assertRaises(ValueError):
                    validate_tier('%s = %d' % (key, value))
            for value in sorted(bounds):
                with self.subTest(key=key, valid=value):
                    self.assertEqual(validate_tier('%s = %d' % (key, value)), {key})


if __name__ == '__main__':
    unittest.main()
