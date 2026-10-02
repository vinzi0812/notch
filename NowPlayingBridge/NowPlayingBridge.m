//
//  NowPlayingBridge.m
//  NowPlayingBridge
//
//  Loaded into /usr/bin/perl by the Notch app. Apple's now-playing daemon only answers
//  Apple-signed processes, and perl is one, so this code runs inside it.
//
//  Protocol (one line per message):
//    stdout: a JSON object whenever anything changes:
//              {"players": [ {title, artist, …, appBundleIdentifier, isPlaying}, … ], "elected": "<bundle id>"}
//            every app with something loaded, and which one macOS picked as "now playing" (the one
//            media keys and system commands go to). {"players": []} when nothing is loaded.
//    stdin:  "toggle", "next" or "previous", sent to macOS's pick; end of input (the app quit) ends the process
//
//  Why only the pick receives commands: MediaRemote can address other players, but in testing that
//  was unreliable (web players ignore it while paused, and even native apps sometimes did). The app
//  controls other players through AppleScript where the app supports it, and never guesses.
//

#import <Foundation/Foundation.h>
#import <objc/message.h>
#include <dlfcn.h>

typedef Boolean (*SendCommandFn)(int command, NSDictionary *options);
typedef void (*SetElapsedTimeFn)(double time);

static const int kCommandTogglePlayPause = 2;
static const int kCommandNextTrack = 4;
static const int kCommandPreviousTrack = 5;

static id Call(id object, const char *selectorName) {
    SEL selector = sel_registerName(selectorName);
    return [object respondsToSelector:selector] ? ((id (*)(id, SEL))objc_msgSend)(object, selector) : nil;
}

typedef void (*GetClientsFn)(dispatch_queue_t queue, void (^completion)(NSArray *clients));
typedef id (*GetOriginFn)(void);

static NSString *AppBundleID(id client) {
    return Call(client, "parentApplicationBundleIdentifier") ?: Call(client, "bundleIdentifier");
}

/// One player's state as JSON-ready values, or nil if it has nothing loaded.
static NSDictionary *PlayerJSON(id client, NSDictionary *info, BOOL isPlaying) {
    NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
    if (title.length == 0) return nil;
    NSDate *timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    return @{
        @"isPlaying": @(isPlaying),
        @"title": title,
        @"artist": info[@"kMRMediaRemoteNowPlayingInfoArtist"] ?: @"",
        @"album": info[@"kMRMediaRemoteNowPlayingInfoAlbum"] ?: @"",
        @"duration": info[@"kMRMediaRemoteNowPlayingInfoDuration"] ?: @0,
        @"elapsedTime": info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] ?: @0,
        @"playbackRate": info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] ?: @0,
        @"timestamp": @(timestamp ? timestamp.timeIntervalSince1970 : NSDate.date.timeIntervalSince1970),
        @"appName": Call(client, "displayName") ?: @"",
        @"appBundleIdentifier": AppBundleID(client) ?: @"",
    };
}

/// Asks every app that has registered with MediaRemote for its state, then calls `completion` on the
/// main queue with the whole snapshot. Each app is asked through a request aimed at its own player path.
static void Snapshot(GetClientsFn getClients, id origin, void (^completion)(NSDictionary *snapshot)) {
    Class request = NSClassFromString(@"MRNowPlayingRequest");
    Class pathClass = NSClassFromString(@"MRPlayerPath");
    id defaultPlayer = Call(NSClassFromString(@"MRPlayer"), "defaultPlayer");
    dispatch_queue_t queue = dispatch_queue_create("notch.nowplaying.snapshot", DISPATCH_QUEUE_SERIAL);
    NSString *elected = AppBundleID(Call(Call(request, "localNowPlayingPlayerPath"), "client"));

    getClients(queue, ^(NSArray *clients) {
        NSMutableArray *players = [NSMutableArray array];
        dispatch_group_t group = dispatch_group_create();
        for (id client in clients) {
            id path = ((id (*)(id, SEL, id, id, id))objc_msgSend)([pathClass alloc], sel_registerName("initWithOrigin:client:player:"), origin, client, defaultPlayer);
            id perPlayer = ((id (*)(id, SEL, id))objc_msgSend)([request alloc], sel_registerName("initWithPlayerPath:"), path);
            __block NSDictionary *info = nil;
            __block BOOL isPlaying = NO;
            dispatch_group_t each = dispatch_group_create();
            dispatch_group_enter(group);
            dispatch_group_enter(each);
            ((void (*)(id, SEL, dispatch_queue_t, id))objc_msgSend)(perPlayer, sel_registerName("requestNowPlayingInfoOnQueue:completion:"), queue, ^(NSDictionary *result, NSError *error) {
                info = result;
                dispatch_group_leave(each);
            });
            dispatch_group_enter(each);
            ((void (*)(id, SEL, dispatch_queue_t, id))objc_msgSend)(perPlayer, sel_registerName("requestIsPlayingOnQueue:completion:"), queue, ^(BOOL playing, NSError *error) {
                isPlaying = playing;
                dispatch_group_leave(each);
            });
            dispatch_group_notify(each, queue, ^{
                NSDictionary *player = PlayerJSON(client, info, isPlaying);
                if (player) [players addObject:player];
                dispatch_group_leave(group);
            });
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            // A stable order, so an unchanged state produces an identical line.
            [players sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"appBundleIdentifier" ascending:YES]]];
            NSMutableDictionary *snapshot = [@{ @"players": players } mutableCopy];
            if (elected) snapshot[@"elected"] = elected;
            completion(snapshot);
        });
    });
}

static void ReadCommands(SendCommandFn send, SetElapsedTimeFn setElapsed) {
    char line[64];
    while (fgets(line, sizeof line, stdin)) {
        NSString *command = [[NSString stringWithUTF8String:line] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([command hasPrefix:@"seek "]) {
            double position = [[command substringFromIndex:5] doubleValue];
            if (setElapsed) setElapsed(position);
        } else {
            int code = [command isEqualToString:@"toggle"] ? kCommandTogglePlayPause
                     : [command isEqualToString:@"next"] ? kCommandNextTrack
                     : [command isEqualToString:@"previous"] ? kCommandPreviousTrack
                     : -1;
            if (code >= 0 && send) send(code, nil);
        }
    }
    exit(0);
}

__attribute__((constructor)) static void StartBridge(void) {
    if (!getenv("NOTCH_NOW_PLAYING_BRIDGE")) return;

    void *mediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    SendCommandFn send = mediaRemote ? (SendCommandFn)dlsym(mediaRemote, "MRMediaRemoteSendCommand") : NULL;
    SetElapsedTimeFn setElapsed = mediaRemote ? (SetElapsedTimeFn)dlsym(mediaRemote, "MRMediaRemoteSetElapsedTime") : NULL;
    GetClientsFn getClients = mediaRemote ? (GetClientsFn)dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingClients") : NULL;
    GetOriginFn localOrigin = mediaRemote ? (GetOriginFn)dlsym(mediaRemote, "MRMediaRemoteGetLocalOrigin") : NULL;
    if (!NSClassFromString(@"MRNowPlayingRequest") || !getClients || !localOrigin) {
        printf("{\"error\":\"MediaRemote unavailable\"}\n");
        fflush(stdout);
        exit(1);
    }
    id origin = localOrigin();

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ ReadCommands(send, setElapsed); });

    __block NSData *lastLine = nil;
    __block BOOL inFlight = NO;
    void (^publish)(void) = ^{
        if (inFlight) return;   // a slow answer never piles up requests
        inFlight = YES;
        Snapshot(getClients, origin, ^(NSDictionary *snapshot) {
            inFlight = NO;
            NSData *line = [NSJSONSerialization dataWithJSONObject:snapshot options:NSJSONWritingSortedKeys error:nil];
            if (!line || [line isEqualToData:lastLine]) return;
            lastLine = line;
            fwrite(line.bytes, 1, line.length, stdout);
            fputc('\n', stdout);
            fflush(stdout);
        });
    };

    publish();
    [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { publish(); }];
    [[NSRunLoop mainRunLoop] run];
}
