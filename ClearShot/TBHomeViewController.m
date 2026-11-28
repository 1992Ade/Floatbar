#import "TBHomeViewController.h"
#import "CSMainViewController.h"
#import "LSMainViewController.h"
#import "SVMainViewController.h"
#import "TWMainViewController.h"
#import "RSMainViewController.h"
#import "ADMainViewController.h"
#import "ABMainViewController.h"
#import "RMMainViewController.h"
#import "ARMainViewController.h"
#import "STMainViewController.h"
#import "WFMainViewController.h"
#import "TBAboutViewController.h"

// Badge Color is pushed from SpringBoard Tweaks' Appearance row now —
// imported there, not at the top-level grid anymore.

typedef UIViewController *(^TBSectionFactory)(void);

@interface TBSection : NSObject
@property (copy) NSString *title;
@property (copy) NSString *subtitle;
@property (copy) NSString *symbol;
@property (strong) UIColor *tint;
@property (copy) TBSectionFactory factory;
@end
@implementation TBSection
@end

@interface TBHomeViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (strong, nonatomic) UICollectionView *grid;
@property (strong, nonatomic) NSArray<TBSection *> *sections;
@end

@implementation TBHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.10 alpha:1.0];
    self.title = @"TrollBox";
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *a = [[UINavigationBarAppearance alloc] init];
        [a configureWithOpaqueBackground];
        a.backgroundColor = self.view.backgroundColor;
        a.titleTextAttributes = @{ NSForegroundColorAttributeName: UIColor.whiteColor };
        a.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: UIColor.whiteColor };
        self.navigationController.navigationBar.standardAppearance = a;
        self.navigationController.navigationBar.scrollEdgeAppearance = a;
        self.navigationController.navigationBar.prefersLargeTitles = YES;
    }

    [self buildSections];
    [self buildGrid];
}

- (void)buildSections {
    NSMutableArray *s = [NSMutableArray array];

    // Order fixed 2026-11-28 (post-swap):
    //   1  LocSim
    //   2  Ad Blocking
    //   3  Reclaim Space
    //   4  AppRepack
    //   5  SpringBoard Tweaks  (contains Badge Color + Clear All + Don't Lock)
    //   6  ResSetter           (2.0.2: write path ported from haoict's IPA)
    //   7  ClearShot
    //   8  Supervise
    //   9  Tweaks
    //   10 Saved WiFi
    //   11 About Device
    //   12 About
    // Jaility dropped; standalone Badge Color merged into SpringBoard Tweaks.

    [s addObject:[self section:@"LocSim"
                      subtitle:@"Simulated GPS location"
                        symbol:@"location.fill"
                          tint:[UIColor systemGreenColor]
                       factory:^UIViewController *{ return [[LSMainViewController alloc] init]; }]];

    [s addObject:[self section:@"Ad Blocking"
                      subtitle:@"MYbloXX-style global HTTP proxy blocker"
                        symbol:@"shield.lefthalf.filled"
                          tint:[UIColor systemRedColor]
                       factory:^UIViewController *{ return [[ABMainViewController alloc] init]; }]];

    [s addObject:[self section:@"Reclaim Space"
                      subtitle:@"Delete analytics/crash/cache iOS forgot"
                        symbol:@"trash.fill"
                          tint:[UIColor systemBrownColor]
                       factory:^UIViewController *{ return [[RMMainViewController alloc] init]; }]];

    [s addObject:[self section:@"AppRepack"
                      subtitle:@"Install older or newer app versions"
                        symbol:@"shippingbox.fill"
                          tint:[UIColor systemMintColor]
                       factory:^UIViewController *{ return [[ARMainViewController alloc] init]; }]];

    [s addObject:[self section:@"SpringBoard Tweaks"
                      subtitle:@"Badge Color, Clear All, Don't Lock"
                        symbol:@"square.grid.2x2.fill"
                          tint:[UIColor systemPinkColor]
                       factory:^UIViewController *{ return [[STMainViewController alloc] init]; }]];

    [s addObject:[self section:@"ResSetter"
                      subtitle:@"Display resolution multiplier"
                        symbol:@"rectangle.expand.vertical"
                          tint:[UIColor systemYellowColor]
                       factory:^UIViewController *{ return [[RSMainViewController alloc] init]; }]];

    [s addObject:[self section:@"ClearShot"
                      subtitle:@"CC Capture+Record, bypass FLAG_SECURE"
                        symbol:@"camera.viewfinder"
                          tint:[UIColor systemBlueColor]
                       factory:^UIViewController *{ return [[CSMainViewController alloc] init]; }]];

    [s addObject:[self section:@"Supervise"
                      subtitle:@"Fake org name, supervised flag"
                        symbol:@"eye.fill"
                          tint:[UIColor systemPurpleColor]
                       factory:^UIViewController *{ return [[SVMainViewController alloc] init]; }]];

    [s addObject:[self section:@"Tweaks"
                      subtitle:@"Inject dylibs / bundles into apps"
                        symbol:@"wrench.and.screwdriver.fill"
                          tint:[UIColor systemOrangeColor]
                       factory:^UIViewController *{ return [[TWMainViewController alloc] init]; }]];

    [s addObject:[self section:@"Saved WiFi"
                      subtitle:@"View, reveal password, forget networks"
                        symbol:@"wifi"
                          tint:[UIColor systemCyanColor]
                       factory:^UIViewController *{ return [[WFMainViewController alloc] init]; }]];

    [s addObject:[self section:@"About Device"
                      subtitle:@"Battery, CPU, RAM, network, diagnostics"
                        symbol:@"iphone"
                          tint:[UIColor systemTealColor]
                       factory:^UIViewController *{ return [[ADMainViewController alloc] init]; }]];

    [s addObject:[self section:@"About"
                      subtitle:@"Version, credits, license"
                        symbol:@"info.circle.fill"
                          tint:[UIColor systemGrayColor]
                       factory:^UIViewController *{ return [[TBAboutViewController alloc] init]; }]];

    self.sections = s;
}

- (TBSection *)section:(NSString *)title
              subtitle:(NSString *)subtitle
                symbol:(NSString *)symbol
                  tint:(UIColor *)tint
               factory:(TBSectionFactory)factory {
    TBSection *s = [[TBSection alloc] init];
    s.title = title; s.subtitle = subtitle;
    s.symbol = symbol; s.tint = tint;
    s.factory = factory;
    return s;
}

- (void)buildGrid {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 14;
    layout.minimumLineSpacing = 14;
    layout.sectionInset = UIEdgeInsetsMake(16, 16, 16, 16);

    self.grid = [[UICollectionView alloc] initWithFrame:self.view.bounds
                                   collectionViewLayout:layout];
    self.grid.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.grid.backgroundColor = self.view.backgroundColor;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    [self.grid registerClass:UICollectionViewCell.class
     forCellWithReuseIdentifier:@"card"];
    [self.view addSubview:self.grid];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UICollectionViewFlowLayout *l = (UICollectionViewFlowLayout *)self.grid.collectionViewLayout;
    CGFloat side = self.view.bounds.size.width;
    CGFloat cellW = floor((side - 16 * 2 - 14) / 2.0);
    l.itemSize = CGSizeMake(cellW, 110);
}

#pragma mark - Collection

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s {
    return self.sections.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv
                   cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"card"
                                                               forIndexPath:ip];
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];

    TBSection *s = self.sections[ip.item];
    cell.contentView.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    cell.contentView.layer.cornerRadius = 16;
    cell.contentView.layer.masksToBounds = YES;

    CGFloat w = cell.contentView.bounds.size.width;

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(14, 12, 28, 28)];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = s.tint;
    if (@available(iOS 13.0, *)) {
        icon.image = [UIImage systemImageNamed:s.symbol];
    }
    [cell.contentView addSubview:icon];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 48, w - 28, 22)];
    title.text = s.title;
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [cell.contentView addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(14, 70, w - 28, 34)];
    sub.text = s.subtitle;
    sub.textColor = [UIColor lightGrayColor];
    sub.font = [UIFont systemFontOfSize:12];
    sub.numberOfLines = 2;
    [cell.contentView addSubview:sub];

    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    [cv deselectItemAtIndexPath:ip animated:YES];
    TBSection *s = self.sections[ip.item];
    UIViewController *vc = s.factory();
    [self.navigationController pushViewController:vc animated:YES];
}

@end
