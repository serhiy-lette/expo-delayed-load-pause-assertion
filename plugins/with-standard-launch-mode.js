// Test setup only: lets `adb shell am start --activity-multiple-task` open a second MainActivity on
// demand. The crash itself does not depend on the launch mode, only on two instances being alive
// while expo-updates is still deciding which update to launch.
const { withAndroidManifest, AndroidConfig } = require('expo/config-plugins');

module.exports = (config) =>
  withAndroidManifest(config, (config) => {
    const mainActivity = AndroidConfig.Manifest.getMainActivityOrThrow(config.modResults);
    mainActivity.$['android:launchMode'] = 'standard';
    return config;
  });
