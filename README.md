# Delayed app load: "Pausing an activity that is not the current activity"

Minimal reproduction for an Android crash in Expo's delayed app load (`expo` + `expo-updates`, SDK 58, New Architecture). The trace, deobfuscated:

```
java.lang.AssertionError: Pausing an activity that is not the current activity, this is incorrect! Current activity: MainActivity Paused activity: MainActivity
    at com.facebook.infer.annotation.Assertions.assertCondition
    at com.facebook.react.runtime.ReactHostImpl.onHostPause
    at com.facebook.react.ReactDelegate.onHostPause
    at com.facebook.react.ReactActivityDelegate.onPause
    at expo.modules.ReactActivityDelegateWrapper$onPause$1.invokeSuspend
    ...
    at expo.modules.ReactActivityDelegateWrapper.onPause
    at com.facebook.react.ReactActivity.onPause
    at android.app.Activity.performPause
```

## What is in here

The app is `create-expo-app --template blank-typescript` plus `expo-updates`. No app code was changed. The whole setup is in `app.json`:

- `updates.url` points at `https://10.0.2.2:8765`, which is `hang-server.js` on the host as seen from the Android emulator. It accepts the connection and never answers, so the update check on launch takes the full `fallbackToCacheTimeout` (6 seconds). This stands in for a slow network.
- `plugins/with-standard-launch-mode.js` sets `android:launchMode="standard"` on `MainActivity`, only so that `adb` can open a second instance on demand.

## Run it

Needs Node, the Android SDK and a running Android emulator (the update URL only works from an emulator).

```
npm install
npx expo prebuild -p android
cd android && ./gradlew :app:assembleRelease && cd ..
adb install -r android/app/build/outputs/apk/release/app-release.apk

node hang-server.js      # keep it running in another terminal
./repro.sh               # 8 runs, about 20 seconds each
```

Each run of `repro.sh` does this:

1. `am force-stop`, then `am start` the app. Its delayed load now waits for the update check.
2. 1.5 seconds later, `am start --activity-multiple-task` opens a second `MainActivity` while the first one is still waiting.
3. Waits for the app to load, prints the `ReactHost` lifecycle calls from logcat, presses Home.
4. Reports whether logcat has the `AssertionError`.

## Result

Android 16 emulator (API 36), `expo` 58.0.26, `expo-updates` 58.0.22, `react-native` 0.88.1:

```
run 1: ReactHost calls before Home: [ Resume Resume Pause ] -> CRASH
run 2: ReactHost calls before Home: [ Resume Resume Pause ] -> CRASH
run 3: ReactHost calls before Home: [ Resume Pause Resume ] -> ok
run 4: ReactHost calls before Home: [ Resume Pause Resume ] -> ok
run 5: ReactHost calls before Home: [ Resume Pause Resume ] -> ok
run 6: ReactHost calls before Home: [ Resume Pause Resume ] -> ok
run 7: ReactHost calls before Home: [ Resume Resume Pause ] -> CRASH
run 8: ReactHost calls before Home: [ Resume Resume Pause ] -> CRASH
4 of 8 runs crashed
```

The runs that crash are the ones where the host sees `Resume Resume Pause`.

## Why

`ReactActivityDelegateWrapper` queues each activity's `onResume` and `onPause` until that activity's delayed load is ready, then replays them. The queue is per activity, but the `ReactHost` is shared.

With two instances alive during the wait, both `whenReady` runnables are posted to the main thread from two IO coroutines, in either order:

| Order of replay | `ReactHost` calls | State afterwards |
| --- | --- | --- |
| older instance first | `onHostResume(older)`, `onHostPause(older)`, `onHostResume(newer)` | host resumed, holds the newer activity: fine |
| older instance last | `onHostResume(newer)`, `onHostResume(older)`, `onHostPause(older)` | host paused, holds the older, already stopped activity |

In the second case the next real pause of the newer activity (Home) reaches `ReactHostImpl.onHostPause` with an activity that is not the host's current one, and React Native's assertion throws.

`ReactActivityDelegateWrapper.onPause` does wrap that call for the delayed load case:

```kotlin
try {
  delegate.onPause()
} catch (e: Exception) {
  Log.e(TAG, "Exception occurred during onPause with delayed app loading", e)
}
```

but the assertion throws `java.lang.AssertionError`, which is an `Error`, not an `Exception`, so it passes the `catch` and the process dies.
