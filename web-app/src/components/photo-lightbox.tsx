"use client";

import React, { useEffect, useCallback, useState } from "react";
import {
  X,
  ChevronLeft,
  ChevronRight,
  Download,
  Calendar,
  Building2,
  Tag,
  User,
  Clock,
  ZoomIn,
  ZoomOut,
  Maximize2,
} from "lucide-react";
import type { SiteProgressPhotoRecord, SiteProgressUpdateRecord } from "@/types/database";
import { formatDisplayDate } from "@/lib/utils";

interface PhotoLightboxProps {
  isOpen: boolean;
  onClose: () => void;
  update: SiteProgressUpdateRecord | null;
  activePhotoIndex: number;
  onNavigate: (index: number) => void;
}

export function PhotoLightbox({
  isOpen,
  onClose,
  update,
  activePhotoIndex,
  onNavigate,
}: PhotoLightboxProps) {
  const [zoomLevel, setZoomLevel] = useState<number>(1);
  const [touchStartX, setTouchStartX] = useState<number | null>(null);

  const photos = update?.photos || [];
  const activePhoto: SiteProgressPhotoRecord | undefined = photos[activePhotoIndex];

  // Reset zoom on photo switch or modal open
  useEffect(() => {
    setZoomLevel(1);
  }, [activePhotoIndex, isOpen]);

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (!isOpen) return;
      if (e.key === "Escape") onClose();
      if (e.key === "ArrowLeft" && activePhotoIndex > 0) {
        onNavigate(activePhotoIndex - 1);
      }
      if (e.key === "ArrowRight" && activePhotoIndex < photos.length - 1) {
        onNavigate(activePhotoIndex + 1);
      }
    },
    [isOpen, onClose, activePhotoIndex, photos.length, onNavigate]
  );

  useEffect(() => {
    window.addEventListener("keydown", handleKeyDown);
    return () => window.removeEventListener("keydown", handleKeyDown);
  }, [handleKeyDown]);

  // Touch swipe support for mobile
  function handleTouchStart(e: React.TouchEvent) {
    setTouchStartX(e.touches[0].clientX);
  }

  function handleTouchEnd(e: React.TouchEvent) {
    if (touchStartX === null) return;
    const diff = touchStartX - e.changedTouches[0].clientX;
    const threshold = 50; // min swipe distance in px

    if (diff > threshold && activePhotoIndex < photos.length - 1) {
      // Swiped left -> Next photo
      onNavigate(activePhotoIndex + 1);
    } else if (diff < -threshold && activePhotoIndex > 0) {
      // Swiped right -> Previous photo
      onNavigate(activePhotoIndex - 1);
    }
    setTouchStartX(null);
  }

  function toggleZoom() {
    setZoomLevel((prev) => (prev === 1 ? 1.75 : prev === 1.75 ? 2.5 : 1));
  }

  if (!isOpen || !update || !activePhoto) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/92 p-2 sm:p-4 backdrop-blur-xs select-none"
      role="dialog"
      aria-modal="true"
    >
      {/* Background click to close */}
      <div className="absolute inset-0" onClick={onClose} />

      {/* Main Container */}
      <div className="relative z-10 flex h-full max-h-[96vh] w-full max-w-5xl flex-col overflow-hidden rounded-2xl bg-slate-900 border border-white/10 shadow-2xl">
        {/* Header Bar */}
        <div className="flex items-center justify-between border-b border-white/10 px-4 py-3 text-white">
          <div className="flex items-center gap-3 min-w-0">
            <span className="rounded-full bg-blue-600/80 px-2.5 py-0.5 text-xs font-semibold">
              {update.category}
            </span>
            <span className="truncate text-sm font-medium text-slate-200">
              {update.sites?.name || "Site"}
            </span>
            <span className="text-xs text-slate-400">
              Photo {activePhotoIndex + 1} of {photos.length}
            </span>
          </div>

          <div className="flex items-center gap-1.5 sm:gap-2">
            {/* Zoom toggle button */}
            <button
              type="button"
              onClick={toggleZoom}
              title={`Zoom (${zoomLevel}x)`}
              className="rounded-lg p-1.5 text-slate-300 hover:bg-white/10 hover:text-white transition-colors cursor-pointer"
            >
              {zoomLevel > 1 ? (
                <ZoomOut className="h-4 w-4 text-blue-400" />
              ) : (
                <ZoomIn className="h-4 w-4" />
              )}
            </button>

            {/* Download/Open original */}
            {activePhoto.signed_url && (
              <a
                href={activePhoto.signed_url}
                target="_blank"
                rel="noreferrer"
                download={`progress-photo-${activePhotoIndex + 1}.jpg`}
                className="rounded-lg p-1.5 text-slate-300 hover:bg-white/10 hover:text-white transition-colors"
                title="Open / Download Full Resolution"
              >
                <Download className="h-4 w-4" />
              </a>
            )}

            {/* Close button */}
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg p-1.5 text-slate-300 hover:bg-white/10 hover:text-white transition-colors cursor-pointer"
              aria-label="Close photo view"
            >
              <X className="h-5 w-5" />
            </button>
          </div>
        </div>

        {/* Center Image Viewport */}
        <div
          className="relative flex flex-1 items-center justify-center overflow-auto bg-black/60 p-2 touch-pan-y"
          onTouchStart={handleTouchStart}
          onTouchEnd={handleTouchEnd}
        >
          {/* Previous Button */}
          {activePhotoIndex > 0 && (
            <button
              type="button"
              onClick={() => onNavigate(activePhotoIndex - 1)}
              className="absolute left-3 top-1/2 -translate-y-1/2 z-20 rounded-full bg-slate-900/80 p-2.5 text-white shadow-lg backdrop-blur-xs hover:bg-blue-600 transition-colors cursor-pointer"
              aria-label="Previous photo"
            >
              <ChevronLeft className="h-5 w-5" />
            </button>
          )}

          {/* Next Button */}
          {activePhotoIndex < photos.length - 1 && (
            <button
              type="button"
              onClick={() => onNavigate(activePhotoIndex + 1)}
              className="absolute right-3 top-1/2 -translate-y-1/2 z-20 rounded-full bg-slate-900/80 p-2.5 text-white shadow-lg backdrop-blur-xs hover:bg-blue-600 transition-colors cursor-pointer"
              aria-label="Next photo"
            >
              <ChevronRight className="h-5 w-5" />
            </button>
          )}

          {/* Image Display with Zoom Transform */}
          {activePhoto.signed_url ? (
            <div
              className="flex items-center justify-center transition-transform duration-200"
              style={{
                transform: `scale(${zoomLevel})`,
                cursor: zoomLevel > 1 ? "zoom-out" : "zoom-in",
              }}
              onClick={toggleZoom}
            >
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={activePhoto.signed_url}
                alt={activePhoto.caption || `${update.category} photo`}
                className="max-h-[75vh] max-w-full rounded-md object-contain select-none"
              />
            </div>
          ) : (
            <div className="flex flex-col items-center justify-center p-8 text-center text-slate-400">
              <p className="text-sm">Signed URL expired or photo unavailable.</p>
            </div>
          )}
        </div>

        {/* Footer Metadata & Caption */}
        <div className="border-t border-white/10 bg-slate-950/80 p-3 sm:p-4 text-xs text-slate-300">
          <div className="flex flex-wrap items-center justify-between gap-2 mb-2">
            <div className="flex flex-wrap items-center gap-3 text-slate-400">
              <span className="flex items-center gap-1">
                <Calendar className="h-3.5 w-3.5 text-blue-400" />
                {formatDisplayDate(update.work_date)}
              </span>
              <span className="flex items-center gap-1">
                <User className="h-3.5 w-3.5 text-emerald-400" />
                {update.creator_profile?.name || "Field Supervisor"}
              </span>
              <span className="flex items-center gap-1">
                <Clock className="h-3.5 w-3.5 text-slate-400" />
                {new Date(activePhoto.created_at || update.created_at).toLocaleTimeString([], {
                  hour: "2-digit",
                  minute: "2-digit",
                })}
              </span>
            </div>

            {/* Thumbnail Strip */}
            {photos.length > 1 && (
              <div className="flex items-center gap-1.5 overflow-x-auto py-0.5">
                {photos.map((p, idx) => (
                  <button
                    key={p.id || idx}
                    type="button"
                    onClick={() => onNavigate(idx)}
                    className={`h-9 w-9 shrink-0 overflow-hidden rounded-md border-2 transition-all cursor-pointer ${idx === activePhotoIndex
                        ? "border-blue-500 scale-105"
                        : "border-transparent opacity-60 hover:opacity-100"
                      }`}
                  >
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img
                      src={p.signed_url}
                      alt={`Thumb ${idx + 1}`}
                      className="h-full w-full object-cover"
                    />
                  </button>
                ))}
              </div>
            )}
          </div>

          {activePhoto.caption && (
            <div className="rounded-lg bg-white/5 p-2 text-slate-200">
              <span className="font-semibold text-blue-400">Caption: </span>
              {activePhoto.caption}
            </div>
          )}

          <div className="mt-1 line-clamp-2 text-slate-400 text-[11px]">
            <span className="font-medium text-slate-300">Description: </span>
            {update.description}
          </div>
        </div>
      </div>
    </div>
  );
}
