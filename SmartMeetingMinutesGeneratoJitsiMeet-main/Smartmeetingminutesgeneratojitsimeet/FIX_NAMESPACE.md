# Fix for jitsi_meet_flutter_sdk Compatibility Issues

The `jitsi_meet_flutter_sdk` package (version 0.1.9) has compatibility issues with newer Android Gradle Plugin versions. Two fixes are required:

1. Missing namespace declaration in `build.gradle`
2. Package attribute in `AndroidManifest.xml` (no longer supported)

## Automated Fix

Run this PowerShell script to apply both fixes:

```powershell
# Fix 1: Add namespace to build.gradle
$buildGradlePath = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\jitsi_meet_flutter_sdk-0.1.9\android\build.gradle"
if (Test-Path $buildGradlePath) {
    $content = Get-Content $buildGradlePath -Raw
    if ($content -notmatch "namespace\s*=") {
        $content = $content -replace "(android\s*\{)", "`$1`n    namespace = `"org.jitsi.jitsi_meet_flutter_sdk`""
        Set-Content -Path $buildGradlePath -Value $content -NoNewline
        Write-Host "Fixed namespace in build.gradle"
    }
}

# Fix 2: Remove package attribute from AndroidManifest.xml
$manifestPath = "$env:LOCALAPPDATA\Pub\Cache\hosted\pub.dev\jitsi_meet_flutter_sdk-0.1.9\android\src\main\AndroidManifest.xml"
if (Test-Path $manifestPath) {
    $content = Get-Content $manifestPath -Raw
    $content = $content -replace 'package="[^"]*"', ''
    Set-Content -Path $manifestPath -Value $content -NoNewline
    Write-Host "Removed package attribute from AndroidManifest.xml"
}
```

## Manual Fix

### Fix 1: Add namespace to build.gradle

1. Navigate to: `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\jitsi_meet_flutter_sdk-0.1.9\android\build.gradle`

2. Find the `android {` block and add `namespace = "org.jitsi.jitsi_meet_flutter_sdk"` right after it:

```gradle
android {
    namespace = "org.jitsi.jitsi_meet_flutter_sdk"
    // ... rest of the configuration
}
```

### Fix 2: Remove package from AndroidManifest.xml

1. Navigate to: `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\jitsi_meet_flutter_sdk-0.1.9\android\src\main\AndroidManifest.xml`

2. Remove the `package` attribute from the `<manifest>` tag:

Change from:
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
  package="org.jitsi.jitsi_meet_flutter_sdk">
```

To:
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
```

3. Save the file and run `flutter clean` then `flutter pub get`

## Note

These fixes need to be reapplied if you delete your pub cache or update the package. Consider forking the package and applying the fixes permanently if this becomes problematic.

