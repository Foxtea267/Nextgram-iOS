 
load("@rules_cc//cc:objc_library.bzl", "objc_library")

# MARK: NEXTGRAM
filegroup(
    name = "nextgram_minizip_headers",
    srcs = ["Sources/minizip/mz.h", "Sources/minizip/mz_compat.h"],
    visibility = ["//Nagram/Update:__pkg__"],
)

objc_library(
    name = "ZipArchive",
    enable_modules = True,
    module_name = "ZipArchive",
    srcs = glob([
        "Sources/*.m",
        "Sources/minizip/*.h",
        "Sources/minizip/*.c",
    ]),
    hdrs = glob([
        "PublicHeaders/**/*.h",
    ]),
    includes = [
      "PublicHeaders",
    ],
    copts = [
        "-DHAVE_ZLIB",
        "-DHAVE_INTTYPES_H",
        "-DHAVE_PKCRYPT",
        "-DHAVE_STDINT_H",
        "-DHAVE_WZAES",
    ],
    sdk_frameworks = [
      "Foundation",
    ],
    visibility = [
        "//visibility:public",
    ],
)
