//
//  AppLovinCustomEventInterstitialEvent.m
//
//
//  Created by Thomas So on 5/20/17.
//
//

#import "AppLovinCustomEventInterstitial.h"

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALAdService.h"
    #import "ALInterstitialAd.h"
#endif

// Convenience macro for checking if AppLovin SDK has support for zones
#define HAS_ZONES_SUPPORT [[ALSdk shared].adService respondsToSelector: @selector(loadNextAdForZoneIdentifier:andNotify:)]
#define DEFAULT_ZONE @""

// This class implementation with the old classname is left here for backwards compatibility purposes.
@implementation AppLovinCustomEventInter
@end

@interface AppLovinCustomEventInterstitial() <ALAdLoadDelegate, ALAdDisplayDelegate, ALAdVideoPlaybackDelegate>
@property (nonatomic, strong) ALInterstitialAd *interstitialAd;
@property (nonatomic,   copy) NSString *zoneIdentifier; // The zone identifier this instance of the custom event is loading for
@end

@implementation AppLovinCustomEventInterstitial
@synthesize delegate;

static const BOOL kALLoggingEnabled = YES;
static NSString *const kALAdMobMediationErrorDomain = @"com.applovin.sdk.mediation.admob.errorDomain";

// A dictionary of Zone -> Queue of `ALAd`s to be shared by instances of the custom event.
// This prevents skipping of ads as this adapter will be re-created and preloaded
// on every ad load regardless if ad was actually displayed or not.
static NSMutableDictionary<NSString *, NSMutableArray<ALAd *> *> *ALGlobalInterstitialAds;
static NSObject *ALGlobalInterstitialAdsLock;

#pragma mark - Class Initialization

+ (void)initialize
{
    [super initialize];
    
    ALGlobalInterstitialAds = [NSMutableDictionary dictionary];
    ALGlobalInterstitialAdsLock = [[NSObject alloc] init];
}

#pragma mark - GADCustomEventInterstitial Protocol

- (void)requestInterstitialAdWithParameter:(NSString *)serverParameter label:(NSString *)serverLabel request:(GADCustomEventRequest *)request
{
    [self log: @"Requesting AppLovin interstitial"];
    
    [[ALSdk shared] setPluginVersion: @"AdMob-2.3.1"];
    
    // Zones support is available on AppLovin SDK 4.5.0 and higher
    if ( HAS_ZONES_SUPPORT && request.additionalParameters[@"zone_id"] )
    {
        self.zoneIdentifier = request.additionalParameters[@"zone_id"];
    }
    else
    {
        self.zoneIdentifier = DEFAULT_ZONE;
    }
    
    // Check if we already have a preloaded ad for the given zone
    ALAd *preloadedAd = [[self class] dequeueAdForZoneIdentifier: self.zoneIdentifier];
    if ( preloadedAd )
    {
        [self log: @"Found preloaded ad for zone: {%@}", self.zoneIdentifier];
        [self adService: [ALSdk shared].adService didLoadAd: preloadedAd];
    }
    // No ad currently preloaded
    else
    {
        // If this is a default Zone, create the incentivized ad normally
        if ( [DEFAULT_ZONE isEqualToString: self.zoneIdentifier] )
        {
            [[ALSdk shared].adService loadNextAd: [ALAdSize sizeInterstitial] andNotify: self];
        }
        // Otherwise, use the Zones API
        else
        {
            // Dynamically load an ad for a given zone without breaking backwards compatibility for publishers on older SDKs
            [[ALSdk shared].adService performSelector: @selector(loadNextAdForZoneIdentifier:andNotify:)
                                           withObject: self.zoneIdentifier
                                           withObject: self];
        }
    }
}

- (void)presentFromRootViewController:(UIViewController *)rootViewController
{
    ALAd *preloadedAd = [[self class] dequeueAdForZoneIdentifier: self.zoneIdentifier];
    if ( preloadedAd )
    {
        self.interstitialAd = [[ALInterstitialAd alloc] initWithSdk: [ALSdk shared]];
        self.interstitialAd.adDisplayDelegate = self;
        self.interstitialAd.adVideoPlaybackDelegate = self;
        [self.interstitialAd showOver: rootViewController.view.window andRender: preloadedAd];
    }
    else
    {
        [self log: @"Failed to show an AppLovin interstitial before one was loaded"];
        
        NSError *error = [NSError errorWithDomain: kALAdMobMediationErrorDomain
                                             code: kALErrorCodeUnableToRenderAd
                                         userInfo: @{NSLocalizedFailureReasonErrorKey : @"Adaptor requested to display an interstitial before one was loaded"}];
        
        [self.delegate customEventInterstitial: self didFailAd: error];
    }
}

#pragma mark - Ad Load Delegate

- (void)adService:(ALAdService *)adService didLoadAd:(ALAd *)ad
{
    [self log: @"Interstitial did load ad: %@", ad.adIdNumber];
    
    [[self class] enqueueAd: ad forZoneIdentifier: self.zoneIdentifier];
    
    if ( [self.delegate respondsToSelector: @selector(customEventInterstitialDidReceiveAd:)] )
    {
        [self.delegate performSelector: @selector(customEventInterstitialDidReceiveAd:) withObject: self];
    }
    // Older versions of AdMob
    else
    {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        [self.delegate customEventInterstitial: self didReceiveAd: ad];
#pragma GCC diagnostic pop
    }
}

- (void)adService:(ALAdService *)adService didFailToLoadAdWithError:(int)code
{
    [self log: @"Interstitial failed to load with error: %d", code];
    
    NSError *error = [NSError errorWithDomain: kALAdMobMediationErrorDomain
                                         code: [self toAdMobErrorCode: code]
                                     userInfo: nil];
    [self.delegate customEventInterstitial: self didFailAd: error];
    
    // TODO: Add support for backfilling on regular ad request if invalid zone entered
}

#pragma mark - Ad Display Delegate

- (void)ad:(ALAd *)ad wasDisplayedIn:(UIView *)view
{
    [self log: @"Interstitial displayed"];
    
    [self.delegate customEventInterstitialWillPresent: self];
}

- (void)ad:(ALAd *)ad wasHiddenIn:(UIView *)view
{
    [self log: @"Interstitial dismissed"];
    
    [self.delegate customEventInterstitialWillDismiss: self];
    [self.delegate customEventInterstitialDidDismiss: self];
    
    self.interstitialAd = nil;
}

- (void)ad:(ALAd *)ad wasClickedIn:(UIView *)view
{
    [self log: @"Interstitial clicked"];
    
    [self.delegate customEventInterstitialWillLeaveApplication: self];
}

#pragma mark - Video Playback Delegate

- (void)videoPlaybackBeganInAd:(ALAd *)ad
{
    [self log: @"Interstitial video playback began"];
}

- (void)videoPlaybackEndedInAd:(ALAd *)ad atPlaybackPercent:(NSNumber *)percentPlayed fullyWatched:(BOOL)wasFullyWatched
{
    [self log: @"Interstitial video playback ended at playback percent: %lu", percentPlayed.unsignedIntegerValue];
}

#pragma mark - Utility Methods

+ (alnullable ALAd *)dequeueAdForZoneIdentifier:(NSString *)zoneIdentifier
{
    @synchronized ( ALGlobalInterstitialAdsLock )
    {
        ALAd *preloadedAd;
        
        NSMutableArray<ALAd *> *preloadedAds = ALGlobalInterstitialAds[zoneIdentifier];
        if ( preloadedAds.count > 0 )
        {
            preloadedAd = preloadedAds[0];
            [preloadedAds removeObjectAtIndex: 0];
        }
        
        return preloadedAd;
    }
}

+ (void)enqueueAd:(ALAd *)ad forZoneIdentifier:(NSString *)zoneIdentifier
{
    @synchronized ( ALGlobalInterstitialAdsLock )
    {
        NSMutableArray<ALAd *> *preloadedAds = ALGlobalInterstitialAds[zoneIdentifier];
        if ( !preloadedAds )
        {
            preloadedAds = [NSMutableArray array];
            ALGlobalInterstitialAds[zoneIdentifier] = preloadedAds;
        }
        
        [preloadedAds addObject: ad];
    }
}

- (void)log:(NSString *)format, ...
{
    if ( kALLoggingEnabled )
    {
        va_list valist;
        va_start(valist, format);
        NSString *message = [[NSString alloc] initWithFormat: format arguments: valist];
        va_end(valist);
        
        NSLog(@"AppLovinCustomEventInterstitial: %@", message);
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
