"use client";

import React, { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/client";
import type { AppRole, SiteRecord, UserProfile } from "@/types/database";
import { fetchSites } from "@/lib/data/sites";

interface AuthContextValue {
  user: User | null;
  profile: UserProfile | null;
  role: AppRole | null;
  isLoading: boolean;
  isDisabled: boolean;
  isAdmin: boolean;
  isProjectManager: boolean;
  isSupervisor: boolean;
  isPmOrAdmin: boolean;
  sites: SiteRecord[];
  selectedSiteId: string; // "" means All Sites
  setSelectedSiteId: (siteId: string) => void;
  refreshProfile: () => Promise<void>;
  refreshSites: () => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | null>(null);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [sites, setSites] = useState<SiteRecord[]>([]);
  const [selectedSiteId, setSelectedSiteIdState] = useState<string>("");
  const [isLoading, setIsLoading] = useState(true);

  const loadUserAndProfile = useCallback(async () => {
    const supabase = createClient();
    try {
      const {
        data: { user: authUser },
      } = await supabase.auth.getUser();

      setUser(authUser ?? null);

      if (!authUser) {
        setProfile(null);
        setSites([]);
        setIsLoading(false);
        return;
      }

      const { data: profileData } = await supabase
        .from("user_profiles")
        .select("*")
        .eq("id", authUser.id)
        .maybeSingle();

      if (profileData) {
        const parsed = profileData as UserProfile;
        setProfile(parsed);

        if (parsed.status === "active") {
          try {
            const loadedSites = await fetchSites();
            setSites(loadedSites);
            // Defensive check: clear stale localStorage site filter if not in RLS-permitted sites
            if (typeof window !== "undefined") {
              const savedSite = window.localStorage.getItem("tsr_selected_site_id");
              if (savedSite && !loadedSites.some((s) => s.id === savedSite)) {
                window.localStorage.removeItem("tsr_selected_site_id");
                setSelectedSiteIdState("");
              }
            }
          } catch {
            setSites([]);
            setSelectedSiteIdState("");
          }
        } else {
          setSites([]);
          setSelectedSiteIdState("");
        }
      } else {
        setProfile(null);
        setSites([]);
      }
    } catch (err) {
      console.error("[AuthProvider] Error loading auth context:", err);
      setProfile(null);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const refreshSites = useCallback(async () => {
    try {
      const loadedSites = await fetchSites();
      setSites(loadedSites);
    } catch {
      // Keep current sites on transient failure
    }
  }, []);

  useEffect(() => {
    // Restore saved site filter
    if (typeof window !== "undefined") {
      const savedSite = window.localStorage.getItem("tsr_selected_site_id");
      if (savedSite) setSelectedSiteIdState(savedSite);
    }

    loadUserAndProfile();

    const supabase = createClient();
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event: string) => {
      loadUserAndProfile();
    });

    return () => {
      subscription.unsubscribe();
    };
  }, [loadUserAndProfile]);

  const setSelectedSiteId = useCallback((siteId: string) => {
    setSelectedSiteIdState(siteId);
    if (typeof window !== "undefined") {
      if (siteId) {
        window.localStorage.setItem("tsr_selected_site_id", siteId);
      } else {
        window.localStorage.removeItem("tsr_selected_site_id");
      }
    }
  }, []);

  const signOut = useCallback(async () => {
    const supabase = createClient();
    await supabase.auth.signOut();
    setUser(null);
    setProfile(null);
    setSites([]);
    if (typeof window !== "undefined") {
      window.localStorage.removeItem("tsr_selected_site_id");
      window.location.href = "/login";
    }
  }, []);

  const isDisabled = Boolean(user && profile && profile.status === "disabled");
  const activeRole: AppRole | null =
    profile && profile.status === "active" ? profile.role : null;

  const value = useMemo<AuthContextValue>(
    () => ({
      user,
      profile,
      role: activeRole,
      isLoading,
      isDisabled,
      isAdmin: activeRole === "admin",
      isProjectManager: activeRole === "projectManager",
      isSupervisor: activeRole === "supervisor",
      isPmOrAdmin: activeRole === "admin" || activeRole === "projectManager",
      sites,
      selectedSiteId,
      setSelectedSiteId,
      refreshProfile: loadUserAndProfile,
      refreshSites,
      signOut,
    }),
    [
      user,
      profile,
      activeRole,
      isLoading,
      isDisabled,
      sites,
      selectedSiteId,
      setSelectedSiteId,
      loadUserAndProfile,
      refreshSites,
      signOut,
    ]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return ctx;
}

