package YOUR_PACKAGE_NAME;

import android.app.Activity;
import android.content.Context;
import android.util.Log;

import com.applovin.adview.AppLovinAdView;
import com.applovin.sdk.AppLovinAd;
import com.applovin.sdk.AppLovinAdClickListener;
import com.applovin.sdk.AppLovinAdDisplayListener;
import com.applovin.sdk.AppLovinAdLoadListener;
import com.applovin.sdk.AppLovinAdSize;
import com.applovin.sdk.AppLovinErrorCodes;
import com.applovin.sdk.AppLovinSdk;
import com.mopub.mobileads.CustomEventBanner;
import com.mopub.mobileads.MoPubErrorCode;

import java.util.Map;

/**
 * AppLovin Banner SDK Mediation for MoPub.
 * <p>
 * Created by Thomas So on 3/6/17.
 *
 * @version 1.0
 */

public class AppLovinBannerAdapter
        extends CustomEventBanner
{
    private static final String TAG = "AppLovinBannerAdapter";

    private static final String AD_WIDTH_KEY  = "adWidth";
    private static final String AD_HEIGHT_KEY = "adHeight";

    @Override
    protected void loadBanner(final Context context, final CustomEventBannerListener customEventBannerListener, final Map<String, Object> localExtras, final Map<String, String> serverExtras)
    {
        // Input check
        if ( !( context instanceof Activity ) )
        {
            Log.e( TAG, "Unable to request AppLovin banner. Invalid context provided." );
            customEventBannerListener.onBannerFailed( MoPubErrorCode.ADAPTER_CONFIGURATION_ERROR );
            return;
        }

        Log.d( TAG, "Requesting AppLovin banner with serverExtras: " + serverExtras );

        final AppLovinAdSize adSize = appLovinAdSizeFromServerExtras( serverExtras );
        if ( adSize != null )
        {
            final AppLovinSdk sdk = AppLovinSdk.getInstance( context );
            sdk.setPluginVersion( "MoPubBanner-1.0" );
            
            final AppLovinAdView adView = new AppLovinAdView( adSize, (Activity) context );
            adView.setAdLoadListener( new AppLovinAdLoadListener()
            {
                @Override
                public void adReceived(final AppLovinAd ad)
                {
                    Log.d( TAG, "Successfully loaded banner ad" );
                }

                @Override
                public void failedToReceiveAd(final int errorCode)
                {
                    Log.e( TAG, "Failed to load banner ad with code: " + errorCode );

                    if ( errorCode == AppLovinErrorCodes.NO_FILL )
                    {
                        customEventBannerListener.onBannerFailed( MoPubErrorCode.NETWORK_NO_FILL );
                    }
                    else if ( errorCode >= 500 )
                    {
                        customEventBannerListener.onBannerFailed( MoPubErrorCode.SERVER_ERROR );
                    }
                    else if ( errorCode < 0 )
                    {
                        customEventBannerListener.onBannerFailed( MoPubErrorCode.INTERNAL_ERROR );
                    }
                    else
                    {
                        customEventBannerListener.onBannerFailed( MoPubErrorCode.UNSPECIFIED );
                    }
                }
            } );
            adView.setAdDisplayListener( new AppLovinAdDisplayListener()
            {
                @Override
                public void adDisplayed(final AppLovinAd ad)
                {
                    Log.d( TAG, "Banner displayed" );
                }

                @Override
                public void adHidden(final AppLovinAd ad)
                {
                    Log.d( TAG, "Banner dismissed" );
                }
            } );
            adView.setAdClickListener( new AppLovinAdClickListener()
            {
                @Override
                public void adClicked(final AppLovinAd ad)
                {
                    Log.d( TAG, "Banner clicked" );

                    customEventBannerListener.onBannerClicked();
                    customEventBannerListener.onLeaveApplication();
                }
            } );
            adView.loadNextAd();

            customEventBannerListener.onBannerLoaded( adView );
        }
        else
        {
            Log.e( TAG, "Unable to request AppLovin banner" );

            customEventBannerListener.onBannerFailed( MoPubErrorCode.ADAPTER_CONFIGURATION_ERROR );
        }
    }

    @Override
    protected void onInvalidate() { }

    private AppLovinAdSize appLovinAdSizeFromServerExtras(final Map<String, String> serverExtras)
    {
        // Handle trivial case
        if ( serverExtras == null || serverExtras.isEmpty() )
        {
            Log.e( TAG, "No serverExtras provided" );

            // Return BANNER by default
            return AppLovinAdSize.BANNER;
        }

        try
        {
            final int width = Integer.parseInt( serverExtras.get( AD_WIDTH_KEY ) );
            final int height = Integer.parseInt( serverExtras.get( AD_HEIGHT_KEY ) );

            // We have valid dimensions
            if ( width > 0 && height > 0 )
            {
                Log.d( TAG, "Valid width (" + width + ") and height (" + height + ") provided" );

                // Use the smallest AppLovinAdSize that will properly contain the adView

                if ( height <= AppLovinAdSize.BANNER.getHeight() )
                {
                    return AppLovinAdSize.BANNER;
                }
                else if ( height <= AppLovinAdSize.MREC.getHeight() )
                {
                    return AppLovinAdSize.MREC;
                }
                else
                {
                    Log.e( TAG, "Provided dimensions does not meet the dimensions required of banner or mrec ads" );
                }
            }
            else
            {
                Log.e( TAG, "Invalid width (" + width + ") and height (" + height + ") provided" );
            }
        }
        catch ( Throwable th )
        {
            Log.e( TAG, "Encountered error while parsing width and height from serverExtras", th );
        }

        // Return BANNER by default
        return AppLovinAdSize.BANNER;
    }
}
