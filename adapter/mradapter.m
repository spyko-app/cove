// Adapter MediaRemote — carregado dentro do /usr/bin/perl (host assinado pela
// Apple, passa o gate do macOS 15.4+). O app fala com ele por pipes:
//   stdout: 1 linha JSON por mudança de now playing (título, artista, estado,
//           artwork base64 quando muda)
//   stdin:  "cmd <n>" → MRMediaRemoteSendCommand(n)
// Chamado via DynaLoader::dl_install_xsub (NUNCA em constructor — lock do dyld
// deadlocka a resposta XPC; provado ao vivo).
#import <Foundation/Foundation.h>
#import <dlfcn.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*RegisterFn)(dispatch_queue_t);
typedef Boolean (*CommandFn)(int, id);
typedef void (*IsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*SetElapsedFn)(double);

static GetInfoFn getInfo;
static RegisterFn registerNotifs;
static CommandFn sendCommand;
static IsPlayingFn getIsPlaying;
static SetElapsedFn setElapsed;
static NSString *lastArtworkID = nil;

static void emit(void) {
    getInfo(dispatch_get_main_queue(), ^(CFDictionaryRef cfInfo) {
        NSDictionary *info = (__bridge NSDictionary *)cfInfo;
        NSMutableDictionary *out = [NSMutableDictionary new];
        out[@"title"] = info[@"kMRMediaRemoteNowPlayingInfoTitle"] ?: @"";
        out[@"artist"] = info[@"kMRMediaRemoteNowPlayingInfoArtist"] ?: @"";
        out[@"album"] = info[@"kMRMediaRemoteNowPlayingInfoAlbum"] ?: @"";
        out[@"duration"] = info[@"kMRMediaRemoteNowPlayingInfoDuration"] ?: @0;
        out[@"elapsed"] = info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] ?: @0;
        NSString *artID = info[@"kMRMediaRemoteNowPlayingInfoArtworkIdentifier"];
        NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        if (art && (!lastArtworkID || ![artID isEqualToString:lastArtworkID])) {
            out[@"artwork"] = [art base64EncodedStringWithOptions:0];
            lastArtworkID = artID ?: @"";
        }
        getIsPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
            out[@"playing"] = @(playing);
            NSData *json = [NSJSONSerialization dataWithJSONObject:out options:0 error:nil];
            if (json) {
                fwrite(json.bytes, json.length, 1, stdout);
                fputc('\n', stdout);
                fflush(stdout);
            }
        });
    });
}

void adapter_run(void *a, void *b) {
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!h) exit(2);
    getInfo = (GetInfoFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
    registerNotifs = (RegisterFn)dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
    sendCommand = (CommandFn)dlsym(h, "MRMediaRemoteSendCommand");
    getIsPlaying = (IsPlayingFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    setElapsed = (SetElapsedFn)dlsym(h, "MRMediaRemoteSetElapsedTime");
    if (!getInfo || !registerNotifs) exit(3);

    registerNotifs(dispatch_get_main_queue());
    for (NSString *name in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                             @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"]) {
        [[NSNotificationCenter defaultCenter]
            addObserverForName:name object:nil queue:nil
                    usingBlock:^(NSNotification *n) { emit(); }];
    }

    // comandos pelo stdin em thread própria
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        char line[128];
        while (fgets(line, sizeof line, stdin)) {
            int cmd;
            double t;
            if (sscanf(line, "cmd %d", &cmd) == 1 && sendCommand)
                dispatch_async(dispatch_get_main_queue(), ^{ sendCommand(cmd, nil); });
            else if (sscanf(line, "seek %lf", &t) == 1 && setElapsed)
                dispatch_async(dispatch_get_main_queue(), ^{ setElapsed(t); emit(); });
        }
        exit(0);  // app fechou o pipe → morre junto
    });

    emit();
    CFRunLoopRun();
}
