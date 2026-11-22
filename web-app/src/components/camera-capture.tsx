"use client";

import React, { useRef, useState } from "react";
import { Camera, Image as ImageIcon, X, CheckCircle2 } from "lucide-react";
import { Button } from "@/components/ui/button";

export interface CapturedPhoto {
  dataUrl: string;
  name: string;
  sizeBytes: number;
}

interface CameraCaptureProps {
  label?: string;
  description?: string;
  onPhotoCaptured: (photo: CapturedPhoto | null) => void;
  currentPhoto?: CapturedPhoto | null;
  className?: string;
}

/**
 * Mobile-first Camera and Photo Attachment component.
 * Uses native HTML5 capture="environment" for rear camera on mobile devices,
 * with graceful file picker fallback on desktop. Includes client-side resize
 * to protect bandwidth and prevent storage bloat.
 */
export function CameraCapture({
  label = "Attach Site Photo / Delivery Slip",
  description = "Take a photo with your mobile camera or upload from gallery",
  onPhotoCaptured,
  currentPhoto,
  className = "",
}: CameraCaptureProps) {
  const cameraInputRef = useRef<HTMLInputElement>(null);
  const galleryInputRef = useRef<HTMLInputElement>(null);
  const [photo, setPhoto] = useState<CapturedPhoto | null>(currentPhoto ?? null);
  const [isProcessing, setIsProcessing] = useState(false);

  async function processFile(file: File) {
    setIsProcessing(true);
    try {
      const img = new Image();
      const reader = new FileReader();

      reader.onload = (e) => {
        img.src = e.target?.result as string;
        img.onload = () => {
          // Resize image to max 1280px width/height to keep payload under 250KB
          const canvas = document.createElement("canvas");
          let width = img.width;
          let height = img.height;
          const maxDim = 1280;

          if (width > height && width > maxDim) {
            height = Math.round((height * maxDim) / width);
            width = maxDim;
          } else if (height > maxDim) {
            width = Math.round((width * maxDim) / height);
            height = maxDim;
          }

          canvas.width = width;
          canvas.height = height;
          const ctx = canvas.getContext("2d");
          ctx?.drawImage(img, 0, 0, width, height);

          const compressedDataUrl = canvas.toDataURL("image/jpeg", 0.75);
          const captured: CapturedPhoto = {
            dataUrl: compressedDataUrl,
            name: file.name || `photo-${Date.now()}.jpg`,
            sizeBytes: Math.round((compressedDataUrl.length * 3) / 4),
          };

          setPhoto(captured);
          onPhotoCaptured(captured);
          setIsProcessing(false);
        };
      };

      reader.readAsDataURL(file);
    } catch (err) {
      console.error("[CameraCapture] Error processing photo:", err);
      setIsProcessing(false);
    }
  }

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (file) {
      processFile(file);
    }
  }

  function handleRemove() {
    setPhoto(null);
    onPhotoCaptured(null);
    if (cameraInputRef.current) cameraInputRef.current.value = "";
    if (galleryInputRef.current) galleryInputRef.current.value = "";
  }

  return (
    <div className={`space-y-2 ${className}`}>
      {label && (
        <label className="block text-xs font-semibold text-slate-700">
          {label}
        </label>
      )}

      {photo ? (
        <div className="relative overflow-hidden rounded-xl border border-slate-200 bg-slate-50 p-2 sm:p-3">
          <div className="flex items-center gap-3">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src={photo.dataUrl}
              alt="Captured document"
              className="h-16 w-16 shrink-0 rounded-lg object-cover border border-slate-200 shadow-xs"
            />
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-1.5 text-xs font-bold text-slate-900">
                <CheckCircle2 className="h-3.5 w-3.5 text-emerald-600 shrink-0" />
                <span className="truncate">{photo.name}</span>
              </div>
              <p className="mt-0.5 text-[11px] text-slate-500">
                Compressed: {(photo.sizeBytes / 1024).toFixed(0)} KB · Ready to save
              </p>
            </div>
            <button
              type="button"
              onClick={handleRemove}
              aria-label="Remove photo"
              className="flex h-8 w-8 items-center justify-center rounded-lg border border-red-200 bg-red-50 text-red-600 hover:bg-red-100 transition-colors cursor-pointer"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>
      ) : (
        <div className="flex flex-col gap-2 rounded-xl border border-dashed border-slate-300 bg-slate-50/50 p-4 text-center transition-colors hover:border-slate-400">
          {/* Hidden HTML5 camera and file inputs */}
          <input
            ref={cameraInputRef}
            type="file"
            accept="image/*"
            capture="environment"
            onChange={handleFileChange}
            className="hidden"
          />
          <input
            ref={galleryInputRef}
            type="file"
            accept="image/*"
            onChange={handleFileChange}
            className="hidden"
          />

          <p className="text-xs text-slate-500">{description}</p>

          <div className="flex flex-wrap justify-center gap-2 pt-1">
            <button
              type="button"
              disabled={isProcessing}
              onClick={() => cameraInputRef.current?.click()}
              className="inline-flex items-center gap-1.5 rounded-lg border border-blue-200 bg-blue-50 px-3 py-2 text-xs font-bold text-blue-700 shadow-xs hover:bg-blue-100 transition-colors cursor-pointer"
            >
              <Camera className="h-3.5 w-3.5" />
              {isProcessing ? "Processing…" : "Take Photo (Camera)"}
            </button>

            <button
              type="button"
              disabled={isProcessing}
              onClick={() => galleryInputRef.current?.click()}
              className="inline-flex items-center gap-1.5 rounded-lg border border-slate-300 bg-white px-3 py-2 text-xs font-semibold text-slate-700 shadow-xs hover:bg-slate-100 transition-colors cursor-pointer"
            >
              <ImageIcon className="h-3.5 w-3.5" />
              Upload from Files
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

