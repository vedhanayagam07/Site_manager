"use client";

import React, { useEffect, useState } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  LayoutDashboard,
  Building2,
  Users,
  ClipboardCheck,
  Camera,
  Package,
  FileText,
  BarChart3,
  ShieldCheck,
  Settings,
  UserCircle,
  LogOut,
  Menu,
  X,
  MapPin,
  ChevronDown,
  Activity,
  Download,
  WifiOff,
  RefreshCw,
  Sparkles,
} from "lucide-react";
import { useAuth } from "@/context/auth-context";
import { useOfflineSync } from "@/hooks/use-offline-sync";
import { cn, formatRoleLabel } from "@/lib/utils";
import { DisabledAccountGate } from "@/components/layout/disabled-account-gate";
import { OfflineBanner } from "@/components/offline-banner";

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
}

interface NavItem {
  label: string;
  href: string;
  icon: React.ComponentType<{ className?: string }>;
  adminOnly?: boolean;
  pmOrAdminOnly?: boolean;
}

const PRIMARY_NAV: NavItem[] = [
  { label: "Dashboard", href: "/dashboard", icon: LayoutDashboard },
  { label: "Glassy Hub", href: "/glassy", icon: Sparkles },
  { label: "Sites", href: "/sites", icon: Building2 },
  { label: "Workers", href: "/workers", icon: Users },
  { label: "Attendance", href: "/attendance", icon: ClipboardCheck },
  { label: "Site Progress", href: "/progress", icon: Camera },
  { label: "Materials", href: "/materials", icon: Package },
  { label: "Loading Memos", href: "/loading-memos", icon: FileText },
  { label: "Reports", href: "/reports", icon: BarChart3 },
  { label: "Activity Log", href: "/activity", icon: Activity, pmOrAdminOnly: true },
  { label: "Admin Panel", href: "/admin", icon: ShieldCheck, adminOnly: true },
];

const SECONDARY_NAV: NavItem[] = [
  { label: "Profile", href: "/profile", icon: UserCircle },
  { label: "Settings", href: "/settings", icon: Settings },
];

const MOBILE_TABS = [
  { label: "Home", href: "/dashboard", icon: LayoutDashboard },
  { label: "Sites", href: "/sites", icon: Building2 },
  { label: "Progress", href: "/progress", icon: Camera },
  { label: "Attend.", href: "/attendance", icon: ClipboardCheck },
  { label: "Stock", href: "/materials", icon: Package },
];

export function AppShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const {
    user,
    profile,
    isLoading,
    isDisabled,
    isAdmin,
    isPmOrAdmin,
    sites,
    selectedSiteId,
    setSelectedSiteId,
    signOut,
  } = useAuth();
  const { isOnline, pendingCount } = useOfflineSync();
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [installPrompt, setInstallPrompt] =
    useState<BeforeInstallPromptEvent | null>(null);

  useEffect(() => {
    const handler = (e: Event) => {
      e.preventDefault();
      setInstallPrompt(e as BeforeInstallPromptEvent);
    };
    window.addEventListener("beforeinstallprompt", handler);
    return () => window.removeEventListener("beforeinstallprompt", handler);
  }, []);

  async function handleInstallPwa() {
    if (!installPrompt) return;
    await installPrompt.prompt();
    const choice = await installPrompt.userChoice;
    if (choice.outcome === "accepted") {
      setInstallPrompt(null);
    }
  }

  if (isLoading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-[#101318]">
        <div className="flex flex-col items-center gap-3">
          <div className="h-9 w-9 animate-spin rounded-full border-2 border-white/10 border-t-[#4B83F5]" />
          <p className="text-xs font-medium text-[#A7B0BE]">
            Loading TSR Builders workspace…
          </p>
        </div>
      </div>
    );
  }

  if (isDisabled) {
    return <DisabledAccountGate reason="disabled" />;
  }

  if (user && !profile) {
    return <DisabledAccountGate reason="unprovisioned" />;
  }

  const visibleNav = PRIMARY_NAV.filter(
    (item) =>
      (!item.adminOnly || isAdmin) && (!item.pmOrAdminOnly || isPmOrAdmin)
  );
  const displayName =
    profile?.name?.trim() ||
    user?.email?.split("@")[0] ||
    "Staff Member";
  const roleLabel = formatRoleLabel(profile?.role);
  const initials = displayName
    .split(" ")
    .map((p) => p[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();

  const renderSidebarContent = (onNavigate?: () => void) => (
    <div className="flex h-full flex-col bg-[rgba(23,28,36,0.95)] backdrop-blur-2xl border-r border-[rgba(190,205,225,0.15)] text-[#A7B0BE]">
      {/* Brand header — natural transparent logo artwork without colored containers */}
      <div className="flex h-16 items-center gap-3 border-b border-[rgba(190,205,225,0.12)] px-5">
        <div className="flex h-10 w-10 shrink-0 items-center justify-center">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/tsrbuilders-transparent.png"
            alt="TSR Builders"
            className="h-full w-full object-contain filter drop-shadow-[0_2px_8px_rgba(234,179,8,0.25)]"
          />
        </div>
        <div className="min-w-0">
          <div className="truncate text-sm font-bold tracking-wider text-[#F2F4F8]">
            TSR BUILDERS
          </div>
          <div className="truncate text-[11px] text-[#778292]">
            Construction Operations
          </div>
        </div>
      </div>

      {/* Primary navigation */}
      <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4" aria-label="Primary navigation">
        <div className="px-2.5 pb-1.5 text-[10px] font-semibold uppercase tracking-wider text-[#778292]">
          Operations
        </div>
        {visibleNav.map((item) => {
          const active =
            pathname === item.href || pathname.startsWith(`${item.href}/`);
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              onClick={onNavigate}
              className={cn(
                "flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-all duration-150",
                active
                  ? "bg-gradient-to-r from-[#4B83F5]/25 via-[#4B83F5]/12 to-transparent text-white border-l-2 border-[#4B83F5] shadow-[0_0_16px_rgba(75,131,245,0.20)]"
                  : "text-[#A7B0BE] hover:bg-white/5 hover:text-[#F2F4F8]"
              )}
            >
              <Icon className={cn("h-4 w-4 shrink-0", active ? "text-[#4B83F5]" : "text-[#778292]")} />
              <span className="truncate">{item.label}</span>
            </Link>
          );
        })}

        <div className="px-2.5 pt-5 pb-1.5 text-[10px] font-semibold uppercase tracking-wider text-[#778292]">
          Account
        </div>
        {SECONDARY_NAV.map((item) => {
          const active = pathname === item.href;
          const Icon = item.icon;
          return (
            <Link
              key={item.href}
              href={item.href}
              onClick={onNavigate}
              className={cn(
                "flex items-center gap-3 rounded-xl px-3 py-2 text-sm font-medium transition-all duration-150",
                active
                  ? "bg-gradient-to-r from-[#4B83F5]/25 via-[#4B83F5]/12 to-transparent text-white border-l-2 border-[#4B83F5]"
                  : "text-[#A7B0BE] hover:bg-white/5 hover:text-[#F2F4F8]"
              )}
            >
              <Icon className={cn("h-4 w-4 shrink-0", active ? "text-[#4B83F5]" : "text-[#778292]")} />
              <span className="truncate">{item.label}</span>
            </Link>
          );
        })}
      </nav>

      {/* User footer — refined glass surface */}
      <div className="border-t border-[rgba(190,205,225,0.12)] p-3">
        <div className="flex items-center gap-3 rounded-xl border border-[rgba(190,205,225,0.15)] bg-[rgba(35,42,53,0.55)] px-3 py-2.5 backdrop-blur-md shadow-xs">
          <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-gradient-to-br from-[#4B83F5] to-blue-700 text-xs font-bold text-white shadow-xs">
            {initials}
          </div>
          <div className="min-w-0 flex-1">
            <div className="truncate text-xs font-semibold text-[#F2F4F8]">
              {displayName}
            </div>
            <div className="truncate text-[11px] text-[#A7B0BE]">
              {roleLabel}
            </div>
          </div>
          <button
            type="button"
            onClick={signOut}
            title="Sign Out"
            aria-label="Sign Out"
            className="rounded-lg p-1.5 text-[#778292] transition-colors hover:bg-white/10 hover:text-white cursor-pointer"
          >
            <LogOut className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );

  return (
    <div className="flex min-h-screen bg-[#101318] text-[#F2F4F8]">
      {/* Desktop Persistent Sidebar */}
      <aside className="hidden w-64 shrink-0 lg:fixed lg:inset-y-0 lg:left-0 lg:z-30 lg:block">
        {renderSidebarContent()}
      </aside>

      {/* Mobile Drawer Overlay */}
      {drawerOpen && (
        <div
          className="fixed inset-0 z-50 flex lg:hidden"
          role="dialog"
          aria-modal="true"
        >
          <div
            className="fixed inset-0 bg-black/75 backdrop-blur-sm"
            onClick={() => setDrawerOpen(false)}
          />
          <div className="relative z-10 flex w-72 max-w-[82vw] flex-col">
            <button
              type="button"
              onClick={() => setDrawerOpen(false)}
              aria-label="Close navigation menu"
              className="absolute top-3.5 right-3 z-20 rounded-lg p-1.5 text-[#A7B0BE] hover:bg-white/10 hover:text-white cursor-pointer"
            >
              <X className="h-5 w-5" />
            </button>
            {renderSidebarContent(() => setDrawerOpen(false))}
          </div>
        </div>
      )}

      {/* Main Content Area */}
      <div className="flex min-w-0 flex-1 flex-col lg:pl-64">
        {/* Floating/Integrated Top Glass Bar */}
        <header className="sticky top-0 z-20 flex h-16 items-center justify-between gap-3 border-b border-[rgba(190,205,225,0.15)] bg-[rgba(23,28,36,0.80)] px-4 backdrop-blur-xl sm:px-6 shadow-sm">
          <div className="flex min-w-0 items-center gap-3">
            <button
              type="button"
              onClick={() => setDrawerOpen(true)}
              aria-label="Open navigation menu"
              className="rounded-xl p-2 text-[#A7B0BE] hover:bg-white/5 hover:text-white lg:hidden cursor-pointer"
            >
              <Menu className="h-5 w-5" />
            </button>

            {/* Quick Site Switcher — Inset Dark Glass Surface */}
            <div className="relative flex items-center">
              <MapPin className="pointer-events-none absolute left-2.5 h-3.5 w-3.5 text-[#778292]" />
              <select
                aria-label="Active site filter"
                value={selectedSiteId}
                onChange={(e) => setSelectedSiteId(e.target.value)}
                className="h-9 max-w-[190px] appearance-none rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 pr-8 pl-8 text-xs font-medium text-[#F2F4F8] transition-colors hover:border-[rgba(190,205,225,0.30)] focus:border-[#4B83F5] focus:outline-none focus:ring-2 focus:ring-[#4B83F5]/25 sm:max-w-[260px]"
              >
                <option value="" className="bg-[#171C24] text-white">All Sites ({sites.length})</option>
                {sites.map((site) => (
                  <option key={site.id} value={site.id} className="bg-[#171C24] text-white">
                    {site.name}
                  </option>
                ))}
              </select>
              <ChevronDown className="pointer-events-none absolute right-2.5 h-3.5 w-3.5 text-[#778292]" />
            </div>
          </div>

          <div className="flex items-center gap-2.5">
            {!isOnline && (
              <span className="flex items-center gap-1.5 rounded-full border border-amber-500/30 bg-amber-500/15 px-2.5 py-0.5 text-[10px] font-bold text-[#E5AD55]">
                <WifiOff className="h-3 w-3" />
                Offline
              </span>
            )}
            {pendingCount > 0 && isOnline && (
              <span className="flex items-center gap-1.5 rounded-full border border-blue-500/30 bg-blue-500/15 px-2.5 py-0.5 text-[10px] font-bold text-[#4B83F5]">
                <RefreshCw className="h-3 w-3 animate-spin text-[#4B83F5]" />
                {pendingCount} Outbox
              </span>
            )}
            {installPrompt && (
              <button
                type="button"
                onClick={handleInstallPwa}
                className="inline-flex items-center gap-1.5 rounded-xl border border-blue-400/30 bg-[#4B83F5]/20 px-2.5 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-[#4B83F5]/30 cursor-pointer"
              >
                <Download className="h-3.5 w-3.5" />
                <span className="hidden sm:inline">Install App</span>
              </button>
            )}
            <span className="hidden rounded-lg border border-blue-500/30 bg-blue-500/15 px-2.5 py-1 text-xs font-medium text-[#4B83F5] sm:inline-flex">
              {roleLabel}
            </span>
            <Link
              href="/profile"
              className="flex items-center gap-2 rounded-xl border border-[rgba(190,205,225,0.18)] bg-[rgba(35,42,53,0.60)] backdrop-blur-md px-2.5 py-1.5 text-xs font-medium text-[#F2F4F8] transition-colors hover:bg-[rgba(45,53,65,0.8)] shadow-xs"
            >
              <span className="flex h-6 w-6 items-center justify-center rounded-lg bg-gradient-to-br from-[#4B83F5] to-blue-700 text-[10px] font-bold text-white shadow-xs">
                {initials}
              </span>
              <span className="hidden max-w-[120px] truncate md:inline">
                {displayName}
              </span>
            </Link>
          </div>
        </header>

        {/* Global Offline Status & Sync Banner */}
        <OfflineBanner />

        {/* Page Content */}
        <main className="mx-auto w-full max-w-7xl flex-1 px-4 pt-6 pb-28 sm:px-6 lg:pb-10">
          {children}
        </main>
      </div>

      {/* Mobile Compact Bottom Tab Bar with Safe Area Support */}
      <nav
        aria-label="Mobile quick navigation"
        className="fixed inset-x-0 bottom-0 z-30 flex items-center justify-around border-t border-[rgba(190,205,225,0.15)] bg-[rgba(23,28,36,0.92)] backdrop-blur-2xl px-1 pt-1.5 pb-[calc(env(safe-area-inset-bottom)+0.375rem)] shadow-[0_-4px_24px_rgba(0,0,0,0.50)] lg:hidden"
      >
        {MOBILE_TABS.map((tab) => {
          const active =
            pathname === tab.href || pathname.startsWith(`${tab.href}/`);
          const Icon = tab.icon;
          const showPendingBadge = tab.href === "/attendance" && pendingCount > 0;

          return (
            <Link
              key={tab.href}
              href={tab.href}
              className={cn(
                "relative flex min-w-0 flex-1 flex-col items-center justify-center gap-0.5 rounded-lg py-1 text-[10px] font-medium transition-colors",
                active ? "text-[#4B83F5] drop-shadow-[0_0_8px_rgba(75,131,245,0.35)]" : "text-[#778292] hover:text-[#A7B0BE]"
              )}
            >
              <div className="relative">
                <Icon className="h-5 w-5" />
                {showPendingBadge && (
                  <span className="absolute -top-1 -right-1.5 flex h-3.5 w-3.5 items-center justify-center rounded-full bg-amber-500 text-[9px] font-black text-white">
                    {pendingCount > 9 ? "9+" : pendingCount}
                  </span>
                )}
              </div>
              <span className="truncate">{tab.label}</span>
            </Link>
          );
        })}
      </nav>
    </div>
  );
}
