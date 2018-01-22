package YOUR_PACKAGE_NAME;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.applovin.adview.AppLovinInterstitialAd;
import com.applovin.adview.AppLovinInterstitialAdDialog;
import com.applovin.sdk.AppLovinAd;
import com.applovin.sdk.AppLovinAdClickListener;
import com.applovin.sdk.AppLovinAdDisplayListener;
import com.applovin.sdk.AppLovinAdLoadListener;
import com.applovin.sdk.AppLovinAdSize;
import com.applovin.sdk.AppLovinAdVideoPlaybackListener;
import com.applovin.sdk.AppLovinErrorCodes;
import com.applovin.sdk.AppLovinSdk;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.mediation.MediationAdRequest;
import com.google.android.gms.ads.mediation.customevent.CustomEventInterstitial;
import com.google.android.gms.ads.mediation.customevent.CustomEventInterstitialListener;

import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.Map;
import java.util.Queue;

import static android.util.Log.DEBUG;
import static android.util.Log.ERROR;

/**
 * AppLovin SDK interstitial adapter for AdMob.
 * <p>
 * Created by Thomas So on 5/28/17.
 */

//
// PLEASE NOTE: We have renamed this class from "YOUR_PACKAGE_NAME.AdMobMediationInterEvent" to "YOUR_PACKAGE_NAME.AppLovinCustomEventInterstitial", you can use either classname in your AdMob account.
//
public class AppLovinCustomEventInterstitial
        implements CustomEventInterstitial, AppLovinAdLoadListener, AppLovinAdDisplayListener, AppLovinAdClickListener, AppLovinAdVideoPlaybackListener
{
    private static final boolean LOGGING_ENABLED = true;
    private static final Handler UI_HANDLER      = new Handler( Looper.getMainLooper() );
    private static final String  DEFAULT_ZONE    = "";

    // A map of Zone -> Queue of `AppLovinAd`s to be shared by instances of the custom event.
    // This prevents skipping of ads as this adapter will be re-created and preloaded
    // on every ad load regardless if ad was actually displayed or not.
    private static final Map<String, Queue<AppLovinAd>> GLOBAL_INTERSTITIAL_ADS      = new HashMap<String, Queue<AppLovinAd>>();
    private static final Object                         GLOBAL_INTERSTITIAL_ADS_LOCK = new Object();

    private Context                         context;
    private CustomEventInterstitialListener listener;

    private String zoneId; // The zone identifier this instance of the custom event is loading for

    //
    // AdMob Custom Event Methods
    //

    @Override
    public void requestInterstitialAd(final Context context, final CustomEventInterstitialListener listener, final String serverParameter, final MediationAdRequest mediationAdRequest, final Bundle customEventExtras)
    {
        log( DEBUG, "Requesting AppLovin interstitial..." );

        // SDK versions BELOW 7.2.0 require a instance of an Activity to be passed in as the context
        if ( AppLovinSdk.VERSION_CODE < 720 && !( context instanceof Activity ) )
        {
            log( ERROR, "Unable to request AppLovin interstitial. Invalid context provided." );
            listener.onAdFailedToLoad( AdRequest.ERROR_CODE_INVALID_REQUEST );

            return;
        }

        // Store parent objects
        this.listener = listener;
        this.context = context;

        final AppLovinSdk sdk = AppLovinSdk.getInstance( context );
        sdk.setPluginVersion( "AdMob-2.0" );

        // Zones support is available on AppLovin SDK 7.5.0 and higher
        if ( AppLovinSdk.VERSION_CODE >= 750 && customEventExtras != null && customEventExtras.containsKey( "zone_id" ) )
        {
            zoneId = customEventExtras.getString( "zone_id" );
        }
        else
        {
            zoneId = DEFAULT_ZONE;
        }

        // Check if we already have a preloaded ad for the given zone
        final AppLovinAd preloadedAd = dequeueAd( zoneId );
        if ( preloadedAd != null )
        {
            log( DEBUG, "Found preloaded ad for zone: {" + zoneId + "}" );
            adReceived( preloadedAd );
        }
        else
        {
            // If this is a default Zone, load the interstitial ad normally
            if ( DEFAULT_ZONE.equals( zoneId ) )
            {
                sdk.getAdService().loadNextAd( AppLovinAdSize.INTERSTITIAL, this );
            }
            // Otherwise, use the Zones API
            else
            {
                // Dynamically load an ad for a given zone without breaking backwards compatibility for publishers on older SDKs
                try
                {
                    final Method method = sdk.getAdService().getClass().getMethod( "loadNextAdForZoneId", String.class, AppLovinAdLoadListener.class );
                    method.invoke( sdk.getAdService(), zoneId, this );
                }
                catch ( Throwable th )
                {
                    log( ERROR, "Unable to load ad for zone: " + zoneId + "..." );
                    listener.onAdFailedToLoad( AdRequest.ERROR_CODE_INVALID_REQUEST );
                }
            }
        }
    }

    @Override
    public void showInterstitial()
    {
        final AppLovinAd preloadedAd = dequeueAd( zoneId );
        if ( preloadedAd != null )
        {
            final AppLovinSdk sdk = AppLovinSdk.getInstance( context );

            final AppLovinInterstitialAdDialog interstitialAd = createInterstitial( context, sdk );
            interstitialAd.setAdDisplayListener( this );
            interstitialAd.setAdClickListener( this );
            interstitialAd.setAdVideoPlaybackListener( this );
            interstitialAd.showAndRender( preloadedAd );
        }
        else
        {
            log( ERROR, "Failed to show an AppLovin interstitial before one was loaded" );
            listener.onAdFailedToLoad( AdRequest.ERROR_CODE_INTERNAL_ERROR );
        }
    }

    @Override
    public void onPause() {}

    @Override
    public void onResume() {}

    @Override
    public void onDestroy() {}

    //
    // Ad Load Listener
    //

    @Override
    public void adReceived(final AppLovinAd ad)
    {
        log( DEBUG, "Interstitial did load ad: " + ad.getAdIdNumber() );

        enqueueAd( ad, zoneId );

        runOnUiThread( new Runnable()
        {
            @Override
            public void run()
            {
                listener.onAdLoaded();
            }
        } );
    }

    @Override
    public void failedToReceiveAd(final int errorCode)
    {
        log( ERROR, "Interstitial failed to load with error: " + errorCode );

        runOnUiThread( new Runnable()
        {
            @Override
            public void run()
            {
                listener.onAdFailedToLoad( toAdMobErrorCode( errorCode ) );
            }
        } );

        // TODO: Add support for backfilling on regular ad request if invalid zone entered
    }

    //
    // Ad Display Listener
    //

    @Override
    public void adDisplayed(final AppLovinAd appLovinAd)
    {
        log( DEBUG, "Interstitial displayed" );
        listener.onAdOpened();
    }

    @Override
    public void adHidden(final AppLovinAd appLovinAd)
    {
        log( DEBUG, "Interstitial dismissed" );
        listener.onAdClosed();
    }

    //
    // Ad Click Listener
    //

    @Override
    public void adClicked(final AppLovinAd appLovinAd)
    {
        log( DEBUG, "Interstitial clicked" );
        listener.onAdLeftApplication();
    }

    //
    // Video Playback Listener
    //

    @Override
    public void videoPlaybackBegan(final AppLovinAd ad)
    {
        log( DEBUG, "Interstitial video playback began" );
    }

    @Override
    public void videoPlaybackEnded(final AppLovinAd ad, final double percentViewed, final boolean fullyWatched)
    {
        log( DEBUG, "Interstitial video playback ended at playback percent: " + percentViewed );
    }

    //
    // Utility Methods
    //

    private static AppLovinAd dequeueAd(final String zoneId)
    {
        synchronized ( GLOBAL_INTERSTITIAL_ADS_LOCK )
        {
            AppLovinAd preloadedAd = null;

            final Queue<AppLovinAd> preloadedAds = GLOBAL_INTERSTITIAL_ADS.get( zoneId );
            if ( preloadedAds != null && !preloadedAds.isEmpty() )
            {
                preloadedAd = preloadedAds.poll();
            }

            return preloadedAd;
        }
    }

    private static void enqueueAd(final AppLovinAd ad, final String zoneId)
    {
        synchronized ( GLOBAL_INTERSTITIAL_ADS_LOCK )
        {
            Queue<AppLovinAd> preloadedAds = GLOBAL_INTERSTITIAL_ADS.get( zoneId );
            if ( preloadedAds == null )
            {
                preloadedAds = new LinkedList<AppLovinAd>();
                GLOBAL_INTERSTITIAL_ADS.put( zoneId, preloadedAds );
            }

            preloadedAds.offer( ad );
        }
    }

    private AppLovinInterstitialAdDialog createInterstitial(final Context context, final AppLovinSdk sdk)
    {
        AppLovinInterstitialAdDialog inter = null;

        try
        {
            // AppLovin SDK < 7.2.0 uses an Activity, as opposed to Context in >= 7.2.0
            final Class<?> contextClass = ( AppLovinSdk.VERSION_CODE < 720 ) ? Activity.class : Context.class;
            final Method method = AppLovinInterstitialAd.class.getMethod( "create", AppLovinSdk.class, contextClass );

            inter = (AppLovinInterstitialAdDialog) method.invoke( null, sdk, context );
        }
        catch ( Throwable th )
        {
            log( ERROR, "Unable to create AppLovinInterstitialAd." );
            listener.onAdFailedToLoad( AdRequest.ERROR_CODE_INTERNAL_ERROR );
        }

        return inter;
    }

    private static void log(final int priority, final String message)
    {
        if ( LOGGING_ENABLED )
        {
            Log.println( priority, "AppLovinInterstitial", message );
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

    /**
     * Performs the given runnable on the main thread.
     */
    public static void runOnUiThread(final Runnable runnable)
    {
        if ( Looper.myLooper() == Looper.getMainLooper() )
        {
            runnable.run();
        }
        else
        {
            UI_HANDLER.post( runnable );
        }
    }
}
