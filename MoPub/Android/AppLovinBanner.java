/**
 * AppLovin Banner SDK Mediation for MoPub
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
import com.mopub.mobileads.CustomEventBanner;
import com.mopub.mobileads.MoPubErrorCode;

import java.util.Map;

public class AppLovinBanner extends CustomEventBanner implements AppLovinAdLoadListener, AppLovinAdClickListener
{

    private CustomEventBanner.CustomEventBannerListener mBannerListener;
    private AppLovinAdView                              adView;

    public static final String SDK_KEY = "sdk_key";

    /*
     * Abstract methods from CustomEventBanner
     */
    @Override
    public void loadBanner(Context context,
            CustomEventBanner.CustomEventBannerListener bannerListener,
            Map<String, Object> localExtras, Map<String, String> serverExtras)
    {
        mBannerListener = bannerListener;

        Activity activity = null;
        if ( context instanceof Activity )
        {
            activity = (Activity) context;
        }
        else
        {
            mBannerListener.onBannerFailed( MoPubErrorCode.INTERNAL_ERROR );
            return;
        }

        Log.d( "AppLovinAdapter", "Request received for new BANNER." );

        AppLovinSdk appLovinSdk;
        if (extrasAreValid(serverExtras)) {
            String key = serverExtras.get(SDK_KEY);
            appLovinSdk = AppLovinSdk.getInstance(key, AppLovinSdkUtils.retrieveUserSettings(context), context);
        } else {
            appLovinSdk = AppLovinSdk.getInstance(context);
        }

        adView = new AppLovinAdView(appLovinSdk, AppLovinAdSize.BANNER, activity);
        adView.setAutoDestroy( false );
        adView.setAdLoadListener( this );
        adView.setAdClickListener( this );
        adView.loadNextAd();
    }

    private boolean extrasAreValid(Map<String, String> extras) {
        return extras.containsKey(SDK_KEY);
    }

    @Override
    public void onInvalidate()
    {
        adView.destroy();
    }

    @Override
    public void adReceived(AppLovinAd ad)
    {
        mBannerListener.onBannerLoaded( adView );
        Log.d( "AppLovinAdapter", "AdView was passed to MoPub." );
    }

    @Override
    public void failedToReceiveAd(int errorCode)
    {
        if ( errorCode == 204 )
        {
            mBannerListener.onBannerFailed( MoPubErrorCode.NO_FILL );
        }
        else if ( errorCode >= 500 )
        {
            mBannerListener.onBannerFailed( MoPubErrorCode.SERVER_ERROR );
        }
        else if ( errorCode < 0 )
        {
            mBannerListener.onBannerFailed( MoPubErrorCode.INTERNAL_ERROR );
        }
        else
        {
            mBannerListener.onBannerFailed( MoPubErrorCode.UNSPECIFIED );
        }
    }

    @Override
    public void adClicked(AppLovinAd appLovinAd)
    {
        mBannerListener.onLeaveApplication();
    }
}
