"use client";

import React, { useEffect } from "react";
import { X } from "lucide-react";
import { cn } from "@/lib/utils";

interface ModalProps {
  open: boolean;
  onClose: () => void;
  title: string;
  description?: string;
  children: React.ReactNode;
  maxWidthClass?: string;
}

export function Modal({
  open,
  onClose,
  title,
  description,
  children,
  maxWidthClass = "max-w-lg",
}: ModalProps) {
  useEffect(() => {
    if (!open) return;
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKeyDown);
    document.body.style.overflow = "hidden";
    return () => {
      document.removeEventListener("keydown", onKeyDown);
      document.body.style.overflow = "";
    };
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4 backdrop-blur-md"
      role="dialog"
      aria-modal="true"
      aria-labelledby="modal-title"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        className={cn(
          "flex max-h-[90vh] w-full flex-col overflow-hidden rounded-2xl border border-[rgba(220,230,245,0.22)] bg-[rgba(23,28,36,0.92)] shadow-[0_24px_64px_rgba(0,0,0,0.7)] backdrop-blur-2xl animate-in fade-in-0 zoom-in-95 duration-150",
          maxWidthClass
        )}
      >
        <div className="flex items-start justify-between gap-4 border-b border-[rgba(190,205,225,0.12)] px-5 py-4">
          <div>
            <h2 id="modal-title" className="text-base font-semibold tracking-tight text-[#F2F4F8]">
              {title}
            </h2>
            {description && (
              <p className="mt-0.5 text-xs text-[#A7B0BE]">{description}</p>
            )}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close modal"
            className="rounded-lg p-1 text-[#778292] transition-colors hover:bg-white/10 hover:text-[#F2F4F8] cursor-pointer"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="overflow-y-auto p-5 text-[#F2F4F8]">{children}</div>
      </div>
    </div>
  );
}
