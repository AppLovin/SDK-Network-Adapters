package YOUR_PACKAGE_NAME;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;
import android.util.Log;

import com.applovin.adview.AppLovinAdView;
import com.applovin.sdk.AppLovinAd;
import com.applovin.sdk.AppLovinAdClickListener;
import com.applovin.sdk.AppLovinAdDisplayListener;
import com.applovin.sdk.AppLovinAdLoadListener;
import com.applovin.sdk.AppLovinAdSize;
import com.applovin.sdk.AppLovinErrorCodes;
import com.applovin.sdk.AppLovinSdk;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.AdSize;
import com.google.android.gms.ads.mediation.MediationAdRequest;
import com.google.android.gms.ads.mediation.customevent.CustomEventBanner;
import com.google.android.gms.ads.mediation.customevent.CustomEventBannerListener;

import static android.util.Log.DEBUG;
import static android.util.Log.ERROR;

/**
 * AppLovin SDK banner adapter for AdMob.
 * <p>
 * Created by thomasso on 4/12/17.
 */

public class AppLovinCustomEventBanner
        implements CustomEventBanner
{
    private static final boolean LOGGING_ENABLED = true;
    private static final String  DEFAULT_ZONE    = "";

    private static final int BANNER_STANDARD_HEIGHT         = 50;
    private static final int BANNER_HEIGHT_OFFSET_TOLERANCE = 10;

    private AppLovinAdView adView;

    //
    // AdMob Custom Event Methods
    //

    @Override
    public void requestBannerAd(final Context context, final CustomEventBannerListener customEventBannerListener, final String serverParameter, final AdSize adSize, final MediationAdRequest mediationAdRequest, final Bundle customEventExtras)
    {
        // SDK versions BELOW 7.1.0 require a instance of an Activity to be passed in as the context
        if ( AppLovinSdk.VERSION_CODE < 710 && !( context instanceof Activity ) )
        {
            log( ERROR, "Unable to request AppLovin banner. Invalid context provided." );
            customEventBannerListener.onAdFailedToLoad( AdRequest.ERROR_CODE_INTERNAL_ERROR );

            return;
        }

        log( DEBUG, "Requesting AppLovin banner of size: " + adSize );

        final AppLovinAdSize appLovinAdSize = appLovinAdSizeFromAdMobAdSize( adSize );
        if ( appLovinAdSize != null )
        {
            final AppLovinSdk sdk = AppLovinSdk.getInstance( context );
            sdk.setPluginVersion( "AdMob-2.2.1" );

            // Zones support is available on AppLovin SDK 7.5.0 and higher
            final String zoneId;
            if ( AppLovinSdk.VERSION_CODE >= 750 && customEventExtras != null && customEventExtras.containsKey( "zone_id" ) )
            {
                zoneId = customEventExtras.getString( "zone_id" );
            }
            else
            {
                zoneId = DEFAULT_ZONE;
            }

            adView = new AppLovinAdView( appLovinAdSize, zoneId, context );
            adView.setAdLoadListener( new AppLovinAdLoadListener()
            {
                @Override
                public void adReceived(final AppLovinAd ad)
                {
                    log( DEBUG, "Successfully loaded banner ad" );
                    customEventBannerListener.onAdLoaded( adView );
                }

                @Override
                public void failedToReceiveAd(final int errorCode)
                {
                    log( ERROR, "Failed to load banner ad with code: " + errorCode );
                    customEventBannerListener.onAdFailedToLoad( toAdMobErrorCode( errorCode ) );
                }
            } );
            adView.setAdDisplayListener( new AppLovinAdDisplayListener()
            {
                @Override
                public void adDisplayed(final AppLovinAd ad)
                {
                    log( DEBUG, "Banner displayed" );
                }

                @Override
                public void adHidden(final AppLovinAd ad)
                {
                    log( DEBUG, "Banner dismissed" );
                }
            } );
            adView.setAdClickListener( new AppLovinAdClickListener()
            {
                @Override
                public void adClicked(final AppLovinAd ad)
                {
                    log( DEBUG, "Banner clicked" );

                    customEventBannerListener.onAdOpened();
                    customEventBannerListener.onAdLeftApplication();
                }
            } );

            adView.loadNextAd();
        }
        else
        {
            log( ERROR, "Unable to request AppLovin banner" );
            customEventBannerListener.onAdFailedToLoad( AdRequest.ERROR_CODE_INTERNAL_ERROR );
        }
    }

    @Override
    public void onDestroy()
    {
        if ( adView != null ) adView.destroy();
    }

    @Override
    public void onPause()
    {
        if ( adView != null ) adView.pause();
    }

    @Override
    public void onResume()
    {
        if ( adView != null ) adView.resume();
    }

    //
    // Utility Methods
    //

    private AppLovinAdSize appLovinAdSizeFromAdMobAdSize(final AdSize adSize)
    {
        final boolean isSmartBanner = ( adSize.getWidth() == AdSize.FULL_WIDTH ) && ( adSize.getHeight() == AdSize.AUTO_HEIGHT );

        if ( AdSize.BANNER.equals( adSize ) || AdSize.LARGE_BANNER.equals( adSize ) || isSmartBanner )
        {
            return AppLovinAdSize.BANNER;
        }
        else if ( AdSize.MEDIUM_RECTANGLE.equals( adSize ) )
        {
            return AppLovinAdSize.MREC;
        }
        else if ( AdSize.LEADERBOARD.equals( adSize ) )
        {
            return AppLovinAdSize.LEADER;
        }
        // This is not a one of AdMob's predefined size
        else
        {
            // Assume fluid width, and check for height with offset tolerance
            final int offset = Math.abs( BANNER_STANDARD_HEIGHT - adSize.getHeight() );
            if ( offset <= BANNER_HEIGHT_OFFSET_TOLERANCE )
            {
                return AppLovinAdSize.BANNER;
            }
        }

        return null;
    }

    private static void log(final int priority, final String message)
    {
        if ( LOGGING_ENABLED )
        {
            Log.println( priority, "AppLovinBanner", message );
        }
    }

    private static int toAdMobErrorCode(final int applovinErrorCode)
    {
        if ( applovinErrorCode == AppLovinErrorCodes.NO_FILL )
        {
            return AdRequest.ERROR_CODE_NO_FILL;
        }
        else if ( applovinErrorCode == AppLovinErrorCodes.NO_NETWORK || applovinErrorCode == AppLovinErrorCodes.FETCH_AD_TIMEOUT )
        {
            return AdRequest.ERROR_CODE_NETWORK_ERROR;
        }
        else
        {
            return AdRequest.ERROR_CODE_INTERNAL_ERROR;
        }
    }
}