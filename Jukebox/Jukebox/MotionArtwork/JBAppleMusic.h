#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Apple Music catalog lookups for animated album covers. Copied from
// pisknk/deezit (DZAppleMusic), itself adapted
// from pisknk/twenty-one-reborn (TJCatalogMatch / TJCatalogAPI):
//   1. iTunes Search API (public, no token): Deezer's album / track names ->
//      the Apple Music album ID
//   2. amp-api catalog (web player token, scraped from music.apple.com and
//      kept until it expires): album ID -> editorialVideo motion covers
//
// `done` is called once, on an arbitrary queue. `tall` is the 3:4 motion cover
// and `square` the 1:1 one; either or both can be nil. `note` says what
// happened, for the debug log.
typedef void (^JBMotionCoverResult)(NSString * _Nullable albumID, NSURL * _Nullable tall,
                                    NSURL * _Nullable square, NSString *note);

// `albumID` is nil only when no album matched or the catalog couldn't be asked
// (worth retrying later); an album without a motion cover comes back with its
// ID and both URLs nil.
void JBAppleMotionCover(NSString *title, NSString *artist, NSString * _Nullable album,
                        NSTimeInterval duration, JBMotionCoverResult done);

// Fallback when the album has no motion cover: other releases of the same
// song (singles first, up to four), the first one with a motion cover.
void JBAppleMotionCoverFromOtherReleases(NSString *title, NSString *artist, NSString * _Nullable excludeAlbumID,
                                         NSTimeInterval duration, JBMotionCoverResult done);

NS_ASSUME_NONNULL_END
