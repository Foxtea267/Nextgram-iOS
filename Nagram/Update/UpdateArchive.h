#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSDictionary<NSString *, id> * _Nullable NextgramUpdateReadAppInfo(NSString *archivePath, NSString *scratchPath);
NSDictionary<NSString *, NSData *> * _Nullable NextgramUpdateReadSigningArchive(NSString *archivePath);

NS_ASSUME_NONNULL_END
