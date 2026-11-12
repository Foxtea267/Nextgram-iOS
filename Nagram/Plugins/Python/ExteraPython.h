#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The implementation is linked into the main application, not TelegramUI or extensions.
@protocol NagramExteraPythonHost
// Called only on the plugin engine's serial worker, never on the UI thread.
+ (NSString *)runWithStdlibPath:(NSString *)stdlibPath
                    bootstrap:(NSString *)bootstrap
                      request:(NSString *)request NS_SWIFT_NAME(run(stdlibPath:bootstrap:request:));
@end

NS_ASSUME_NONNULL_END
