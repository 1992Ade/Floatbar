#import "LSMainViewController.h"
#import "LSManager.h"
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

// ============================================================================
// LocSim — Andromeda-style MapKit UI. Long-press on the map drops a pin,
// the search bar accepts named places (geocoded via MKLocalSearch), a
// Favorites button lists coordinates you save often, and a re-center
// button zooms (500 m) on your real current location.
// ============================================================================

static NSString * const kFavoritesKey = @"TBLocSimFavorites"; // array of
                                                               // @{name,lat,lng}

@interface LSFavorite : NSObject
@property (copy) NSString *name;
@property (assign) double lat;
@property (assign) double lng;
@end
@implementation LSFavorite @end

@interface LSMainViewController () <MKMapViewDelegate,
                                     UISearchBarDelegate,
                                     CLLocationManagerDelegate>
@property (strong, nonatomic) MKMapView *mapView;
@property (strong, nonatomic) UISearchBar *searchBar;
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) UIButton *startBtn;
@property (strong, nonatomic) UIButton *stopBtn;
@property (strong, nonatomic) UIButton *favBtn;
@property (strong, nonatomic) UIButton *recenterBtn;
@property (strong, nonatomic) MKPointAnnotation *currentPin;
@property (strong, nonatomic) CLLocationManager *locMgr;
@property (strong, nonatomic) NSMutableArray<LSFavorite *> *favorites;
@end

@implementation LSMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.title = @"LocSim";

    [self loadFavorites];
    [self buildUI];
    [self refreshStatus];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStatus];
}

#pragma mark - UI

- (void)buildUI {
    CGRect b = self.view.bounds;

    // Search bar at the top.
    self.searchBar = [[UISearchBar alloc] initWithFrame:
                       CGRectMake(0, 100, b.size.width, 44)];
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.placeholder = @"Search a place…";
    self.searchBar.delegate = self;
    self.searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:self.searchBar];

    // Map view takes the center.
    CGFloat mapTop = CGRectGetMaxY(self.searchBar.frame);
    CGFloat mapBottom = b.size.height - 180;
    self.mapView = [[MKMapView alloc] initWithFrame:
                     CGRectMake(0, mapTop, b.size.width, mapBottom - mapTop)];
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.mapView.delegate = self;
    self.mapView.showsCompass = YES;
    self.mapView.showsScale = YES;
    // Blue dot for the real current position — the piece that was missing
    // in 2.0.0/2.0.1 and that the user wanted visible permanently, in
    // addition to the re-center button. Only takes effect once CoreLocation
    // authorization is granted (user tapping re-center the first time).
    self.mapView.showsUserLocation = YES;
    [self.view addSubview:self.mapView];

    // Long-press to drop a pin.
    UILongPressGestureRecognizer *lp =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                       action:@selector(didLongPressMap:)];
    lp.minimumPressDuration = 0.6;
    [self.mapView addGestureRecognizer:lp];

    // Overlay buttons on top-right of the map: favorites + re-center.
    self.favBtn = [self overlayButtonWithSymbol:@"star.fill"
                                          action:@selector(didTapFavorites)];
    self.favBtn.frame = CGRectMake(b.size.width - 56, mapTop + 12, 44, 44);
    self.favBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:self.favBtn];

    self.recenterBtn = [self overlayButtonWithSymbol:@"location.circle.fill"
                                               action:@selector(didTapRecenter)];
    self.recenterBtn.frame = CGRectMake(b.size.width - 56, mapTop + 64, 44, 44);
    self.recenterBtn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:self.recenterBtn];

    // Status + start/stop row at the bottom.
    CGFloat y = mapBottom + 12;
    self.statusLabel = [[UILabel alloc] initWithFrame:
                         CGRectMake(20, y, b.size.width - 40, 36)];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 2;
    self.statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.statusLabel];
    y += 44;

    CGFloat halfW = (b.size.width - 40 - 12) / 2.0;
    self.startBtn = [self makeButton:@"Start simulation"
                               frame:CGRectMake(20, y, halfW, 48)
                               color:[UIColor systemBlueColor]
                              action:@selector(didTapStart)];
    self.startBtn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    [self.view addSubview:self.startBtn];

    self.stopBtn = [self makeButton:@"Stop"
                              frame:CGRectMake(20 + halfW + 12, y, halfW, 48)
                              color:[UIColor systemOrangeColor]
                             action:@selector(didTapStop)];
    self.stopBtn.autoresizingMask = UIViewAutoresizingFlexibleTopMargin
                                 | UIViewAutoresizingFlexibleLeftMargin;
    [self.view addSubview:self.stopBtn];
}

- (UIButton *)overlayButtonWithSymbol:(NSString *)symbolName
                                 action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    b.tintColor = [UIColor whiteColor];
    b.layer.cornerRadius = 12;
    if (@available(iOS 13.0, *)) {
        [b setImage:[UIImage systemImageNamed:symbolName] forState:UIControlStateNormal];
    }
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (UIButton *)makeButton:(NSString *)title frame:(CGRect)f
                    color:(UIColor *)color action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = f;
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = color;
    b.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    b.layer.cornerRadius = 10;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)refreshStatus {
    if (self.currentPin) {
        self.statusLabel.text = [NSString stringWithFormat:
                                  @"Pin: %.5f, %.5f\n%@",
                                  self.currentPin.coordinate.latitude,
                                  self.currentPin.coordinate.longitude,
                                  [LSManager isActive] ? @"✅ Simulating from this pin"
                                                        : @"Ready — tap Start to begin"];
        self.statusLabel.textColor = [LSManager isActive]
            ? [UIColor systemGreenColor] : [UIColor whiteColor];
    } else {
        self.statusLabel.text = @"Long-press the map to drop a pin, or search a place.";
        self.statusLabel.textColor = [UIColor lightGrayColor];
    }
}

#pragma mark - Map interaction

- (void)didLongPressMap:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    CGPoint pt = [g locationInView:self.mapView];
    CLLocationCoordinate2D coord = [self.mapView convertPoint:pt
                                        toCoordinateFromView:self.mapView];
    [self setPinAtCoordinate:coord name:nil];
}

- (void)setPinAtCoordinate:(CLLocationCoordinate2D)coord name:(NSString *)name {
    if (self.currentPin) {
        [self.mapView removeAnnotation:self.currentPin];
    }
    self.currentPin = [[MKPointAnnotation alloc] init];
    self.currentPin.coordinate = coord;
    self.currentPin.title = name ?: @"Dropped pin";
    [self.mapView addAnnotation:self.currentPin];
    [self refreshStatus];
}

#pragma mark - Start / stop

- (void)didTapStart {
    if (!self.currentPin) {
        [self alert:@"No pin"
            message:@"Drop a pin by long-pressing on the map or picking a "
                    @"favorite first."];
        return;
    }
    CLLocation *loc = [[CLLocation alloc]
                        initWithLatitude:self.currentPin.coordinate.latitude
                               longitude:self.currentPin.coordinate.longitude];
    [LSManager startWithLocation:loc];
    [self refreshStatus];
}

- (void)didTapStop {
    [LSManager stop];
    [self refreshStatus];
}

#pragma mark - Search

- (void)searchBarSearchButtonClicked:(UISearchBar *)sb {
    [sb resignFirstResponder];
    NSString *q = sb.text;
    if (!q.length) return;

    MKLocalSearchRequest *req = [[MKLocalSearchRequest alloc] init];
    req.naturalLanguageQuery = q;
    req.region = self.mapView.region;

    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:req];
    [search startWithCompletionHandler:^(MKLocalSearchResponse *resp, NSError *err) {
        if (err || resp.mapItems.count == 0) {
            [self alert:@"No match" message:err.localizedDescription ?: @"Nothing found."];
            return;
        }
        MKMapItem *first = resp.mapItems.firstObject;
        CLLocationCoordinate2D c = first.placemark.coordinate;
        [self setPinAtCoordinate:c name:(first.name ?: @"Searched")];
        [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 500, 500)
                        animated:YES];
    }];
}

#pragma mark - Re-center

- (void)didTapRecenter {
    if (!self.locMgr) {
        self.locMgr = [[CLLocationManager alloc] init];
        self.locMgr.delegate = self;
    }
    CLAuthorizationStatus st = [CLLocationManager authorizationStatus];
    if (st == kCLAuthorizationStatusNotDetermined) {
        [self.locMgr requestWhenInUseAuthorization];
        return;
    }
    if (st == kCLAuthorizationStatusDenied || st == kCLAuthorizationStatusRestricted) {
        [self alert:@"Location access denied"
            message:@"Enable it in Settings → Privacy → Location Services → "
                    @"TrollBox so we can center the map on your real position."];
        return;
    }
    [self.locMgr requestLocation];
}

- (void)locationManager:(CLLocationManager *)manager
      didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    if (!loc) return;
    [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(loc.coordinate, 500, 500)
                    animated:YES];
}

- (void)locationManager:(CLLocationManager *)manager
       didFailWithError:(NSError *)error {
    [self alert:@"Location failed"
        message:error.localizedDescription ?: @"Unknown error."];
}

- (void)locationManager:(CLLocationManager *)manager
  didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
        status == kCLAuthorizationStatusAuthorizedAlways) {
        [self.locMgr requestLocation];
    }
}

#pragma mark - Favorites

- (void)loadFavorites {
    NSArray *raw = [[NSUserDefaults standardUserDefaults] arrayForKey:kFavoritesKey];
    self.favorites = [NSMutableArray array];
    for (NSDictionary *d in raw) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        LSFavorite *f = [LSFavorite new];
        f.name = d[@"name"];
        f.lat  = [d[@"lat"] doubleValue];
        f.lng  = [d[@"lng"] doubleValue];
        if (f.name.length) [self.favorites addObject:f];
    }
}

- (void)saveFavorites {
    NSMutableArray *raw = [NSMutableArray array];
    for (LSFavorite *f in self.favorites) {
        [raw addObject:@{ @"name": f.name, @"lat": @(f.lat), @"lng": @(f.lng) }];
    }
    [[NSUserDefaults standardUserDefaults] setObject:raw forKey:kFavoritesKey];
}

- (void)didTapFavorites {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Favorites"
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];

    // Add current pin as a favorite
    if (self.currentPin) {
        [ac addAction:[UIAlertAction actionWithTitle:@"⭐ Save current pin as favorite"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a) {
            [self promptSaveCurrentPin];
        }]];
    }

    // One row per saved favorite
    for (LSFavorite *f in self.favorites) {
        NSString *title = [NSString stringWithFormat:@"%@ (%.4f, %.4f)",
                           f.name, f.lat, f.lng];
        [ac addAction:[UIAlertAction actionWithTitle:title
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a) {
            CLLocationCoordinate2D c = CLLocationCoordinate2DMake(f.lat, f.lng);
            [self setPinAtCoordinate:c name:f.name];
            [self.mapView setRegion:MKCoordinateRegionMakeWithDistance(c, 500, 500)
                            animated:YES];
        }]];
    }

    if (self.favorites.count > 0) {
        [ac addAction:[UIAlertAction actionWithTitle:@"Manage favorites…"
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *a) {
            [self presentFavoritesManager];
        }]];
    }

    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = self.favBtn;
    ac.popoverPresentationController.sourceRect = self.favBtn.bounds;
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)promptSaveCurrentPin {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Save favorite"
                         message:[NSString stringWithFormat:@"%.5f, %.5f",
                                  self.currentPin.coordinate.latitude,
                                  self.currentPin.coordinate.longitude]
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"Name (Home, Work, …)";
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Save"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        NSString *name = ac.textFields.firstObject.text;
        if (!name.length) name = @"Unnamed pin";
        LSFavorite *f = [LSFavorite new];
        f.name = name;
        f.lat = self.currentPin.coordinate.latitude;
        f.lng = self.currentPin.coordinate.longitude;
        [self.favorites addObject:f];
        [self saveFavorites];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)presentFavoritesManager {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Delete a favorite"
                         message:nil
                  preferredStyle:UIAlertControllerStyleActionSheet];
    for (LSFavorite *f in [self.favorites copy]) {
        [ac addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"🗑 %@", f.name]
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *a) {
            [self.favorites removeObject:f];
            [self saveFavorites];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    ac.popoverPresentationController.sourceView = self.favBtn;
    ac.popoverPresentationController.sourceRect = self.favBtn.bounds;
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Alert helper

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
