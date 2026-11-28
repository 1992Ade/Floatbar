#import "STMainViewController.h"
#import "TFInjector.h"
#import "CSProcessUtils.h"
#import "TBSpringBoardPrefs.h"
#import "BCMainViewController.h"

// SpringBoard bundle ID — target for every hook in this section.
static NSString * const kSpringBoardBundleID = @"com.apple.springboard";

// Hook leafnames we ship bundled. Each resolves to a dylib living alongside
// our app binary at /Applications/ClearShot.app/<leaf>.
static NSString * const kHookClearAll = @"libClearAllHook.dylib";

@interface STMainViewController () <UITableViewDataSource, UITableViewDelegate>
@property (strong, nonatomic) UITableView *table;
@property (strong, nonatomic) UISwitch *clearAllSwitch;
@property (strong, nonatomic) UISwitch *dontLockSwitch;
@end

@implementation STMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"SpringBoard Tweaks";
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];

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

#pragma mark - Hook state

- (BOOL)isHookActive:(NSString *)leaf {
    return [[TFInjector injectedDylibLeafsForAppID:kSpringBoardBundleID]
             containsObject:leaf];
}

#pragma mark - Table layout
// 0: Quick actions  (respring now — always-available, no toggle required)
// 1: Appearance    (Badge Color push)
// 2: Hooks         (Clear All toggle)
// 3: Persistence   (Don't Lock mirror)
// 4: SpringBoard state + uninject-all nuke

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 5; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;   // Respring now
    if (s == 1) return 1;   // Badge Color
    if (s == 2) return 1;   // Clear All
    if (s == 3) return 1;   // Don't lock
    return 2;                // status row + nuke row
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"Quick actions";
    if (s == 1) return @"Appearance";
    if (s == 2) return @"Hooks";
    if (s == 3) return @"Persistence";
    return @"SpringBoard state";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        return @"Kills SpringBoard immediately. Any pending visual change "
               @"(Badge Color, hook toggles, Don't-lock-after-respring) is "
               @"picked up on the next launch.";
    }
    if (s == 1) {
        return @"Badge Color recolors SpringBoard notification pips system-wide. "
               @"It writes a bitmap to the SpringBoard icon cache and needs a "
               @"respring to take effect.";
    }
    if (s == 2) {
        return @"Each toggle injects a dylib into SpringBoard via the Tweaks "
               @"engine (TFInjector). A respring picks up the change. Toggle "
               @"off to eject the dylib and respring again.\n\n"
               @"⚠ Before updating iOS, use \"Uninject all SB hooks\" below "
               @"so SpringBoard launches clean on the new system version.";
    }
    if (s == 3) {
        return @"Mirrored toggle: this is the same SBDontLockAfterCrash key "
               @"Badge Color and ClearShot write. Change any one, all three "
               @"sections stay in sync.";
    }
    if (s == 4) {
        NSArray *leafs = [TFInjector injectedDylibLeafsForAppID:kSpringBoardBundleID];
        if (leafs.count == 0) return @"No TrollBox hooks are currently injected into SpringBoard.";
        return [NSString stringWithFormat:@"Injected now: %@",
                 [leafs componentsJoinedByString:@", "]];
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc]
                              initWithStyle:UITableViewCellStyleSubtitle
                             reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    cell.detailTextLabel.numberOfLines = 0;

    if (ip.section == 0) {
        cell.textLabel.text = @"Respring now";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    } else if (ip.section == 1) {
        cell.textLabel.text = @"Badge Color";
        cell.detailTextLabel.text = @"Recolor SpringBoard notification badges";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    } else if (ip.section == 2) {
        cell.textLabel.text = @"Clear All in app switcher";
        cell.detailTextLabel.text = @"Adds a Clear All button to the native app "
                                     @"switcher — kills every app except "
                                     @"SpringBoard, backboardd, mediaserverd "
                                     @"and TrollBox.";
        if (!self.clearAllSwitch) {
            self.clearAllSwitch = [[UISwitch alloc] init];
            [self.clearAllSwitch addTarget:self action:@selector(didToggleClearAll:)
                            forControlEvents:UIControlEventValueChanged];
        }
        self.clearAllSwitch.on = [self isHookActive:kHookClearAll];
        cell.accessoryView = self.clearAllSwitch;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

    } else if (ip.section == 3) {
        cell.textLabel.text = @"Don't lock device after respring";
        BOOL on = [TBSpringBoardPrefs dontLockActive];
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
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

    } else {
        if (ip.row == 0) {
            NSArray *leafs = [TFInjector injectedDylibLeafsForAppID:kSpringBoardBundleID];
            cell.textLabel.text = [NSString stringWithFormat:
                                    @"%lu dylib%@ injected into SpringBoard",
                                    (unsigned long)leafs.count,
                                    leafs.count == 1 ? @"" : @"s"];
            cell.detailTextLabel.text = leafs.count
                ? [leafs componentsJoinedByString:@"\n"]
                : @"SpringBoard is untouched.";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"Uninject all SB hooks + respring";
            cell.textLabel.textColor = [UIColor systemRedColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.detailTextLabel.text = nil;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) {
        // Quick action: respring immediately. No confirmation sheet — the
        // whole point of the button being here is a one-tap path.
        [CSProcessUtils forceRespring];
    } else if (ip.section == 1) {
        BCMainViewController *vc = [[BCMainViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (ip.section == 4 && ip.row == 1) {
        [self confirmNuke];
    }
}

#pragma mark - Toggles

- (void)didToggleClearAll:(UISwitch *)sw {
    [self toggleHook:kHookClearAll on:sw.on sender:sw];
}

- (void)toggleHook:(NSString *)leaf on:(BOOL)on sender:(UISwitch *)sw {
    if (on) {
        NSString *src = [[[NSBundle mainBundle] bundlePath]
                          stringByAppendingPathComponent:leaf];
        if (![[NSFileManager defaultManager] fileExistsAtPath:src]) {
            sw.on = NO;
            [self alert:@"Dylib missing"
                message:[NSString stringWithFormat:
                          @"%@ isn't in the app bundle. Rebuild TrollBox with "
                          @"the Hook target compiled.", leaf]];
            return;
        }
        NSError *err = nil;
        NSString *out = [TFInjector injectDylibAtPath:src
                                             intoAppID:kSpringBoardBundleID
                                                 error:&err];
        if (!out) {
            sw.on = NO;
            [self alert:@"Inject failed"
                message:err.localizedDescription ?: @"unknown"];
            return;
        }
    } else {
        NSError *err = nil;
        BOOL ok = [TFInjector ejectDylibLeaf:leaf
                                   fromAppID:kSpringBoardBundleID
                                       error:&err];
        if (!ok) {
            sw.on = YES;
            [self alert:@"Eject failed"
                message:err.localizedDescription ?: @"unknown"];
            return;
        }
    }
    [self confirmRespring];
    [self.table reloadData];
}

- (void)didToggleDontLock:(UISwitch *)sw {
    NSError *err = nil;
    if (![TBSpringBoardPrefs setDontLockActive:sw.on error:&err]) {
        sw.on = !sw.on;
        [self alert:@"Write failed"
            message:err.localizedDescription ?: @"unknown"];
        return;
    }
    [self.table reloadSections:[NSIndexSet indexSetWithIndex:2]
              withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - Nuke all SB hooks

- (void)confirmNuke {
    NSArray *leafs = [TFInjector injectedDylibLeafsForAppID:kSpringBoardBundleID];
    if (leafs.count == 0) {
        [self alert:@"Nothing to uninject"
            message:@"SpringBoard has no TrollBox hooks currently injected."];
        return;
    }
    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Uninject all SB hooks"
                              message:[NSString stringWithFormat:
                                        @"Remove %lu dylib%@ from SpringBoard "
                                        @"and respring?\n\n%@\n\n"
                                        @"After the respring, SpringBoard is "
                                        @"back to stock. Safe to update iOS.",
                                        (unsigned long)leafs.count,
                                        leafs.count == 1 ? @"" : @"s",
                                        [leafs componentsJoinedByString:@"\n"]]
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Uninject + respring"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        NSArray *list = [TFInjector injectedDylibLeafsForAppID:kSpringBoardBundleID];
        for (NSString *leaf in list) {
            [TFInjector ejectDylibLeaf:leaf fromAppID:kSpringBoardBundleID error:nil];
        }
        [CSProcessUtils forceRespring];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Respring prompt

- (void)confirmRespring {
    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Respring"
                              message:@"The hook change needs a respring to take effect."
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

#pragma mark - Alert

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
