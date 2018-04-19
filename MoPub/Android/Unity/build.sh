#!/bin/bash
#
#  build.sh
#
#  Created by Thomas So on 11/22/17.
#
#  This script is used to build the underlying JAR, for publishers using Unity.
#
#  It takes in 4 arguments -
#    1. The path to the Android SDK JAR.
#    2. The path to the Android Annotations JAR.
#    3. The path to the AppLovin SDK JAR.
#    4. The path to the MoPub base SDK JAR.
#    5. The path to the MoPub banner SDK JAR.
#    6. The path to the MoPub interstitial SDK JAR.
#    7. The path to the MoPub rewarded SDK JAR.
#    8. The path to the MoPub native ads SDK JAR.
#
#  Example Usage: ./build.sh {ANDROID_SDK_JAR} {ANDROID_ANNOTATIONS_JAR} {APPLOVIN_SDK_JAR} {MOPUB_BASE_SDK_JAR} {MOPUB_BANNER_SDK_JAR} {MOPUB_INTERSTITIAL_SDK_JAR} {MOPUB_REWARDED_SDK_JAR} {MOPUB_NATIVE_ADS_SDK_JAR}
#

# Input parameters check
if [ "$#" -lt 8 ]; then
    echo "Invalid number of parameters"
    exit 1
fi

# Assign parameters
ANDROID_SDK_JAR=$1
ANDROID_SUPPORT_ANNOTATIONS_JAR=$2
APPLOVIN_SDK_JAR=$3
MOPUB_SDK_JAR_BASE=$4
MOPUB_SDK_JAR_BANNER=$5
MOPUB_SDK_JAR_INTER=$6
MOPUB_SDK_JAR_REWARD=$7
MOPUB_SDK_JAR_NATIVE=$8

# Setup build folder
if [ ! -d "build" ]; then
    mkdir build
else
    rm -R build/*
fi

# Replace placeholder package name
LC_ALL=C sed -i '' 's/YOUR_PACKAGE_NAME/com.applovin.mediation.mopub/g' ../*.java

# Compile source files into build folder
javac -classpath \
    "${ANDROID_SDK_JAR}:${ANDROID_SUPPORT_ANNOTATIONS_JAR}:${APPLOVIN_SDK_JAR}:${MOPUB_SDK_JAR_BASE}:${MOPUB_SDK_JAR_BANNER}:${MOPUB_SDK_JAR_INTER}:${MOPUB_SDK_JAR_REWARD}:${MOPUB_SDK_JAR_NATIVE}" \
    -source 1.7 \
    -target 1.7 \
    -d build \
    ../*.java

# Package compiled files into JAR
cd build
jar cvf ../applovin-mopub-adapters.jar *
