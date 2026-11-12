#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

NSError * _Nullable NextgramSignUpdateIPA(NSString *source, NSString *destination, NSString *installedApp,
    NSString *scratch, NSString *version, NSData *certificate, NSString *password, NSArray<NSData *> *profiles);

NS_ASSUME_NONNULL_END
