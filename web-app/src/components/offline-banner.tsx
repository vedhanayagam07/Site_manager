"use client";

import React from "react";
import { WifiOff, RefreshCw } from "lucide-react";
import { useOfflineSync } from "@/hooks/use-offline-sync";

export function OfflineBanner() {
  const { isOnline, pendingCount, isSyncing, triggerSync } = useOfflineSync();

  if (isOnline && pendingCount === 0) {
    return null;
  }

  return (
    <div
      role="status"
      aria-live="polite"
      className={`border-b px-4 py-2 text-xs transition-colors backdrop-blur-md ${
        !isOnline
          ? "border-amber-500/30 bg-amber-500/10 text-amber-200"
          : "border-blue-500/30 bg-blue-500/10 text-blue-200"
      }`}
    >
      <div className="mx-auto flex max-w-7xl items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          {!isOnline ? (
            <WifiOff className="h-4 w-4 shrink-0 text-[#E5AD55]" />
          ) : (
            <RefreshCw
              className={`h-4 w-4 shrink-0 text-[#4B83F5] ${isSyncing ? "animate-spin" : ""}`}
            />
          )}
          <span>
            {!isOnline ? (
              <>
                <strong className="text-white">Working Offline:</strong> Network connection lost. Submissions will be stored in your local Outbox.
              </>
            ) : (
              <>
                <strong className="text-white">Online:</strong> {pendingCount} submission{pendingCount === 1 ? "" : "s"} pending synchronization.
              </>
            )}
          </span>
        </div>

        {pendingCount > 0 && isOnline && (
          <button
            type="button"
            onClick={triggerSync}
            disabled={isSyncing}
            className="inline-flex items-center gap-1.5 rounded-lg border border-blue-400/30 bg-[#4B83F5]/20 px-2.5 py-1 text-xs font-semibold text-white shadow-xs hover:bg-[#4B83F5]/30 disabled:opacity-50 cursor-pointer transition-colors"
          >
            <RefreshCw className={`h-3 w-3 ${isSyncing ? "animate-spin" : ""}`} />
            {isSyncing ? "Syncing…" : `Sync Outbox (${pendingCount})`}
          </button>
        )}
      </div>
    </div>
  );
}
