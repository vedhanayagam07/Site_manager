"use client";

import React, { createContext, useCallback, useContext, useState } from "react";
import { CheckCircle2, AlertCircle, Info, X } from "lucide-react";
import { cn } from "@/lib/utils";

type ToastType = "success" | "error" | "info" | "warning";

interface ToastItem {
  id: number;
  type: ToastType;
  message: string;
}

interface ToastContextValue {
  toast: (message: string, type?: ToastType) => void;
  success: (message: string) => void;
  error: (message: string) => void;
  info: (message: string) => void;
  warning: (message: string) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([]);

  const dismiss = useCallback((id: number) => {
    setItems((prev) => prev.filter((item) => item.id !== id));
  }, []);

  const push = useCallback(
    (message: string, type: ToastType = "info") => {
      const id = Date.now() + Math.floor(Math.random() * 1000);
      setItems((prev) => [...prev, { id, type, message }]);
      window.setTimeout(() => dismiss(id), 4500);
    },
    [dismiss]
  );

  const value: ToastContextValue = {
    toast: push,
    success: (m) => push(m, "success"),
    error: (m) => push(m, "error"),
    info: (m) => push(m, "info"),
    warning: (m) => push(m, "warning"),
  };

  return (
    <ToastContext.Provider value={value}>
      {children}
      <div className="pointer-events-none fixed right-4 bottom-20 z-50 flex w-full max-w-sm flex-col gap-2.5 sm:bottom-5">
        {items.map((item) => (
          <div
            key={item.id}
            role="status"
            className={cn(
              "pointer-events-auto flex items-start gap-3 rounded-2xl border px-4 py-3 text-sm shadow-[0_12px_36px_rgba(0,0,0,0.60)] backdrop-blur-xl animate-in slide-in-from-right-4 duration-150",
              item.type === "success" && "border-emerald-500/30 bg-[rgba(23,28,36,0.92)] text-[#F2F4F8]",
              item.type === "error" && "border-red-500/30 bg-[rgba(23,28,36,0.92)] text-[#F2F4F8]",
              item.type === "warning" && "border-amber-500/30 bg-[rgba(23,28,36,0.92)] text-[#F2F4F8]",
              item.type === "info" && "border-blue-500/30 bg-[rgba(23,28,36,0.92)] text-[#F2F4F8]"
            )}
          >
            {item.type === "success" && (
              <div className="rounded-lg bg-emerald-500/20 p-1 text-[#39B980] shrink-0">
                <CheckCircle2 className="h-4 w-4" />
              </div>
            )}
            {item.type === "error" && (
              <div className="rounded-lg bg-red-500/20 p-1 text-[#E56B72] shrink-0">
                <AlertCircle className="h-4 w-4" />
              </div>
            )}
            {item.type === "warning" && (
              <div className="rounded-lg bg-amber-500/20 p-1 text-[#E5AD55] shrink-0">
                <AlertCircle className="h-4 w-4" />
              </div>
            )}
            {item.type === "info" && (
              <div className="rounded-lg bg-blue-500/20 p-1 text-[#4B83F5] shrink-0">
                <Info className="h-4 w-4" />
              </div>
            )}
            <span className="flex-1 text-xs font-medium leading-5 text-[#F2F4F8]">{item.message}</span>
            <button
              type="button"
              onClick={() => dismiss(item.id)}
              className="rounded-lg p-1 text-[#778292] hover:bg-white/10 hover:text-white cursor-pointer transition-colors"
              aria-label="Dismiss notification"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast(): ToastContextValue {
  const ctx = useContext(ToastContext);
  if (!ctx) {
    throw new Error("useToast must be used within a ToastProvider");
  }
  return ctx;
}
