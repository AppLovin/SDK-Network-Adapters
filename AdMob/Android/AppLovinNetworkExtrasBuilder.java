package YOUR_PACKAGE_NAME;

import android.os.Bundle;

/**
 * Created by joshgleeson on 11/15/17.
 * <p>
 * Helper class to create the `Bundle` containing various parameters to be passed into the request object for AppLovin.
 */
public final class AppLovinNetworkExtrasBuilder
{
    private static final String KEY_ZONE_ID = "zone_id";

    /**
     * The AppLovin Zone ID to be used for the ad requests.
     */
    private String zoneId;

    public AppLovinNetworkExtrasBuilder setZoneId(final String zoneId)
    {
        this.zoneId = zoneId;
        return this;
    }

    public Bundle build()
    {
        final Bundle bundle = new Bundle();
        bundle.putString( KEY_ZONE_ID, zoneId );

        return bundle;
    }
}
