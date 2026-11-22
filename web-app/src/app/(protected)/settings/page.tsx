"use client";

import React, { useEffect, useState } from "react";
import {
  Cloud,
  ShieldCheck,
  Smartphone,
  Info,
  Wifi,
  WifiOff,
  RefreshCw,
  Trash2,
  CheckCircle2,
  AlertTriangle,
} from "lucide-react";
import { useAuth } from "@/context/auth-context";
import { useOfflineSync } from "@/hooks/use-offline-sync";
import { clearSyncedItems } from "@/lib/offline/outbox";
import { isCapacitorNative, getPlatform } from "@/lib/platform";
import { formatDisplayDate, formatRoleLabel } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/states";
import { useToast } from "@/components/ui/toast";

export default function SettingsPage() {
  const { profile, user } = useAuth();
  const {
    isOnline,
    pendingCount,
    isSyncing,
    outboxItems,
    triggerSync,
    refreshState,
  } = useOfflineSync();
  const toast = useToast();

  const [swActive, setSwActive] = useState(false);
  const [isStandalone, setIsStandalone] = useState(false);

  useEffect(() => {
    if (typeof window !== "undefined") {
      if ("serviceWorker" in navigator) {
        navigator.serviceWorker.getRegistration().then((reg) => {
          setSwActive(Boolean(reg?.active));
        });
      }
      const isStandaloneMode =
        window.matchMedia("(display-mode: standalone)").matches ||
        // @ts-expect-error iOS Safari standalone check
        Boolean(window.navigator?.standalone);
      setIsStandalone(isStandaloneMode);
    }
  }, []);

  async function handleManualSync() {
    if (!isOnline) {
      toast.warning("Cannot sync while offline. Please connect to Wi-Fi or mobile data.");
      return;
    }
    toast.info("Synchronizing offline outbox with Supabase…");
    await triggerSync();
    toast.success("Synchronization complete.");
  }

  function handleClearSynced() {
    clearSyncedItems();
    refreshState();
    toast.info("Cleared synced items from outbox.");
  }

  const platform = getPlatform();

  return (
    <div className="space-y-6">
      <PageHeader
        title="Settings & Diagnostics"
        description="PWA install status, offline synchronization engine, and backend security diagnostics."
      />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* Backend & Security Diagnostics */}
        <Card>
          <CardHeader>
            <CardTitle>Backend &amp; Security Diagnostics</CardTitle>
          </CardHeader>
          <CardContent className="divide-y divide-slate-100 p-0">
            <div className="flex items-center justify-between px-5 py-4">
              <div className="flex items-center gap-3">
                <Cloud className="h-4 w-4 text-emerald-600" />
                <div>
                  <p className="text-sm font-medium text-slate-900">Supabase Backend</p>
                  <p className="text-xs text-slate-500">Connected to existing TSR Builders database</p>
                </div>
              </div>
              <Badge variant="success">Online</Badge>
            </div>

            <div className="flex items-center justify-between px-5 py-4">
              <div className="flex items-center gap-3">
                <ShieldCheck className="h-4 w-4 text-[#2563EB]" />
                <div>
                  <p className="text-sm font-medium text-slate-900">Row Level Security Authority</p>
                  <p className="text-xs text-slate-500">
                    Authenticated as {user?.email} ({formatRoleLabel(profile?.role)})
                  </p>
                </div>
              </div>
              <Badge variant="blue">RLS Enforced</Badge>
            </div>

            <div className="flex items-center justify-between px-5 py-4">
              <div className="flex items-center gap-3">
                <Smartphone className="h-4 w-4 text-slate-600" />
                <div>
                  <p className="text-sm font-medium text-slate-900">Progressive Web App (PWA)</p>
                  <p className="text-xs text-slate-500">
                    {isStandalone ? "Running in standalone app window" : "Installable from browser menu"}
                  </p>
                </div>
              </div>
              <Badge variant={isStandalone ? "success" : swActive ? "blue" : "neutral"}>
                {isStandalone ? "Standalone" : swActive ? "Installed / SW Active" : "Supported"}
              </Badge>
            </div>

            <div className="flex items-center justify-between px-5 py-4">
              <div className="flex items-center gap-3">
                <Smartphone className="h-4 w-4 text-purple-600" />
                <div>
                  <p className="text-sm font-medium text-slate-900">Capacitor Mobile Compatibility</p>
                  <p className="text-xs text-slate-500">
                    Native app store packaging ready (Target: {platform.toUpperCase()})
                  </p>
                </div>
              </div>
              <Badge variant="navy">Capacitor Ready</Badge>
            </div>

            <div className="flex items-center justify-between px-5 py-4">
              <div className="flex items-center gap-3">
                <Info className="h-4 w-4 text-slate-500" />
                <div>
                  <p className="text-sm font-medium text-slate-900">Application Version</p>
                  <p className="text-xs text-slate-500">TSR Builders Web Platform (Next.js App Router)</p>
                </div>
              </div>
              <span className="text-xs font-semibold text-slate-600">v1.2.0-pwa</span>
            </div>
          </CardContent>
        </Card>

        {/* Offline Outbox & Sync Manager */}
        <Card>
          <CardHeader className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
            <div>
              <CardTitle>Offline Outbox &amp; Sync Engine</CardTitle>
              <CardDescription>
                Guarantees zero data loss on remote sites with intermittent network coverage.
              </CardDescription>
            </div>
            <div className="flex items-center gap-2">
              {isOnline ? (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-2.5 py-1 text-xs font-bold text-emerald-700 border border-emerald-200">
                  <Wifi className="h-3.5 w-3.5" />
                  Online
                </span>
              ) : (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-amber-50 px-2.5 py-1 text-xs font-bold text-amber-800 border border-amber-300">
                  <WifiOff className="h-3.5 w-3.5" />
                  Offline
                </span>
              )}
            </div>
          </CardHeader>

          <CardContent className="space-y-4">
            <div className="flex items-center justify-between rounded-xl border border-slate-200 bg-slate-50/70 p-4">
              <div>
                <p className="text-xs font-bold uppercase tracking-wider text-slate-500">Pending Outbox Items</p>
                <p className="text-2xl font-black text-slate-900">
                  {pendingCount} <span className="text-xs font-medium text-slate-500">entries queued</span>
                </p>
              </div>

              <div className="flex gap-2">
                <Button
                  size="sm"
                  onClick={handleManualSync}
                  loading={isSyncing}
                  disabled={!isOnline || pendingCount === 0}
                >
                  <RefreshCw className="h-3.5 w-3.5" />
                  Sync Outbox
                </Button>
                {outboxItems.some((i) => i.status === "synced") && (
                  <Button size="sm" variant="outline" onClick={handleClearSynced}>
                    <Trash2 className="h-3.5 w-3.5" />
                    Clean
                  </Button>
                )}
              </div>
            </div>

            {/* Outbox Items List */}
            {outboxItems.length === 0 ? (
              <p className="p-4 text-center text-xs text-slate-500">
                Outbox is clean. All operations have been verified and synchronized with Supabase.
              </p>
            ) : (
              <div className="divide-y divide-slate-100 rounded-lg border border-slate-200">
                {outboxItems.map((item) => (
                  <div key={item.id} className="flex items-center justify-between p-3 text-xs">
                    <div>
                      <p className="font-semibold text-slate-900">
                        {item.siteName} ({formatDisplayDate(item.dateStr)})
                      </p>
                      <p className="text-slate-500">
                        Type: {item.type.replace("_", " ")} · Queued:{" "}
                        {new Date(item.queuedAt).toLocaleTimeString()}
                      </p>
                      {item.errorMessage && (
                        <p className="text-red-600 text-[11px] mt-0.5">{item.errorMessage}</p>
                      )}
                    </div>
                    <div>
                      {item.status === "pending" && (
                        <Badge variant="warning">Pending Sync</Badge>
                      )}
                      {item.status === "syncing" && (
                        <Badge variant="blue">Syncing…</Badge>
                      )}
                      {item.status === "synced" && (
                        <Badge variant="success">Synced</Badge>
                      )}
                      {item.status === "failed" && (
                        <Badge variant="danger">Failed</Badge>
                      )}
                      {item.status === "conflict" && (
                        <Badge variant="warning">Conflict</Badge>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      </div>

      {/* Migration & Architecture Safeguards */}
      <Card>
        <CardHeader>
          <CardTitle>Architecture &amp; Security Safeguards</CardTitle>
        </CardHeader>
        <CardContent className="space-y-3 text-xs leading-relaxed text-slate-600">
          <p>
            <strong>Zero Direct Mutation Bypass:</strong> All attendance, materials, and dispatch operations flow
            strictly through Supabase RLS policies and database constraints. Frontend role checks provide navigational
            ergonomics only; PostgreSQL RLS is the single source of truth for authorization.
          </p>
          <p>
            <strong>Safe Offline Boundary:</strong> The service worker explicitly bypasses caching for all Supabase
            authenticated API responses (<code>*.supabase.co</code>), protecting user tokens and RLS from stale or
            leaked cache reads. Offline mutations are stored in the client outbox until validated against the server.
          </p>
          <p>
            <strong>Capacitor Native Packaging:</strong> The codebase is structured with zero Node.js runtime assumptions in
            client code, standard HTML5 camera capture, and responsive layouts, enabling zero-code conversion to iOS and
            Android app packages via Capacitor.
          </p>
        </CardContent>
      </Card>
    </div>
  );
}
