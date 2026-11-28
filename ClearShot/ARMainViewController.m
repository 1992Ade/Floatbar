#import "ARMainViewController.h"
#import "ARIPAPatcher.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <objc/runtime.h>

// ============================================================================
// Private StoreKitUI classes (StoreKitUI.framework). Same signatures as
// Muffinstore's MFSRootViewController. Entitlement needed:
// com.apple.itunesstored.private.
// ============================================================================
@interface SKUIItemStateCenter : NSObject
+ (id)defaultCenter;
- (id)_newPurchasesWithItems:(id)items;
- (void)_performPurchases:(id)purchases
         hasBundlePurchase:(BOOL)purchase
         withClientContext:(id)context
           completionBlock:(id)block;
@end
@interface SKUIItem : NSObject
- (id)initWithLookupDictionary:(id)dict;
@end
@interface SKUIItemOffer : NSObject
- (id)initWithLookupDictionary:(id)dict;
@end
@interface SKUIClientContext : NSObject
+ (id)defaultContext;
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString*)identifier;
@property (readonly) NSString *bundleIdentifier;
@property (readonly) NSString *localizedName;
@end
@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (NSArray *)allApplications;
@end

// ============================================================================
// Version picker (inline class — scope is small, no need for a separate file).
//
// Shows every version from the catalog, newest-first, with a verdict column:
//   🟢 highest version compatible with this iOS = Apple's "Latest" pick
//   🔴 above the green line (needs MinimumOSVersion patch)
//   🔵 below the green line (will install directly)
// The "⭐ Latest compatible" shortcut is sticky at the top.
// ============================================================================

@class ARVersionPickerVC;
@protocol ARVersionPickerDelegate <NSObject>
- (void)versionPicker:(ARVersionPickerVC *)vc didPickVersionID:(long long)vid
          bundleString:(NSString *)bundleString
            compatible:(BOOL)compatible
    requiredMinVersion:(NSString *)requiredMinVersion;
- (void)versionPickerDidPickLatestCompatible:(ARVersionPickerVC *)vc;
@end

@interface ARVersionPickerVC : UITableViewController
@property (copy) NSArray<NSDictionary *> *versions;   // sorted newest-first
@property (copy) NSString *deviceOSVersion;           // e.g. "15.8.8"
@property (assign) NSInteger highestCompatibleIndex;  // -1 if none
@property (weak)   id<ARVersionPickerDelegate> delegate;
@end

@implementation ARVersionPickerVC

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {}
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Pick a version";
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                       target:self
                                                       action:@selector(didCancel)];
}

- (void)didCancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// Sections:
// 0 — "⭐ Latest compatible (Apple picks)" sticky
// 1 — Newer versions (red, above green)
// 2 — Compatible versions (green on top, then blue below)

- (NSArray<NSDictionary *> *)newerThanCompatible {
    if (self.highestCompatibleIndex < 0) return self.versions;   // nothing compat → everything is newer
    return [self.versions subarrayWithRange:
            NSMakeRange(0, (NSUInteger)self.highestCompatibleIndex)];
}

- (NSArray<NSDictionary *> *)compatibleOrOlder {
    if (self.highestCompatibleIndex < 0) return @[];
    return [self.versions subarrayWithRange:
            NSMakeRange((NSUInteger)self.highestCompatibleIndex,
                        self.versions.count - (NSUInteger)self.highestCompatibleIndex)];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    if (s == 1) return [self newerThanCompatible].count;
    return [self compatibleOrOlder].count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 1) {
        NSUInteger n = [self newerThanCompatible].count;
        return n ? [NSString stringWithFormat:@"Newer than iOS %@ (needs patch, %lu)",
                     self.deviceOSVersion, (unsigned long)n]
                 : nil;
    }
    if (s == 2) {
        NSUInteger n = [self compatibleOrOlder].count;
        return n ? [NSString stringWithFormat:@"Compatible with iOS %@ (%lu)",
                     self.deviceOSVersion, (unsigned long)n]
                 : nil;
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) {
        return @"Red versions need Info.plist MinimumOSVersion patching before "
               @"install. Tap one for compatibility details and estimated "
               @"success rate.";
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
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    if (ip.section == 0) {
        cell.textLabel.text = @"⭐  Latest compatible (Apple picks)";
        cell.textLabel.textColor = [UIColor systemGreenColor];
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = @"iOS picks the newest version your device supports";
        return cell;
    }

    NSDictionary *v = (ip.section == 1)
        ? [self newerThanCompatible][ip.row]
        : [self compatibleOrOlder][ip.row];

    NSString *bundleVersion = v[@"bundle_version"] ?: @"?";
    NSString *rawMinOS = v[@"minimum_os_version"] ?: v[@"minimumOsVersion"];
    NSString *minOS = rawMinOS.length ? rawMinOS : @"?";
    BOOL minOSKnown = rawMinOS.length > 0;

    // When the catalog doesn't ship minimum_os_version (bilin.eu.org/history/
    // never returns it), highestCompatibleIndex is -1 and every version
    // lands in section 1. A blanket red tint reads as "none of these are
    // installable" which is misleading — we simply don't know. Grey the
    // unknowns instead so the user sees "try at your own risk" rather than
    // "forbidden".
    NSString *icon;
    UIColor *tint;
    if (ip.section == 1 && !minOSKnown) {
        icon = @"⚪️"; tint = [UIColor lightGrayColor];
    } else if (ip.section == 1) {
        icon = @"🔴"; tint = [UIColor systemRedColor];
    } else if (ip.row == 0) {
        icon = @"🟢"; tint = [UIColor systemGreenColor];
    } else {
        icon = @"🔵"; tint = [UIColor systemBlueColor];
    }

    cell.textLabel.text = [NSString stringWithFormat:@"%@  %@", icon, bundleVersion];
    cell.textLabel.textColor = tint;
    cell.detailTextLabel.text = minOSKnown
        ? [NSString stringWithFormat:@"needs iOS %@+", minOS]
        : @"iOS requirement unknown (try at your own risk)";
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];

    if (ip.section == 0) {
        [self.delegate versionPickerDidPickLatestCompatible:self];
        return;
    }

    NSDictionary *v = (ip.section == 1)
        ? [self newerThanCompatible][ip.row]
        : [self compatibleOrOlder][ip.row];

    long long vid = [v[@"external_identifier"] longLongValue];
    NSString *bundleStr = v[@"bundle_version"] ?: @"?";
    NSString *minOS = v[@"minimum_os_version"] ?: v[@"minimumOsVersion"];
    BOOL compatible = (ip.section == 2);

    [self.delegate versionPicker:self
                didPickVersionID:vid
                    bundleString:bundleStr
                      compatible:compatible
              requiredMinVersion:minOS];
}

@end

// ============================================================================
// Main AppRepack VC
// ============================================================================

@interface ARMainViewController () <ARVersionPickerDelegate, UIDocumentPickerDelegate>
@property (strong) NSArray *installedApps;
@property (strong) UIAlertController *progressAlert;
@property (copy)   NSString *pendingPatchMinVersion;  // for the Files patcher flow
@end

@implementation ARMainViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AppRepack";
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;
    [self loadInstalledApps];
}

- (void)loadInstalledApps {
    Class ws = NSClassFromString(@"LSApplicationWorkspace");
    if (!ws) { self.installedApps = @[]; return; }
    id workspace = [ws performSelector:@selector(defaultWorkspace)];
    NSArray *apps = [workspace performSelector:@selector(allApplications)];
    NSMutableArray *user = [NSMutableArray array];
    for (id a in apps) {
        NSString *type = [a performSelector:@selector(applicationType)];
        if (![type isEqualToString:@"User"]) continue;
        [user addObject:a];
    }
    [user sortUsingComparator:^NSComparisonResult(id a, id b) {
        NSString *na = [a performSelector:@selector(localizedName)];
        NSString *nb = [b performSelector:@selector(localizedName)];
        return [na localizedCaseInsensitiveCompare:nb];
    }];
    self.installedApps = user;
}

#pragma mark - Table

// 0: Preamble (info card)
// 1: Start from AppStore URL
// 2: Patch an existing IPA from Files
// 3: Installed apps

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;      // the preamble card
    if (s == 1) return 1;      // URL picker
    if (s == 2) return 1;      // Files patcher
    return MAX((NSInteger)self.installedApps.count, 1);
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 1) return @"Start from AppStore URL";
    if (s == 2) return @"Patch an existing IPA";
    if (s == 3) return @"Installed apps";
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        return @"Port of Muffinstore (mineek) + MinimumOSVersion patcher. "
               @"Uses iOS's native Store download flow (SKUIItemStateCenter) "
               @"via your active Apple ID session — TrollBox never sees your "
               @"password. Version history from apis.bilin.eu.org.\n\n"
               @"Realistic success rates after MinimumOSVersion patch "
               @"(for apps 1 iOS major above):\n"
               @"  • WebView wrappers (Instagram, X, banking…) : ~95 %\n"
               @"  • UIKit classics                             : ~60 %\n"
               @"  • Recent SwiftUI                             : ~30 %\n"
               @"  • Games / AR / Core ML                       : ~10 %\n"
               @"  • Apple system apps                          :   ~0 %\n"
               @"2 majors above: divide by three. 3+ above: forget it.";
    }
    if (s == 2) {
        return @"Pick a .ipa already on your device (Files → Downloads). "
               @"TrollBox will patch its MinimumOSVersion and share the "
               @"result to TrollStore for install.";
    }
    if (s == 3) return @"Tap an installed app to see its version history.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc]
                              initWithStyle:UITableViewCellStyleSubtitle
                             reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];

    if (ip.section == 0) {
        cell.textLabel.text = @"📦  AppRepack · install older or newer app versions";
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = @"Read the footer for success rates by app type.";
        cell.detailTextLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (ip.section == 1) {
        cell.textLabel.text = @"Enter AppStore URL…";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        return cell;
    }
    if (ip.section == 2) {
        cell.textLabel.text = @"Pick .ipa from Files…";
        cell.textLabel.textColor = [UIColor systemMintColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        return cell;
    }
    // Section 3 — installed apps
    if (self.installedApps.count == 0) {
        cell.textLabel.text = @"No user apps installed";
        cell.textLabel.textColor = [UIColor lightGrayColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        id app = self.installedApps[ip.row];
        cell.textLabel.text = [app performSelector:@selector(localizedName)];
        cell.detailTextLabel.text = [app performSelector:@selector(bundleIdentifier)];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) { [self promptForURL]; return; }
    if (ip.section == 2) { [self pickIPAFromFiles]; return; }
    if (ip.section == 3) {
        if (self.installedApps.count == 0) return;
        id app = self.installedApps[ip.row];
        NSString *bid = [app performSelector:@selector(bundleIdentifier)];
        [self lookupBundleID:bid];
    }
}

#pragma mark - URL flow

- (void)promptForURL {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"AppStore URL"
                         message:@"Paste the App Store link to the app you "
                                 @"want an older or newer version of."
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"https://apps.apple.com/app/idXXXXXXXXX";
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Continue"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        NSString *link = ac.textFields.firstObject.text;
        long long trackId = [self parseTrackIdFromURL:link];
        if (trackId == 0) {
            [self alert:@"Invalid link" message:@"Couldn't find an id parameter."];
            return;
        }
        [self fetchVersionsForTrackId:trackId];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (long long)parseTrackIdFromURL:(NSString *)link {
    NSRange r = [link rangeOfString:@"/id"];
    if (r.location == NSNotFound) return 0;
    NSString *tail = [link substringFromIndex:NSMaxRange(r)];
    return [tail longLongValue];
}

- (void)lookupBundleID:(NSString *)bid {
    [self showProgress:@"Looking up on iTunes…"];
    NSString *urlStr = [NSString stringWithFormat:
        @"https://itunes.apple.com/lookup?bundleId=%@&limit=1&media=software", bid];
    NSURLSessionDataTask *t = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr]
        completionHandler:^(NSData *data, NSURLResponse *r, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self dismissProgressAnimated:YES completion:^{
                    if (err || !data) {
                        [self alert:@"Lookup failed"
                            message:err.localizedDescription ?: @"empty response"];
                        return;
                    }
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                          options:0 error:nil];
                    NSArray *results = json[@"results"];
                    if (results.count == 0) {
                        [self alert:@"No match"
                            message:@"iTunes doesn't know this bundle ID."];
                        return;
                    }
                    long long trackId = [results.firstObject[@"trackId"] longLongValue];
                    [self fetchVersionsForTrackId:trackId];
                }];
            });
        }];
    [t resume];
}

- (void)fetchVersionsForTrackId:(long long)trackId {
    [self showProgress:@"Fetching version history…"];
    NSString *urlStr = [NSString stringWithFormat:
        @"https://apis.bilin.eu.org/history/%lld", trackId];
    NSURLSessionDataTask *t = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr]
        completionHandler:^(NSData *data, NSURLResponse *r, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self dismissProgressAnimated:YES completion:^{
                    if (err || !data) {
                        [self alert:@"Catalog unavailable"
                            message:err.localizedDescription ?: @"No records on bilin.eu.org."];
                        return;
                    }
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                          options:0 error:nil];
                    NSArray *versions = json[@"data"];
                    if (versions.count == 0) {
                        [self alert:@"No versions"
                            message:@"The catalog has no records for this app."];
                        return;
                    }
                    [self presentVersionPickerForTrackId:trackId versions:versions];
                }];
            });
        }];
    [t resume];
}

#pragma mark - Picker presentation

- (void)presentVersionPickerForTrackId:(long long)trackId versions:(NSArray *)versions {
    // bilin.eu.org returns newest-first already; normalise anyway.
    NSArray *sorted = [versions sortedArrayUsingComparator:
                        ^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"bundle_version"] compare:a[@"bundle_version"]
                                       options:NSNumericSearch];
    }];

    NSString *deviceOS = [UIDevice currentDevice].systemVersion;
    NSInteger highest = [self highestCompatibleIndexIn:sorted deviceOS:deviceOS];

    ARVersionPickerVC *picker = [[ARVersionPickerVC alloc] init];
    picker.versions = sorted;
    picker.deviceOSVersion = deviceOS;
    picker.highestCompatibleIndex = highest;
    picker.delegate = self;

    UINavigationController *nav = [[UINavigationController alloc]
                                    initWithRootViewController:picker];
    nav.modalPresentationStyle = UIModalPresentationFormSheet;

    // Stash the trackId on the picker via associated object so the delegate
    // callback knows what to download.
    objc_setAssociatedObject(picker, "trackId", @(trackId), OBJC_ASSOCIATION_RETAIN);
    [self presentViewController:nav animated:YES completion:nil];
}

- (NSInteger)highestCompatibleIndexIn:(NSArray<NSDictionary *> *)sorted
                                deviceOS:(NSString *)deviceOS {
    // Iterate newest → oldest, pick the first whose minimum_os_version ≤ device.
    for (NSInteger i = 0; i < (NSInteger)sorted.count; i++) {
        NSString *minOS = sorted[i][@"minimum_os_version"] ?:
                          sorted[i][@"minimumOsVersion"];
        if (!minOS.length) continue;   // unknown → skip for green assignment
        if ([self version:minOS isLessThanOrEqualTo:deviceOS]) return i;
    }
    return -1;
}

- (BOOL)version:(NSString *)a isLessThanOrEqualTo:(NSString *)b {
    return [a compare:b options:NSNumericSearch] != NSOrderedDescending;
}

#pragma mark - ARVersionPickerDelegate

- (void)versionPickerDidPickLatestCompatible:(ARVersionPickerVC *)vc {
    NSNumber *tid = objc_getAssociatedObject(vc, "trackId");
    [vc dismissViewControllerAnimated:YES completion:^{
        [self downloadTrack:tid.longLongValue version:0];
    }];
}

- (void)versionPicker:(ARVersionPickerVC *)vc didPickVersionID:(long long)vid
          bundleString:(NSString *)bundleString
            compatible:(BOOL)compatible
    requiredMinVersion:(NSString *)requiredMinVersion {
    NSNumber *tid = objc_getAssociatedObject(vc, "trackId");
    long long trackId = tid.longLongValue;

    if (compatible) {
        [vc dismissViewControllerAnimated:YES completion:^{
            [self downloadTrack:trackId version:vid];
        }];
        return;
    }

    // Incompatible → gap-aware warning dialog
    NSString *device = [UIDevice currentDevice].systemVersion;
    int gap = [self majorGapFrom:device to:requiredMinVersion];
    NSString *verdict;
    if (gap <= 1)      verdict = @"Likely to work if the app is a WebView wrapper or classic UIKit. May crash at launch if it uses iOS-16+ APIs.";
    else if (gap == 2) verdict = @"Low chance: iOS is two majors behind. Apple's Store will likely refuse — fallback is to grab the .ipa elsewhere and use 'Patch an existing IPA'.";
    else               verdict = @"Very unlikely to work: 3+ iOS majors above.";

    NSString *msg = [NSString stringWithFormat:
        @"Version %@ needs iOS %@+. You're on %@.\n\n%@\n\n"
        @"⚠ Known Store behaviour: when you request a version above your "
        @"device's iOS, iTunesStore silently serves the latest compatible "
        @"version instead of refusing. The MinOS patch therefore doesn't "
        @"get a chance to run through this path.\n\n"
        @"To actually install v%@, grab the .ipa from a 3rd-party catalog "
        @"(AppDB, ipa.aspy.dev) and use \"Patch an IPA from Files\".",
        bundleString, requiredMinVersion ?: @"?", device, verdict, bundleString];

    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Not directly compatible"
                              message:msg
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Get the IPA →"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [vc dismissViewControllerAnimated:YES completion:^{
            [self offerIPASources:trackId bundleString:bundleString];
        }];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Patch an IPA from Files"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [vc dismissViewControllerAnimated:YES completion:^{
            [self pickIPAFromFiles];
        }];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Try Store anyway (will likely downgrade)"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        [vc dismissViewControllerAnimated:YES completion:^{
            [self downloadTrack:trackId version:vid];
        }];
    }]];
    [vc presentViewController:ac animated:YES completion:nil];
}

- (void)offerIPASources:(long long)trackId bundleString:(NSString *)bundleString {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Get the IPA"
                         message:[NSString stringWithFormat:
                                  @"Open one of these catalogs in Safari and "
                                  @"download the .ipa for v%@. Once downloaded "
                                  @"to Files, come back here and tap \"Patch "
                                  @"an IPA from Files\".", bundleString]
                  preferredStyle:UIAlertControllerStyleActionSheet];
    NSDictionary *urls = @{
        @"AppDB":        [NSString stringWithFormat:@"https://appdb.to/app/%lld", trackId],
        @"ipa.aspy.dev": [NSString stringWithFormat:@"https://ipa.aspy.dev/app/%lld", trackId],
        @"ArmConverter": [NSString stringWithFormat:@"https://armconverter.com/decryptedappstore/%lld", trackId],
    };
    for (NSString *name in @[@"AppDB", @"ipa.aspy.dev", @"ArmConverter"]) {
        NSString *url = urls[name];
        [ac addAction:[UIAlertAction actionWithTitle:name
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a) {
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:url]
                                               options:@{}
                                     completionHandler:nil];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = self.view;
    ac.popoverPresentationController.sourceRect =
        CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    [self presentViewController:ac animated:YES completion:nil];
}

- (int)majorGapFrom:(NSString *)deviceOS to:(NSString *)requiredOS {
    int deviceMajor = [[[deviceOS componentsSeparatedByString:@"."] firstObject] intValue];
    int requiredMajor = [[[requiredOS componentsSeparatedByString:@"."] firstObject] intValue];
    return requiredMajor - deviceMajor;
}

#pragma mark - Store download (SKUIItemStateCenter path)

- (void)downloadTrack:(long long)trackId version:(long long)versionId {
    [self showProgress:@"Sending Store purchase request…"];
    NSString *adamId = [NSString stringWithFormat:@"%lld", trackId];
    NSString *appExtVrsId = versionId > 0
        ? [NSString stringWithFormat:@"%lld", versionId] : @"0";

    NSString *offer;
    if (versionId == 0) {
        offer = [NSString stringWithFormat:
            @"productType=C&price=0&salableAdamId=%@&pricingParameters=STDQ"
            @"&clientBuyId=1&installed=0&trolled=1", adamId];
    } else {
        offer = [NSString stringWithFormat:
            @"productType=C&price=0&salableAdamId=%@&pricingParameters=STDQ"
            @"&appExtVrsId=%@&clientBuyId=1&installed=0&trolled=1",
            adamId, appExtVrsId];
    }

    Class itemC   = NSClassFromString(@"SKUIItem");
    Class offerC  = NSClassFromString(@"SKUIItemOffer");
    Class ctrC    = NSClassFromString(@"SKUIItemStateCenter");
    Class ctxC    = NSClassFromString(@"SKUIClientContext");
    if (!itemC || !offerC || !ctrC || !ctxC) {
        [self dismissProgressAnimated:YES completion:^{
            [self alert:@"StoreKitUI missing"
                message:@"Private SKUI* classes aren't exposed in this build."];
        }];
        return;
    }

    SKUIItemOffer *so = [[offerC alloc] initWithLookupDictionary:@{ @"buyParams": offer }];
    SKUIItem *item = [[itemC alloc] initWithLookupDictionary:@{ @"_itemOffer": adamId }];
    [item setValue:so forKey:@"_itemOffer"];
    [item setValue:@"iosSoftware" forKey:@"_itemKindString"];
    if (versionId > 0) [item setValue:@(versionId) forKey:@"_versionIdentifier"];

    SKUIItemStateCenter *center = [ctrC performSelector:@selector(defaultCenter)];
    id purchases = [center _newPurchasesWithItems:@[item]];
    [center _performPurchases:purchases
             hasBundlePurchase:NO
             withClientContext:[ctxC performSelector:@selector(defaultContext)]
               completionBlock:^(id result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissProgressAnimated:YES completion:^{
                [self alert:@"Download started"
                    message:@"iOS is downloading the app. Check your Home "
                            @"Screen for the install progress ring. If the "
                            @"version was incompatible, iOS will silently "
                            @"refuse — in that case use 'Patch an existing "
                            @"IPA' instead."];
            }];
        });
    }];
}

#pragma mark - Patch IPA from Files

- (void)pickIPAFromFiles {
    NSArray *types;
    if (@available(iOS 14.0, *)) {
        types = @[ [UTType typeWithFilenameExtension:@"ipa"] ?: UTTypeData ];
        UIDocumentPickerViewController *dp =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types
                                                                    asCopy:YES];
        dp.delegate = self;
        [self presentViewController:dp animated:YES completion:nil];
    } else {
        [self alert:@"iOS 14+ required" message:@"Document picker API needs iOS 14 or later."];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
   didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;

    // Read current version first, so the "new version" dialog shows context.
    NSError *err = nil;
    NSString *current = [ARIPAPatcher minimumOSVersionOfIPAAtPath:url.path error:&err];
    NSString *device = [UIDevice currentDevice].systemVersion;
    NSString *msg = [NSString stringWithFormat:
                      @"Current MinimumOSVersion: %@\nYour iOS: %@\n\n"
                      @"Patch to:",
                      current ?: @"(unknown)", device];

    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Patch IPA"
                              message:msg
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.text = device;    // suggest the device OS version
        f.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Patch"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        NSString *target = ac.textFields.firstObject.text;
        [self patchIPAAtPath:url.path toVersion:target];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)patchIPAAtPath:(NSString *)path toVersion:(NSString *)ver {
    [self showProgress:@"Patching IPA…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        NSString *outIPA = [ARIPAPatcher patchedIPAFromIPAAtPath:path
                                           newMinimumOSVersion:ver
                                                         error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissProgressAnimated:YES completion:^{
                if (!outIPA) {
                    [self alert:@"Patch failed"
                        message:err.localizedDescription ?: @"unknown"];
                    return;
                }
                // Share sheet for TrollStore handoff.
                NSURL *url = [NSURL fileURLWithPath:outIPA];
                UIActivityViewController *av =
                    [[UIActivityViewController alloc] initWithActivityItems:@[url]
                                                     applicationActivities:nil];
                av.popoverPresentationController.sourceView = self.view;
                av.popoverPresentationController.sourceRect =
                    CGRectMake(self.view.bounds.size.width/2, 0, 1, 1);
                [self presentViewController:av animated:YES completion:nil];
            }];
        });
    });
}

#pragma mark - Progress alert

- (void)showProgress:(NSString *)msg {
    self.progressAlert = [UIAlertController
        alertControllerWithTitle:@"Working"
                         message:msg
                  preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:self.progressAlert animated:YES completion:nil];
}

- (void)dismissProgressAnimated:(BOOL)animated completion:(void (^)(void))c {
    if (self.progressAlert) {
        [self.progressAlert dismissViewControllerAnimated:animated completion:c];
        self.progressAlert = nil;
    } else if (c) c();
}

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
