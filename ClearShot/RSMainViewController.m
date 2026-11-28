#import "RSMainViewController.h"
#import "CSProcessUtils.h"
#import "TBSpringBoardPrefs.h"
#import <sys/stat.h>
#import <unistd.h>

// ============================================================================
// Paths and keys
//
// The write path is now a port of haoict's ResolutionSetterSwift (TrollStore
// 1.1). Reading the shipped binary confirmed: they stage the plist in a
// sandbox-writable path then cp -f it to /var/mobile/Library/Preferences/
// via a child process that has been persona-promoted to uid=0. They write
// XML plist (not binary — our prior assumption was wrong). They use the
// four keys canvas_width / canvas_height / screenWidth / screenHeight in
// landscape form.
// ============================================================================

// Landing path iOS actually reads.
static NSString * const kGfxPlist =
    @"/var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist";

// Sandbox-accessible staging directory. haoict uses
// /private/var/tmp/com.haoict.iokit.IOMobileGraphicsFamily/; we use our own
// slug to avoid stepping on their files if the user had their app installed
// before. Our process can writeToURL: here directly even at euid=501
// because /private/var/tmp is 0777 on iOS.
static NSString * const kGfxStageDir  =
    @"/private/var/tmp/com.trollbox.iokit";
static NSString * const kGfxStagePath =
    @"/private/var/tmp/com.trollbox.iokit/com.apple.iokit.IOMobileGraphicsFamily.plist";

// LaunchDaemon that re-applies the saved backup on every boot. This is OUR
// addition on top of haoict's logic (they document "reboot to revert" as
// the escape hatch — there's no persistence).
static NSString * const kAutoApplyDaemonPath =
    @"/Library/LaunchDaemons/com.trollbox.ressetter.plist";
static NSString * const kAutoApplyBackupPath =
    @"/var/mobile/Library/Preferences/TrollBoxGfxBackup.plist";
static NSString * const kAutoApplyDaemonLabel = @"com.trollbox.ressetter";

// NSUserDefaults keys.
static NSString * const kFactorKey      = @"TBResSetterFactor";
static NSString * const kLastWidthKey   = @"TBResSetterLastWidth";
static NSString * const kLastHeightKey  = @"TBResSetterLastHeight";

// The gfx plist keys ResSetter writes/removes.
static NSString * const kGfxCanvasWidth  = @"canvas_width";
static NSString * const kGfxCanvasHeight = @"canvas_height";
static NSString * const kGfxScreenWidth  = @"screenWidth";
static NSString * const kGfxScreenHeight = @"screenHeight";

// Slider bounds — same range haoict exposes in the app, plus their built-in
// warning about going too far.
static const double kFactorMin = 1.0;
static const double kFactorMax = 1.5;

// ============================================================================

@interface RSMainViewController () <UITableViewDataSource, UITableViewDelegate>
@property (strong, nonatomic) UITableView *table;
@property (assign, nonatomic) double factor;
@property (strong, nonatomic) UISlider *factorSlider;
@property (strong, nonatomic) UILabel *factorReadout;
@property (strong, nonatomic) UISwitch *autoApplySwitch;
@property (strong, nonatomic) UISwitch *dontLockSwitch;
@end

@implementation RSMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.title = @"ResSetter";

    [self loadFactor];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds
                                              style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = self.view.backgroundColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.table reloadData];
}

#pragma mark - Factor persistence

- (void)loadFactor {
    double f = [[NSUserDefaults standardUserDefaults] doubleForKey:kFactorKey];
    if (f < kFactorMin || f > kFactorMax) f = 1.0;
    self.factor = f;
}

- (void)saveFactor:(double)f {
    self.factor = f;
    [[NSUserDefaults standardUserDefaults] setDouble:f forKey:kFactorKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Device native (LANDSCAPE form)

// iOS expects canvas_width / canvas_height in the gfx plist to be the
// landscape-orientation form of the panel (width = long side, height =
// short side). UIScreen.nativeBounds returns portrait form on a portrait
// phone, so we MAX / MIN on the way out. Same convention haoict uses.
- (CGSize)deviceNativeSize {
    UIScreen *s = [UIScreen mainScreen];
    CGRect nb = [s respondsToSelector:@selector(nativeBounds)] ? s.nativeBounds : s.bounds;
    CGFloat longer  = MAX(nb.size.width, nb.size.height);
    CGFloat shorter = MIN(nb.size.width, nb.size.height);
    return CGSizeMake(longer, shorter);
}

// Same convention for "Current" — read whatever's in the plist, normalize.
- (CGSize)currentPixelSize {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kGfxPlist];
    NSNumber *w = d[kGfxCanvasWidth];
    NSNumber *h = d[kGfxCanvasHeight];
    if (w.doubleValue > 0 && h.doubleValue > 0) {
        CGFloat longer  = MAX(w.doubleValue, h.doubleValue);
        CGFloat shorter = MIN(w.doubleValue, h.doubleValue);
        return CGSizeMake(longer, shorter);
    }
    return [self deviceNativeSize];
}

- (CGSize)targetPixelSize {
    CGSize n = [self deviceNativeSize];
    return CGSizeMake(round(n.width * self.factor),
                      round(n.height * self.factor));
}

#pragma mark - Table layout
// 0: This device (Native + Current)
// 1: Multiplier (slider, target preview, apply)
// 2: Reset to native (single destructive button)
// 3: Persistence (re-apply boot + don't lock)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 2;         // native + current
    if (s == 1) return 3;         // slider row, target row, apply row
    if (s == 2) return 1;         // reset
    return 2;                      // 2 persistence toggles
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"This device";
    if (s == 1) return @"Multiplier";
    if (s == 2) return @"Recover";
    return @"Persistence";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) {
        return @"Slide between ×1.00 and ×1.50. Target = native × factor, "
               @"rounded to whole pixels in landscape form.\n\n"
               @"⚠ haoict's warning stands: don't push the factor to crazy "
               @"values. If the screen becomes black or unusable, reboot "
               @"the phone to return to the native resolution.";
    }
    if (s == 2) {
        return @"Nukes every trace ResSetter left behind: the LaunchDaemon "
               @"(if installed), the saved backup plist, the gfx plist, and "
               @"the persisted factor. All path-removals go through "
               @"rootSpawn — they succeed even when our main process can't "
               @"touch root-owned files directly.";
    }
    if (s == 3) {
        return @"• Re-apply at every boot: installs a LaunchDaemon that "
               @"restores the last-applied size before backboardd reads it.\n\n"
               @"• Don't lock device after respring: writes "
               @"SBDontLockAfterCrash=YES to SpringBoard's managed prefs. "
               @"Mirrored in SpringBoard Tweaks, Badge Color and ClearShot "
               @"— change any one, all four stay in sync.";
    }
    return nil;
}

#pragma mark - Table cells

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc]
                              initWithStyle:UITableViewCellStyleSubtitle
                             reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    cell.textLabel.font = [UIFont systemFontOfSize:17];

    if (ip.section == 0) {
        if (ip.row == 0) {
            CGSize n = [self deviceNativeSize];
            cell.textLabel.text = @"Native hardware panel";
            cell.detailTextLabel.text = [NSString stringWithFormat:
                                         @"%d × %d pixels (landscape)",
                                         (int)n.width, (int)n.height];
        } else {
            CGSize c = [self currentPixelSize];
            cell.textLabel.text = @"Current";
            cell.detailTextLabel.text = [NSString stringWithFormat:
                                         @"%d × %d pixels",
                                         (int)c.width, (int)c.height];
        }

    } else if (ip.section == 1) {
        if (ip.row == 0) {
            cell.textLabel.text = nil;
            cell.detailTextLabel.text = nil;
            [self installSliderCell:cell];

        } else if (ip.row == 1) {
            CGSize t = [self targetPixelSize];
            cell.textLabel.text = @"Target";
            cell.detailTextLabel.text = [NSString stringWithFormat:
                                         @"%d × %d pixels",
                                         (int)t.width, (int)t.height];

        } else {
            cell.textLabel.text = @"Apply";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }

    } else if (ip.section == 2) {
        cell.textLabel.text = @"Reset to native";
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    } else {
        if (ip.row == 0) {
            cell.textLabel.text = @"Re-apply at every boot";
            BOOL on = [self autoApplyActive];
            cell.detailTextLabel.text = on
                ? @"LaunchDaemon installed."
                : @"Off — resolution reverts to native on reboot.";
            if (!self.autoApplySwitch) {
                self.autoApplySwitch = [[UISwitch alloc] init];
                [self.autoApplySwitch addTarget:self action:@selector(didToggleAutoApply:)
                                forControlEvents:UIControlEventValueChanged];
            }
            self.autoApplySwitch.on = on;
            cell.accessoryView = self.autoApplySwitch;
        } else {
            cell.textLabel.text = @"Don't lock device after respring";
            BOOL on = [self dontLockActive];
            cell.detailTextLabel.text = on
                ? @"SBDontLockAfterCrash = YES."
                : @"Off — passcode prompt returns after respring.";
            if (!self.dontLockSwitch) {
                self.dontLockSwitch = [[UISwitch alloc] init];
                [self.dontLockSwitch addTarget:self action:@selector(didToggleDontLock:)
                               forControlEvents:UIControlEventValueChanged];
            }
            self.dontLockSwitch.on = on;
            cell.accessoryView = self.dontLockSwitch;
        }
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 1 && ip.row == 0) return 72;
    return UITableViewAutomaticDimension;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1 && ip.row == 2) [self confirmApply];
    else if (ip.section == 2)           [self confirmReset];
}

#pragma mark - Slider cell

- (void)installSliderCell:(UITableViewCell *)cell {
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    if (!self.factorSlider) {
        self.factorSlider = [[UISlider alloc] init];
        self.factorSlider.minimumValue = (float)kFactorMin;
        self.factorSlider.maximumValue = (float)kFactorMax;
        self.factorSlider.tintColor    = [UIColor systemBlueColor];
        [self.factorSlider addTarget:self action:@selector(didSlideFactor:)
                     forControlEvents:UIControlEventValueChanged];
    }
    self.factorSlider.value = (float)self.factor;

    if (!self.factorReadout) {
        self.factorReadout = [[UILabel alloc] init];
        self.factorReadout.font = [UIFont monospacedDigitSystemFontOfSize:17
                                                                   weight:UIFontWeightSemibold];
        self.factorReadout.textColor = [UIColor whiteColor];
        self.factorReadout.textAlignment = NSTextAlignmentRight;
    }
    self.factorReadout.text = [NSString stringWithFormat:@"×%.2f", self.factor];

    UILabel *header = [[UILabel alloc] init];
    header.text = @"Factor";
    header.textColor = [UIColor whiteColor];
    header.font = [UIFont systemFontOfSize:15];
    header.translatesAutoresizingMaskIntoConstraints = NO;

    self.factorSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.factorReadout.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:header];
    [cell.contentView addSubview:self.factorReadout];
    [cell.contentView addSubview:self.factorSlider];

    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
        [header.topAnchor     constraintEqualToAnchor:cell.contentView.topAnchor constant:10],

        [self.factorReadout.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20],
        [self.factorReadout.centerYAnchor  constraintEqualToAnchor:header.centerYAnchor],
        [self.factorReadout.widthAnchor    constraintEqualToConstant:72],

        [self.factorSlider.leadingAnchor  constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
        [self.factorSlider.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20],
        [self.factorSlider.topAnchor      constraintEqualToAnchor:header.bottomAnchor constant:8],
        [self.factorSlider.bottomAnchor   constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
    ]];
}

- (void)didSlideFactor:(UISlider *)s {
    double v = round(s.value * 100.0) / 100.0;
    [self saveFactor:v];
    self.factorReadout.text = [NSString stringWithFormat:@"×%.2f", self.factor];
    [self.table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:1]]
                      withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Core write path (haoict pattern — stage then rootSpawn cp)

// Write the full plist dict (XML, haoict-style) to the system destination.
// Returns a human-readable error string on failure, or nil on success.
- (NSString *)writeGfxPlist:(NSDictionary *)d {
    NSFileManager *fm = [NSFileManager defaultManager];

    // 1. Make sure the stage directory exists. /private/var/tmp is 0777 so
    //    we can create a subdirectory at euid=501 without rootSpawn.
    NSError *mkdirErr = nil;
    if (![fm createDirectoryAtPath:kGfxStageDir
                withIntermediateDirectories:YES
                                 attributes:nil
                                      error:&mkdirErr]) {
        return [NSString stringWithFormat:@"Couldn't create stage dir %@: %@",
                kGfxStageDir, mkdirErr.localizedDescription ?: @"?"];
    }

    // 2. Write the plist to the stage. writeToURL: produces XML format, the
    //    same shape haoict's ResolutionSetterSwift ships (confirmed from
    //    the IPA strings: <?xml version="1.0" encoding="UTF-8"?> + plist
    //    DOCTYPE). The sandbox allows us to write here directly even at
    //    euid=501.
    NSError *writeErr = nil;
    if (![d writeToURL:[NSURL fileURLWithPath:kGfxStagePath] error:&writeErr]) {
        return [NSString stringWithFormat:@"Stage write failed: %@",
                writeErr.localizedDescription ?: @"?"];
    }

    // 3. cp -f via rootSpawn so the copy lands on /var/mobile/Library/Preferences/
    //    even though that file is root-owned. In-process NSFileManager would
    //    fail silently here (the 2.0.0 brick). rootSpawn uses persona_np
    //    to promote the child to uid=0, same mechanism haoict's app uses.
    NSString *spawnOut = nil, *spawnErr = nil;
    int rc = [CSProcessUtils rootSpawn:@"/bin/cp"
                                  args:@[@"-f", kGfxStagePath, kGfxPlist]
                                stdOut:&spawnOut stdErr:&spawnErr];
    if (rc != 0) {
        return [NSString stringWithFormat:
                @"rootSpawn /bin/cp exit=%d\nstderr: %@\nstdout: %@",
                rc, spawnErr ?: @"(none)", spawnOut ?: @"(none)"];
    }
    return nil;
}

#pragma mark - Apply

- (void)confirmApply {
    CGSize t = [self targetPixelSize];
    NSString *msg = [NSString stringWithFormat:
                     @"Apply %d × %d pixels (native × %.2f)?\n\n"
                     @"A respring is needed to pick up the change. If the "
                     @"screen becomes unusable at this factor, reboot the "
                     @"phone to revert to native.",
                     (int)t.width, (int)t.height, self.factor];
    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Apply resolution"
                              message:msg
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Apply"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        [self applyTargetSize:t];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)applyTargetSize:(CGSize)t {
    NSInteger w = (NSInteger)t.width;
    NSInteger h = (NSInteger)t.height;

    // Merge with the existing plist (preserve any iOS-written sibling keys).
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:kGfxPlist];
    if (existing) [d addEntriesFromDictionary:existing];
    d[kGfxCanvasWidth]  = @(w);
    d[kGfxCanvasHeight] = @(h);
    d[kGfxScreenWidth]  = @(w);
    d[kGfxScreenHeight] = @(h);

    NSString *err = [self writeGfxPlist:d];
    if (err) {
        [self alert:@"Apply failed" message:err];
        return;
    }

    [[NSUserDefaults standardUserDefaults] setInteger:w forKey:kLastWidthKey];
    [[NSUserDefaults standardUserDefaults] setInteger:h forKey:kLastHeightKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if ([self autoApplyActive]) [self writeBackupForWidth:w height:h];
    [self.table reloadData];

    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Applied"
                              message:@"Respring now to pick up the new size?"
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Later"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Respring now"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [CSProcessUtils forceRespring];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Reset (nuke everything via rootSpawn)

- (void)confirmReset {
    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Reset to native"
                              message:@"Nuke ResSetter's full state:\n\n"
                                      @"  • /Library/LaunchDaemons/com.trollbox.ressetter.plist\n"
                                      @"  • /var/mobile/Library/Preferences/TrollBoxGfxBackup.plist\n"
                                      @"  • /var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist\n"
                                      @"  • NSUserDefaults factor\n\n"
                                      @"All removals go through rootSpawn so they succeed even "
                                      @"at euid=501. Respring after to return to native."
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Reset + respring"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        [self performReset];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)performReset {
    NSMutableArray<NSString *> *log = [NSMutableArray array];
    NSArray<NSString *> *targets = @[
        kAutoApplyDaemonPath,
        kAutoApplyBackupPath,
        kGfxPlist,
    ];
    for (NSString *p in targets) {
        if (access([p fileSystemRepresentation], F_OK) != 0) {
            [log addObject:[NSString stringWithFormat:@"— %@ (absent)", p]];
            continue;
        }
        NSString *out = nil, *errStr = nil;
        int rc = [CSProcessUtils rootSpawn:@"/bin/rm"
                                      args:@[@"-f", p]
                                    stdOut:&out stdErr:&errStr];
        if (rc == 0) {
            [log addObject:[NSString stringWithFormat:@"✅ %@", p]];
        } else {
            [log addObject:[NSString stringWithFormat:@"❌ %@ (rc=%d %@)",
                            p, rc, errStr ?: @"?"]];
        }
    }

    // Reset NSUserDefaults factor/last size.
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    [u removeObjectForKey:kFactorKey];
    [u removeObjectForKey:kLastWidthKey];
    [u removeObjectForKey:kLastHeightKey];
    [u synchronize];
    self.factor = 1.0;
    [log addObject:@"✅ NSUserDefaults (factor + last size)"];

    [self.table reloadData];

    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Reset done"
                              message:[log componentsJoinedByString:@"\n"]
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Later"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Respring now"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        [CSProcessUtils forceRespring];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Persist across reboot (LaunchDaemon — our own addition)

- (BOOL)autoApplyActive {
    return [[NSFileManager defaultManager] fileExistsAtPath:kAutoApplyDaemonPath];
}

- (BOOL)writeBackupForWidth:(NSInteger)w height:(NSInteger)h {
    NSDictionary *payload = @{
        kGfxCanvasWidth:  @(w),
        kGfxCanvasHeight: @(h),
        kGfxScreenWidth:  @(w),
        kGfxScreenHeight: @(h),
    };
    // /var/mobile/Library/Preferences is user-mobile-owned, so a direct
    // writeToURL: here is fine at euid=501 (unlike the system gfx plist).
    NSError *err = nil;
    BOOL ok = [payload writeToURL:[NSURL fileURLWithPath:kAutoApplyBackupPath]
                            error:&err];
    if (!ok) NSLog(@"[TrollBox/Res] backup write err=%@", err);
    return ok;
}

- (BOOL)installAutoApplyDaemonForWidth:(NSInteger)w height:(NSInteger)h
                                 error:(NSError **)outErr {
    if (![self writeBackupForWidth:w height:h]) {
        if (outErr) *outErr = [NSError errorWithDomain:@"TrollBox" code:10
                                               userInfo:@{NSLocalizedDescriptionKey:
            @"Couldn't write the backup plist the LaunchDaemon depends on."}];
        return NO;
    }

    NSString *shellCmd = [NSString stringWithFormat:
        @"/bin/cp -f '%@' '%@'", kAutoApplyBackupPath, kGfxPlist];
    NSDictionary *daemon = @{
        @"Label":            kAutoApplyDaemonLabel,
        @"ProgramArguments": @[ @"/bin/sh", @"-c", shellCmd ],
        @"RunAtLoad":        @YES,
        @"UserName":         @"root",
        @"GroupName":        @"wheel",
    };

    // Stage in tmp, cp -f via rootSpawn — same pattern as the gfx plist.
    // Skip the previous "try direct writeToURL first" shortcut since it
    // never succeeds at euid=501 and its failure path produced the
    // misleading "root authorization" error.
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          @"com.trollbox.ressetter.plist"];
    if (![daemon writeToURL:[NSURL fileURLWithPath:tmpPath] error:outErr]) return NO;

    NSString *out = nil, *errStr = nil;
    int rc = [CSProcessUtils rootSpawn:@"/bin/cp"
                                  args:@[@"-f", tmpPath, kAutoApplyDaemonPath]
                                stdOut:&out stdErr:&errStr];
    if (rc != 0) {
        if (outErr) *outErr = [NSError errorWithDomain:@"TrollBox" code:11
                                               userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"rootSpawn cp exit=%d%@%@",
             rc,
             errStr.length ? [@"\nstderr: " stringByAppendingString:errStr] : @"",
             out.length    ? [@"\nstdout: " stringByAppendingString:out]    : @""]}];
        return NO;
    }
    [CSProcessUtils rootSpawn:@"/usr/sbin/chown" args:@[@"root:wheel", kAutoApplyDaemonPath]
                       stdOut:NULL stdErr:NULL];
    [CSProcessUtils rootSpawn:@"/bin/chmod"     args:@[@"0644", kAutoApplyDaemonPath]
                       stdOut:NULL stdErr:NULL];
    return YES;
}

- (void)removeAutoApplyDaemon {
    if (access([kAutoApplyDaemonPath fileSystemRepresentation], F_OK) != 0) return;
    [CSProcessUtils rootSpawn:@"/bin/rm" args:@[@"-f", kAutoApplyDaemonPath]
                       stdOut:NULL stdErr:NULL];
}

- (void)didToggleAutoApply:(UISwitch *)sw {
    if (sw.on) {
        NSInteger w = [[NSUserDefaults standardUserDefaults] integerForKey:kLastWidthKey];
        NSInteger h = [[NSUserDefaults standardUserDefaults] integerForKey:kLastHeightKey];
        if (w <= 0 || h <= 0) {
            [self alert:@"Apply once first"
                message:@"Set a factor and tap Apply at least once so the "
                        @"daemon has a size to restore."];
            sw.on = NO;
            return;
        }
        UIAlertController *ac = [UIAlertController
                                  alertControllerWithTitle:@"Re-apply at every boot"
                                  message:[NSString stringWithFormat:
                                           @"Install a LaunchDaemon that restores "
                                           @"%ld × %ld at each boot?",
                                           (long)w, (long)h]
                                  preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                               style:UIAlertActionStyleCancel
                                             handler:^(UIAlertAction *a) {
            sw.on = NO;
        }]];
        [ac addAction:[UIAlertAction actionWithTitle:@"Install daemon"
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *a) {
            NSError *err = nil;
            BOOL ok = [self installAutoApplyDaemonForWidth:w height:h error:&err];
            if (!ok) {
                sw.on = NO;
                [self alert:@"Install failed"
                    message:[NSString stringWithFormat:@"%@\n\nTarget:\n%@",
                             err.localizedDescription ?: @"unknown",
                             kAutoApplyDaemonPath]];
            }
            [self.table reloadData];
        }]];
        [self presentViewController:ac animated:YES completion:nil];
    } else {
        [self removeAutoApplyDaemon];
        [self.table reloadData];
    }
}

#pragma mark - Don't lock after respring (via shared TBSpringBoardPrefs)

- (BOOL)dontLockActive { return [TBSpringBoardPrefs dontLockActive]; }

- (void)didToggleDontLock:(UISwitch *)sw {
    NSError *err = nil;
    if (![TBSpringBoardPrefs setDontLockActive:sw.on error:&err]) {
        sw.on = !sw.on;
        [self alert:@"Write failed"
            message:err.localizedDescription ?: @"unknown"];
        return;
    }
    [self.table reloadSections:[NSIndexSet indexSetWithIndex:3]
              withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - Alerts

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
