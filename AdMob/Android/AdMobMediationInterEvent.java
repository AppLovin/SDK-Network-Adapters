/**
 * Copyright (c) 2013 AppLovin.
 */
package YOUR_PACKAGE_NAME;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;
import android.util.Log;

import com.applovin.adview.AppLovinInterstitialAd;
import com.applovin.adview.AppLovinInterstitialAdDialog;
import com.applovin.sdk.AppLovinAd;
import com.applovin.sdk.AppLovinAdClickListener;
import com.applovin.sdk.AppLovinAdDisplayListener;
import com.applovin.sdk.AppLovinAdLoadListener;
import com.applovin.sdk.AppLovinAdSize;
import com.applovin.sdk.AppLovinErrorCodes;
import com.applovin.sdk.AppLovinSdk;
import com.google.android.gms.ads.AdRequest;
import com.google.android.gms.ads.mediation.MediationAdRequest;
import com.google.android.gms.ads.mediation.customevent.CustomEventInterstitial;
import com.google.android.gms.ads.mediation.customevent.CustomEventInterstitialListener;


/**
 * This class must be defined and referenced from AdMob's website for AdMob Mediation
 *
 * @author David Anderson
 * @since 4.2
 */
public class AdMobMediationInterEvent implements CustomEventInterstitial {
    private Context mContext;
    private AppLovinAd lastAd;
    private CustomEventInterstitialListener mListener;

    @Override
    public synchronized void onDestroy() {
        Log.i("admob", "admob on destroy called");
        lastAd = null;
        mListener = null;
        mContext = null;
    }


    @Override
    public void onPause() {
    }

    @Override
    public void onResume() {
    }

    private synchronized void notifySuccess() {
        if (null != mContext) {
            Activity activity = (Activity)mContext;
            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    synchronized (AdMobMediationInterEvent.this) {
                        if (null != mListener) {
                            mListener.onAdLoaded();
                        }
                    }
                }
            });
        }
    }

    private synchronized void notifyFailure(final int error) {
        if (null != mContext) {
            Activity activity = (Activity)mContext;

            activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    synchronized (AdMobMediationInterEvent.this) {
                        mListener.onAdFailedToLoad(error);
                    }
                }
            });
        }
    }

    /**
     * This method will be called by AdMob's Mediation through Custom Event mechanism.
     */
    @Override
    public void requestInterstitialAd(final Context context,
                                      final CustomEventInterstitialListener listener,
                                      String serverParameter,
                                      MediationAdRequest mediationAdRequest,
                                      Bundle customEventExtras) {

        Log.i("admob", "request interstitial called by admob");
        mListener = listener;
        mContext = context;
        if (!(mContext instanceof Activity)) {
            mListener.onAdFailedToLoad(AdRequest.ERROR_CODE_INVALID_REQUEST);
            Log.w("AppLovinSdk", "AppLovin cannot serve ads through AdMob. Please make sure to pass an Activity instance when instantiating com.google.android.gms.ads.InterstitialAd");
            return;
        }


        AppLovinSdk.getInstance(mContext).getAdService().loadNextAd(AppLovinAdSize.INTERSTITIAL, new AppLovinAdLoadListener() {
            @Override
            public void adReceived(AppLovinAd ad) {
                lastAd = ad;
                notifySuccess();

            }

            @Override
            public void failedToReceiveAd(int errorCode) {

                if (errorCode == 204)
                    notifyFailure(AdRequest.ERROR_CODE_NO_FILL);

                else if (errorCode == AppLovinErrorCodes.UNSPECIFIED_ERROR)
                    notifyFailure(AdRequest.ERROR_CODE_INTERNAL_ERROR);

                else if (errorCode == AppLovinErrorCodes.INVALID_URL)
                    notifyFailure( AdRequest.ERROR_CODE_INVALID_REQUEST);

                else if (errorCode < 0)
                    notifyFailure(AdRequest.ERROR_CODE_NETWORK_ERROR);

                else
                    notifyFailure(AdRequest.ERROR_CODE_INTERNAL_ERROR);

            }
        });
    }

    @Override
    public synchronized void showInterstitial() {
        if (lastAd == null) return;
        if (mListener == null) return;
        if (mContext == null) return;

        Log.i("admob", "showing interstitial through admob");
        AppLovinInterstitialAdDialog dialog = AppLovinInterstitialAd.create(AppLovinSdk.getInstance(mContext), (Activity) mContext);

        dialog.setAdDisplayListener(new AppLovinAdDisplayListener() {
            @Override
            public void adHidden(AppLovinAd ad) {
                synchronized (AdMobMediationInterEvent.this) {
                    if (null != mListener) {
                        mListener.onAdClosed();
                    }
                }
            }

            @Override
            public void adDisplayed(AppLovinAd ad) {
                synchronized (AdMobMediationInterEvent.this) {
                    if (null != mListener) {
                        mListener.onAdOpened();
                    }
                }
            }
        });

        dialog.setAdClickListener(new AppLovinAdClickListener() {
            @Override
            public void adClicked(AppLovinAd appLovinAd) {
                synchronized (AdMobMediationInterEvent.this) {
                    if (null != mListener) {
                        mListener.onAdLeftApplication();
                    }
                }
            }
        });

        dialog.showAndRender(lastAd);
    }

}