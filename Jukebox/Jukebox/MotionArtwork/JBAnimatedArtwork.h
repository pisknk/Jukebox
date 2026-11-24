#pragma once
#import <Foundation/Foundation.h>
#import <MediaPlayer/MediaPlayer.h>

NS_ASSUME_NONNULL_BEGIN

// Animated now-playing artwork (iOS 26+): MPMediaItemAnimatedArtwork, put in the
// now-playing info under one of +[MPNowPlayingInfoCenter supportedAnimatedArtworkKeys].
// The lock screen then plays a local video file. Ported from pisknk/deezit
// (DZLockArtwork.x); everything is looked up at runtime, so older iOS simply
// reports it as unavailable.

// YES on iOS 26+ when the API exists.
BOOL JBAnimatedArtworkAvailable(void);

// The now-playing info key for a 3:4 (tall) animated cover, if this iOS offers one.
NSString * _Nullable JBAnimatedArtworkKey3x4(void);

// An MPMediaItemAnimatedArtwork playing `file`. `still` is used for the preview
// image if the video's first frame can't be read.
id _Nullable JBMakeAnimatedArtwork(NSString *artworkID, NSURL *file, MPMediaItemArtwork * _Nullable still);

NS_ASSUME_NONNULL_END
