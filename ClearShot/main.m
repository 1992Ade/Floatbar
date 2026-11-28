#import <UIKit/UIKit.h>
#import <unistd.h>
#import "CSAppDelegate.h"

// Elevate to root BEFORE UIKit spins up. TrollStore's platform-application +
// no-sandbox + no-container entitlements give us the RIGHT to elevate, but
// LaunchServices starts us at uid=501 (mobile) for compatibility — we have
// to make the setuid(0)/setgid(0) call ourselves, same pattern Andromeda
// uses in its own main.m. Without this, every root-owned path write
// (/Library/ControlCenter/Bundles for ClearShot, /Library/LaunchDaemons for
// ResSetter, /private/var/log for Reclaim Space, /var/Managed Preferences
// for the Don't Lock After Respring toggle) silently fails and rootSpawn
// returns exit=-1 because the kernel SIGKILLs the persona-overridden child.
//
// After these two lines: getuid() == geteuid() == 0, and NSFileManager
// writes/removes anywhere / allows us to write.
// Captured once at launch so the Diagnostics screen can report the exact
// reason setuid(0) refused — without this we'd see "euid=501" with no way
// to tell EPERM (not platformized) from EINVAL (persona mgmt not up) from
// anything else. The symbol is read by TBDiagnosticsManager.
int kTBSetuidErrno = 0;
int kTBSetgidErrno = 0;

int main(int argc, char *argv[]) {
    errno = 0;
    if (setuid(0) != 0) kTBSetuidErrno = errno;
    errno = 0;
    if (setgid(0) != 0) kTBSetgidErrno = errno;
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([CSAppDelegate class]));
    }
}
