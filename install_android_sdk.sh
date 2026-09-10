#!/bin/bash
set -e
echo "Downloading Android Command Line Tools..."
wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmdline-tools.zip
echo "Extracting..."
unzip -q cmdline-tools.zip
mkdir -p ~/Android/Sdk/cmdline-tools/latest
mv cmdline-tools/bin ~/Android/Sdk/cmdline-tools/latest/
mv cmdline-tools/lib ~/Android/Sdk/cmdline-tools/latest/
mv cmdline-tools/source.properties ~/Android/Sdk/cmdline-tools/latest/
rm -rf cmdline-tools cmdline-tools.zip

echo "Accepting Licenses & Installing Platforms..."
yes | ~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager --licenses >/dev/null 2>&1 || true
~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager "build-tools;34.0.0" "platforms;android-34" "platform-tools" >/dev/null 2>&1

echo "Configuring Flutter..."
/home/love/shop/flutter/bin/flutter config --android-sdk ~/Android/Sdk
/home/love/shop/flutter/bin/flutter doctor
