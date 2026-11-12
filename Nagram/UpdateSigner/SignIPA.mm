#import "SignIPA.h"
#import <ZipArchive/ZipArchive.h>

#include "bundle.h"
#include <RGUpdateOpenSSL/openssl/cms.h>
#include <RGUpdateOpenSSL/openssl/pkcs12.h>
#include <list>
#include <memory>
#include <mutex>

static NSError *SigningError(NSInteger code, NSString *reason) {
    return [NSError errorWithDomain:@"Nextgram.UpdateSigner" code:code userInfo:@{NSLocalizedDescriptionKey: reason}];
}

static uint32_t ReadWord(NSData *data, NSUInteger offset, bool bigEndian) {
    uint32_t value;
    memcpy(&value, (const uint8_t *)data.bytes + offset, sizeof(value));
    return bigEndian ? CFSwapInt32BigToHost(value) : CFSwapInt32LittleToHost(value);
}

static NSData *ReadSigningSlot(NSString *path, uint32_t slot, uint32_t expectedMagic) {
    NSData *binary = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:NULL];
    // CI device IPAs contain a thin arm64 Mach-O. Stop on an unknown executable layout.
    if (binary.length < 32 || ReadWord(binary, 0, false) != 0xfeedfacf) {
        return nil;
    }
    NSUInteger commandsSize = ReadWord(binary, 20, false);
    if (commandsSize > binary.length - 32) {
        return nil;
    }
    NSUInteger offset = 32;
    NSUInteger end = offset + commandsSize;
    for (uint32_t i = 0, count = ReadWord(binary, 16, false); i < count && end - offset >= 8; i++) {
        uint32_t command = ReadWord(binary, offset, false);
        NSUInteger size = ReadWord(binary, offset + 4, false);
        if (size < 8 || size > end - offset) {
            return nil;
        }
        if (command != 0x1d) {
            offset += size;
            continue;
        }
        if (size != 16) {
            return nil;
        }
        NSUInteger signature = ReadWord(binary, offset + 8, false);
        NSUInteger signatureSize = ReadWord(binary, offset + 12, false);
        if (signature > binary.length || signatureSize > binary.length - signature || signatureSize < 12 ||
            ReadWord(binary, signature, true) != 0xfade0cc0) {
            return nil;
        }
        NSUInteger blobSize = ReadWord(binary, signature + 4, true);
        NSUInteger slots = ReadWord(binary, signature + 8, true);
        if (blobSize < 12 || blobSize > signatureSize || slots > (blobSize - 12) / 8) {
            return nil;
        }
        for (NSUInteger j = 0; j < slots; j++) {
            NSUInteger index = signature + 12 + j * 8;
            if (ReadWord(binary, index, true) != slot) {
                continue;
            }
            NSUInteger relative = ReadWord(binary, index + 4, true);
            if (relative < 12 + slots * 8 || relative > blobSize - 8) {
                return nil;
            }
            NSUInteger start = signature + relative;
            NSUInteger length = ReadWord(binary, start + 4, true);
            if (ReadWord(binary, start, true) != expectedMagic || length < 8 || length > blobSize - relative) {
                return nil;
            }
            return [binary subdataWithRange:NSMakeRange(start + 8, length - 8)];
        }
        return nil;
    }
    return nil;
}

static BOOL MatchesInstalledCertificate(NSString *executable, X509 *certificate) {
    NSData *data = ReadSigningSlot(executable, 0x10000, 0xfade0b01);
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    CMS_ContentInfo *cms = data ? d2i_CMS_ContentInfo(NULL, &bytes, data.length) : NULL;
    if (!cms) {
        return NO;
    }
    STACK_OF(CMS_SignerInfo) *signers = CMS_get0_SignerInfos(cms);
    BOOL matches = signers && sk_CMS_SignerInfo_num(signers) == 1 &&
        CMS_SignerInfo_cert_cmp(sk_CMS_SignerInfo_value(signers, 0), certificate) == 0;
    if (matches) {
        matches = NO;
        STACK_OF(X509) *embedded = CMS_get1_certs(cms);
        for (int i = 0; embedded && i < sk_X509_num(embedded); i++) {
            if (X509_cmp(sk_X509_value(embedded, i), certificate) == 0) {
                matches = YES;
                break;
            }
        }
        sk_X509_pop_free(embedded, X509_free);
    }
    CMS_ContentInfo_free(cms);
    return matches;
}

static NSDictionary *ReadDictionary(NSData *data) {
    id object = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL] : nil;
    return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

static NSDictionary *ReadProfile(NSData *data) {
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    CMS_ContentInfo *cms = d2i_CMS_ContentInfo(NULL, &bytes, data.length);
    if (!cms) {
        return nil;
    }
    ASN1_OCTET_STRING **content = CMS_get0_content(cms);
    NSDictionary *profile = nil;
    if (content && *content && ASN1_STRING_length(*content) > 0) {
        profile = ReadDictionary([NSData dataWithBytes:ASN1_STRING_get0_data(*content) length:ASN1_STRING_length(*content)]);
    }
    CMS_ContentInfo_free(cms);
    return profile;
}

static BOOL ProfileAllows(id entitlement, id permission) {
    if ([entitlement isEqual:permission]) {
        return YES;
    }
    if ([entitlement isKindOfClass:NSString.class] && [permission isKindOfClass:NSString.class] && [permission hasSuffix:@"*"]) {
        return [entitlement hasPrefix:[permission substringToIndex:[permission length] - 1]];
    }
    if ([entitlement isKindOfClass:NSArray.class] && [permission isKindOfClass:NSArray.class]) {
        for (id value in entitlement) {
            BOOL found = NO;
            for (id allowed in permission) {
                if (ProfileAllows(value, allowed)) {
                    found = YES;
                    break;
                }
            }
            if (!found) {
                return NO;
            }
        }
        return YES;
    }
    if ([entitlement isKindOfClass:NSDictionary.class] && [permission isKindOfClass:NSDictionary.class]) {
        for (NSString *key in entitlement) {
            if (!ProfileAllows(entitlement[key], permission[key])) {
                return NO;
            }
        }
        return YES;
    }
    return !permission && entitlement && CFGetTypeID((__bridge CFTypeRef)entitlement) == CFBooleanGetTypeID() && ![entitlement boolValue];
}

static NSDictionary<NSString *, NSBundle *> *SigningTargets(NSString *appPath) {
    NSBundle *app = [NSBundle bundleWithPath:appPath];
    if (!app.bundleIdentifier || !app.executablePath) {
        return nil;
    }
    NSMutableDictionary *targets = [NSMutableDictionary dictionaryWithObject:app forKey:app.bundleIdentifier];
    NSString *extensionsPath = [appPath stringByAppendingPathComponent:@"PlugIns"];
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:extensionsPath error:NULL]) {
        if (![name hasSuffix:@".appex"]) {
            return nil;
        }
        NSBundle *extension = [NSBundle bundleWithPath:[extensionsPath stringByAppendingPathComponent:name]];
        if (!extension.bundleIdentifier || !extension.executablePath || targets[extension.bundleIdentifier]) {
            return nil;
        }
        targets[extension.bundleIdentifier] = extension;
    }
    return targets;
}

static NSData *MatchingProfile(NSArray<NSData *> *profiles, NSData *certificate, NSDictionary *entitlements) {
    for (NSData *data in profiles) {
        NSDictionary *profile = ReadProfile(data);
        id date = profile[@"ExpirationDate"];
        id certificates = profile[@"DeveloperCertificates"];
        id permissions = profile[@"Entitlements"];
        if ([date isKindOfClass:NSDate.class] && [date timeIntervalSinceNow] > 0 &&
            [certificates isKindOfClass:NSArray.class] && [certificates containsObject:certificate] &&
            [permissions isKindOfClass:NSDictionary.class] && ProfileAllows(entitlements, permissions)) {
            return data;
        }
    }
    return nil;
}

NSError *NextgramSignUpdateIPA(NSString *source, NSString *destination, NSString *installedApp,
    NSString *scratch, NSString *version, NSData *certificate, NSString *password, NSArray<NSData *> *profiles) {
    static std::mutex lock;
    std::lock_guard<std::mutex> signing(lock);
    NSFileManager *files = NSFileManager.defaultManager;
    NSError *error = nil;
    NSString *archiveRoot = [scratch stringByAppendingPathComponent:@"archive"];
    NSString *payload = [archiveRoot stringByAppendingPathComponent:@"Payload"];
    if (![files createDirectoryAtPath:archiveRoot withIntermediateDirectories:NO attributes:nil error:&error]) {
        return error;
    }
    if (![SSZipArchive unzipFileAtPath:source toDestination:archiveRoot]) {
        return SigningError(1, @"Could not extract the verified IPA.");
    }
    NSArray<NSString *> *children = [files contentsOfDirectoryAtPath:payload error:NULL];
    if (children.count != 1 || ![children.firstObject hasSuffix:@".app"]) {
        return SigningError(1, @"The IPA has an unexpected application layout.");
    }
    NSString *app = [payload stringByAppendingPathComponent:children.firstObject];
    NSDictionary<NSString *, NSBundle *> *installed = SigningTargets(installedApp);
    NSDictionary<NSString *, NSBundle *> *candidate = SigningTargets(app);
    NSBundle *main = [NSBundle bundleWithPath:app];
    if (!installed || !candidate || ![[NSSet setWithArray:installed.allKeys] isEqualToSet:[NSSet setWithArray:candidate.allKeys]] ||
        ![main.bundleIdentifier isEqualToString:[NSBundle bundleWithPath:installedApp].bundleIdentifier] ||
        ![[main objectForInfoDictionaryKey:@"NextgramVersion"] isEqual:version]) {
        return SigningError(2, @"The IPA application or extension identities differ from the installed version.");
    }

    const unsigned char *bytes = (const unsigned char *)certificate.bytes;
    PKCS12 *p12 = d2i_PKCS12(NULL, &bytes, certificate.length);
    EVP_PKEY *key = NULL;
    X509 *signingCertificate = NULL;
    BOOL parsed = p12 && PKCS12_parse(p12, password.UTF8String, &key, &signingCertificate, NULL);
    PKCS12_free(p12);
    EVP_PKEY_free(key);
    if (!parsed || !signingCertificate || X509_cmp_current_time(X509_get0_notBefore(signingCertificate)) >= 0 ||
        X509_cmp_current_time(X509_get0_notAfter(signingCertificate)) <= 0) {
        X509_free(signingCertificate);
        return SigningError(3, @"The signing certificate cannot be opened or is outside its validity period.");
    }
    std::unique_ptr<X509, decltype(&X509_free)> cert(signingCertificate, X509_free);
    unsigned char *encoded = NULL;
    int length = i2d_X509(cert.get(), &encoded);
    NSData *certData = length > 0 ? [NSData dataWithBytes:encoded length:length] : nil;
    OPENSSL_free(encoded);
    if (!certData) {
        return SigningError(3, @"Could not read the signing certificate.");
    }
    NSString *keyPath = [scratch stringByAppendingPathComponent:@"signing.p12"];
    if (![certificate writeToFile:keyPath options:NSDataWritingFileProtectionComplete error:&error]) {
        return error;
    }
    std::list<ZSignAsset> assets;
    NSMutableDictionary<NSString *, NSDictionary *> *expectedEntitlements = [NSMutableDictionary dictionary];
    for (NSString *identifier in installed) {
        NSBundle *original = installed[identifier];
        NSBundle *update = candidate[identifier];
        if (![(original.infoDictionary[@"CFBundleURLTypes"] ?: @[]) isEqual:(update.infoDictionary[@"CFBundleURLTypes"] ?: @[])]) {
            return SigningError(2, [NSString stringWithFormat:@"URL schemes changed for %@.", identifier]);
        }
        NSDictionary *entitlements = ReadDictionary(ReadSigningSlot(original.executablePath, 5, 0xfade7171));
        NSString *applicationID = entitlements[@"application-identifier"];
        if (![applicationID isKindOfClass:NSString.class] || ![applicationID hasSuffix:[@"." stringByAppendingString:identifier]] ||
            !MatchesInstalledCertificate(original.executablePath, cert.get())) {
            return SigningError(3, [NSString stringWithFormat:@"The signing identity does not match %@.", identifier]);
        }
        NSData *embedded = [NSData dataWithContentsOfFile:[original.bundlePath stringByAppendingPathComponent:@"embedded.mobileprovision"]];
        NSArray<NSData *> *choices = embedded ? [profiles arrayByAddingObject:embedded] : profiles;
        NSData *profile = MatchingProfile(choices, certData, entitlements);
        if (!profile) {
            return SigningError(4, [NSString stringWithFormat:@"No unexpired profile authorizes all permissions for %@.", identifier]);
        }
        expectedEntitlements[identifier] = entitlements;
        NSString *prefix = [scratch stringByAppendingPathComponent:identifier];
        NSString *profilePath = [prefix stringByAppendingPathExtension:@"mobileprovision"];
        NSString *entitlementsPath = [prefix stringByAppendingPathExtension:@"plist"];
        NSData *xml = [NSPropertyListSerialization dataWithPropertyList:entitlements format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        if (!xml || ![profile writeToFile:profilePath options:NSDataWritingFileProtectionComplete error:&error] ||
            ![xml writeToFile:entitlementsPath options:NSDataWritingFileProtectionComplete error:&error]) {
            return error ?: SigningError(5, @"Could not write the signing inputs.");
        }
        if ([identifier isEqualToString:main.bundleIdentifier]) {
            assets.emplace_front();
        } else {
            assets.emplace_back();
        }
        ZSignAsset &asset = [identifier isEqualToString:main.bundleIdentifier] ? assets.front() : assets.back();
        if (!asset.Init("", keyPath.UTF8String, profilePath.UTF8String, entitlementsPath.UTF8String, password.UTF8String, false, false, false)) {
            return SigningError(5, [NSString stringWithFormat:@"Could not prepare signing for %@.", identifier]);
        }
        asset.m_strApplicationId = applicationID.UTF8String;
    }
    ZBundle signer;
    if (!signer.SignFolder(&assets, app.UTF8String, "", "", "", {}, {}, true, false, false)) {
        return SigningError(5, @"zsign could not sign the application and its nested code.");
    }
    for (NSString *identifier in candidate) {
        NSString *executable = candidate[identifier].executablePath;
        NSDictionary *entitlements = ReadDictionary(ReadSigningSlot(executable, 5, 0xfade7171));
        if (![entitlements isEqual:expectedEntitlements[identifier]] || !MatchesInstalledCertificate(executable, cert.get())) {
            return SigningError(5, [NSString stringWithFormat:@"Could not verify the new signature for %@.", identifier]);
        }
    }
    if (![SSZipArchive createZipFileAtPath:destination withContentsOfDirectory:archiveRoot]) {
        return SigningError(6, @"Could not package the signed IPA.");
    }
    return nil;
}
