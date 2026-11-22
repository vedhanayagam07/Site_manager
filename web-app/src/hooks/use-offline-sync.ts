"use client";

import { useCallback, useEffect, useState } from "react";
import {
  getOfflineOutbox,
  getPendingOutboxCount,
  syncOfflineOutbox,
} from "@/lib/offline/outbox";
import type { OfflineOutboxItem, SyncOutcome } from "@/lib/offline/types";

export function useOfflineSync() {
  const [isOnline, setIsOnline] = useState<boolean>(() => {
    return typeof navigator !== "undefined" ? navigator.onLine : true;
  });
  const [pendingCount, setPendingCount] = useState<number>(0);
  const [isSyncing, setIsSyncing] = useState<boolean>(false);
  const [outboxItems, setOutboxItems] = useState<OfflineOutboxItem[]>([]);
  const [lastSyncResult, setLastSyncResult] = useState<SyncOutcome | null>(null);

  const refreshState = useCallback(() => {
    setPendingCount(getPendingOutboxCount());
    setOutboxItems(getOfflineOutbox());
  }, []);

  const triggerSync = useCallback(async () => {
    if (typeof navigator === "undefined" || !navigator.onLine || isSyncing) {
      return;
    }
    setIsSyncing(true);
    try {
      const outcome = await syncOfflineOutbox();
      setLastSyncResult(outcome);
      refreshState();
    } finally {
      setIsSyncing(false);
    }
  }, [isSyncing, refreshState]);

  useEffect(() => {
    refreshState();

    const handleOnline = () => {
      setIsOnline(true);
      // Auto-synchronize when connectivity is restored
      triggerSync();
    };

    const handleOffline = () => {
      setIsOnline(false);
    };

    const handleOutboxUpdate = () => {
      refreshState();
    };

    window.addEventListener("online", handleOnline);
    window.addEventListener("offline", handleOffline);
    window.addEventListener("tsr:outbox-updated", handleOutboxUpdate);

    return () => {
      window.removeEventListener("online", handleOnline);
      window.removeEventListener("offline", handleOffline);
      window.removeEventListener("tsr:outbox-updated", handleOutboxUpdate);
    };
  }, [refreshState, triggerSync]);

  return {
    isOnline,
    pendingCount,
    isSyncing,
    outboxItems,
    lastSyncResult,
    triggerSync,
    refreshState,
  };
}

