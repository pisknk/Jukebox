#pragma once
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// The lock screen's animated artwork wants a local video file. Apple Music's
// motion covers are HLS: this picks the variant closest to ~1100 px wide (HEVC
// first), downloads it as one MP4 (its segments are byte ranges of a single
// fragmented MP4, or are concatenated if not) into
// Library/Caches/Jukebox/motion/<name>.mp4, and keeps the folder under 150 MB.
// Concurrent requests for the same name share one download.
void JBMotionFile(NSURL *master, NSString *name, void (^done)(NSURL * _Nullable file, NSString *note));

// Same, for a square (1:1) motion cover the lock screen wants as 3:4: the
// square clip is downloaded, centre-cropped to 3:4 once (HEVC re-encode) and
// cached as <name>.mp4; the square download is then deleted.
void JBMotionFileSquareTo3x4(NSURL *master, NSString *name, void (^done)(NSURL * _Nullable file, NSString *note));

// Where the videos are kept (Library/Caches/Jukebox/motion).
NSURL *JBMotionCacheDirectory(void);

// First frame of the clip, for the still the lock screen shows before / around it.
void JBMotionPreview(NSURL *file, CGSize size, void (^done)(UIImage * _Nullable image));

NS_ASSUME_NONNULL_END
