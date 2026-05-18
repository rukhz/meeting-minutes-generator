# Release build

## Command

```bash
flutter build apk --release
```

Output APK: `build/app/outputs/flutter-apk/app-release.apk`

---

## If build fails: "Could not resolve..." / "No route to host" / "No such host is known"

The failure is **network-related**: Gradle cannot download dependencies from Maven Central or plugins.gradle.org.

### What to do

1. **Check your network**
   - Try a different Wi‑Fi or mobile hotspot.
   - Temporarily disable VPN if you use one.
   - Make sure you can open https://repo.maven.apache.org and https://plugins.gradle.org in a browser.

2. **DNS**
   - If "No such host is known" appears, try changing DNS (e.g. 8.8.8.8 / 8.8.4.4) in your network adapter.

3. **Corporate proxy**
   - If you're behind a proxy, create or edit `android/gradle.properties` and add (replace with your proxy host/port/user/pass):
   ```properties
   systemProp.http.proxyHost=your.proxy.host
   systemProp.http.proxyPort=8080
   systemProp.https.proxyHost=your.proxy.host
   systemProp.https.proxyPort=8080
   # If proxy needs auth:
   systemProp.http.proxyUser=user
   systemProp.http.proxyPassword=pass
   systemProp.https.proxyUser=user
   systemProp.https.proxyPassword=pass
   ```

4. **Build once on a working network, then offline**
   - On a network where the build succeeds, run: `flutter build apk --release`
   - Then you can reuse the Gradle cache and build offline:
   ```bash
   cd android
   ./gradlew assembleRelease --offline
   ```
   (Or run `flutter build apk --release` again; if dependencies are cached, it may work without internet.)

5. **Firewall / antivirus**
   - Allow your IDE and `gradle` / `java` processes to access the internet, or temporarily disable to test.

After fixing network/proxy/DNS, run `flutter clean` then `flutter build apk --release` again.
