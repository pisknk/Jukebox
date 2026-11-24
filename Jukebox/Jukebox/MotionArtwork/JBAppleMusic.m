#import "JBAppleMusic.h"
#import "JBLog.h"
#import <string.h>

// Copied from pisknk/deezit (DZAppleMusic.m). Adapted from pisknk/twenty-one-reborn: TJCatalogMatch.m (name matching via
// the iTunes Search API) and TJCatalogAPI.m (web-player token + amp-api).

static NSString *const kJBAMTokenKey = @"appleMusicWebToken";
static NSString *const kJBAMMobileUA = @"Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1";
static NSString *const kJBAMDesktopUA = @"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15";

static NSString *storefront(void) {
    NSString *cc = [[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
    return cc.length == 2 ? cc.lowercaseString : @"us";
}

static void httpGet(NSURL *url, NSString *bearer, NSString *userAgent, NSTimeInterval timeout,
                    void (^done)(NSData *data, NSInteger status)) {
    if (!url) { done(nil, 0); return; }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.timeoutInterval = timeout;
    [req setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    if (bearer) {
        [req setValue:[@"Bearer " stringByAppendingString:bearer] forHTTPHeaderField:@"Authorization"];
        [req setValue:@"https://music.apple.com" forHTTPHeaderField:@"Origin"];
        [req setValue:@"https://music.apple.com/" forHTTPHeaderField:@"Referer"];
    }
    [[NSURLSession.sharedSession dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
        NSInteger status = [resp isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)resp).statusCode : 0;
        done(err ? nil : data, status);
    }] resume];
}

static id jsonObject(NSData *data) {
    return data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
}

#pragma mark - token (TJCatalogAPI)

static NSDictionary *jwtPart(NSString *part) {
    NSString *b64 = [[part stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                     stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while (b64.length % 4) b64 = [b64 stringByAppendingString:@"="];
    NSData *data = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
    id json = jsonObject(data);
    return [json isKindOfClass:[NSDictionary class]] ? json : nil;
}

static NSTimeInterval tokenExpiry(NSString *jwt) {
    NSArray<NSString *> *parts = [jwt componentsSeparatedByString:@"."];
    if (parts.count != 3) return 0;
    id exp = jwtPart(parts[1])[@"exp"];
    return [exp isKindOfClass:[NSNumber class]] ? [exp doubleValue] : 0;
}

static BOOL tokenUsable(NSString *jwt) {
    NSArray<NSString *> *parts = [jwt componentsSeparatedByString:@"."];
    return parts.count == 3 && jwtPart(parts[0])[@"alg"] &&
           tokenExpiry(jwt) > NSDate.date.timeIntervalSince1970 + 300;
}

static NSString *jwtInData(NSData *data) {
    const char *bytes = data.bytes;
    NSUInteger n = data.length, from = 0;
    while (bytes && from + 3 <= n) {
        const char *hit = memmem(bytes + from, n - from, "eyJ", 3);
        if (!hit) break;
        NSUInteger start = (NSUInteger)(hit - bytes), j = start, seg = 0;
        int dots = 0;
        while (j < n) {
            char c = bytes[j];
            if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_') { seg++; j++; }
            else if (c == '.' && dots < 2 && seg >= 10) { dots++; seg = 0; j++; }
            else break;
        }
        if (dots == 2 && seg >= 10) {
            NSString *candidate = [[NSString alloc] initWithBytes:bytes + start length:j - start encoding:NSASCIIStringEncoding];
            if (candidate && tokenUsable(candidate)) return candidate;
        }
        from = start + 1;
    }
    return nil;
}

static NSArray<NSString *> *chunkNames(NSData *js) {
    NSString *text = [[NSString alloc] initWithData:js encoding:NSISOLatin1StringEncoding];
    if (!text.length) return @[];
    static NSRegularExpression *re;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        re = [NSRegularExpression regularExpressionWithPattern:@"[A-Za-z0-9_.-]+~[0-9a-f]{6,}\\.js" options:0 error:nil];
    });
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet orderedSet];
    for (NSTextCheckingResult *m in [re matchesInString:text options:0 range:NSMakeRange(0, text.length)]) {
        [names addObject:[text substringWithRange:m.range]];
        if (names.count >= 200) break;
    }
    return names.array;
}

static void searchScripts(NSMutableArray<NSString *> *queue, NSMutableSet<NSString *> *seen, NSUInteger scanned,
                          NSString *ua, void (^done)(NSString *token)) {
    if (!queue.count || scanned >= 40) { done(nil); return; }
    NSString *path = queue.firstObject;
    [queue removeObjectAtIndex:0];
    httpGet([NSURL URLWithString:[@"https://music.apple.com" stringByAppendingString:path]], nil, ua, 10,
            ^(NSData *js, NSInteger status) {
        NSString *token = js ? jwtInData(js) : nil;
        if (token) { done(token); return; }
        for (NSString *name in js ? chunkNames(js) : @[]) {
            NSString *chunk = [@"/assets/" stringByAppendingString:name];
            if ([seen containsObject:chunk]) continue;
            [seen addObject:chunk];
            [queue addObject:chunk];
        }
        searchScripts(queue, seen, scanned + 1, ua, done);
    });
}

static void scrapeToken(NSString *ua, void (^done)(NSString *token)) {
    NSURL *page = [NSURL URLWithString:[NSString stringWithFormat:@"https://music.apple.com/%@/browse", storefront()]];
    httpGet(page, nil, ua, 10, ^(NSData *data, NSInteger status) {
        NSString *html = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        if (!html) { done(nil); return; }
        NSString *inPage = jwtInData(data);
        if (!inPage) {
            NSString *decoded = html.stringByRemovingPercentEncoding;
            if (decoded) inPage = jwtInData([decoded dataUsingEncoding:NSUTF8StringEncoding]);
        }
        if (inPage) { done(inPage); return; }
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(?:src|href)=\"(/assets/[^\"]+\\.js)\""
                                                                            options:0 error:nil];
        NSMutableArray<NSString *> *scripts = [NSMutableArray array];
        for (NSTextCheckingResult *m in [re matchesInString:html options:0 range:NSMakeRange(0, html.length)]) {
            NSString *path = [html substringWithRange:[m rangeAtIndex:1]];
            if ([scripts containsObject:path]) continue;
            if ([path.lastPathComponent hasPrefix:@"index"]) [scripts insertObject:path atIndex:0];
            else [scripts addObject:path];
        }
        searchScripts(scripts, [NSMutableSet setWithArray:scripts], 0, ua, done);
    });
}

// One fetch at a time; everyone asking meanwhile waits for it. A token is
// kept in UserDefaults until about five minutes before it expires; after a
// failed scrape nobody retries for ten minutes.
static void withToken(BOOL fresh, void (^use)(NSString *token)) {
    static dispatch_queue_t q;
    static NSString *token;
    static NSMutableArray *waiters;
    static BOOL fetching;
    static NSTimeInterval failedUntil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("ph.neilbayron.jukebox.amtoken", DISPATCH_QUEUE_SERIAL);
        waiters = [NSMutableArray array];
    });
    dispatch_async(q, ^{
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        if (fresh) token = nil;
        else if (!token) token = [NSUserDefaults.standardUserDefaults stringForKey:kJBAMTokenKey].length ? [NSUserDefaults.standardUserDefaults stringForKey:kJBAMTokenKey] : nil;
        if (token && tokenExpiry(token) > now + 300) { use(token); return; }
        if (failedUntil > now) { use(nil); return; }

        [waiters addObject:[use copy]];
        if (fetching) return;
        fetching = YES;
        void (^finish)(NSString *) = ^(NSString *got) {
            dispatch_async(q, ^{
                fetching = NO;
                token = got;
                if (got) [NSUserDefaults.standardUserDefaults setObject:got forKey:kJBAMTokenKey];
                else failedUntil = NSDate.date.timeIntervalSince1970 + 600;
                JBLog("lock art: Apple Music token %@", got ? [NSString stringWithFormat:@"read, good until %@",
                      [NSDate dateWithTimeIntervalSince1970:tokenExpiry(got)]] : @"not found (retry in 10 min)");
                NSArray *pending = [waiters copy];
                [waiters removeAllObjects];
                for (void (^w)(NSString *) in pending) w(got);
            });
        };
        scrapeToken(kJBAMMobileUA, ^(NSString *got) {
            if (got) { finish(got); return; }
            scrapeToken(kJBAMDesktopUA, finish);
        });
    });
}

static void catalogGet(NSString *path, BOOL retried, void (^done)(NSData *data, NSInteger status)) {
    withToken(retried, ^(NSString *token) {
        if (!token) { done(nil, 0); return; }
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://amp-api.music.apple.com/v1/catalog/%@/%@",
                                           storefront(), path]];
        httpGet(url, token, kJBAMMobileUA, 10, ^(NSData *data, NSInteger status) {
            if ((status == 401 || status == 403) && !retried) { catalogGet(path, YES, done); return; }
            done(data, status);
        });
    });
}

#pragma mark - name matching (TJCatalogMatch)

static NSString *normalize(NSString *s) {
    if (!s.length) return @"";
    NSString *t = [s.precomposedStringWithCanonicalMapping
                   stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch | NSWidthInsensitiveSearch
                   locale:nil].lowercaseString;
    static NSRegularExpression *brackets, *dashSuffix;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *words = @"(feat\\.?|ft\\.?|featuring|with |remaster|explicit|clean|radio edit|mono|stereo)";
        brackets = [NSRegularExpression regularExpressionWithPattern:
                    [NSString stringWithFormat:@"[\\(\\[][^\\)\\]]*%@[^\\)\\]]*[\\)\\]]", words] options:0 error:nil];
        dashSuffix = [NSRegularExpression regularExpressionWithPattern:
                      [NSString stringWithFormat:@"\\s+-\\s+.*%@.*$", words] options:0 error:nil];
    });
    t = [brackets stringByReplacingMatchesInString:t options:0 range:NSMakeRange(0, t.length) withTemplate:@""];
    t = [dashSuffix stringByReplacingMatchesInString:t options:0 range:NSMakeRange(0, t.length) withTemplate:@""];
    NSMutableString *out = [NSMutableString string];
    [t enumerateSubstringsInRange:NSMakeRange(0, t.length) options:NSStringEnumerationByComposedCharacterSequences
                       usingBlock:^(NSString *ch, NSRange r1, NSRange r2, BOOL *stop) {
        if ([ch rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet].location != NSNotFound) [out appendString:ch];
    }];
    return out;
}

static NSString *normalizeAlbum(NSString *s) {
    if (!s.length) return @"";
    static NSRegularExpression *edition, *suffix;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        edition = [NSRegularExpression regularExpressionWithPattern:
                   @"\\s*[\\(\\[][^\\)\\]]*(deluxe|edition|expanded|bonus)[^\\)\\]]*[\\)\\]]"
                                                            options:NSRegularExpressionCaseInsensitive error:nil];
        suffix = [NSRegularExpression regularExpressionWithPattern:@"\\s+-\\s+(single|ep)\\s*$"
                                                           options:NSRegularExpressionCaseInsensitive error:nil];
    });
    NSString *t = [edition stringByReplacingMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@""];
    t = [suffix stringByReplacingMatchesInString:t options:0 range:NSMakeRange(0, t.length) withTemplate:@""];
    return normalize(t);
}

static NSString *primaryArtist(NSString *artist) {
    NSString *a = artist ?: @"";
    for (NSString *sep in @[@", ", @" & ", @" feat. ", @" feat ", @" ft. ", @" x ", @" with "]) {
        NSRange r = [a.lowercaseString rangeOfString:sep];
        if (r.location != NSNotFound && r.location > 0) a = [a substringToIndex:r.location];
    }
    return a;
}

static BOOL artistMatches(id got, NSString *want) {
    NSString *g = [got isKindOfClass:[NSString class]] ? normalize(got) : @"";
    return g.length && want.length && ([g containsString:want] || [want containsString:g]);
}

static void itunesSearch(NSString *term, NSString *entity, NSUInteger limit, void (^done)(NSArray *results)) {
    NSMutableCharacterSet *allowed = [NSCharacterSet.URLQueryAllowedCharacterSet mutableCopy];
    [allowed removeCharactersInString:@"&+=?#"];
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://itunes.apple.com/search?term=%@&entity=%@&limit=%lu&country=%@",
                                       [term stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"",
                                       entity, (unsigned long)limit, storefront()]];
    httpGet(url, nil, kJBAMMobileUA, 8, ^(NSData *data, NSInteger status) {
        if (status != 200 || !data) { done(nil); return; }
        NSDictionary *json = jsonObject(data);
        NSArray *results = [json isKindOfClass:[NSDictionary class]] ? json[@"results"] : nil;
        done([results isKindOfClass:[NSArray class]] ? results : @[]);
    });
}

// Album first (Deezer's album name is the thing we want the cover of), then
// the track, which also finds albums whose names differ between services.
static void matchAlbum(NSString *title, NSString *artist, NSString *album, NSTimeInterval duration,
                       void (^done)(NSString *albumID, NSString *note)) {
    NSString *primary = primaryArtist(artist);
    NSString *wantArtist = normalize(primary), *wantAlbum = normalizeAlbum(album), *wantTitle = normalize(title);
    if (!wantArtist.length || (!wantAlbum.length && !wantTitle.length)) { done(nil, @"no artist / album / title to match"); return; }

    void (^bySong)(void) = ^{
        if (!wantTitle.length) { done(nil, @"album not found, no title to try"); return; }
        itunesSearch([NSString stringWithFormat:@"%@ %@", title, primary], @"song", 15, ^(NSArray *songs) {
            if (!songs) { done(nil, @"iTunes song search failed"); return; }
            NSDictionary *best = nil;
            BOOL bestSameAlbum = NO;
            for (NSDictionary *r in songs) {
                if (![r isKindOfClass:[NSDictionary class]] || !r[@"collectionId"]) continue;
                if (![normalize(r[@"trackName"]) isEqualToString:wantTitle] || !artistMatches(r[@"artistName"], wantArtist)) continue;
                if (duration > 0 && [r[@"trackTimeMillis"] isKindOfClass:[NSNumber class]] &&
                    fabs([r[@"trackTimeMillis"] doubleValue] / 1000.0 - duration) > 3.0) continue;
                BOOL same = wantAlbum.length && [normalizeAlbum(r[@"collectionName"]) isEqualToString:wantAlbum];
                if (!best || (same && !bestSameAlbum)) { best = r; bestSameAlbum = same; }
                if (bestSameAlbum) break;
            }
            if (!best) { done(nil, [NSString stringWithFormat:@"no confident match among %lu songs", (unsigned long)songs.count]); return; }
            done([best[@"collectionId"] description],
                 [NSString stringWithFormat:@"song match -> \"%@\" (%@)", best[@"collectionName"], best[@"artistName"]]);
        });
    };

    if (!wantAlbum.length) { bySong(); return; }
    itunesSearch([NSString stringWithFormat:@"%@ %@", album, primary], @"album", 10, ^(NSArray *albums) {
        for (NSDictionary *a in albums ?: @[]) {
            if (![a isKindOfClass:[NSDictionary class]] || !a[@"collectionId"]) continue;
            if (![normalizeAlbum(a[@"collectionName"]) isEqualToString:wantAlbum] || !artistMatches(a[@"artistName"], wantArtist)) continue;
            done([a[@"collectionId"] description],
                 [NSString stringWithFormat:@"album match -> \"%@\" (%@)", a[@"collectionName"], a[@"artistName"]]);
            return;
        }
        bySong();
    });
}

#pragma mark - editorial video

static NSURL *videoIn(NSDictionary *editorial, NSArray<NSString *> *keys) {
    for (NSString *key in keys) {
        NSDictionary *v = editorial[key];
        NSString *s = [v isKindOfClass:[NSDictionary class]] ? v[@"video"] : nil;
        if ([s isKindOfClass:[NSString class]] && [s hasPrefix:@"https://"] && [s containsString:@".m3u8"]) {
            NSURL *u = [NSURL URLWithString:s];
            if (u) return u;
        }
    }
    return nil;
}

// The album's motion covers. `ok` is NO when the catalog couldn't be asked
// (token / network), so the caller retries later instead of concluding there
// is no cover.
static void editorialFor(NSString *albumID, void (^done)(BOOL ok, NSURL *tall, NSURL *square, NSString *what)) {
    catalogGet([NSString stringWithFormat:@"albums/%@?extend=editorialVideo", albumID], NO, ^(NSData *data, NSInteger status) {
        if (status != 200) { done(NO, nil, nil, [NSString stringWithFormat:@"catalog HTTP %ld", (long)status]); return; }
        NSDictionary *json = jsonObject(data);
        NSArray *items = [json isKindOfClass:[NSDictionary class]] ? json[@"data"] : nil;
        NSDictionary *first = [items isKindOfClass:[NSArray class]] && items.count ? items.firstObject : nil;
        NSDictionary *attrs = [first isKindOfClass:[NSDictionary class]] ? first[@"attributes"] : nil;
        NSDictionary *ev = [attrs isKindOfClass:[NSDictionary class]] ? attrs[@"editorialVideo"] : nil;
        if (![ev isKindOfClass:[NSDictionary class]]) { done(YES, nil, nil, @"no motion cover"); return; }
        NSURL *tall = videoIn(ev, @[@"motionDetailTall", @"motionTallVideo3x4"]);
        NSURL *square = videoIn(ev, @[@"motionDetailSquare", @"motionSquareVideo1x1"]);
        done(YES, tall, square, [NSString stringWithFormat:@"tall %@, square %@", tall ? @"yes" : @"no", square ? @"yes" : @"no"]);
    });
}

// Apple Music often has several albums with the same name (re-issues, clean /
// explicit, regional editions) and only one of them carries the motion cover:
// on device "Radical Optimism" matched 1745741774 (no cover) while 1734980417
// has one. So ask the catalog's own search with editorialVideo, and among the
// same artist's albums of that name take one that actually has a cover
// (exact name first, then the name without "(Deluxe)", " - Single" etc).
static void searchMotionAlbum(NSString *artist, NSString *album, JBMotionCoverResult done) {
    NSString *primary = primaryArtist(artist);
    NSString *wantArtist = normalize(primary), *wantExact = normalize(album), *wantBase = normalizeAlbum(album);
    if (!wantArtist.length || !wantBase.length) { done(nil, nil, nil, @"no artist / album to search"); return; }
    NSURLComponents *query = [NSURLComponents new];
    query.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"term" value:[NSString stringWithFormat:@"%@ %@", primary, album]],
        [NSURLQueryItem queryItemWithName:@"types" value:@"albums"],
        [NSURLQueryItem queryItemWithName:@"limit" value:@"15"],
        [NSURLQueryItem queryItemWithName:@"extend" value:@"editorialVideo"],
    ];
    catalogGet([@"search?" stringByAppendingString:query.percentEncodedQuery ?: @""], NO, ^(NSData *data, NSInteger status) {
        if (status != 200) { done(nil, nil, nil, [NSString stringWithFormat:@"catalog search HTTP %ld", (long)status]); return; }
        NSDictionary *json = jsonObject(data);
        NSDictionary *results = [json isKindOfClass:[NSDictionary class]] ? json[@"results"] : nil;
        NSDictionary *albums = [results isKindOfClass:[NSDictionary class]] ? results[@"albums"] : nil;
        NSArray *list = [albums isKindOfClass:[NSDictionary class]] ? albums[@"data"] : nil;
        NSString *bestID = nil, *bestName = nil;
        NSURL *bestTall = nil, *bestSquare = nil;
        int bestRank = 0;
        NSUInteger sameName = 0;
        for (NSDictionary *a in [list isKindOfClass:[NSArray class]] ? list : @[]) {
            NSDictionary *attrs = [a isKindOfClass:[NSDictionary class]] ? a[@"attributes"] : nil;
            if (![attrs isKindOfClass:[NSDictionary class]] || !artistMatches(attrs[@"artistName"], wantArtist)) continue;
            NSString *name = [attrs[@"name"] isKindOfClass:[NSString class]] ? attrs[@"name"] : @"";
            BOOL exact = [normalize(name) isEqualToString:wantExact];
            if (!exact && ![normalizeAlbum(name) isEqualToString:wantBase]) continue;
            sameName++;
            NSDictionary *ev = attrs[@"editorialVideo"];
            if (![ev isKindOfClass:[NSDictionary class]]) continue;
            NSURL *tall = videoIn(ev, @[@"motionDetailTall", @"motionTallVideo3x4"]);
            NSURL *square = videoIn(ev, @[@"motionDetailSquare", @"motionSquareVideo1x1"]);
            if (!tall && !square) continue;
            int rank = (exact ? 4 : 2) + (tall ? 1 : 0);
            if (rank <= bestRank) continue;
            bestRank = rank;
            bestID = [a[@"id"] description];
            bestName = name;
            bestTall = tall;
            bestSquare = square;
        }
        if (bestID.length) {
            done(bestID, bestTall, bestSquare, [NSString stringWithFormat:@"catalog search -> \"%@\" (%@, %lu same-name album%@): tall %@, square %@",
                                                bestName, bestID, (unsigned long)sameName, sameName == 1 ? @"" : @"s",
                                                bestTall ? @"yes" : @"no", bestSquare ? @"yes" : @"no"]);
        } else {
            done(nil, nil, nil, [NSString stringWithFormat:@"catalog search: %lu same-name album%@, none with a motion cover",
                                 (unsigned long)sameName, sameName == 1 ? @"" : @"s"]);
        }
    });
}

void JBAppleMotionCover(NSString *title, NSString *artist, NSString *album, NSTimeInterval duration, JBMotionCoverResult done) {
    void (^byItunesMatch)(NSString *) = ^(NSString *searchNote) {
        matchAlbum(title, artist, album ?: @"", duration, ^(NSString *albumID, NSString *matchNote) {
            if (!albumID.length) { done(nil, nil, nil, [NSString stringWithFormat:@"%@; %@", searchNote, matchNote]); return; }
            editorialFor(albumID, ^(BOOL ok, NSURL *tall, NSURL *square, NSString *what) {
                done(ok ? albumID : nil, tall, square,
                     [NSString stringWithFormat:@"%@; %@; album %@: %@", searchNote, matchNote, albumID, what]);
            });
        });
    };
    if (!album.length) { byItunesMatch(@"no album name to search"); return; }
    searchMotionAlbum(artist, album, ^(NSString *albumID, NSURL *tall, NSURL *square, NSString *note) {
        if (albumID && (tall || square)) { done(albumID, tall, square, note); return; }
        // nothing with a cover under that name: the iTunes match (and, if that
        // album has no cover either, the song's other releases) decide
        byItunesMatch(note);
    });
}

// Tries the candidates in order until one has a motion cover.
static void firstWithMotion(NSArray<NSDictionary *> *candidates, NSUInteger i, NSMutableArray *tried, JBMotionCoverResult done) {
    if (i >= candidates.count) {
        done(nil, nil, nil, tried.count ? [NSString stringWithFormat:@"no other release with a motion cover (checked %@)",
                                           [tried componentsJoinedByString:@", "]]
                                        : @"no other release of this song found");
        return;
    }
    NSDictionary *c = candidates[i];
    NSString *albumID = [c[@"collectionId"] description];
    editorialFor(albumID, ^(BOOL ok, NSURL *tall, NSURL *square, NSString *what) {
        [tried addObject:[NSString stringWithFormat:@"\"%@\" %@", c[@"collectionName"], what]];
        if (tall || square) {
            done(albumID, tall, square, [NSString stringWithFormat:@"other release \"%@\" (%@): %@",
                                         c[@"collectionName"], albumID, what]);
            return;
        }
        firstWithMotion(candidates, i + 1, tried, done);
    });
}

void JBAppleMotionCoverFromOtherReleases(NSString *title, NSString *artist, NSString *excludeAlbumID,
                                         NSTimeInterval duration, JBMotionCoverResult done) {
    NSString *primary = primaryArtist(artist);
    NSString *wantTitle = normalize(title), *wantArtist = normalize(primary);
    if (!wantTitle.length || !wantArtist.length) { done(nil, nil, nil, @"no title / artist"); return; }
    itunesSearch([NSString stringWithFormat:@"%@ %@", title, primary], @"song", 25, ^(NSArray *songs) {
        if (!songs) { done(nil, nil, nil, @"iTunes song search failed"); return; }
        NSMutableArray<NSDictionary *> *singles = [NSMutableArray array], *others = [NSMutableArray array];
        NSMutableSet *seen = [NSMutableSet setWithObject:excludeAlbumID ?: @""];
        for (NSDictionary *r in songs) {
            if (![r isKindOfClass:[NSDictionary class]] || !r[@"collectionId"]) continue;
            NSString *cid = [r[@"collectionId"] description];
            if ([seen containsObject:cid]) continue;
            if (![normalize(r[@"trackName"]) isEqualToString:wantTitle] || !artistMatches(r[@"artistName"], wantArtist)) continue;
            if (duration > 0 && [r[@"trackTimeMillis"] isKindOfClass:[NSNumber class]] &&
                fabs([r[@"trackTimeMillis"] doubleValue] / 1000.0 - duration) > 3.0) continue;
            [seen addObject:cid];
            NSString *name = [r[@"collectionName"] isKindOfClass:[NSString class]] ? r[@"collectionName"] : @"";
            // the song's own single is the likeliest to have a motion cover
            NSMutableArray *bucket = [name hasSuffix:@" - Single"] ? singles : others;
            [bucket addObject:r];
        }
        NSArray *candidates = [singles arrayByAddingObjectsFromArray:others];
        if (candidates.count > 4) candidates = [candidates subarrayWithRange:NSMakeRange(0, 4)];
        firstWithMotion(candidates, 0, [NSMutableArray array], done);
    });
}
