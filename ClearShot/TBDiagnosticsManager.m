#import "TBDiagnosticsManager.h"
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <sys/stat.h>
#import <unistd.h>
#import <errno.h>
#import <stdio.h>
#import <string.h>

// Section classes that currently export diagnostics. A class that doesn't
// conform to TBDiagnosticProvider is simply skipped — this list can grow
// faster than every section catches up.
#import "CSInstaller.h"              // ClearShot — already has diagnosticReport
#import "CSProcessUtils.h"           // for the rootSpawn live-fire test
// Other sections implement the protocol as a category in their own .m.

// Written by main() when setuid/setgid refuse — gives us the exact errno
// in the header block instead of just "setuid(0) likely failed".
extern int kTBSetuidErrno;
extern int kTBSetgidErrno;

@implementation TBDiagnosticsManager

+ (NSArray<Class> *)diagnosticProviders {
    return @[
        NSClassFromString(@"ABMainViewController")       ?: (Class)NSNull.class,
        NSClassFromString(@"RSMainViewController")       ?: (Class)NSNull.class,
        NSClassFromString(@"BCMainViewController")       ?: (Class)NSNull.class,
        NSClassFromString(@"CSInstaller")                ?: (Class)NSNull.class,
        NSClassFromString(@"RMMainViewController")       ?: (Class)NSNull.class,
        NSClassFromString(@"ARMainViewController")       ?: (Class)NSNull.class,
        NSClassFromString(@"WFMainViewController")       ?: (Class)NSNull.class,
        NSClassFromString(@"TBSupervisionManager")       ?: (Class)NSNull.class,
    ];
}

// ============================================================================
// Header: who are we, what are we running on
// ============================================================================

+ (NSString *)processIdentityBlock {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"pid=%d  uid=%d  euid=%d  gid=%d  egid=%d\n",
     getpid(), getuid(), geteuid(), getgid(), getegid()];

    UIDevice *d = [UIDevice currentDevice];
    struct utsname sys; uname(&sys);
    [s appendFormat:@"device: %@ · iOS %@ · machine %s\n",
     d.model, d.systemVersion, sys.machine];

    NSString *exec = [[NSBundle mainBundle] executablePath];
    [s appendFormat:@"exec: %@\n", exec];

    NSString *bundle = [[NSBundle mainBundle] bundleIdentifier];
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *build   = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    [s appendFormat:@"bundle: %@ · version %@ (build %@)\n",
     bundle ?: @"(nil)", version ?: @"?", build ?: @"?"];

    if (geteuid() == 0) {
        [s appendString:@"\n✅ Running at euid=0 — all root-owned paths writable.\n"];
    } else {
        [s appendFormat:@"\n⚠️ Not running as root (euid=%d).\n", geteuid()];
        if (kTBSetuidErrno != 0) {
            [s appendFormat:@"   setuid(0) → errno=%d (%s)\n",
             kTBSetuidErrno, strerror(kTBSetuidErrno)];
        }
        if (kTBSetgidErrno != 0) {
            [s appendFormat:@"   setgid(0) → errno=%d (%s)\n",
             kTBSetgidErrno, strerror(kTBSetgidErrno)];
        }
        [s appendString:@"   (not fatal — system writes go through rootSpawn; "
                        @"see rootSpawn liveness below)\n"];
    }
    return s;
}

// ============================================================================
// Live rootSpawn test — the single most important signal in this report.
// If this shows uid=0 then every root-owned path we want to write is
// reachable via rootSpawn, and in-process euid=501 doesn't matter. If this
// shows uid=501 or a spawn error, NOTHING will install — that's the real
// problem to debug.
// ============================================================================
+ (NSString *)rootSpawnLivenessBlock {
    NSMutableString *s = [NSMutableString string];
    NSString *out = nil, *err = nil;
    int rc = [CSProcessUtils rootSpawn:@"/usr/bin/id"
                                  args:@[]
                                stdOut:&out
                                stdErr:&err];
    [s appendFormat:@"rootSpawn /usr/bin/id → exit=%d\n", rc];
    if (out.length) {
        NSString *trimmed = [out stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [s appendFormat:@"  stdout: %@\n", trimmed];
        if ([trimmed containsString:@"uid=0"]) {
            [s appendString:@"  ✅ rootSpawn promotes child to uid=0 — "
                            @"system-path writes are fine.\n"];
        } else {
            [s appendString:@"  ❌ child is NOT at uid=0 — persona_np did not take.\n"];
        }
    }
    if (err.length) {
        NSString *trimmed = [err stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (trimmed.length) [s appendFormat:@"  stderr: %@\n", trimmed];
    }
    return s;
}

// ============================================================================
// Writability checks for every root-owned path TrollBox writes to
// ============================================================================

+ (NSString *)writabilityBlock {
    NSArray *paths = @[
        @"/Library/ControlCenter/Bundles",                    // ClearShot
        @"/Library/LaunchDaemons",                             // ResSetter boot daemon
        @"/var/mobile/Library/Preferences",                    // ResSetter gfx plist
        @"/var/Managed Preferences/mobile",                    // Don't-Lock-After-Respring
        @"/var/mobile/Library/Caches/MappedImageCache/Persistent", // Badge Color
        @"/var/containers/Shared/SystemGroup",                 // Supervise
        @"/var/mobile/Library/Logs/CrashReporter/Analytics",   // Reclaim Space
        @"/var/mobile/Library/Logs/CrashReporter",             // Reclaim Space
        @"/var/mobile/Library/Logs/AppleSupport",              // Reclaim Space
        @"/var/log",                                           // Reclaim Space system logs
        @"/var/mobile/Containers/Data/Application",            // Reclaim Space orphans
        @"/var/mobile/Library/Caches",                         // Reclaim Space system caches
    ];
    NSMutableString *s = [NSMutableString string];
    for (NSString *p in paths) {
        const char *cp = [p fileSystemRepresentation];
        errno = 0;
        BOOL exists = (access(cp, F_OK) == 0);
        int existsErrno = errno;
        errno = 0;
        BOOL writable = (access(cp, W_OK) == 0);
        int writeErrno = errno;

        NSString *marker;
        NSString *extra = @"";
        if (!exists) {
            // Split ENOENT (truly missing, we'll create it via rootSpawn
            // when needed) from EACCES (parent not traversable, which is
            // a signal the sandbox isn't fully off).
            if (existsErrno == ENOENT) {
                marker = @"— ";
                extra = @"  (does not exist — rootSpawn mkdir will create)";
            } else {
                marker = @"— ";
                extra = [NSString stringWithFormat:@"  (F_OK errno=%d %s)",
                         existsErrno, strerror(existsErrno)];
            }
        } else if (writable) {
            marker = @"✅";
        } else {
            marker = @"❌";
            extra = [NSString stringWithFormat:@"  (W_OK errno=%d %s — rootSpawn required)",
                     writeErrno, strerror(writeErrno)];
        }
        [s appendFormat:@"  %@ %@%@\n", marker, p, extra];
    }
    return s;
}

// ============================================================================
// Per-section diagnostics via TBDiagnosticProvider conformance
// ============================================================================

+ (NSString *)sectionBlock {
    NSMutableString *s = [NSMutableString string];
    for (Class c in [self diagnosticProviders]) {
        if (c == (Class)NSNull.class || !c) continue;
        if (![c respondsToSelector:@selector(diagnosticInfo)]) continue;
        NSString *info = nil;
        @try {
            info = [c performSelector:@selector(diagnosticInfo)];
        } @catch (NSException *e) {
            info = [NSString stringWithFormat:@"⚠️ %@ threw while gathering diagnostics: %@",
                    NSStringFromClass(c), e];
        }
        if (info.length) {
            [s appendFormat:@"\n── %@ ──\n%@\n", NSStringFromClass(c), info];
        }
    }
    return s;
}

// ============================================================================
// Full report assembly
// ============================================================================

+ (NSString *)fullReport {
    NSMutableString *r = [NSMutableString string];

    [r appendString:@"═══════════ TrollBox diagnostic report ═══════════\n\n"];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    [r appendFormat:@"Generated: %@\n\n", [fmt stringFromDate:[NSDate date]]];

    [r appendString:@"─── Process identity ───\n"];
    [r appendString:[self processIdentityBlock]];

    [r appendString:@"\n─── Writability checks ───\n"];
    [r appendString:[self writabilityBlock]];

    [r appendString:@"\n─── rootSpawn liveness ───\n"];
    [r appendString:[self rootSpawnLivenessBlock]];

    [r appendString:@"\n─── Section diagnostics ───\n"];
    [r appendString:[self sectionBlock]];

    [r appendString:@"\n═══════════ end of report ═══════════\n"];
    return r;
}

@end
