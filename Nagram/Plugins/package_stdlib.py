import sys
from pathlib import Path
from zipfile import ZIP_STORED, ZipFile, ZipInfo


def package(output, files):
    with ZipFile(output, "w", compression=ZIP_STORED) as archive:
        for filename in sorted(files):
            source = Path(filename)
            name = source.as_posix().split("/python3.11/", 1)[1]
            archive.writestr(ZipInfo(name), source.read_bytes())
        if "encodings/__init__.py" not in archive.namelist():
            raise ValueError("Python 3.11 standard library is missing encodings")


if __name__ == "__main__":
    package(sys.argv[1], sys.argv[2:])
