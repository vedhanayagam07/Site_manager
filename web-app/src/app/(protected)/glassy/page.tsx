"use client";

import React from "react";
import Link from "next/link";
import { LayoutDashboard } from "lucide-react";
import GlassyDashboard from "@/components/ui/glassy-dashboard";
import { Button } from "@/components/ui/button";

export default function GlassyPage() {
  return (
    <div className="relative -m-4 min-h-screen sm:-m-6 lg:-m-8">
      {/* Floating Header Actions */}
      <div className="fixed top-4 right-4 z-50 flex items-center gap-2 rounded-full border border-white/20 bg-[#0B1628]/85 px-3 py-1.5 text-white shadow-xl backdrop-blur-md">
        <Link href="/dashboard">
          <Button
            size="sm"
            variant="ghost"
            className="h-7 rounded-full px-2.5 text-xs font-semibold text-slate-200 hover:bg-white/10 hover:text-white"
          >
            <LayoutDashboard className="h-3.5 w-3.5" />
            Classic Dashboard
          </Button>
        </Link>
      </div>

      <GlassyDashboard
        workspaceName="TSR BUILDERS"
        backgroundImage="/tsrbuilders.png"
        initialTheme="dark"
      />
    </div>
  );
}
