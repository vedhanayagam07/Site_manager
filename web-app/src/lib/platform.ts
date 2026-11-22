// ==============================================================================
// TSR BUILDERS — PLATFORM & CAPACITOR COMPATIBILITY ABSTRACTION
// File: src/lib/platform.ts
// ==============================================================================
// Designed to keep business logic and UI 100% compatible with both modern web
// browsers (PWA) and future Capacitor native wrappers (iOS & Android) without
// code fragmentation or browser-only assumptions.
// ==============================================================================

export type PlatformType = "web" | "ios" | "android";

interface CapacitorWindow extends Window {
  Capacitor?: {
    isNativePlatform: () => boolean;
    getPlatform: () => string;
    Plugins?: Record<string, unknown>;
  };
}

export function isCapacitorNative(): boolean {
  if (typeof window === "undefined") return false;
  const win = window as CapacitorWindow;
  return win.Capacitor?.isNativePlatform?.() ?? false;
}

export function getPlatform(): PlatformType {
  if (typeof window === "undefined") return "web";
  const win = window as CapacitorWindow;
  if (win.Capacitor?.isNativePlatform?.()) {
    const platform = win.Capacitor.getPlatform?.();
    if (platform === "ios") return "ios";
    if (platform === "android") return "android";
  }

  // User-agent fallback for mobile browser detection
  const ua = navigator.userAgent || "";
  if (/iPad|iPhone|iPod/.test(ua)) return "ios";
  if (/Android/.test(ua)) return "android";
  return "web";
}

export function isMobileDevice(): boolean {
  if (typeof window === "undefined") return false;
  return /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(
    navigator.userAgent
  );
}

/**
 * Triggers light haptic feedback when running inside Capacitor or supported mobile browsers.
 */
export function triggerHapticFeedback(): void {
  if (typeof window === "undefined") return;
  // Standard Web Vibration API (Android Chrome & PWA)
  if ("vibrate" in navigator && typeof navigator.vibrate === "function") {
    try {
      navigator.vibrate(12);
    } catch {
      // Ignore vibration error on unsupported platforms
    }
  }
}

