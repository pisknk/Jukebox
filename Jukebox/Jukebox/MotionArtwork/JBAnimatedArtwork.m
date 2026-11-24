// Ported from pisknk/deezit (DZLockArtwork.x): the parts that create the
// iOS 26 animated now-playing artwork. Jukebox sets its own now-playing info,
// so no hooking is needed.

#import "JBAnimatedArtwork.h"
#import "JBMotionFile.h"
#import "JBLog.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <dlfcn.h>

typedef void (^JBImageDone)(UIImage *image);
typedef void (^JBURLDone)(NSURL *url);

static NSString *constantNamed(const char *name) {
    NSString *__unsafe_unretained *p = (NSString *__unsafe_unretained *)dlsym(RTLD_DEFAULT, name);
    return p ? *p : nil;
}

BOOL JBAnimatedArtworkAvailable(void) {
    return NSClassFromString(@"MPMediaItemAnimatedArtwork") &&
           [MPNowPlayingInfoCenter respondsToSelector:NSSelectorFromString(@"supportedAnimatedArtworkKeys")];
}

NSString *JBAnimatedArtworkKey3x4(void) {
    static NSString *key;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!JBAnimatedArtworkAvailable()) return;
        id keys = ((id (*)(id, SEL))objc_msgSend)([MPNowPlayingInfoCenter class], NSSelectorFromString(@"supportedAnimatedArtworkKeys"));
        NSString *k3 = constantNamed("MPNowPlayingInfoProperty3x4AnimatedArtwork");
        for (id candidate in [keys isKindOfClass:[NSArray class]] || [keys isKindOfClass:[NSSet class]] ? keys : @[]) {
            if (![candidate isKindOfClass:[NSString class]]) continue;
            if ([candidate isEqualToString:k3 ?: @""] || [candidate containsString:@"3x4"]) { key = candidate; break; }
        }
        JBLog("animated artwork: 3:4 key %@", key ?: @"not offered");
    });
    return key;
}

id JBMakeAnimatedArtwork(NSString *artworkID, NSURL *file, MPMediaItemArtwork *still) {
    Class cls = NSClassFromString(@"MPMediaItemAnimatedArtwork");
    SEL init = NSSelectorFromString(@"initWithArtworkID:previewImageRequestHandler:videoAssetFileURLRequestHandler:");
    if (!cls || ![cls instancesRespondToSelector:init]) return nil;
    void (^preview)(CGSize, JBImageDone) = ^(CGSize size, JBImageDone done) {
        JBMotionPreview(file, size, ^(UIImage *image) {
            done(image ?: [still imageWithSize:size]);
        });
    };
    void (^video)(CGSize, JBURLDone) = ^(CGSize size, JBURLDone done) {
        done(file);
    };
    @try {
        return ((id (*)(id, SEL, NSString *, id, id))objc_msgSend)([cls alloc], init, artworkID, preview, video);
    } @catch (NSException *ex) {
        JBLog("animated artwork: MPMediaItemAnimatedArtwork refused: %@", ex.reason);
        return nil;
    }
}
