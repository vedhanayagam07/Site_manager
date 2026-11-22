"use client";

import React from "react";
import { ShieldOff, LogOut } from "lucide-react";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/context/auth-context";

export function DisabledAccountGate({
  reason = "disabled",
}: {
  reason?: "disabled" | "unprovisioned";
}) {
  const { profile, user, signOut } = useAuth();
  const isUnprovisioned = reason === "unprovisioned";

  return (
    <div className="flex min-h-screen items-center justify-center bg-[#101318] p-6 text-[#F2F4F8]">
      <div className="w-full max-w-md rounded-2xl border border-[rgba(220,230,245,0.22)] bg-[rgba(23,28,36,0.92)] p-8 text-center shadow-[0_24px_64px_rgba(0,0,0,0.7)] backdrop-blur-2xl">
        <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl border border-red-500/30 bg-red-500/15 text-[#E56B72] shadow-[0_0_20px_rgba(229,107,114,0.25)]">
          <ShieldOff className="h-7 w-7" />
        </div>
        <h1 className="mt-5 text-xl font-bold tracking-tight text-[#F2F4F8]">
          {isUnprovisioned ? "Access Not Provisioned" : "Account Disabled"}
        </h1>
        <p className="mt-2 text-sm leading-relaxed text-[#A7B0BE]">
          {isUnprovisioned ? (
            <>
              Your login ({user?.email}) succeeded, but no active staff profile
              exists in <code className="rounded bg-black/40 px-1.5 py-0.5 text-blue-300">public.user_profiles</code>. Operational data is
              blocked by database security policy until an administrator
              provisions your role.
            </>
          ) : (
            <>
              Your TSR Builders account ({profile?.email ?? user?.email}) has
              been disabled by an administrator. Database access is restricted
              while your account is inactive.
            </>
          )}
        </p>
        <p className="mt-3 text-xs text-[#778292]">
          If you believe this is an error, please contact your company administrator.
        </p>
        <div className="mt-6">
          <Button variant="outline" className="w-full" onClick={signOut}>
            <LogOut className="h-4 w-4" />
            Sign Out
          </Button>
        </div>
      </div>
    </div>
  );
}
