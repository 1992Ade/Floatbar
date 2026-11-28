#import "TBAboutViewController.h"

@implementation TBAboutViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.title = @"About";

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.alwaysBounceVertical = YES;
    [self.view addSubview:scroll];

    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 80;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 40)];
    title.text = @"TrollBox";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    [scroll addSubview:title];
    y += 44;

    NSDictionary *info = [NSBundle mainBundle].infoDictionary;
    NSString *ver = info[@"CFBundleShortVersionString"] ?: @"?";
    NSString *build = info[@"CFBundleVersion"] ?: @"?";
    UILabel *verLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 20)];
    verLabel.text = [NSString stringWithFormat:@"Version %@ (build %@)", ver, build];
    verLabel.textColor = [UIColor lightGrayColor];
    verLabel.font = [UIFont systemFontOfSize:13];
    [scroll addSubview:verLabel];
    y += 30;

    UILabel *blurb = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 120)];
    blurb.text = @"TrollBox is a re-bundle of various TrollStore utilities "
                 @"that work on iOS 14 to 16 and that I use daily on an "
                 @"iPhone SE 1st-gen. Other similar tools exist; these are "
                 @"the ones I use and judge useful and functional. "
                 @"Everything here runs with the TrollStore "
                 @"platform-application entitlement — no jailbreak, no "
                 @"tweak injection into SpringBoard, no MobileSubstrate / "
                 @"ElleKit.";
    blurb.textColor = [UIColor lightGrayColor];
    blurb.font = [UIFont systemFontOfSize:14];
    blurb.numberOfLines = 0;
    [blurb sizeToFit];
    CGRect bf = blurb.frame; bf.size.width = w - 40; blurb.frame = bf;
    [scroll addSubview:blurb];
    y += blurb.frame.size.height + 20;

    // Sections included (post-2026-11-28 reorg).
    y = [self appendSection:@"Sections included"
                       body:@"• LocSim — simulated CLLocation (MapKit UI, favorites, re-center)\n"
                            @"• Ad Blocking — MYbloXX-style blocker, PACs embedded locally\n"
                            @"• Reclaim Space — delete logs, caches, orphan containers iOS forgets\n"
                            @"• AppRepack — install older AND newer versions (Muffinstore + MinOS patcher)\n"
                            @"• SpringBoard Tweaks — Badge Color + Clear All in app switcher + Don't lock mirror\n"
                            @"• ResSetter — slider ×1.0→×1.5, write path ported from haoict's IPA, Reset via rootSpawn, boot-persistence LaunchDaemon\n"
                            @"• ClearShot — CC Capture + Record, bypasses FLAG_SECURE, native-gesture hook\n"
                            @"• Supervise — toggle IsSupervised / OrganizationName\n"
                            @"• Tweaks — dylib / bundle injection (TrollFools engine ported)\n"
                            @"• Saved WiFi — list, reveal, forget, export known networks\n"
                            @"• About Device — battery, CPU, RAM, storage, network, diagnostics"
                      intoScroll:scroll
                               y:y
                               w:w];

    // Credits — upstream + collaborators. One entry per source, with what
    // we took from it.
    y = [self appendSection:@"Credits & upstream sources"
                       body:@"TrollBox ports, adapts or reuses work from these projects. Thanks to their authors.\n\n"
                            @"• TrollStore (opa334) — platform-application ecosystem\n"
                            @"  github.com/opa334/TrollStore\n\n"
                            @"• TrollInstallerDark (rockylabs-dev) — TrollStore installer for iOS 15.8.x\n"
                            @"  github.com/rockylabs-dev/TrollInstallerDark\n\n"
                            @"• Andromeda / Geranium (Son3ra1n) — LocSim MapKit UI, Supervise, respring, setuid(0) pattern, entitlements template\n"
                            @"  github.com/Son3ra1n/Andromeda\n\n"
                            @"• TrollFools (Lessica) — Tweaks injection engine (TFInjector / TFMachO / TFCodesign ports)\n"
                            @"  github.com/Lessica/TrollFools\n\n"
                            @"• ResolutionSetterSwift (haoict) — ResSetter mechanism\n"
                            @"  github.com/haoict/ResolutionSetterSwift\n\n"
                            @"• NiceBattery — About Device battery metrics + auto-refresh pattern\n\n"
                            @"• MYbloXX for iOS (pegakmupyem) — Ad Blocking mechanism + base PACs\n"
                            @"  github.com/pegakmupyem/myxxdev\n\n"
                            @"• StevenBlack/hosts — fresh blocklists merged into the PACs at build\n"
                            @"  github.com/StevenBlack/hosts\n\n"
                            @"• Muffinstore (mineek) — AppRepack mechanism\n"
                            @"  github.com/mineek/muffinstore\n\n"
                            @"• Cowabunga (leminlimez, BadgeChanger by exerhythm) — Badge Color\n"
                            @"  github.com/leminlimez/Cowabunga\n\n"
                            @"• Jaility (haxi0) — SBDontLockAfterCrash mechanism migrated into ResSetter\n\n"
                            @"• WiFiList (EthanArbuckle) — Saved WiFi plist layout + keychain query inspiration\n\n"
                            @"• YTLite (dayanch96), BHInstagram, BHTwitter (BandarHL) — example tweak sources referenced in Tweaks\n\n"
                            @"• Apple Configurator 2 — documented path for non-TrollStore supervision (free, Mac App Store)\n\n"
                            @"• Amy While — SpringBoard respring-by-snapshot trick\n\n"
                            @"• c22dev/TrollBox — the app icon (GPL v3, re-used with attribution)\n"
                            @"  github.com/c22dev/TrollBox\n\n"
                            @"• Claude (Anthropic) — development assistance across the refactor:\n"
                            @"  large section rewrites (ResSetter, AppRepack, Reclaim Space),\n"
                            @"  TBDiagnosticsManager, Saved WiFi, README + About, bug hunting.\n"
                            @"  claude.com\n"
                      intoScroll:scroll
                               y:y
                               w:w];

    y = [self appendSection:@"License"
                       body:@"GNU General Public License v3.0.\n\n"
                            @"TrollBox is distributed under the terms of the GPLv3 to preserve "
                            @"the licensing of its upstream components (Andromeda, TrollFools, "
                            @"TrollStore are also GPL-family). See LICENSE in the repository."
                      intoScroll:scroll
                               y:y
                               w:w];

    y = [self appendSection:@"Disclaimer"
                       body:@"Provided for personal use, research and accessibility. Some features "
                            @"(screen capture of other apps' protected content, simulated locations, "
                            @"supervision toggles, binary modification) can violate third-party "
                            @"terms of service and, depending on content and jurisdiction, local law. "
                            @"Use responsibly on devices you own."
                      intoScroll:scroll
                               y:y
                               w:w];

    scroll.contentSize = CGSizeMake(w, y + 40);
}

- (CGFloat)appendSection:(NSString *)heading
                    body:(NSString *)body
              intoScroll:(UIScrollView *)scroll
                       y:(CGFloat)y
                       w:(CGFloat)w {
    UILabel *h = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 24)];
    h.text = heading;
    h.textColor = [UIColor whiteColor];
    h.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    [scroll addSubview:h];
    y += 28;

    UILabel *b = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 0)];
    b.text = body;
    b.textColor = [UIColor lightGrayColor];
    b.font = [UIFont systemFontOfSize:13];
    b.numberOfLines = 0;
    [b sizeToFit];
    CGRect bf = b.frame; bf.size.width = w - 40; b.frame = bf;
    [scroll addSubview:b];
    return y + b.frame.size.height + 24;
}

@end
