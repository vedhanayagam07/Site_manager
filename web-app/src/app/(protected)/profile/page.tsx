"use client";

import React from "react";
import Link from "next/link";
import { Mail, Building2, Shield, LogOut, MapPin } from "lucide-react";
import { useAuth } from "@/context/auth-context";
import { formatRoleLabel } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { PageHeader } from "@/components/ui/states";

export default function ProfilePage() {
  const { user, profile, sites, signOut } = useAuth();

  const displayName =
    profile?.name?.trim() || user?.email?.split("@")[0] || "Staff Member";
  const initials = displayName
    .split(" ")
    .map((p) => p[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();

  return (
    <div>
      <PageHeader
        title="My Profile"
        description="Authenticated account details loaded directly from public.user_profiles."
        actions={
          <Button variant="danger" size="sm" onClick={signOut}>
            <LogOut className="h-4 w-4" />
            Sign Out
          </Button>
        }
      />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <Card>
          <CardContent className="flex flex-col items-center p-6 text-center">
            <div className="flex h-20 w-20 items-center justify-center rounded-full bg-[#0B1628] text-2xl font-bold text-white">
              {initials}
            </div>
            <h2 className="mt-4 text-lg font-bold text-slate-900">{displayName}</h2>
            <div className="mt-2 flex items-center gap-2">
              <Badge variant="blue">{formatRoleLabel(profile?.role)}</Badge>
              <StatusBadge status={profile?.status ?? "unknown"} />
            </div>
            <p className="mt-3 text-xs text-slate-500">
              TSR Builders Pvt Ltd · Supabase Auth Session
            </p>
          </CardContent>
        </Card>

        <div className="space-y-6 lg:col-span-2">
          <Card>
            <CardHeader>
              <CardTitle>Account Credentials</CardTitle>
            </CardHeader>
            <CardContent className="divide-y divide-slate-100 p-0">
              <div className="flex items-center gap-3 px-5 py-3.5">
                <Mail className="h-4 w-4 text-[#2563EB]" />
                <div>
                  <p className="text-xs text-slate-500">Email Address</p>
                  <p className="text-sm font-medium text-slate-900">
                    {profile?.email ?? user?.email ?? "—"}
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-3 px-5 py-3.5">
                <Shield className="h-4 w-4 text-[#2563EB]" />
                <div>
                  <p className="text-xs text-slate-500">Database Role Authority</p>
                  <p className="text-sm font-medium text-slate-900">
                    {formatRoleLabel(profile?.role)} ({profile?.role ?? "none"})
                  </p>
                </div>
              </div>
              <div className="flex items-center gap-3 px-5 py-3.5">
                <Building2 className="h-4 w-4 text-[#2563EB]" />
                <div>
                  <p className="text-xs text-slate-500">Organization</p>
                  <p className="text-sm font-medium text-slate-900">
                    TSR Builders Pvt Ltd
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Accessible Sites ({sites.length})</CardTitle>
            </CardHeader>
            <CardContent className="divide-y divide-slate-100 p-0">
              {sites.length === 0 ? (
                <p className="p-6 text-center text-xs text-slate-500">
                  No sites accessible for this account.
                </p>
              ) : (
                sites.map((s) => (
                  <Link
                    key={s.id}
                    href={`/sites/${s.id}`}
                    className="flex items-center justify-between px-5 py-3.5 hover:bg-slate-50"
                  >
                    <div className="flex items-center gap-3">
                      <MapPin className="h-4 w-4 text-slate-400" />
                      <div>
                        <p className="text-sm font-semibold text-slate-900">{s.name}</p>
                        <p className="text-xs text-slate-500">
                          {s.location || "No location specified"}
                        </p>
                      </div>
                    </div>
                    <StatusBadge status={s.status} />
                  </Link>
                ))
              )}
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}

