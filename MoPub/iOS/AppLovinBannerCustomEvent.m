//
//  AppLovinBannerCustomEvent.m
//
//
//  Created by Thomas So on 7/6/17.
//
//


#import "AppLovinBannerCustomEvent.h"
#import "MPConstants.h"
#import "MPError.h"

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALAdView.h"
#endif

// Convenience macro for checking if AppLovin SDK has support for zones
#define HAS_ZONES_SUPPORT [[ALSdk shared].adService respondsToSelector: @selector(loadNextAdForZoneIdentifier:andNotify:)]
#define EMPTY_ZONE @""

/**
 * The receiver object of the ALAdView's delegates. This is used to prevent a retain cycle between the ALAdView and AppLovinBannerCustomEvent.
 */
@interface AppLovinMoPubBannerDelegate : NSObject<ALAdLoadDelegate, ALAdDisplayDelegate, ALAdViewEventDelegate>
@property (nonatomic, weak) AppLovinBannerCustomEvent *parentCustomEvent;
- (instancetype)initWithCustomEvent:(AppLovinBannerCustomEvent *)parentCustomEvent;
@end

@interface AppLovinBannerCustomEvent()
@property (nonatomic, strong) ALAdView *adView;
@end

@implementation AppLovinBannerCustomEvent

static const BOOL kALLoggingEnabled = YES;
static NSString *const kALMoPubMediationErrorDomain = @"com.applovin.sdk.mediation.mopub.errorDomain";

static const CGFloat kALBannerHeightOffsetTolerance = 10.0f;
static const CGFloat kALBannerStandardHeight = 50.0f;

// A dictionary of Zone -> AdView to be shared by instances of the custom event.
static NSMutableDictionary<NSString *, ALAdView *> *ALGlobalAdViews;

+ (void)initialize
{
    [super initialize];

    ALGlobalAdViews = [NSMutableDictionary dictionary];
}

#pragma mark - MPBannerCustomEvent Overridden Methods

- (void)requestAdWithSize:(CGSize)size customEventInfo:(NSDictionary *)info
{
    [self log: @"Requesting AppLovin banner of size %@ with info: %@", NSStringFromCGSize(size), info];
    
    // Convert requested size to AppLovin Ad Size
    ALAdSize *adSize = [self appLovinAdSizeFromRequestedSize: size];
    if ( adSize )
    {
        [[ALSdk shared] setPluginVersion: @"MoPub-2.1.0"];
        
        // Zones support is available on AppLovin SDK 4.5.0 and higher
        NSString *zoneIdentifier = info[@"zone_id"];
        if ( HAS_ZONES_SUPPORT && zoneIdentifier.length > 0 )
        {
            self.adView = ALGlobalAdViews[zoneIdentifier];
            if ( !self.adView )
            {
                self.adView = [self adViewWithAdSize: adSize zoneIdentifier: zoneIdentifier];
                ALGlobalAdViews[zoneIdentifier] = self.adView;
            }
        }
        else
        {
            self.adView = ALGlobalAdViews[EMPTY_ZONE];
            if ( !self.adView )
            {
                self.adView = [[ALAdView alloc] initWithFrame: CGRectMake(0.0f, 0.0f, size.width, size.height)
                                                         size: adSize
                                                          sdk: [ALSdk shared]];
                ALGlobalAdViews[EMPTY_ZONE] = self.adView;
            }
        }
        
        AppLovinMoPubBannerDelegate *delegate = [[AppLovinMoPubBannerDelegate alloc] initWithCustomEvent: self];
        self.adView.adLoadDelegate = delegate;
        self.adView.adDisplayDelegate = delegate;
        
        // As of iOS SDK >= 4.3.0, we added a delegate for banner events
        if ( [self.adView respondsToSelector: @selector(setAdEventDelegate:)] )
        {
            self.adView.adEventDelegate = delegate;
        }
        
        [self.adView loadNextAd];
    }
    else
    {
        [self log: @"Failed to create an AppLovin banner with invalid size"];
        
        NSString *failureReason = [NSString stringWithFormat: @"Adaptor requested to display a banner with invalid size: %@.", NSStringFromCGSize(size)];
        NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain
                                             code: kALErrorCodeUnableToRenderAd
                                         userInfo: @{NSLocalizedFailureReasonErrorKey : failureReason}];
        
        [self.delegate bannerCustomEvent: self didFailToLoadAdWithError: error];
    }
}

- (BOOL)enableAutomaticImpressionAndClickTracking
{
    return NO;
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

- (ALAdSize *)appLovinAdSizeFromRequestedSize:(CGSize)size
{
    if ( CGSizeEqualToSize(size, MOPUB_BANNER_SIZE) )
    {
        return [ALAdSize sizeBanner];
    }
    else if ( CGSizeEqualToSize(size, MOPUB_MEDIUM_RECT_SIZE) )
    {
        return [ALAdSize sizeMRec];
    }
    else if ( CGSizeEqualToSize(size, MOPUB_LEADERBOARD_SIZE) )
    {
        return [ALAdSize sizeLeader];
    }
    // This is not a one of MoPub's predefined size
    else
    {
        // Assume fluid width, and check for height with offset tolerance
        CGFloat offset = ABS(kALBannerStandardHeight - size.height);
        if ( offset <= kALBannerHeightOffsetTolerance )
        {
            return [ALAdSize sizeBanner];
        }
    }
    
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
        
        NSLog(@"AppLovinBannerCustomEvent: %@", message);
    }
}

- (MOPUBErrorCode)toMoPubErrorCode:(int)appLovinErrorCode
{
    if ( appLovinErrorCode == kALErrorCodeNoFill )
    {
        return MOPUBErrorAdapterHasNoInventory;
    }
    else if ( appLovinErrorCode == kALErrorCodeAdRequestNetworkTimeout )
    {
        return MOPUBErrorNetworkTimedOut;
    }
    else if ( appLovinErrorCode == kALErrorCodeInvalidResponse )
    {
        return MOPUBErrorServerError;
    }
    else
    {
        return MOPUBErrorUnknown;
    }
}

@end

@implementation AppLovinMoPubBannerDelegate

#pragma mark - Initialization

- (instancetype)initWithCustomEvent:(AppLovinBannerCustomEvent *)parentCustomEvent
{
    self = [super init];
    if ( self )
    {
        self.parentCustomEvent = parentCustomEvent;
    }
    return self;
}

#pragma mark - Ad Load Delegate

- (void)adService:(ALAdService *)adService didLoadAd:(ALAd *)ad
{
    [self.parentCustomEvent log: @"Banner did load ad: %@", ad.adIdNumber];
    [self.parentCustomEvent.delegate bannerCustomEvent: self.parentCustomEvent didLoadAd: self.parentCustomEvent.adView];
}

- (void)adService:(ALAdService *)adService didFailToLoadAdWithError:(int)code
{
    [self.parentCustomEvent log: @"Banner failed to load with error: %d", code];
    
    NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain
                                         code: [self.parentCustomEvent toMoPubErrorCode: code]
                                     userInfo: nil];
    [self.parentCustomEvent.delegate bannerCustomEvent: self.parentCustomEvent didFailToLoadAdWithError: error];
    
    // TODO: Add support for backfilling on regular ad request if invalid zone entered
}

#pragma mark - Ad Display Delegate

- (void)ad:(ALAd *)ad wasDisplayedIn:(UIView *)view
{
    [self.parentCustomEvent log: @"Banner displayed"];
    
    // `didDisplayAd` of this class would not be called by MoPub on AppLovin banner refresh if enabled.
    // Only way to track impression of AppLovin refresh is via this callback.
    [self.parentCustomEvent.delegate trackImpression];
}

- (void)ad:(ALAd *)ad wasHiddenIn:(UIView *)view
{
    [self.parentCustomEvent log: @"Banner dismissed"];
}

- (void)ad:(ALAd *)ad wasClickedIn:(UIView *)view
{
    [self.parentCustomEvent log: @"Banner clicked"];
    
    [self.parentCustomEvent.delegate trackClick];
    [self.parentCustomEvent.delegate bannerCustomEventWillLeaveApplication: self.parentCustomEvent];
}

#pragma mark - Ad View Event Delegate

- (void)ad:(ALAd *)ad didPresentFullscreenForAdView:(ALAdView *)adView
{
    [self.parentCustomEvent log: @"Banner presented fullscreen"];
    [self.parentCustomEvent.delegate bannerCustomEventWillBeginAction: self.parentCustomEvent];
}

- (void)ad:(ALAd *)ad willDismissFullscreenForAdView:(ALAdView *)adView
{
    [self.parentCustomEvent log: @"Banner will dismiss fullscreen"];
}

- (void)ad:(ALAd *)ad didDismissFullscreenForAdView:(ALAdView *)adView
{
    [self.parentCustomEvent log: @"Banner did dismiss fullscreen"];
    [self.parentCustomEvent.delegate bannerCustomEventDidFinishAction: self.parentCustomEvent];
}

- (void)ad:(ALAd *)ad willLeaveApplicationForAdView:(ALAdView *)adView
{
    // We will fire bannerCustomEventWillLeaveApplication:: in the ad:wasClickedIn: callback
    [self.parentCustomEvent log: @"Banner left application"];
}

- (void)ad:(ALAd *)ad didFailToDisplayInAdView:(ALAdView *)adView withError:(ALAdViewDisplayErrorCode)code
{
    [self.parentCustomEvent log: @"Banner failed to display: %ld", code];
}

@end
