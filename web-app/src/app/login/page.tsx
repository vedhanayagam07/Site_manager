"use client";

import React, { Suspense, useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";
import { ShieldCheck, Mail, Lock, Eye, EyeOff, AlertCircle } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Button } from "@/components/ui/button";

function LoginForm() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const redirect = searchParams.get("redirect") || "/dashboard";

  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setLoading(true);

    try {
      const supabase = createClient();
      const { data, error: authError } = await supabase.auth.signInWithPassword({
        email: email.trim().toLowerCase(),
        password,
      });

      if (authError) {
        setError(authError.message || "Invalid email or password.");
        setLoading(false);
        return;
      }

      if (data.user) {
        // Successful login
        router.push(redirect);
        router.refresh();
      }
    } catch {
      setError("Unable to reach authentication server. Please try again.");
      setLoading(false);
    }
  }

  return (
    <div className="flex min-h-screen flex-col lg:flex-row bg-[#101318] text-[#F2F4F8]">
      {/* Left Enterprise Graphite Glass Panel */}
      <div className="relative overflow-hidden flex flex-col justify-between bg-[rgba(23,28,36,0.95)] border-b lg:border-b-0 lg:border-r border-[rgba(190,205,225,0.15)] px-8 py-10 lg:w-[44%] lg:px-14 lg:py-14">
        {/* Subtle Brand Background Watermark */}
        <div className="pointer-events-none absolute -bottom-16 -right-16 opacity-5 select-none">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src="/tsrbuilders-transparent.png"
            alt=""
            className="h-96 w-96 object-contain"
          />
        </div>
        <div className="flex items-center gap-3">
          {/* Natural transparent logo artwork without colored container */}
          <div className="flex h-12 w-12 items-center justify-center">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img
              src="/tsrbuilders-transparent.png"
              alt="TSR Builders"
              className="h-full w-full object-contain filter drop-shadow-[0_2px_10px_rgba(234,179,8,0.3)]"
            />
          </div>
          <div>
            <div className="text-base font-bold tracking-wider text-[#F2F4F8]">TSR BUILDERS</div>
            <div className="text-xs text-[#A7B0BE]">
              Construction Operations Platform
            </div>
          </div>
        </div>

        <div className="my-10 lg:my-0">
          <div className="inline-flex items-center gap-2 rounded-full border border-blue-400/25 bg-[#4B83F5]/10 px-3 py-1 text-xs font-medium text-[#4B83F5]">
            <ShieldCheck className="h-3.5 w-3.5" />
            Role-Secured Enterprise Workspace
          </div>
          <h1 className="mt-5 text-2xl font-bold leading-tight tracking-tight text-[#F2F4F8] sm:text-3xl">
            Manage sites, workforce attendance, and materials in real time.
          </h1>
          <p className="mt-3 max-w-md text-sm leading-relaxed text-[#A7B0BE]">
            Unified operational control for Administrators, Project Managers, and
            Site Supervisors — powered by your existing Supabase backend and
            row-level security policies.
          </p>
        </div>

        <div className="hidden border-t border-[rgba(190,205,225,0.12)] pt-6 text-xs text-[#778292] lg:block">
          TSR Builders Pvt Ltd · Authenticated Access Only
        </div>
      </div>

      {/* Right Sign-In Glass Form */}
      <div className="flex flex-1 items-center justify-center bg-[#101318] px-6 py-12">
        <div className="w-full max-w-md rounded-2xl border border-[rgba(220,230,245,0.20)] bg-[rgba(35,42,53,0.60)] p-7 shadow-[0_24px_64px_rgba(0,0,0,0.65)] backdrop-blur-xl sm:p-8">
          <div className="mb-6">
            <h2 className="text-xl font-bold tracking-tight text-[#F2F4F8]">Sign in</h2>
            <p className="mt-1 text-sm text-[#A7B0BE]">
              Use your assigned TSR Builders credentials to continue.
            </p>
          </div>

          {error && (
            <div
              role="alert"
              className="mb-5 flex items-start gap-2.5 rounded-xl border border-red-500/30 bg-red-950/40 px-3.5 py-3 text-xs font-medium text-red-200"
            >
              <AlertCircle className="mt-0.5 h-4 w-4 shrink-0 text-[#E56B72]" />
              <span>{error}</span>
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-1.5">
              <label
                htmlFor="email"
                className="block text-xs font-medium text-[#A7B0BE]"
              >
                Email Address
              </label>
              <div className="relative">
                <Mail className="pointer-events-none absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2 text-[#778292]" />
                <input
                  id="email"
                  type="email"
                  autoComplete="email"
                  required
                  disabled={loading}
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  placeholder="name@tsrbuilders.com"
                  className="flex h-10 w-full rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 pr-3 pl-9 text-sm text-[#F2F4F8] placeholder:text-[#778292] focus:border-[#4B83F5] focus:bg-[#101318]/90 focus:outline-none focus:ring-2 focus:ring-[#4B83F5]/25 disabled:opacity-50"
                />
              </div>
            </div>

            <div className="space-y-1.5">
              <label
                htmlFor="password"
                className="block text-xs font-medium text-[#A7B0BE]"
              >
                Password
              </label>
              <div className="relative">
                <Lock className="pointer-events-none absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2 text-[#778292]" />
                <input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  autoComplete="current-password"
                  required
                  disabled={loading}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="Enter your password"
                  className="flex h-10 w-full rounded-xl border border-[rgba(190,205,225,0.18)] bg-[#101318]/70 pr-10 pl-9 text-sm text-[#F2F4F8] placeholder:text-[#778292] focus:border-[#4B83F5] focus:bg-[#101318]/90 focus:outline-none focus:ring-2 focus:ring-[#4B83F5]/25 disabled:opacity-50"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword((prev) => !prev)}
                  aria-label={showPassword ? "Hide password" : "Show password"}
                  className="absolute top-1/2 right-2.5 -translate-y-1/2 rounded-lg p-1 text-[#778292] hover:bg-white/10 hover:text-white cursor-pointer"
                >
                  {showPassword ? (
                    <EyeOff className="h-4 w-4" />
                  ) : (
                    <Eye className="h-4 w-4" />
                  )}
                </button>
              </div>
            </div>

            <Button
              type="submit"
              loading={loading}
              className="mt-2 w-full"
              size="lg"
            >
              Sign In
            </Button>
          </form>

          <p className="mt-6 text-center text-xs text-[#778292]">
            Access is provisioned by your TSR Builders administrator.
          </p>
        </div>
      </div>
    </div>
  );
}

export default function LoginPage() {
  return (
    <Suspense
      fallback={
        <div className="flex min-h-screen items-center justify-center bg-[#101318]">
          <div className="h-8 w-8 animate-spin rounded-full border-2 border-white/10 border-t-[#4B83F5]" />
        </div>
      }
    >
      <LoginForm />
    </Suspense>
  );
}
