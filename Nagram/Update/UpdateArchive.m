#import "UpdateArchive.h"
#import <ZipArchive/ZipArchive.h>
#include "third-party/ZipArchive/Sources/minizip/mz_compat.h"
#include <sys/stat.h>

static NSDictionary<NSString *, NSData *> *ReadSigningEntries(unzFile zip) {
    unz_global_info64 global = {0};
    if (unzGetGlobalInfo64(zip, &global) != UNZ_OK || global.number_entry == 0 || global.number_entry > 256 ||
        unzGoToFirstFile(zip) != UNZ_OK) { return nil; }
    NSMutableDictionary<NSString *, NSData *> *files = [NSMutableDictionary dictionary];
    const NSUInteger limit = 4 * 1024 * 1024;
    NSUInteger total = 0;
    for (NSUInteger index = 0; index < global.number_entry; index++) {
        if (index != 0 && unzGoToNextFile(zip) != UNZ_OK) { return nil; }
        unz_file_info64 entry = {0};
        char pathBytes[1024] = {0};
        if (unzGetCurrentFileInfo64(zip, &entry, pathBytes, sizeof(pathBytes), NULL, 0, NULL, 0) != UNZ_OK ||
            entry.size_filename == 0 || entry.size_filename >= sizeof(pathBytes)) { return nil; }
        NSString *path = [[NSString alloc] initWithBytes:pathBytes length:entry.size_filename encoding:NSUTF8StringEncoding];
        if (path == nil || [path hasPrefix:@"__MACOSX/"] || [path hasSuffix:@"/"]) { continue; }
        NSString *name = path.lastPathComponent;
        NSString *extension = name.pathExtension.lowercaseString;
        if ([name hasPrefix:@"."] ||
            ![@[@"p12", @"pfx", @"mobileprovision"] containsObject:extension]) { continue; }
        if (files.count >= 16 || files[name] != nil || entry.uncompressed_size == 0 ||
            entry.uncompressed_size > limit - total || (entry.flag & 1) != 0 ||
            S_ISLNK(entry.external_fa >> 16) || unzOpenCurrentFile(zip) != UNZ_OK) { return nil; }
        NSMutableData *data = [NSMutableData data];
        uint8_t buffer[4096];
        int count;
        while ((count = unzReadCurrentFile(zip, buffer, sizeof(buffer))) > 0) {
            if ((NSUInteger)count > entry.uncompressed_size - data.length) {
                unzCloseCurrentFile(zip);
                return nil;
            }
            [data appendBytes:buffer length:(NSUInteger)count];
        }
        int closed = unzCloseCurrentFile(zip);
        if (count < 0 || closed != UNZ_OK || data.length != entry.uncompressed_size) { return nil; }
        files[name] = data;
        total += data.length;
    }
    return files.count > 0 ? files : nil;
}

NSDictionary<NSString *, NSData *> *NextgramUpdateReadSigningArchive(NSString *archivePath) {
    unzFile zip = unzOpen(archivePath.fileSystemRepresentation);
    if (zip == NULL) { return nil; }
    NSDictionary<NSString *, NSData *> *files = ReadSigningEntries(zip);
    unzClose(zip);
    return files;
}

NSDictionary<NSString *, id> *NextgramUpdateReadAppInfo(NSString *archivePath, NSString *scratchPath) {
    NSArray<SSZipEntry *> *entries = [SSZipArchive getEntriesForFileAtPath:archivePath];
    NSMutableSet<NSString *> *appNames = [NSMutableSet set];
    SSZipEntry *infoEntry = nil;
    for (SSZipEntry *entry in entries) {
        NSArray<NSString *> *parts = [entry.path componentsSeparatedByString:@"/"];
        if (parts.count < 2 || ![parts[0] isEqualToString:@"Payload"] || ![parts[1] hasSuffix:@".app"]) {
            continue;
        }
        [appNames addObject:parts[1]];
        if (parts.count == 3 && [parts[2] isEqualToString:@"Info.plist"]) {
            if (infoEntry != nil) {
                return nil;
            }
            infoEntry = entry;
        }
    }
    if (appNames.count != 1 || infoEntry == nil || infoEntry.uncompressedSize == 0 ||
        infoEntry.uncompressedSize > 512 * 1024) {
        return nil;
    }
    // Read only the root application's plist into a private, fixed destination.
    if (![SSZipArchive extractFileFromArchiveAtPath:archivePath filePath:infoEntry.path toPath:scratchPath]) {
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfFile:scratchPath];
    if (data == nil || data.length != infoEntry.uncompressedSize) {
        return nil;
    }
    id plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    if (![plist isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id executable = plist[@"CFBundleExecutable"];
    if (![executable isKindOfClass:[NSString class]] || [executable length] == 0 ||
        [executable containsString:@"/"] || [executable containsString:@"\\"] ||
        [executable isEqualToString:@"."] || [executable isEqualToString:@".."]) {
        return nil;
    }
    NSString *executablePath = [[infoEntry.path stringByDeletingLastPathComponent] stringByAppendingPathComponent:executable];
    NSUInteger executableCount = 0;
    for (SSZipEntry *entry in entries) {
        if ([entry.path isEqualToString:executablePath] && entry.uncompressedSize > 0) {
            executableCount++;
        }
    }
    return executableCount == 1 ? plist : nil;
}
