//
//  GADMAdapterAppLovinRewardBasedVideoAd.h
//
//
//  Created by Thomas So on 5/20/17.
//
//

@import GoogleMobileAds;

#if __has_include(<AppLovinSDK/AppLovinSDK.h>)
    #import <AppLovinSDK/AppLovinSDK.h>
#else
    #import "ALAnnotations.h"
#endif

AL_ASSUME_NONNULL_BEGIN

@interface GADMAdapterAppLovinRewardBasedVideoAd : NSObject <GADMRewardBasedVideoAdNetworkAdapter>

@end

@interface AppLovinAdNetworkExtras : NSObject<GADAdNetworkExtras>

// AppLovin Zone ID to be used for rewarded video ad requests.
@property (nonatomic, copy, alnullable) NSString *zoneIdentifier;

@end

AL_ASSUME_NONNULL_END
