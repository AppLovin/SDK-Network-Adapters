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
#import "MoPub.h"

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALAdView.h"
    #import "ALPrivacySettings.h"
#endif

#define EMPTY_ZONE @""

/**
 * The receiver object of the ALAdView's delegates. This is used to prevent a retain cycle between the ALAdView and AppLovinBannerCustomEvent.
 */
@interface AppLovinMoPubBannerDelegate : NSObject<ALAdLoadDelegate, ALAdDisplayDelegate, ALAdViewEventDelegate>
@property (nonatomic, weak) AppLovinBannerCustomEvent *parentCustomEvent;
- (instancetype)initWithCustomEvent:(AppLovinBannerCustomEvent *)parentCustomEvent;
@end

@interface AppLovinBannerCustomEvent()
@property (nonatomic, strong) ALSdk *sdk;
@property (nonatomic, strong) ALAdView *adView;
@end

@implementation AppLovinBannerCustomEvent

static const BOOL kALLoggingEnabled = YES;
static NSString *const kALMoPubMediationErrorDomain = @"com.applovin.sdk.mediation.mopub.errorDomain";

static const CGFloat kALBannerHeightOffsetTolerance = 10.0f;
static const CGFloat kALBannerStandardHeight = 50.0f;
static const CGFloat kALLeaderHeightOffsetTolerance = 16.0f;
static const CGFloat kALLeaderStandardHeight = 90.0f;

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
    
    // Collect and pass the user's consent from MoPub into the AppLovin SDK
    if ( [[MoPub sharedInstance] isGDPRApplicable] == MPBoolYes )
    {
        BOOL canCollectPersonalInfo = [[MoPub sharedInstance] canCollectPersonalInfo];
        [ALPrivacySettings setHasUserConsent: canCollectPersonalInfo];
    }
    
    // Convert requested size to AppLovin Ad Size
    ALAdSize *adSize = [self appLovinAdSizeFromRequestedSize: size];
    if ( adSize )
    {
        self.sdk = [self SDKFromCustomEventInfo: info];
        [self.sdk setPluginVersion: @"MoPub-3.0.0"];
        
        // Zones support is available on AppLovin SDK 4.5.0 and higher
        NSString *zoneIdentifier = info[@"zone_id"];
        if ( zoneIdentifier.length > 0 )
        {
            self.adView = ALGlobalAdViews[zoneIdentifier];
            if ( !self.adView )
            {
                self.adView = [[ALAdView alloc] initWithSdk: self.sdk size: adSize];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
                [self.adView performSelector: @selector(setZoneIdentifier:) withObject: zoneIdentifier];
#pragma clang diagnostic pop
                
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
                                                          sdk: self.sdk];
                ALGlobalAdViews[EMPTY_ZONE] = self.adView;
            }
        }
        
        AppLovinMoPubBannerDelegate *delegate = [[AppLovinMoPubBannerDelegate alloc] initWithCustomEvent: self];
        self.adView.adLoadDelegate = delegate;
        self.adView.adDisplayDelegate = delegate;
        self.adView.adEventDelegate = delegate;
        
        [self.adView loadNextAd];
    }
    else
    {
        [self log: @"Failed to create an AppLovin banner with invalid size"];
        
        NSString *failureReason = [NSString stringWithFormat: @"Adapter requested to display a banner with invalid size: %@.", NSStringFromCGSize(size)];
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

- (ALAdSize *)appLovinAdSizeFromRequestedSize:(CGSize)size
{
    if ( CGSizeEqualToSize(size, kMPPresetMaxAdSize50Height) )
    {
        return ALAdSize.banner;
    }
    else if ( CGSizeEqualToSize(size, kMPPresetMaxAdSize250Height) )
    {
        return ALAdSize.mrec;
    }
    else if ( CGSizeEqualToSize(size, kMPPresetMaxAdSize90Height) )
    {
        return ALAdSize.leader;
    }
    // This is not a one of MoPub's predefined size
    else
    {
        // Assume fluid width, and check for height with offset tolerance
        
        CGFloat bannerOffset = ABS(kALBannerStandardHeight - size.height);
        CGFloat leaderOffset = ABS(kALLeaderStandardHeight - size.height);
        
        if ( bannerOffset <= kALBannerHeightOffsetTolerance )
        {
            return ALAdSize.banner;
        }
        else if ( leaderOffset <= kALLeaderHeightOffsetTolerance )
        {
            return ALAdSize.leader;
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

- (ALSdk *)SDKFromCustomEventInfo:(NSDictionary *)info
{
    NSString *SDKKey = info[@"sdk_key"];
    if ( SDKKey.length > 0 )
    {
        return [ALSdk sharedWithKey: SDKKey];
    }
    else
    {
        return [ALSdk shared];
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
    
    // Ensure logic is ran on main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.parentCustomEvent.delegate bannerCustomEvent: self.parentCustomEvent
                                                 didLoadAd: self.parentCustomEvent.adView];
    });
}

- (void)adService:(ALAdService *)adService didFailToLoadAdWithError:(int)code
{
    // Ensure logic is ran on main queue
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.parentCustomEvent log: @"Banner failed to load with error: %d", code];
        
        NSError *error = [NSError errorWithDomain: kALMoPubMediationErrorDomain
                                             code: [self.parentCustomEvent toMoPubErrorCode: code]
                                         userInfo: nil];
        [self.parentCustomEvent.delegate bannerCustomEvent: self.parentCustomEvent didFailToLoadAdWithError: error];
    });
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
