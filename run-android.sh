#!/bin/bash
# Convenience script to run Android app with proper environment

export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$PATH:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools

# Kill any existing metro bundler
lsof -ti:8081 | xargs kill -9 2>/dev/null || true

# Run the app
npx expo run:android
