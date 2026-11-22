# TSR Builders — Future Native Mobile App Packaging Guide (Capacitor)

This guide documents how the TSR Builders Next.js web application is packaged into native **Android** (`.apk` / `.aab`) and **iOS** (`.ipa`) applications using **Capacitor**, without rewriting any business logic or rebuilding a Flutter application.

---

## 1. Architectural Compatibility Guarantees

The TSR Builders web codebase has been authored to adhere strictly to Capacitor requirements:
1. **Zero Browser-Only Assumptions in Core Services:**
   - No direct usage of Node.js `fs`, `path`, or server-only modules in client components.
   - Platform detection and haptics abstracted via [`src/lib/platform.ts`](file:///D:/TSRAPP/site_manager_pro/web-app/src/lib/platform.ts).
2. **Native Camera & File Handling:**
   - Native HTML5 `<input capture="environment" />` in [`src/components/camera-capture.tsx`](file:///D:/TSRAPP/site_manager_pro/web-app/src/components/camera-capture.tsx) works seamlessly in Android WebView and iOS WKWebView, automatically invoking the system camera.
3. **Safe Offline Outbox:**
   - [`src/lib/offline/outbox.ts`](file:///D:/TSRAPP/site_manager_pro/web-app/src/lib/offline/outbox.ts) operates with local storage queues and automatic reconnection sync across both native apps and web browsers.
4. **Mobile Navigation & Safe-Area Insets:**
   - [`src/components/layout/app-shell.tsx`](file:///D:/TSRAPP/site_manager_pro/web-app/src/components/layout/app-shell.tsx) incorporates `env(safe-area-inset-bottom)` and `env(safe-area-inset-top)` for iPhone Dynamic Island and Android navigation bars.

---

## 2. Step-by-Step Native Packaging (When Ready)

When you are ready to produce app store packages for Google Play and the Apple App Store, execute the following commands in `web-app`:

### Step A: Install Capacitor Core & CLI
```bash
npm install @capacitor/core
npm install -D @capacitor/cli @capacitor/android @capacitor/ios
```

### Step B: Initialize Capacitor Configuration
```bash
npx cap init "TSR Builders" "com.tsrbuilders.sitemanager" --web-dir out
```
Create `capacitor.config.ts`:
```typescript
import { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.tsrbuilders.sitemanager',
  appName: 'TSR Builders',
  webDir: 'out',
  server: {
    androidScheme: 'https',
    // During local development, you can point directly to your dev server:
    // url: 'http://192.168.1.100:3000',
    // cleartext: true
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 1500,
      backgroundColor: '#0B1628',
      showSpinner: false,
    },
  },
};

export default config;
```

### Step C: Add Native Platforms
```bash
npx cap add android
npx cap add ios
```

### Step D: Build & Sync
```bash
# 1. Export the Next.js static build
npm run build

# 2. Sync web assets into the Android & iOS projects
npx cap sync
```

### Step E: Open in Android Studio / Xcode
```bash
# To build APK / AAB for Android:
npx cap open android

# To build IPA for iOS (on macOS):
npx cap open ios
```

---

## 3. Recommended Capacitor Plugins (Optional Enhancements)

When native device features are desired:
- `@capacitor/camera`: For advanced native camera overlay.
- `@capacitor/haptics`: For haptic feedback on attendance buttons.
- `@capacitor/status-bar`: For dark status bar styling matching `#0B1628`.
- `@capacitor/network`: For low-level native cellular/Wi-Fi connection state.

All of these can be dropped in without changing the core Supabase authentication or Next.js App Router design.

