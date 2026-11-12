load("@rules_cc//cc:cc_library.bzl", "cc_library")
load("@rules_cc//cc:objc_library.bzl", "objc_library")
_openssl_headers = [
    "asn1.h", "asn1err.h", "bio.h", "bioerr.h", "bn.h", "bnerr.h", "buffer.h", "buffererr.h",
    "cms.h", "cmserr.h", "conf.h", "conferr.h", "crypto.h", "cryptoerr.h", "dh.h", "dherr.h",
    "dsa.h", "dsaerr.h", "e_os2.h", "ebcdic.h", "ec.h", "ecerr.h", "err.h", "evp.h", "evperr.h",
    "lhash.h", "obj_mac.h", "objects.h", "objectserr.h", "opensslconf.h", "opensslv.h", "ossl_typ.h",
    "pem.h", "pemerr.h", "pkcs12.h", "pkcs12err.h", "pkcs7.h", "pkcs7err.h", "rsa.h", "rsaerr.h",
    "safestack.h", "sha.h", "stack.h", "symhacks.h", "x509.h", "x509_vfy.h", "x509err.h", "x509v3.h",
    "x509v3err.h",
]
_headers = ["Generated/RGUpdateOpenSSL/openssl/" + name for name in _openssl_headers]

genrule(
    name = "build_signing_crypto",
    srcs = [
        "//submodules/openssl:build-openssl-bazel.sh",
        "//submodules/openssl:openssl-1.1.1d.tar.gz",
        "//submodules/openssl:patch-conf.patch",
        "//submodules/openssl:patch-include.patch",
    ],
    tools = ["build_signing_crypto.py"],
    outs = ["libNextgramSigningCrypto.a", "Generated/RGUpdateOpenSSL/Symbols.h", "Nextgram-OpenSSL-LICENSE.txt"] + _headers,
    cmd = "python3 $(location build_signing_crypto.py) '$(TARGET_CPU)' '$(RULEDIR)' $(SRCS)",
)

cc_library(
    name = "SigningCrypto",
    srcs = [":libNextgramSigningCrypto.a"],
    hdrs = ["Generated/RGUpdateOpenSSL/Symbols.h"] + _headers,
    includes = ["Generated"],
)

objc_library(
    name = "NextgramUpdateSigner",
    module_name = "NextgramUpdateSigner",
    enable_modules = True,
    srcs = ["SignIPA.mm"] + glob(["Vendor/zsign/**/*.cpp", "Vendor/zsign/**/*.h"]),
    hdrs = ["SignIPA.h"],
    includes = ["Vendor/zsign", "Vendor/zsign/common"],
    copts = ["-std=c++17", "-Wno-deprecated-declarations"],
    sdk_frameworks = ["Foundation"],
    deps = [":SigningCrypto", "//third-party/ZipArchive:ZipArchive"],
    visibility = ["//Nagram/Update:__pkg__"],
)

genrule(
    name = "zsign_license",
    srcs = ["Vendor/zsign/LICENSE"],
    outs = ["Nextgram-zsign-LICENSE.txt"],
    cmd = "cp $< $@",
)

filegroup(
    name = "Notices",
    srcs = [":Nextgram-zsign-LICENSE.txt", ":Nextgram-OpenSSL-LICENSE.txt"],
    visibility = ["//Telegram:__pkg__"],
)
