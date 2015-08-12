/**
 * AppLovin Interstitial SDK Mediation for MoPub
 *
 * @author Matt Szaro
 * @version 1.2
 **/

package com.mopub.mobileads;

import android.app.Activity;
import android.content.Context;
import android.util.Log;
import com.applovin.adview.AppLovinAdView;
import com.applovin.sdk.*;
import com.mopub.mobileads.CustomEventInterstitial;
import com.mopub.mobileads.MoPubErrorCode;

import java.util.Map;

public class AppLovinInterstitial extends CustomEventInterstitial
        implements AppLovinAdLoadListener {
    private CustomEventInterstitial.CustomEventInterstitialListener mInterstitialListener;
    private Activity parentActivity;
    private AppLovinAdService adService;
    private AppLovinAd lastReceived;

    public static final String SDK_KEY = "sdk_key";

    /*
     * Abstract methods from CustomEventInterstitial
     */
    @Override
    public void loadInterstitial(Context context, CustomEventInterstitial.CustomEventInterstitialListener interstitialListener, Map<String, Object> localExtras, Map<String, String> serverExtras) {
        mInterstitialListener = interstitialListener;

        if (context instanceof Activity) {
            parentActivity = (Activity) context;
        } else {
            mInterstitialListener.onInterstitialFailed(MoPubErrorCode.INTERNAL_ERROR);
            return;
        }

        Log.d("AppLovinAdapter", "Request received for new interstitial.");

        if (extrasAreValid(serverExtras)) {
            String key = serverExtras.get(SDK_KEY);
            adService = AppLovinSdk.getInstance(key, AppLovinSdkUtils.retrieveUserSettings(context), context).getAdService();
        } else {
            adService = AppLovinSdk.getInstance(context).getAdService();
        }

        adService.loadNextAd(AppLovinAdSize.INTERSTITIAL, this);
    }

    private boolean extrasAreValid(Map<String, String> extras) {
        return extras.containsKey(SDK_KEY);
    }

    @Override
    public void showInterstitial() {
        final AppLovinAd adToRender = lastReceived;

        if (adToRender != null) {
            Log.d("MoPub", "Showing AppLovin interstitial ad...");

            parentActivity.runOnUiThread(new Runnable() {
                public void run() {
                    AppLovinAdView adView = new AppLovinAdView(AppLovinAdSize.BANNER, parentActivity);

                    adView.setAdClickListener(new AppLovinAdClickListener() {
                        @Override
                        public void adClicked(AppLovinAd appLovinAd) {
                            mInterstitialListener.onLeaveApplication();
                        }
                    });

                    adView.setAdDisplayListener(new AppLovinAdDisplayListener() {
                        @Override
                        public void adDisplayed(AppLovinAd appLovinAd) {
                            mInterstitialListener.onInterstitialShown();
                        }

                        @Override
                        public void adHidden(AppLovinAd appLovinAd) {
                            mInterstitialListener.onInterstitialDismissed();
                        }
                    });
                    adView.renderAd(adToRender);
                }
            });
        }
    }

    @Override
    public void onInvalidate() {

    }

    @Override
    public void adReceived(AppLovinAd ad) {
        Log.d("MoPub", "AppLovin interstitial loaded successfully.");

        lastReceived = ad;

        parentActivity.runOnUiThread(new Runnable() {
            public void run() {
                mInterstitialListener.onInterstitialLoaded();
            }
        });
    }

    @Override
    public void failedToReceiveAd(final int errorCode) {
        parentActivity.runOnUiThread(new Runnable() {
            public void run() {
                if (errorCode == 204) {
                    mInterstitialListener.onInterstitialFailed(MoPubErrorCode.NO_FILL);
                } else if (errorCode >= 500) {
                    mInterstitialListener.onInterstitialFailed(MoPubErrorCode.SERVER_ERROR);
                } else if (errorCode < 0) {
                    mInterstitialListener.onInterstitialFailed(MoPubErrorCode.INTERNAL_ERROR);
                } else {
                    mInterstitialListener.onInterstitialFailed(MoPubErrorCode.UNSPECIFIED);
                }
            }
        });
    }
}
