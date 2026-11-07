"""Exercise SDK cleanup and shader-hash semantics without a GPU or NVIDIA DLL."""
import ctypes as c
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import aftermath_decode as a


class FakeSDK:
    api_version = a.API_VERSION

    def __init__(self, payload=b'{"device":{"status":"Timeout"}}', generate=1):
        self.payload, self.generate, self.destroyed = payload, generate, 0

    def CreateDecoder(self, api, raw, size, decoder):
        c.cast(decoder, c.POINTER(c.c_void_p))[0] = 7
        return 1

    def DestroyDecoder(self, decoder):
        self.destroyed += 1
        return 1

    def GenerateJSON(self, decoder, flags, fmt, *args):
        c.cast(args[-1], c.POINTER(c.c_uint32))[0] = len(self.payload) + 1
        return self.generate

    def GetJSON(self, decoder, size, output):
        output.value = self.payload
        return 1

    def GetActiveShadersInfoCount(self, decoder, count):
        c.cast(count, c.POINTER(c.c_uint32))[0] = 2
        return 1

    def GetActiveShadersInfo(self, decoder, count, output):
        output[0] = output[1] = a.ShaderInfo(0x99, 0, 0, 5)
        return 1

    def ShaderHash(self, decoder, shader, value):
        c.cast(value, c.POINTER(c.c_uint64))[0] = 0x42
        return 1


class DecodeTests(unittest.TestCase):
    def test_uses_binary_hash_not_instance_hash_and_retains_sdk_json(self):
        sdk = FakeSDK()
        result = a.decode(sdk, b'dump', {'0000000000000042': ['omm.spv']})
        self.assertEqual(result['sdk']['device']['status'], 'Timeout')
        self.assertEqual(result['active_shaders'][0]['names'], ['omm.spv'])
        self.assertEqual(result['active_shaders'][0]['instances'], 2)
        self.assertEqual(sdk.destroyed, 1)

    def test_sdk_failure_releases_decoder(self):
        sdk = FakeSDK(generate=0xBAD00001)
        with self.assertRaises(a.DecodeError):
            a.decode(sdk, b'dump')
        self.assertEqual(sdk.destroyed, 1)

    def test_invalid_json_releases_decoder(self):
        sdk = FakeSDK(payload=b'{')
        with self.assertRaises(json.JSONDecodeError):
            a.decode(sdk, b'dump')
        self.assertEqual(sdk.destroyed, 1)

    def test_unavailable_binary_hash_is_not_treated_as_zero_hash(self):
        sdk = FakeSDK()
        sdk.ShaderHash = lambda *args: 2
        result = a.decode(sdk, b'dump', {'0000000000000000': ['wrong.spv']})
        self.assertIsNone(result['active_shaders'][0]['binary_hash'])
        self.assertEqual(result['active_shaders'][0]['names'], [])

    def test_empty_dump_does_not_create_decoder(self):
        sdk = FakeSDK()
        with self.assertRaises(a.DecodeError):
            a.decode(sdk, b'')
        self.assertEqual(sdk.destroyed, 0)

    def test_dump_without_shader_information_still_decodes(self):
        sdk = FakeSDK()
        sdk.GetActiveShadersInfoCount = lambda *args: 2
        result = a.decode(sdk, b'dump')
        self.assertEqual(result['active_shaders'], [])
        self.assertEqual(result['sdk']['device']['status'], 'Timeout')
        self.assertEqual(len(result['warnings']), 1)
        self.assertEqual(sdk.destroyed, 1)


if __name__ == '__main__':
    unittest.main()
