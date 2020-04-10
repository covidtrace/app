# COVID Trace

## Local Setup

The app requires you to specify some local configuration values to be able to compile debug and release builds for Android and iOS.

### For iOS do the following:

Create `ios/Flutter/App.xcconfig` and add the following line

```
GOOGLE_MAPS_API_KEY={INSERT_GOOGLE_API_KEY_HERE}
```

### For Android do the following:

Modify `app/android/local.properties` and add the following lines

```
app.googleMapsApiKey={INSERT_GOOGLE_API_KEY_HERE}
app.locationManagerLicense={INSERT_BACKGROUND_LOCATION_LICENSE_KEY_HERE}
```

## Troubleshooting

- **Issue:** Flutter build fails for iOS after building and running via Xcode.

  **Fix:** `rm -rf ios/Flutter/App.framework`

* **Issue:** Flutter Android build get stuck trying to install debug .apk on to a device.

  **Fix:** `/Path/to/adb uninstall com.covidtrace.app` On MacOS the `adb` tool is typically located at `~/Library/Android/sdk/platform-tools/adb`

  Make sure that you can run `fluttter devices` successfully afterwards. If that hangs kill any running `adb` processes.
