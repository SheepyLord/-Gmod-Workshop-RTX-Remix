"""Decode a local NVIDIA Aftermath GPU dump with the installed SDK DLL; never uploads it."""
from __future__ import annotations

import argparse
import ctypes as c
import json
import os
from pathlib import Path
import sys

# ABI from Aftermath 2026.3 / API 2.27, GFSDK_Aftermath_{Defines,GpuCrashDumpDecoding}.h.
# Enums and the SDK's bool unions occupy four bytes; pointer/struct packing is eight.
API_VERSION = 0x21B
ALL_INFO = 0x3FFF
SUCCESS = 1
MAX_DUMP = 1 << 30
MAX_JSON = 256 << 20


class DecodeError(RuntimeError):
    pass


class ShaderInfo(c.Structure):
    _pack_ = 8
    _fields_ = [('shaderHash', c.c_uint64), ('shaderDebugInfoUid', c.c_uint64),
                ('isInternal', c.c_uint32), ('shaderType', c.c_uint32)]


class SpirvCode(c.Structure):
    _pack_ = 8
    _fields_ = [('pData', c.c_void_p), ('size', c.c_uint32)]


def check(result: int, operation: str) -> None:
    # NotAvailable (2) is not an error to GFSDK_Aftermath_SUCCEED, but has no output.
    if result != SUCCESS:
        raise DecodeError(f'{operation}: Aftermath returned 0x{result:08x}')


class Aftermath:
    def __init__(self, dll: Path, api_version: int = API_VERSION):
        if os.name != 'nt' or c.sizeof(c.c_void_p) != 8:
            raise DecodeError('the decoder requires 64-bit Python on Windows')
        self.api_version = api_version
        self.dll = c.CDLL(str(dll.resolve(strict=True)), winmode=0x1100)
        signatures = {
            'CreateDecoder': [c.c_uint32, c.c_void_p, c.c_uint32, c.POINTER(c.c_void_p)],
            'DestroyDecoder': [c.c_void_p],
            'GenerateJSON': [c.c_void_p, c.c_uint32, c.c_uint32, c.c_void_p, c.c_void_p,
                             c.c_void_p, c.c_void_p, c.POINTER(c.c_uint32)],
            'GetJSON': [c.c_void_p, c.c_uint32, c.c_void_p],
            'GetActiveShadersInfoCount': [c.c_void_p, c.POINTER(c.c_uint32)],
            'GetActiveShadersInfo': [c.c_void_p, c.c_uint32, c.POINTER(ShaderInfo)],
        }
        for name, args in signatures.items():
            fn = getattr(self.dll, 'GFSDK_Aftermath_GpuCrashDump_' + name)
            fn.argtypes, fn.restype = args, c.c_uint32
            setattr(self, name, fn)
        self.ShaderHash = self.dll.GFSDK_Aftermath_GetShaderHashForShaderInfo
        self.ShaderHash.argtypes = [c.c_void_p, c.POINTER(ShaderInfo), c.POINTER(c.c_uint64)]
        self.ShaderHash.restype = c.c_uint32
        self.SpirvHash = self.dll.GFSDK_Aftermath_GetShaderHashSpirv
        self.SpirvHash.argtypes = [c.c_uint32, c.POINTER(SpirvCode), c.POINTER(c.c_uint64)]
        self.SpirvHash.restype = c.c_uint32


def shader_index(sdk: Aftermath, root: Path | None) -> dict[str, list[str]]:
    """Map the SDK's binary hashes, not shader-instance hashes, to available SPIR-V names."""
    result: dict[str, list[str]] = {}
    if root is None:
        return result
    if not root.is_dir():
        raise DecodeError(f'SPIR-V directory does not exist: {root}')
    for path in sorted(root.rglob('*.spv')):
        data = path.read_bytes()
        if len(data) < 20 or len(data) % 4 or data[:4] != b'\x03\x02\x23\x07':
            continue
        buffer = c.create_string_buffer(data)
        code = SpirvCode(c.cast(buffer, c.c_void_p), len(data))
        value = c.c_uint64()
        check(sdk.SpirvHash(sdk.api_version, c.byref(code), c.byref(value)), 'GetShaderHashSpirv')
        result.setdefault(f'{value.value:016x}', []).append(path.relative_to(root).as_posix())
    return result


def decode(sdk: Aftermath, data: bytes, names: dict[str, list[str]] | None = None) -> dict:
    if not data or len(data) > MAX_DUMP:
        raise DecodeError('dump must be nonempty and at most 1 GiB')
    raw = c.create_string_buffer(data)
    decoder = c.c_void_p()
    check(sdk.CreateDecoder(sdk.api_version, raw, len(data), c.byref(decoder)), 'CreateDecoder')
    try:
        size = c.c_uint32()
        check(sdk.GenerateJSON(decoder, ALL_INFO, 0, None, None, None, None, c.byref(size)), 'GenerateJSON')
        if not 0 < size.value <= MAX_JSON:
            raise DecodeError(f'JSON size outside 1..{MAX_JSON}: {size.value}')
        output = c.create_string_buffer(size.value)
        check(sdk.GetJSON(decoder, size.value, output), 'GetJSON')
        report = json.loads(output.value.decode('utf-8'))
        count = c.c_uint32()
        check(sdk.GetActiveShadersInfoCount(decoder, c.byref(count)), 'GetActiveShadersInfoCount')
        if count.value > 1_000_000:
            raise DecodeError(f'unreasonable active shader count: {count.value}')
        shaders = (ShaderInfo * count.value)()
        if count.value:
            check(sdk.GetActiveShadersInfo(decoder, count.value, shaders), 'GetActiveShadersInfo')
        active = {}
        for shader in shaders:
            binary = c.c_uint64()
            status = sdk.ShaderHash(decoder, c.byref(shader), c.byref(binary))
            binary_hash = f'{binary.value:016x}' if status == SUCCESS else None
            key = (binary_hash, shader.shaderType, bool(shader.isInternal), shader.shaderHash)
            entry = active.setdefault(key, dict(binary_hash=binary_hash,
                instance_hash=f'{shader.shaderHash:016x}', shader_type=shader.shaderType,
                internal=bool(shader.isInternal), names=(names or {}).get(binary_hash, []),
                hash_result=f'0x{status:08x}', instances=0))
            entry['instances'] += 1
        return dict(api_version=f'0x{sdk.api_version:x}', sdk=report, active_shaders=list(active.values()),
                    spirv_hashes_indexed=len(names or {}))
    finally:
        # Release even when JSON parsing, shader enumeration or a lookup fails.
        check(sdk.DestroyDecoder(decoder), 'DestroyDecoder')


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('dump', type=Path)
    parser.add_argument('--dll', required=True, type=Path, help='trusted GFSDK_Aftermath_Lib.x64.dll')
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--spirv-root', type=Path, help='matching runtime build, containing compiled *.spv')
    parser.add_argument('--api-version', type=lambda value: int(value, 0), default=API_VERSION)
    args = parser.parse_args(argv)
    try:
        if not 0 < args.dump.stat().st_size <= MAX_DUMP:
            raise DecodeError('dump must be nonempty and at most 1 GiB')
        sdk = Aftermath(args.dll, args.api_version)
        result = decode(sdk, args.dump.read_bytes(), shader_index(sdk, args.spirv_root))
        args.out.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.out.with_name(args.out.name + f'.{os.getpid()}.tmp')
        try:
            temporary.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
            os.replace(temporary, args.out)
        finally:
            temporary.unlink(missing_ok=True)
        print(f'Decoded {args.dump} -> {args.out} ({len(result["active_shaders"])} active shader entries)')
        return 0
    except (OSError, ValueError, DecodeError) as error:
        print(f'aftermath_decode: {error}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
