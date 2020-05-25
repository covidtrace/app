# COVID Trace

COVID Trace is a mobile app that use the Google/Apple Exposure Notification APIs to alert users to potential COVID-19 exposures.

Main features:

- Integrates with the reference [Google Exposure Notification Server](https://github.com/google/exposure-notifications-server)
- Has support for verifying positive COVID-19 diagnosis from authorized health authorities.
- Is easily customizable for the specific needs of local governments and health organizations.

<a href="https://www.figma.com/proto/dZ26JcuOaKsLCMzz3KEnKH/COVID-Trace-App?node-id=1%3A8&scaling=scale-down">![Screenshot of Mobile App](https://covidtrace.com/static/9d0931ab8ac1b315288d947d475bf49e/b19f8/preview.png)</a>

## Local Setup

The app is build on the Flutter framework for both iOS and Android. Follow the local development setup guide here:
https://flutter.dev/docs/get-started/install

The app relies on a combination of local and remote JSON configuration. Be sure to edit `assets/config.json` to specify your remote configuration URL. Here's the minimum remote configuration you must specify:

```json
{
  "exposurePublishUrl": "http://localhost:8080",
  "exposureKeysPublishedBucket": "covidtrace-exposure-keys-published"
}
```

In particular you should update `exposurePublishUrl` to point to your server for reporting expsoure keys. For local development, you can specify a path in the `/assets` directory to a configuration.

## Troubleshooting

- **Issue:** Flutter build fails for iOS after building and running via Xcode.

  **Fix:** `rm -rf ios/Flutter/App.framework`

* **Issue:** Flutter Android build get stuck trying to install debug .apk on to a device.

  **Fix:** `/Path/to/adb uninstall com.covidtrace.app` On MacOS the `adb` tool is typically located at `~/Library/Android/sdk/platform-tools/adb`

  Make sure that you can run `fluttter devices` successfully afterwards. If that hangs kill any running `adb` processes.
