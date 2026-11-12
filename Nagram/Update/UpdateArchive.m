#import "UpdateArchive.h"
#import <ZipArchive/ZipArchive.h>

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
