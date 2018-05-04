//
//  AppLovinCustomEventBanner.m
//
//
//  Created by Thomas So on 4/12/17.
//
//

#import "AppLovinCustomEventBanner.h"

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALAdView.h"
#endif

// Convenience macro for checking if AppLovin SDK has support for zones
#define HAS_ZONES_SUPPORT [[ALSdk shared].adService respondsToSelector: @selector(loadNextAdForZoneIdentifier:andNotify:)]
#define DEFAULT_ZONE @""

#define IS_IPHONE ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
#define IS_IPAD ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)

/**
 * The receiver object of the ALAdView's delegates. This is used to prevent a retain cycle between the ALAdView and AppLovinBannerCustomEvent.
 */
@interface AppLovinAdMobBannerDelegate : NSObject<ALAdLoadDelegate, ALAdDisplayDelegate>
@property (nonatomic, weak) AppLovinCustomEventBanner *parentCustomEvent;
- (instancetype)initWithCustomEvent:(AppLovinCustomEventBanner *)parentCustomEvent;
@end

@interface AppLovinCustomEventBanner()
@property (nonatomic, strong) ALAdView *adView;
@end

@implementation AppLovinCustomEventBanner
@synthesize delegate;

static const BOOL kALLoggingEnabled = YES;
static NSString *const kALAdMobMediationErrorDomain = @"com.applovin.sdk.mediation.admob.errorDomain";

static const CGFloat kALBannerHeightOffsetTolerance = 10.0f;
static const CGFloat kALBannerStandardHeight = 50.0f;

// A dictionary of Zone -> AdView to be shared by instances of the custom event.
static NSMutableDictionary<NSString *, ALAdView *> *ALGlobalAdViews;

+ (void)initialize
{
    [super initialize];
    
    ALGlobalAdViews = [NSMutableDictionary dictionary];
}

#pragma mark - GADCustomEventBanner Protocol

- (void)requestBannerAd:(GADAdSize)adSize parameter:(NSString *)serverParameter label:(NSString *)serverLabel request:(GADCustomEventRequest *)request
{
    [self log: @"Requesting AppLovin banner of size %@", NSStringFromGADAdSize(adSize)];
    
    // Convert requested size to AppLovin Ad Size
    ALAdSize *appLovinAdSize = [self appLovinAdSizeFromRequestedSize: adSize];
    if ( appLovinAdSize )
    {
        [[ALSdk shared] setPluginVersion: @"AdMob-2.3.1"];
        [ALSdk shared].mediationProvider = ALMediationProviderAdMob;
        
        CGSize size = CGSizeFromGADAdSize(adSize);
        
        // Zones support is available on AppLovin SDK 4.5.0 and higher
        NSString *zoneIdentifier;
        if ( HAS_ZONES_SUPPORT && request.additionalParameters[@"zone_id"] )
        {
            zoneIdentifier = request.additionalParameters[@"zone_id"];
        }
        else
        {
            zoneIdentifier = DEFAULT_ZONE;
        }
        
        
        self.adView = ALGlobalAdViews[zoneIdentifier];
        
        // Check if we already have an ALAdView for the given zone
        if ( !self.adView )
        {
            // If this is a default Zone, create the incentivized ad normally
            if ( [DEFAULT_ZONE isEqualToString: zoneIdentifier] )
            {
                self.adView = [[ALAdView alloc] initWithFrame: CGRectMake(0.0f, 0.0f, size.width, size.height)
                                                         size: appLovinAdSize
                                                          sdk: [ALSdk shared]];
            }
            // Otherwise, use the Zones API
            else
            {
                self.adView = [self adViewWithAdSize: appLovinAdSize zoneIdentifier: zoneIdentifier];
            }
            
            ALGlobalAdViews[zoneIdentifier] = self.adView;
        }
        
        AppLovinAdMobBannerDelegate *delegate = [[AppLovinAdMobBannerDelegate alloc] initWithCustomEvent: self];
        self.adView.adLoadDelegate = delegate;
        self.adView.adDisplayDelegate = delegate;
        
        [self.adView loadNextAd];
    }
    else
    {
        [self log: @"Failed to create an AppLovin Banner with invalid size"];
        
        NSError *error = [NSError errorWithDomain: kALAdMobMediationErrorDomain
                                             code: kGADErrorMediationInvalidAdSize
                                         userInfo: nil];
        [self.delegate customEventBanner: self didFailAd: error];
    }
}

#pragma mark - Utility Methods

/**
 * Dynamically create an instance of ALAdView with a given zone without breaking backwards compatibility for publishers on older SDKs.
 */
- (ALAdView *)adViewWithAdSize:(ALAdSize *)adSize zoneIdentifier:(NSString *)zoneIdentifier
{
    // Prematurely create instance of ALAdView to store initialized one in later
    ALAdView *adView = [ALAdView alloc];
    
    // We must use NSInvocation over performSelector: for initializers
    NSMethodSignature *methodSignature = [ALAdView instanceMethodSignatureForSelector: @selector(initWithSize:zoneIdentifier:)];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature: methodSignature];
    [inv setSelector: @selector(initWithSize:zoneIdentifier:)];
    [inv setArgument: &adSize atIndex: 2];
    [inv setArgument: &zoneIdentifier atIndex: 3];
    [inv setReturnValue: &adView];
    [inv invokeWithTarget: adView];
    
    return adView;
}

- (ALAdSize *)appLovinAdSizeFromRequestedSize:(GADAdSize)size
{
    if ( GADAdSizeEqualToSize(kGADAdSizeBanner, size) ||
        GADAdSizeEqualToSize(kGADAdSizeLargeBanner, size) ||
        (IS_IPHONE && GADAdSizeEqualToSize(kGADAdSizeSmartBannerPortrait, size)) ) // Smart iPhone portrait banners 50px tall
    {
        return [ALAdSize sizeBanner];
    }
    else if ( GADAdSizeEqualToSize(kGADAdSizeMediumRectangle, size) )
    {
        return [ALAdSize sizeMRec];
    }
    else if ( GADAdSizeEqualToSize(kGADAdSizeLeaderboard, size) || (IS_IPAD && GADAdSizeEqualToSize(kGADAdSizeSmartBannerPortrait, size)) ) // Smart iPad portrait "banners" 90px tall
    {
        return [ALAdSize sizeLeader];
    }
    // This is not a one of AdMob's predefined size
    else
    {
        CGSize frameSize = size.size;
        
        // Attempt to check for fluid size
        if ( CGRectGetWidth([UIScreen mainScreen].bounds) == frameSize.width )
        {
            CGFloat frameHeight = frameSize.height;
            if ( frameHeight == CGSizeFromGADAdSize(kGADAdSizeBanner).height || frameHeight == CGSizeFromGADAdSize(kGADAdSizeLargeBanner).height )
            {
                return [ALAdSize sizeBanner];
            }
            else if ( frameHeight == CGSizeFromGADAdSize(kGADAdSizeMediumRectangle).height )
            {
                return [ALAdSize sizeMRec];
            }
            else if ( frameHeight == CGSizeFromGADAdSize(kGADAdSizeLeaderboard).height )
            {
                return [ALAdSize sizeLeader];
            }
        }
        
        // Assume fluid width, and check for height with offset tolerance
        CGFloat offset = ABS(kALBannerStandardHeight - frameSize.height);
        if ( offset <= kALBannerHeightOffsetTolerance )
        {
            return [ALAdSize sizeBanner];
        }
    }
    
    [self log: @"Unable to retrieve AppLovin size from GADAdSize: %@", NSStringFromGADAdSize(size)];
    
    return nil;
}

- (void)log:(NSString *)format, ...
{
    if ( kALLoggingEnabled )
    {
        va_list valist;
        va_start(valist, format);
        NSString *message = [[NSString alloc] initWithFormat: format arguments: valist];
        va_end(valist);
        
        NSLog(@"AppLovinCustomEventBanner: %@", message);
    }
}

- (GADErrorCode)toAdMobErrorCode:(int)appLovinErrorCode
{
    if ( appLovinErrorCode == kALErrorCodeNoFill )
    {
        return kGADErrorMediationNoFill;
    }
    else if ( appLovinErrorCode == kALErrorCodeAdRequestNetworkTimeout )
    {
        return kGADErrorTimeout;
    }
    else if ( appLovinErrorCode == kALErrorCodeInvalidResponse )
    {
        return kGADErrorReceivedInvalidResponse;
    }
    else if ( appLovinErrorCode == kALErrorCodeUnableToRenderAd )
    {
        return kGADErrorServerError;
    }
    else
    {
        return kGADErrorInternalError;
    }
}

@end

@implementation AppLovinAdMobBannerDelegate

#pragma mark - Initialization

- (instancetype)initWithCustomEvent:(AppLovinCustomEventBanner *)parentCustomEvent
{
    self = [super init];
    if ( self )
    {
        self.parentCustomEvent = parentCustomEvent;
    }
    return self;
}

#pragma mark - AppLovin Ad Load Delegate

- (void)adService:(ALAdService *)adService didLoadAd:(ALAd *)ad
{
    [self.parentCustomEvent log: @"Banner did load ad: %@", ad.adIdNumber];
    [self.parentCustomEvent.delegate customEventBanner: self.parentCustomEvent didReceiveAd: self.parentCustomEvent.adView];
}

- (void)adService:(ALAdService *)adService didFailToLoadAdWithError:(int)code
{
    [self.parentCustomEvent log: @"Banner failed to load with error: %d", code];
    
    NSError *error = [NSError errorWithDomain: kALAdMobMediationErrorDomain
                                         code: [self.parentCustomEvent toAdMobErrorCode: code]
                                     userInfo: nil];
    [self.parentCustomEvent.delegate customEventBanner: self.parentCustomEvent didFailAd: error];
    
    // TODO: Add support for backfilling on regular ad request if invalid zone entered
}

#pragma mark - Ad Display Delegate

- (void)ad:(ALAd *)ad wasDisplayedIn:(UIView *)view
{
    [self.parentCustomEvent log: @"Banner displayed"];
}

- (void)ad:(ALAd *)ad wasHiddenIn:(UIView *)view
{
    [self.parentCustomEvent log: @"Banner dismissed"];
}

- (void)ad:(ALAd *)ad wasClickedIn:(UIView *)view
{
    [self.parentCustomEvent log: @"Banner clicked"];
    
    [self.parentCustomEvent.delegate customEventBannerWasClicked: self.parentCustomEvent];
    [self.parentCustomEvent.delegate customEventBannerWillLeaveApplication: self.parentCustomEvent];
}

@end
