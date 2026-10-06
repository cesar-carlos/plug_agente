from __future__ import annotations

import ctypes
from ctypes import wintypes
import os
from pathlib import Path
import re
import shutil
import struct
import tempfile

PROJECT_ROOT = Path(__file__).resolve().parents[2]
PRODUCT_NAME = "Plug Agente"


def application_version() -> str:
    match = re.search(r"^version:\s*(\d+\.\d+\.\d+\+\d+)\s*$",
                      (PROJECT_ROOT / "pubspec.yaml").read_text(encoding="utf-8"), re.MULTILINE)
    if match is None:
        raise ValueError("Expected an application version including the build number")
    version_parts(match.group(1))
    return match.group(1)


def version_parts(version: str) -> tuple[int, ...]:
    if not re.fullmatch(r"\d+\.\d+\.\d+\+\d+", version):
        raise ValueError("Invalid Windows product version")
    parts = tuple(int(part) for part in version.replace("+", ".").split("."))
    if any(part > 65535 for part in parts):
        raise ValueError("Windows version components must be at most 65535")
    return parts


def _block(key: str, value: bytes = b"", children: bytes = b"", *, text: bool = False) -> bytes:
    body = key.encode("utf-16-le") + b"\0\0"
    body += b"\0" * (-(len(body) + 6) % 4)
    body += value
    body += b"\0" * (-(len(body) + 6) % 4)
    body += children
    value_length = len(value) // 2 if text else len(value)
    return struct.pack("<HHH", len(body) + 6, value_length, int(text)) + body


def version_resource(version: str, filename: str) -> bytes:
    major, minor, patch, build = version_parts(version)
    fixed = struct.pack("<13I", 0xFEEF04BD, 0x10000,
                        (major << 16) | minor, (patch << 16) | build,
                        (major << 16) | minor, (patch << 16) | build,
                        0x3F, 0, 0x40004, 1, 0, 0, 0)
    values = {
        "CompanyName": "Se7e Sistemas", "FileDescription": PRODUCT_NAME,
        "FileVersion": version, "InternalName": Path(filename).stem,
        "LegalCopyright": "Copyright (c) 2026 Se7e Sistemas",
        "OriginalFilename": filename, "ProductName": PRODUCT_NAME,
        "ProductVersion": version,
    }
    strings = b"".join(_block(key, (value + "\0").encode("utf-16-le"), text=True)
                       for key, value in values.items())
    table = _block("040904b0", children=strings, text=True)
    string_info = _block("StringFileInfo", children=table, text=True)
    translation = _block("Translation", struct.pack("<HH", 0x409, 1200))
    var_info = _block("VarFileInfo", children=translation, text=True)
    return _block("VS_VERSION_INFO", fixed, string_info + var_info)


def executable_overlay(data: bytes) -> bytes:
    if data[:2] != b"MZ":
        raise ValueError("Not a Windows executable")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("Invalid PE header")
    count = struct.unpack_from("<H", data, pe + 6)[0]
    optional_size = struct.unpack_from("<H", data, pe + 20)[0]
    optional = pe + 24
    magic = struct.unpack_from("<H", data, optional)[0]
    directories = optional + (112 if magic == 0x20B else 96)
    if magic not in (0x10B, 0x20B):
        raise ValueError("Unsupported PE format")
    certificate_offset, certificate_size = struct.unpack_from("<II", data, directories + 4 * 8)
    if certificate_offset or certificate_size:
        raise ValueError("Refusing to modify an already signed executable")
    end = struct.unpack_from("<I", data, optional + 60)[0]
    for index in range(count):
        section = optional + optional_size + index * 40
        size, offset = struct.unpack_from("<II", data, section + 16)
        end = max(end, offset + size)
    if end > len(data):
        raise ValueError("Truncated executable")
    return data[end:]


def read_version_info(path: Path) -> dict[str, str]:
    if os.name != "nt":
        raise OSError("Windows version resources require Windows")
    path = path.resolve(strict=True)
    api = ctypes.WinDLL("version", use_last_error=True)
    api.GetFileVersionInfoSizeW.argtypes = [wintypes.LPCWSTR, ctypes.POINTER(wintypes.DWORD)]
    api.GetFileVersionInfoSizeW.restype = wintypes.DWORD
    api.GetFileVersionInfoW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID]
    api.GetFileVersionInfoW.restype = wintypes.BOOL
    api.VerQueryValueW.argtypes = [wintypes.LPCVOID, wintypes.LPCWSTR, ctypes.POINTER(wintypes.LPVOID), ctypes.POINTER(wintypes.UINT)]
    api.VerQueryValueW.restype = wintypes.BOOL
    size = api.GetFileVersionInfoSizeW(str(path), None)
    if not size:
        raise OSError(f"Missing version resource: {path}")
    buffer = ctypes.create_string_buffer(size)
    if not api.GetFileVersionInfoW(str(path), 0, size, buffer):
        raise ctypes.WinError(ctypes.get_last_error())
    pointer = wintypes.LPVOID()
    length = wintypes.UINT()
    if not api.VerQueryValueW(buffer, "\\VarFileInfo\\Translation", ctypes.byref(pointer), ctypes.byref(length)) or length.value < 4:
        raise ValueError(f"Missing version translation: {path}")
    language, encoding = struct.unpack("<HH", ctypes.string_at(pointer, 4))
    result = {}
    for key in ("ProductName", "ProductVersion", "OriginalFilename"):
        pointer = wintypes.LPVOID()
        length = wintypes.UINT()
        if not api.VerQueryValueW(buffer, f"\\StringFileInfo\\{language:04x}{encoding:04x}\\{key}", ctypes.byref(pointer), ctypes.byref(length)):
            raise ValueError(f"Missing version attribute {key}: {path}")
        result[key] = ctypes.wstring_at(pointer, max(0, length.value - 1))
    return result


def set_version_info(path: Path, version: str) -> None:
    if os.name != "nt":
        raise OSError("Windows version resources require Windows")
    path = path.resolve(strict=True)
    resource = version_resource(version, path.name)
    overlay = executable_overlay(path.read_bytes())
    api = ctypes.WinDLL("kernel32", use_last_error=True)
    api.BeginUpdateResourceW.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
    api.BeginUpdateResourceW.restype = wintypes.HANDLE
    api.UpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.LPCWSTR, wintypes.LPCWSTR,
                                   wintypes.WORD, wintypes.LPVOID, wintypes.DWORD]
    api.UpdateResourceW.restype = wintypes.BOOL
    api.EndUpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.BOOL]
    api.EndUpdateResourceW.restype = wintypes.BOOL
    with tempfile.TemporaryDirectory(dir=path.parent) as temporary:
        candidate = Path(temporary) / path.name
        shutil.copy2(path, candidate)
        handle = api.BeginUpdateResourceW(str(candidate), False)
        if not handle:
            raise ctypes.WinError(ctypes.get_last_error())
        data = ctypes.create_string_buffer(resource)
        updated = api.UpdateResourceW(handle, ctypes.cast(16, wintypes.LPCWSTR),
                                      ctypes.cast(1, wintypes.LPCWSTR), 0x409, data, len(resource))
        error = ctypes.get_last_error()
        if not api.EndUpdateResourceW(handle, not updated):
            raise ctypes.WinError(ctypes.get_last_error())
        if not updated:
            raise ctypes.WinError(error)
        # Dart executables carry the AOT payload after the PE sections.
        # Windows resource editing may remove this overlay; preserve it exactly.
        current = executable_overlay(candidate.read_bytes())
        if current != overlay:
            if current:
                raise ValueError("Resource editing changed the executable overlay unexpectedly")
            with candidate.open("ab") as output:
                output.write(overlay)
        info = read_version_info(candidate)
        if info["ProductName"] != PRODUCT_NAME or info["ProductVersion"] != version:
            raise ValueError("Windows product metadata verification failed")
        candidate.replace(path)
