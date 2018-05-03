
//
//  GADMAdapterAppLovinRewardBasedVideoAd.m
//
//
//  Created by Thomas So on 5/20/17.
//
//

#import "GADMAdapterAppLovinRewardBasedVideoAd.h"

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALSdk.h"
    #import "ALIncentivizedInterstitialAd.h"
#endif

// Convenience macro for checking if AppLovin SDK has support for zones
#define HAS_ZONES_SUPPORT [[ALSdk shared].adService respondsToSelector: @selector(loadNextAdForZoneIdentifier:andNotify:)]
#define DEFAULT_ZONE @""

@interface GADMAdapterAppLovinRewardBasedVideoAd() <ALAdLoadDelegate, ALAdDisplayDelegate, ALAdVideoPlaybackDelegate, ALAdRewardDelegate>

@property (nonatomic, strong) ALIncentivizedInterstitialAd *incent;

@property (nonatomic, assign) BOOL fullyWatched;
@property (nonatomic, strong) GADAdReward *reward;

@property (nonatomic,   weak) id<GADMRewardBasedVideoAdNetworkConnector> connector;

@end

@implementation GADMAdapterAppLovinRewardBasedVideoAd

static const BOOL kALLoggingEnabled = YES;
static NSString *const kALAdMobMediationErrorDomain = @"com.applovin.sdk.mediation.admob.errorDomain";
static NSString *const kALAdMobAdapterVersion = @"AdMob-2.3.1";

// A dictionary of Zone -> `ALIncentivizedInterstitialAd` to be shared by instances of the custom event.
// This prevents skipping of ads as this adapter will be re-created and preloaded (along with underlying `ALIncentivizedInterstitialAd`)
// on every ad load regardless if ad was actually displayed or not.
static NSMutableDictionary<NSString *, ALIncentivizedInterstitialAd *> *ALGlobalIncentivizedInterstitialAds;

#pragma mark - Class Initialization

+ (void)initialize
{
    [super initialize];
    
    ALGlobalIncentivizedInterstitialAds = [NSMutableDictionary dictionary];
}

#pragma mark - GADMRewardBasedVideoAdNetworkAdapter Protocol

+ (NSString *)adapterVersion
{
    return kALAdMobAdapterVersion;
}

+ (Class<GADAdNetworkExtras>)networkExtrasClass
{
    return [AppLovinAdNetworkExtras class];
}

- (instancetype)initWithRewardBasedVideoAdNetworkConnector:(id<GADMRewardBasedVideoAdNetworkConnector>)connector
{
    self = [super init];
    if ( self )
    {
        self.connector = connector;
    }
    return self;
}

- (void)setUp
{
    [[ALSdk shared] initializeSdk];
    [[ALSdk shared] setPluginVersion: kALAdMobAdapterVersion];
    
    [self.connector adapterDidSetUpRewardBasedVideoAd: self];
}

- (void)requestRewardBasedVideoAd
{
    [self log: @"Requesting AppLovin rewarded video"];
    
    NSString *adapterVersion = [[self class] adapterVersion];
    [[ALSdk shared] setPluginVersion: adapterVersion];
    
    // Zones support is available on AppLovin SDK 4.5.0 and higher
    AppLovinAdNetworkExtras *extras = (AppLovinAdNetworkExtras *)self.connector.networkExtras;
    NSString *zoneIdentifier = (extras.zoneIdentifier && HAS_ZONES_SUPPORT) ? extras.zoneIdentifier : DEFAULT_ZONE;
    
    // Check if incentivized ad for zone already exists
    if ( ALGlobalIncentivizedInterstitialAds[zoneIdentifier] )
    {
        self.incent = ALGlobalIncentivizedInterstitialAds[zoneIdentifier];
    }
    else
    {
        // If this is a default Zone, create the incentivized ad normally
        if ( [DEFAULT_ZONE isEqualToString: zoneIdentifier] )
        {
            self.incent = [[ALIncentivizedInterstitialAd alloc] initWithSdk: [ALSdk shared]];
        }
        // Otherwise, use the Zones API
        else
        {
            self.incent = [self incentivizedInterstitialAdWithZoneIdentifier: zoneIdentifier];
        }
        
        ALGlobalIncentivizedInterstitialAds[zoneIdentifier] = self.incent;
    }
    
    self.incent.adVideoPlaybackDelegate = self;
    self.incent.adDisplayDelegate = self;
    
    [self.incent preloadAndNotify: self];
}

- (void)presentRewardBasedVideoAdWithRootViewController:(UIViewController *)viewController
{
    if ( self.incent.readyForDisplay )
    {
        self.reward = nil;
        self.fullyWatched = NO;
        
        [self.incent showAndNotify: self];
    }
    else
    {
        [self log: @"Failed to show an AppLovin rewarded video before one was loaded"];
        
        NSError *error = [NSError errorWithDomain: kALAdMobMediationErrorDomain
                                             code: kALErrorCodeUnableToRenderAd
                                         userInfo: @{NSLocalizedFailureReasonErrorKey : @"Adapter requested to display a rewarded video before one was loaded"}];
        
        [self.connector adapter: self didFailToSetUpRewardBasedVideoAdWithError: error];
    }
}

- (void)stopBeingDelegate
{
    self.connector = nil;
}

#pragma mark - Ad Load Delegate

- (void)adService:(ALAdService *)adService didLoadAd:(ALAd *)ad
{
    [self log: @"Rewarded video did load ad: %@", ad.adIdNumber];
    [self.connector adapterDidReceiveRewardBasedVideoAd: self];
}

- (void)adService:(ALAdService *)adService didFailToLoadAdWithError:(int)code
{
    [self log: @"Rewarded video failed to load with error: %d", code];
    
    NSError *error = [NSError errorWithDomain: kALAdMobMediationErrorDomain
                                         code: [self toAdMobErrorCode: code]
                                     userInfo: @{NSLocalizedFailureReasonErrorKey : @"Adapter requested to display a rewarded video before one was loaded"}];
    [self.connector adapter: self didFailToLoadRewardBasedVideoAdwithError: error];
}

#pragma mark - Ad Display Delegate

- (void)ad:(ALAd *)ad wasDisplayedIn:(UIView *)view
{
    [self log: @"Rewarded video displayed"];
    [self.connector adapterDidOpenRewardBasedVideoAd: self];
}

- (void)ad:(ALAd *)ad wasHiddenIn:(UIView *)view
{
    [self log: @"Rewarded video dismissed"];
    
    if ( self.fullyWatched && self.reward )
    {
        [self.connector adapter: self didRewardUserWithReward: self.reward];
    }
    
    [self.connector adapterDidCloseRewardBasedVideoAd: self];
    
    self.incent = nil;
}

- (void)ad:(ALAd *)ad wasClickedIn:(UIView *)view
{
    [self log: @"Rewarded video clicked"];
    
    [self.connector adapterDidGetAdClick: self];
    [self.connector adapterWillLeaveApplication: self];
}

#pragma mark - Video Playback Delegate

- (void)videoPlaybackBeganInAd:(ALAd *)ad
{
    [self log: @"Interstitial video playback began"];
    [self.connector adapterDidStartPlayingRewardBasedVideoAd: self];
}

- (void)videoPlaybackEndedInAd:(ALAd *)ad atPlaybackPercent:(NSNumber *)percentPlayed fullyWatched:(BOOL)wasFullyWatched
{
    [self log: @"Interstitial video playback ended at playback percent: %lu", percentPlayed.unsignedIntegerValue];
    
    self.fullyWatched = wasFullyWatched;
}

#pragma mark - Reward Delegate

- (void)rewardValidationRequestForAd:(ALAd *)ad didExceedQuotaWithResponse:(NSDictionary *)response
{
    [self log: @"Rewarded video validation request for ad did exceed quota with response: %@", response];
}

- (void)rewardValidationRequestForAd:(ALAd *)ad didFailWithError:(NSInteger)responseCode
{
    [self log: @"Rewarded video validation request for ad failed with error code: %ld", responseCode];
}

- (void)rewardValidationRequestForAd:(ALAd *)ad wasRejectedWithResponse:(NSDictionary *)response
{
    [self log: @"Rewarded video validation request was rejected with response: %@", response];
}

- (void)userDeclinedToViewAd:(ALAd *)ad
{
    [self log: @"User declined to view rewarded video"];
}

- (void)rewardValidationRequestForAd:(ALAd *)ad didSucceedWithResponse:(NSDictionary *)response
{
    NSDecimalNumber *amount = [NSDecimalNumber decimalNumberWithString: response[@"amount"]];
    NSString *currency = response[@"currency"];
    
    [self log: @"Rewarded %@ %@", amount, currency];
    
    self.reward = [[GADAdReward alloc] initWithRewardType: currency rewardAmount: amount];
}

#pragma mark - Incentivized Interstitial

/**
 * Dynamically create an instance of ALAdView with a given zone without breaking backwards compatibility for publishers on older SDKs.
 */
- (ALIncentivizedInterstitialAd *)incentivizedInterstitialAdWithZoneIdentifier:(NSString *)zoneIdentifier
{
    // Prematurely create instance of ALAdView to store initialized one in later
    ALIncentivizedInterstitialAd *incent = [ALIncentivizedInterstitialAd alloc];
    
    // We must use NSInvocation over performSelector: for initializers
    NSMethodSignature *methodSignature = [ALIncentivizedInterstitialAd instanceMethodSignatureForSelector: @selector(initWithZoneIdentifier:)];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature: methodSignature];
    [inv setSelector: @selector(initWithZoneIdentifier:)];
    [inv setArgument: &zoneIdentifier atIndex: 2];
    [inv setReturnValue: &incent];
    [inv invokeWithTarget: incent];
    
    return incent;
}

#pragma mark - Utility Methods

- (void)log:(NSString *)format, ...
{
    if ( kALLoggingEnabled )
    {
        va_list valist;
        va_start(valist, format);
        NSString *message = [[NSString alloc] initWithFormat: format arguments: valist];
        va_end(valist);
        
        NSLog(@"AppLovinCustomEventRewardedVideo: %@", message);
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

@implementation AppLovinAdNetworkExtras

@end
