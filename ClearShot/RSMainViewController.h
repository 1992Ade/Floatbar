#import <UIKit/UIKit.h>

// ResSetter — display resolution multiplier.
//
// 2.0.2 rewrite: the write/reset path is now a verbatim port of haoict's
// ResolutionSetterSwift (TrollStore version 1.1) — stage the plist in
// /private/var/tmp/com.trollbox.iokit/, then rootSpawn /bin/cp -f to the
// system destination. Our 2.0.0 shortcut (writeToURL: on the root-owned
// path) failed silently at euid=501 and was the bricking cause. Our
// additions on top of haoict's logic: a LaunchDaemon that re-applies the
// last-saved size at every boot, an in-app Reset button that cleans all
// three files, and the Don't-Lock-After-Respring mirror shared with the
// other sections.
@interface RSMainViewController : UIViewController
@end
