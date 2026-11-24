// Copied from pisknk/deezit (DZMotionFile.m).
#import "JBMotionFile.h"
#import "JBLog.h"
#import <AVFoundation/AVFoundation.h>
#import <float.h>

static const unsigned long long kJBMotionCacheCap = 150ull * 1024 * 1024;
static const double kJBTargetWidth = 1100;

static NSURL *cacheDir(void) {
    NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *dir = [caches URLByAppendingPathComponent:@"Jukebox/motion" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

NSURL *JBMotionCacheDirectory(void) {
    return cacheDir();
}

// Oldest files go first until the folder fits the cap again.
static void trimCache(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray<NSURLResourceKey> *keys = @[NSURLContentModificationDateKey, NSURLFileSizeKey];
    NSArray<NSURL *> *files = [fm contentsOfDirectoryAtURL:cacheDir() includingPropertiesForKeys:keys options:0 error:nil];
    unsigned long long total = 0;
    for (NSURL *f in files) total += [[f resourceValuesForKeys:keys error:nil][NSURLFileSizeKey] unsignedLongLongValue];
    if (total <= kJBMotionCacheCap) return;
    NSArray *oldestFirst = [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        NSDate *da = [a resourceValuesForKeys:keys error:nil][NSURLContentModificationDateKey] ?: NSDate.distantPast;
        NSDate *db = [b resourceValuesForKeys:keys error:nil][NSURLContentModificationDateKey] ?: NSDate.distantPast;
        return [da compare:db];
    }];
    for (NSURL *f in oldestFirst) {
        if (total <= kJBMotionCacheCap) break;
        total -= [[f resourceValuesForKeys:keys error:nil][NSURLFileSizeKey] unsignedLongLongValue];
        [fm removeItemAtURL:f error:nil];
    }
}

static void fetchText(NSURL *url, void (^done)(NSString *text)) {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = 10;
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        done(!err && status == 200 && data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil);
    }] resume];
}

static NSArray<NSString *> *playlistLines(NSString *text) {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *raw in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
        NSString *l = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (l.length) [out addObject:l];
    }
    return out;
}

static NSString *attribute(NSString *attrs, NSString *name) {
    NSString *pattern = [NSString stringWithFormat:@"(?:^|,)%@=(\"[^\"]*\"|[^,]*)", name];
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:attrs options:0 range:NSMakeRange(0, attrs.length)];
    if (!m) return nil;
    NSString *v = [attrs substringWithRange:[m rangeAtIndex:1]];
    return [v hasPrefix:@"\""] && v.length >= 2 ? [v substringWithRange:NSMakeRange(1, v.length - 2)] : v;
}

// The variant closest to ~1100 px wide; HEVC wins a tie. nil when the master
// is already a media playlist.
static NSURL *pickVariant(NSString *master, NSURL *base, NSString *__strong *note) {
    NSArray<NSString *> *lines = playlistLines(master);
    NSURL *best = nil;
    double bestScore = DBL_MAX;
    for (NSUInteger i = 0; i < lines.count; i++) {
        if (![lines[i] hasPrefix:@"#EXT-X-STREAM-INF:"]) continue;
        NSString *attrs = [lines[i] substringFromIndex:@"#EXT-X-STREAM-INF:".length];
        NSString *uri = nil;
        for (NSUInteger j = i + 1; j < lines.count; j++) {
            if (![lines[j] hasPrefix:@"#"]) { uri = lines[j]; break; }
        }
        if (!uri) continue;
        NSArray *res = [attribute(attrs, @"RESOLUTION") componentsSeparatedByString:@"x"];
        double width = res.count == 2 ? [res[0] doubleValue] : 0;
        NSString *codecs = attribute(attrs, @"CODECS") ?: @"";
        BOOL hevc = [codecs containsString:@"hvc1"] || [codecs containsString:@"hev1"];
        double score = (width > 0 ? fabs(width - kJBTargetWidth) : 5000) + (hevc ? 0 : 1);
        if (score < bestScore) {
            bestScore = score;
            best = [NSURL URLWithString:uri relativeToURL:base].absoluteURL;
            *note = [NSString stringWithFormat:@"%.0f px %@", width, hevc ? @"HEVC" : @"H.264"];
        }
    }
    return best;
}

typedef struct { long long offset, length; } JBRange;   // length < 0 = whole resource

// (url, range) pieces of a media playlist: the EXT-X-MAP init section, then
// every segment in order.
static NSArray<NSArray *> *mediaPieces(NSString *media, NSURL *base) {
    NSMutableArray<NSArray *> *pieces = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSNumber *> *nextOffset = [NSMutableDictionary dictionary];
    NSString *pendingRange = nil;
    for (NSString *l in playlistLines(media)) {
        NSString *uri = nil, *range = nil;
        if ([l hasPrefix:@"#EXT-X-MAP:"]) {
            NSString *attrs = [l substringFromIndex:@"#EXT-X-MAP:".length];
            uri = attribute(attrs, @"URI");
            range = attribute(attrs, @"BYTERANGE");
        } else if ([l hasPrefix:@"#EXT-X-BYTERANGE:"]) {
            pendingRange = [l substringFromIndex:@"#EXT-X-BYTERANGE:".length];
            continue;
        } else if (![l hasPrefix:@"#"]) {
            uri = l;
            range = pendingRange;
            pendingRange = nil;
        }
        if (!uri.length) continue;
        NSURL *url = [NSURL URLWithString:uri relativeToURL:base].absoluteURL;
        if (!url) continue;
        JBRange r = { 0, -1 };
        if (range.length) {
            NSArray *parts = [range componentsSeparatedByString:@"@"];
            r.length = [parts[0] longLongValue];
            r.offset = parts.count > 1 ? [parts[1] longLongValue] : nextOffset[url.absoluteString].longLongValue;
            nextOffset[url.absoluteString] = @(r.offset + r.length);
        }
        [pieces addObject:@[url, [NSValue valueWithBytes:&r objCType:@encode(JBRange)]]];
    }
    return pieces;
}

// Fetches piece `index` (with its byte range), appends it, then the next one.
static void downloadPiece(NSArray<NSArray *> *pieces, NSUInteger index, NSFileHandle *out, NSURL *partial, NSURL *dest,
                          void (^done)(BOOL ok, NSString *note)) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (index >= pieces.count) {
        [out closeFile];
        BOOL ok = [fm moveItemAtURL:partial toURL:dest error:nil];
        done(ok, [NSString stringWithFormat:@"%lu pieces", (unsigned long)pieces.count]);
        return;
    }
    NSArray *p = pieces[index];
    JBRange r;
    [p[1] getValue:&r];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:p[0]];
    req.timeoutInterval = 20;
    if (r.length >= 0) {
        [req setValue:[NSString stringWithFormat:@"bytes=%lld-%lld", r.offset, r.offset + r.length - 1] forHTTPHeaderField:@"Range"];
    }
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        if (err || !data || (status != 200 && status != 206)) {
            [out closeFile];
            [fm removeItemAtURL:partial error:nil];
            done(NO, [NSString stringWithFormat:@"piece %lu failed (HTTP %ld)", (unsigned long)index, (long)status]);
            return;
        }
        [out writeData:data];
        downloadPiece(pieces, index + 1, out, partial, dest, done);
    }] resume];
}

// Downloads the pieces in order into one file. When they are all ranges of the
// same file (Apple's usual layout) that file is simply fetched whole.
static void downloadPieces(NSArray<NSArray *> *pieces, NSURL *dest, void (^done)(BOOL ok, NSString *note)) {
    NSMutableSet *urls = [NSMutableSet set];
    for (NSArray *p in pieces) [urls addObject:p[0]];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *partial = [dest URLByAppendingPathExtension:@"part"];
    [fm removeItemAtURL:partial error:nil];

    if (urls.count == 1) {
        NSURLRequest *req = [NSURLRequest requestWithURL:urls.anyObject cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:30];
        [[NSURLSession.sharedSession downloadTaskWithRequest:req completionHandler:^(NSURL *tmp, NSURLResponse *resp, NSError *err) {
            NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
            BOOL ok = tmp && !err && status == 200 && [fm moveItemAtURL:tmp toURL:partial error:nil] &&
                      [fm moveItemAtURL:partial toURL:dest error:nil];
            done(ok, ok ? @"one file" : [NSString stringWithFormat:@"download failed (HTTP %ld %@)", (long)status, err.localizedDescription ?: @""]);
        }] resume];
        return;
    }

    [NSData.data writeToURL:partial atomically:NO];
    NSFileHandle *out = [NSFileHandle fileHandleForWritingToURL:partial error:nil];
    if (!out) { done(NO, @"can't write the cache file"); return; }
    downloadPiece(pieces, 0, out, partial, dest, done);
}

void JBMotionFile(NSURL *master, NSString *name, void (^done)(NSURL *file, NSString *note)) {
    static dispatch_queue_t q;
    static NSMutableDictionary<NSString *, NSMutableArray *> *waiting;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("ph.neilbayron.jukebox.motionfile", DISPATCH_QUEUE_SERIAL);
        waiting = [NSMutableDictionary dictionary];
    });
    NSString *safe = [[name componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]
                      componentsJoinedByString:@"-"];
    NSURL *dest = [cacheDir() URLByAppendingPathComponent:[safe stringByAppendingPathExtension:@"mp4"]];

    dispatch_async(q, ^{
        if ([NSFileManager.defaultManager fileExistsAtPath:dest.path]) {
            [NSFileManager.defaultManager setAttributes:@{ NSFileModificationDate: NSDate.date } ofItemAtPath:dest.path error:nil];
            done(dest, @"cached");
            return;
        }
        if (waiting[safe]) { [waiting[safe] addObject:[done copy]]; return; }
        waiting[safe] = [NSMutableArray arrayWithObject:[done copy]];

        void (^finish)(NSURL *, NSString *) = ^(NSURL *file, NSString *note) {
            dispatch_async(q, ^{
                if (file) trimCache();
                NSArray *callbacks = waiting[safe];
                [waiting removeObjectForKey:safe];
                for (void (^cb)(NSURL *, NSString *) in callbacks) cb(file, note);
            });
        };
        fetchText(master, ^(NSString *masterText) {
            if (!masterText) { finish(nil, @"master playlist failed"); return; }
            NSString *variantNote = @"single playlist";
            NSURL *variant = pickVariant(masterText, master, &variantNote);
            void (^withMedia)(NSString *, NSURL *) = ^(NSString *media, NSURL *mediaURL) {
                NSArray *pieces = media ? mediaPieces(media, mediaURL) : @[];
                if (!pieces.count) { finish(nil, @"media playlist empty or failed"); return; }
                downloadPieces(pieces, dest, ^(BOOL ok, NSString *how) {
                    finish(ok ? dest : nil, [NSString stringWithFormat:@"%@, %@", variantNote, how]);
                });
            };
            if (!variant) { withMedia(masterText, master); return; }
            fetchText(variant, ^(NSString *media) { withMedia(media, variant); });
        });
    });
}

// Centre-crops a square clip to 3:4 (full height, sides trimmed).
static void cropTo3x4(NSURL *src, NSURL *dest, void (^done)(BOOL ok, NSString *note)) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:src options:nil];
    [asset loadTracksWithMediaType:AVMediaTypeVideo completionHandler:^(NSArray<AVAssetTrack *> *tracks, NSError *err) {
        AVAssetTrack *track = tracks.firstObject;
        if (!track) { done(NO, [NSString stringWithFormat:@"no video track (%@)", err.localizedDescription ?: @"?"]); return; }
        CGSize size = track.naturalSize;
        CGFloat height = floor(size.height / 2) * 2;
        CGFloat width = floor(height * 3.0 / 4.0 / 2) * 2;
        if (size.width < width || height < 2) { done(NO, @"clip too small to crop"); return; }
        float fps = track.nominalFrameRate > 1 ? track.nominalFrameRate : 30;

        AVMutableVideoCompositionLayerInstruction *layer =
            [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
        [layer setTransform:CGAffineTransformConcat(track.preferredTransform,
                                                    CGAffineTransformMakeTranslation(-(size.width - width) / 2, 0))
                     atTime:kCMTimeZero];
        AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
        instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
        instruction.layerInstructions = @[layer];
        AVMutableVideoComposition *composition = [AVMutableVideoComposition videoComposition];
        composition.renderSize = CGSizeMake(width, height);
        composition.frameDuration = CMTimeMake(1, (int32_t)lroundf(fps));
        composition.instructions = @[instruction];

        AVAssetExportSession *export = [AVAssetExportSession exportSessionWithAsset:asset presetName:AVAssetExportPresetHEVCHighestQuality];
        if (!export) { done(NO, @"no HEVC export session"); return; }
        NSURL *partial = [dest URLByAppendingPathExtension:@"part.mp4"];
        [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
        export.videoComposition = composition;
        export.outputURL = partial;
        export.outputFileType = AVFileTypeMPEG4;
        [export exportAsynchronouslyWithCompletionHandler:^{
            BOOL ok = export.status == AVAssetExportSessionStatusCompleted &&
                      [NSFileManager.defaultManager moveItemAtURL:partial toURL:dest error:nil];
            if (!ok) [NSFileManager.defaultManager removeItemAtURL:partial error:nil];
            done(ok, ok ? [NSString stringWithFormat:@"cropped %.0fx%.0f -> %.0fx%.0f", size.width, size.height, width, height]
                        : [NSString stringWithFormat:@"crop failed: %@", export.error.localizedDescription ?: @"?"]);
        }];
    }];
}

void JBMotionFileSquareTo3x4(NSURL *master, NSString *name, void (^done)(NSURL *file, NSString *note)) {
    NSString *safe = [[name componentsSeparatedByCharactersInSet:NSCharacterSet.alphanumericCharacterSet.invertedSet]
                      componentsJoinedByString:@"-"];
    NSURL *dest = [cacheDir() URLByAppendingPathComponent:[safe stringByAppendingPathExtension:@"mp4"]];
    if ([NSFileManager.defaultManager fileExistsAtPath:dest.path]) {
        [NSFileManager.defaultManager setAttributes:@{ NSFileModificationDate: NSDate.date } ofItemAtPath:dest.path error:nil];
        done(dest, @"cached");
        return;
    }
    JBMotionFile(master, [safe stringByAppendingString:@"-square"], ^(NSURL *square, NSString *note) {
        if (!square) { done(nil, note); return; }
        cropTo3x4(square, dest, ^(BOOL ok, NSString *cropNote) {
            [NSFileManager.defaultManager removeItemAtURL:square error:nil];
            done(ok ? dest : nil, [NSString stringWithFormat:@"%@, %@", note, cropNote]);
        });
    });
}

void JBMotionPreview(NSURL *file, CGSize size, void (^done)(UIImage *image)) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:file options:nil];
    AVAssetImageGenerator *gen = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    if (size.width > 0 && size.height > 0) gen.maximumSize = size;
    if (@available(iOS 16.0, *)) {
        [gen generateCGImageAsynchronouslyForTime:kCMTimeZero completionHandler:^(CGImageRef image, CMTime actual, NSError *err) {
            done(image ? [UIImage imageWithCGImage:image] : nil);
        }];
    } else {
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            CGImageRef image = [gen copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
            UIImage *ui = image ? [UIImage imageWithCGImage:image] : nil;
            if (image) CGImageRelease(image);
            done(ui);
        });
    }
}
