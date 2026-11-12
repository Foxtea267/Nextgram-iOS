"""Build zsign's libcrypto in a private Mach-O symbol namespace."""

from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile


PREFIX = "NextgramSigningSSL_"
ARCHIVE_MAGIC = b"!<arch>\n"


def exported_symbols(path):
    output = subprocess.check_output(["xcrun", "nm", "-Ugj", str(path)], text=True)
    return {line[1:] for line in output.splitlines() if re.fullmatch(r"_[A-Za-z0-9_]+", line)}


def prefix_object(original, names):
    data = bytearray(original)
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected a 64-bit Mach-O object")
    command_count, command_size = struct.unpack_from("<II", data, 16)
    position = 32
    for _ in range(command_count):
        command, size = struct.unpack_from("<II", data, position)
        if size < 8 or position + size > 32 + command_size:
            raise ValueError("Invalid Mach-O load commands")
        if command == 2:
            symtab = position
            break
        position += size
    else:
        raise ValueError("Mach-O object is missing its symbol table")

    table, count, strings, length = struct.unpack_from("<IIII", data, symtab + 8)
    if table + count * 16 > len(data) or strings + length > len(data):
        raise ValueError("Invalid Mach-O symbol table")
    string_table = bytearray(data[strings:strings + length])
    new_indices = {}
    for index in range(count):
        entry = table + index * 16
        offset, = struct.unpack_from("<I", data, entry)
        if offset == 0:
            continue
        end = string_table.find(0, offset, length)
        if end < 0:
            raise ValueError("Invalid Mach-O symbol name")
        replacement = names.get(bytes(string_table[offset:end]))
        if replacement is None:
            continue
        if replacement not in new_indices:
            new_indices[replacement] = len(string_table)
            string_table.extend(replacement + b"\0")
        struct.pack_into("<I", data, entry, new_indices[replacement])
    # Relocations refer to symbol indices. Keep the original entries and replace their string table.
    if strings + length == len(data):
        del data[strings:]
    else:
        strings = (len(data) + 7) & ~7
        data.extend(b"\0" * (strings - len(data)))
    struct.pack_into("<II", data, symtab + 16, strings, len(string_table))
    data.extend(string_table)
    return data


def prefix_archive(source, destination, names):
    archive = source.read_bytes()
    if not archive.startswith(ARCHIVE_MAGIC):
        raise ValueError("Expected a thin libcrypto archive")
    position = len(ARCHIVE_MAGIC)
    with destination.open("wb") as result:
        result.write(ARCHIVE_MAGIC)
        while position < len(archive):
            header = archive[position:position + 60]
            if len(header) != 60 or header[-2:] != b"`\n":
                raise ValueError("Invalid libcrypto archive member")
            name_field = header[:16].strip()
            size = int(header[48:58])
            start = position + 60
            end = start + size
            if end > len(archive):
                raise ValueError("Truncated libcrypto archive")
            position = end + (size % 2)
            name_length = int(name_field[3:]) if name_field.startswith(b"#1/") else 0
            filename = archive[start:start + name_length].rstrip(b"\0") if name_length else name_field.rstrip(b"/")
            if filename.startswith(b"__.SYMDEF") or name_field in (b"/", b"//"):
                continue
            member = archive[start:start + name_length] + prefix_object(archive[start + name_length:end], names)
            result.write(header[:48] + f"{len(member):<10}".encode("ascii") + header[58:60])
            result.write(member)
            if len(member) % 2:
                result.write(b"\n")
    subprocess.run(["xcrun", "ranlib", "-D", str(destination)], check=True)


def build(cpu, destination, sources):
    platform = {
        "ios_arm64": ("arm64", "iphoneos"),
        "ios_sim_arm64": ("arm64", "iphonesimulator"),
        "ios_x86_64": ("x86_64", "iphonesimulator"),
    }.get(cpu)
    if platform is None:
        raise ValueError(f"Unsupported signing architecture: {cpu}")
    arch, sdk = platform
    paths = {path.name: path for path in sources}
    destination = destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="nextgram-signing-", dir=destination) as directory:
        workspace = Path(directory)
        stage = workspace / "openssl"
        stage.mkdir()
        for name in ("openssl-1.1.1d.tar.gz", "patch-conf.patch", "patch-include.patch"):
            shutil.copyfile(paths[name], stage / name)
        source = paths["build-openssl-bazel.sh"].read_text()
        command = "make && make install_sw"
        if command not in source:
            raise ValueError("Review the updated OpenSSL builder")
        source = source.replace(command, "make build_libs && make install_dev")
        if arch == "arm64" and sdk == "iphonesimulator":
            source = source.replace("build_for ios64-cross arm64 IOS", "build_for ios64-cross arm64 SIM")
            source = source.replace('./Configure $PLATFORM "-arch $ARCH"', './Configure $PLATFORM "-arch $ARCH" "-target arm64-apple-ios15.0-simulator"')
        builder = workspace / "build.sh"
        builder.write_text(source)
        log = workspace / "build.log"
        with log.open("w") as output:
            status = subprocess.run(["bash", str(builder), "openssl", "openssl", arch], cwd=workspace,
                                    stdout=output, stderr=subprocess.STDOUT)
        if status.returncode:
            print("\n".join(log.read_text(errors="replace").splitlines()[-55:]))
            raise ValueError("Could not build private OpenSSL for the update signer")
        installed = stage / "build" / arch
        archive = installed / "lib" / "libcrypto.a"
        exports = exported_symbols(archive)
        if not {"BN_div", "CMS_sign", "PKCS12_parse"} <= exports:
            raise ValueError("OpenSSL did not provide the signing API")
        mapping = {("_" + name).encode(): ("_" + PREFIX + name).encode() for name in exports}
        private = destination / "libNextgramSigningCrypto.a"
        prefix_archive(archive, private, mapping)
        emitted = exported_symbols(private)
        if not emitted or emitted != {PREFIX + name for name in exports}:
            raise ValueError("Signer OpenSSL exported unexpected symbols")

        includes = destination / "Generated" / "RGUpdateOpenSSL"
        (includes / "openssl").mkdir(parents=True, exist_ok=True)
        macros = ["#pragma once", *(f"#define {name} {PREFIX}{name}" for name in sorted(exports))]
        (includes / "Symbols.h").write_text("\n".join(macros) + "\n")
        for header in (installed / "include" / "openssl").glob("*.h"):
            content = re.sub(r'(#\s*include\s*[<"])openssl/', r'\1RGUpdateOpenSSL/openssl/', header.read_text())
            (includes / "openssl" / header.name).write_text("#include <RGUpdateOpenSSL/Symbols.h>\n" + content)
        shutil.copyfile(stage / "openssl-1.1.1d" / "LICENSE", destination / "Nextgram-OpenSSL-LICENSE.txt")


if __name__ == "__main__":
    build(sys.argv[1], Path(sys.argv[2]), [Path(value) for value in sys.argv[3:]])
