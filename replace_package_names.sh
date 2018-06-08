#!/bin/bash
#
#  replace_package_names.sh
#
#  Created by Thomas So on 5/18/18.
#
#  This script is used to quickly replace the package name placeholders "YOUR_PACKAGE_NAME_HERE" with that of the current directly structure. Used for internal testing.
#

LC_ALL=C sed -i '' 's/package YOUR_PACKAGE_NAME/package AdMob.Android/g' AdMob/Android/*.java
LC_ALL=C sed -i '' 's/package com.applovin.mediation/package AdMob.Android/g' AdMob/Android/*.java
LC_ALL=C sed -i '' 's/package YOUR_PACKAGE_NAME/package MoPub.Android/g' MoPub/Android/*.java

exit 0