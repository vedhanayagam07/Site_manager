"use client";

import React, { useCallback, useEffect, useMemo, useState } from "react";
import {
  ShieldCheck,
  Users,
  Activity,
  UserPlus,
  Pencil,
  Power,
  Trash2,
  Lock,
  FileDown,
  Search,
  RefreshCw,
} from "lucide-react";
import { useAuth } from "@/context/auth-context";
import {
  adminCreateUser,
  adminDeleteUser,
  adminToggleUserStatus,
  adminUpdateUser,
  fetchAllUserProfiles,
} from "@/lib/data/admin";
import { fetchActivityLogs } from "@/lib/data/activity-logs";
import { exportActivityLogPdf } from "@/lib/pdf/generators";
import { createClient } from "@/lib/supabase/client";
import type {
  AccountStatus,
  ActivityLogRecord,
  AppRole,
  UserProfile,
} from "@/types/database";
import {
  formatDisplayDateTime,
  formatRoleLabel,
  getErrorMessage,
  todayIsoDate,
} from "@/lib/utils";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { StatCard } from "@/components/ui/stat-card";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Input, Select } from "@/components/ui/input";
import { Modal } from "@/components/ui/modal";
import { ConfirmDialog } from "@/components/ui/confirm-dialog";
import {
  adminCreateUserSchema,
  adminUpdateUserSchema,
  extractFieldErrors,
} from "@/lib/validation/schemas";
import {
  EmptyState,
  ErrorBanner,
  LoadingTable,
  PageHeader,
} from "@/components/ui/states";
import { useToast } from "@/components/ui/toast";

type AdminTab = "users" | "logs";

const LOG_MODULES = [
  "All",
  "Attendance",
  "Materials",
  "Workers",
  "Sites",
  "Loading Memo",
  "Reports",
  "Admin",
  "Auth",
];

export default function AdminPage() {
  const { user, isAdmin } = useAuth();
  const toast = useToast();

  const [tab, setTab] = useState<AdminTab>("users");
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [stats, setStats] = useState({
    totalUsers: 0,
    activeUsers: 0,
    activeSites: 0,
    materials: 0,
    todayAttendance: 0,
  });

  const [profiles, setProfiles] = useState<UserProfile[]>([]);
  const [logs, setLogs] = useState<ActivityLogRecord[]>([]);

  // Log filters
  const [logSearch, setLogSearch] = useState("");
  const [logModule, setLogModule] = useState("All");
  const [fromDate, setFromDate] = useState("");
  const [toDate, setToDate] = useState("");

  // Add / Edit User Modal
  const [userModalOpen, setUserModalOpen] = useState(false);
  const [editingUser, setEditingUser] = useState<UserProfile | null>(null);
  const [formName, setFormName] = useState("");
  const [formEmail, setFormEmail] = useState("");
  const [formPassword, setFormPassword] = useState("");
  const [formRole, setFormRole] = useState<AppRole>("supervisor");
  const [formStatus, setFormStatus] = useState<AccountStatus>("active");
  const [savingUser, setSavingUser] = useState(false);
  const [userErrors, setUserErrors] = useState<Record<string, string>>({});
  const [userToDelete, setUserToDelete] = useState<UserProfile | null>(null);
  const [deletingUser, setDeletingUser] = useState(false);

  const loadDashboard = useCallback(async () => {
    if (!isAdmin) return;
    setLoading(true);
    setError(null);
    try {
      const supabase = createClient();
      const today = todayIsoDate();

      const [
        usersList,
        activeSitesRes,
        materialsRes,
        todayAttRes,
        logsList,
      ] = await Promise.all([
        fetchAllUserProfiles(),
        supabase
          .from("sites")
          .select("id", { count: "exact", head: true })
          .in("status", ["Active", "ACTIVE", "active"]),
        supabase.from("materials").select("id", { count: "exact", head: true }),
        supabase
          .from("site_attendance")
          .select("id", { count: "exact", head: true })
          .eq("attendance_date", today),
        fetchActivityLogs({
          moduleFilter: logModule,
          searchQuery: logSearch,
          fromDate: fromDate || undefined,
          toDate: toDate || undefined,
          limit: 100,
        }),
      ]);

      setProfiles(usersList);
      setLogs(logsList);
      setStats({
        totalUsers: usersList.length,
        activeUsers: usersList.filter((u) => u.status === "active").length,
        activeSites: activeSitesRes.count ?? 0,
        materials: materialsRes.count ?? 0,
        todayAttendance: todayAttRes.count ?? 0,
      });
    } catch (err) {
      setError(getErrorMessage(err, "Failed to load admin console."));
    } finally {
      setLoading(false);
    }
  }, [isAdmin, logModule, logSearch, fromDate, toDate]);

  useEffect(() => {
    if (isAdmin) loadDashboard();
  }, [isAdmin, loadDashboard]);

  const filteredLogs = useMemo(() => logs, [logs]);

  if (!isAdmin) {
    return (
      <div className="py-12">
        <EmptyState
          icon={Lock}
          title="Administrator Access Required"
          description="This panel is restricted to active Administrators. User management and audit logs are protected by server-side RLS policies and Edge Function authorization."
        />
      </div>
    );
  }

  function openCreateUser() {
    setEditingUser(null);
    setUserErrors({});
    setFormName("");
    setFormEmail("");
    setFormPassword("");
    setFormRole("supervisor");
    setFormStatus("active");
    setUserModalOpen(true);
  }

  function openEditUser(target: UserProfile) {
    setEditingUser(target);
    setUserErrors({});
    setFormName(target.name);
    setFormEmail(target.email);
    setFormPassword("");
    setFormRole(target.role);
    setFormStatus(target.status);
    setUserModalOpen(true);
  }

  async function handleSaveUser(e: React.FormEvent) {
    e.preventDefault();
    if (editingUser) {
      const parsed = adminUpdateUserSchema.safeParse({
        name: formName,
        role: formRole,
        status: formStatus,
      });
      if (!parsed.success) {
        setUserErrors(extractFieldErrors(parsed.error));
        return;
      }
      setUserErrors({});
      setSavingUser(true);
      try {
        await adminUpdateUser({
          userId: editingUser.id,
          name: parsed.data.name,
          role: parsed.data.role,
          status: parsed.data.status,
        });
        toast.success("User profile updated.");
        setUserModalOpen(false);
        await loadDashboard();
      } catch (err) {
        toast.error(getErrorMessage(err, "User management action failed."));
      } finally {
        setSavingUser(false);
      }
      return;
    }

    const parsed = adminCreateUserSchema.safeParse({
      name: formName,
      email: formEmail,
      password: formPassword,
      role: formRole,
      status: formStatus,
    });
    if (!parsed.success) {
      setUserErrors(extractFieldErrors(parsed.error));
      return;
    }
    setUserErrors({});
    setSavingUser(true);
    try {
      await adminCreateUser(parsed.data);
      toast.success("User account created successfully.");
      setUserModalOpen(false);
      await loadDashboard();
    } catch (err) {
      toast.error(getErrorMessage(err, "User management action failed."));
    } finally {
      setSavingUser(false);
    }
  }

  async function handleToggleStatus(target: UserProfile) {
    const nextStatus: AccountStatus =
      target.status === "active" ? "disabled" : "active";
    if (target.id === user?.id && nextStatus === "disabled") {
      toast.error("Administrators cannot disable their own active account.");
      return;
    }
    try {
      await adminToggleUserStatus(target, nextStatus);
      toast.success(
        `${target.name || target.email} ${nextStatus === "active" ? "enabled" : "disabled"}.`
      );
      await loadDashboard();
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to change account status."));
    }
  }

  async function confirmDeleteUser() {
    if (!userToDelete) return;
    if (userToDelete.id === user?.id) {
      toast.error("Administrators cannot delete their own account.");
      setUserToDelete(null);
      return;
    }
    setDeletingUser(true);
    try {
      await adminDeleteUser(userToDelete);
      toast.success("User deleted successfully.");
      setUserToDelete(null);
      await loadDashboard();
    } catch (err) {
      toast.error(getErrorMessage(err, "Failed to delete user."));
    } finally {
      setDeletingUser(false);
    }
  }

  return (
    <div>
      <PageHeader
        title="Administration & Audit Control"
        description="Manage staff accounts via the server-verified admin-manage-user Edge Function and inspect immutable audit logs."
        actions={
          <>
            <Button variant="outline" size="sm" onClick={loadDashboard} loading={loading}>
              <RefreshCw className="h-3.5 w-3.5" />
              Refresh
            </Button>
            <Button size="sm" onClick={openCreateUser}>
              <UserPlus className="h-4 w-4" />
              Add User
            </Button>
          </>
        }
      />

      {error && <ErrorBanner message={error} onRetry={loadDashboard} />}

      {/* Admin Stats */}
      <div className="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <StatCard
          label="Total Users"
          value={stats.totalUsers}
          subtitle={`${stats.activeUsers} active accounts`}
          icon={Users}
          tone="blue"
        />
        <StatCard
          label="Active Sites"
          value={stats.activeSites}
          subtitle="Operational projects"
          icon={ShieldCheck}
          tone="emerald"
        />
        <StatCard
          label="Catalog Items"
          value={stats.materials}
          subtitle="Tracked materials"
          icon={Activity}
          tone="slate"
        />
        <StatCard
          label="Today's Attendance"
          value={stats.todayAttendance}
          subtitle="Logged staff entries"
          icon={Activity}
          tone="amber"
        />
      </div>

      {/* Tabs */}
      <div className="mb-5 flex gap-2 border-b border-slate-200 pb-3">
        <button
          type="button"
          onClick={() => setTab("users")}
          className={`inline-flex items-center gap-2 rounded-lg px-4 py-2 text-xs font-semibold transition-colors cursor-pointer ${
            tab === "users"
              ? "bg-[#0B1628] text-white"
              : "border border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
          }`}
        >
          <Users className="h-3.5 w-3.5" />
          User Management ({profiles.length})
        </button>
        <button
          type="button"
          onClick={() => setTab("logs")}
          className={`inline-flex items-center gap-2 rounded-lg px-4 py-2 text-xs font-semibold transition-colors cursor-pointer ${
            tab === "logs"
              ? "bg-[#0B1628] text-white"
              : "border border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
          }`}
        >
          <Activity className="h-3.5 w-3.5" />
          Activity Audit Log ({filteredLogs.length})
        </button>
      </div>

      {/* TAB 1: User Management */}
      {tab === "users" && (
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Staff Accounts &amp; Roles</CardTitle>
              <CardDescription>
                All mutations execute server-side through{" "}
                <code>admin-manage-user</code>. Direct client writes to{" "}
                <code>user_profiles</code> are blocked by PostgreSQL grants.
              </CardDescription>
            </div>
          </CardHeader>
          <CardContent className="p-0">
            {loading ? (
              <div className="p-5">
                <LoadingTable rows={4} />
              </div>
            ) : profiles.length === 0 ? (
              <p className="p-8 text-center text-xs text-slate-500">
                No user profiles found.
              </p>
            ) : (
              <>
                {/* Desktop Table */}
                <div className="hidden overflow-x-auto md:block">
                  <table className="w-full text-left text-sm">
                    <thead className="border-b border-slate-200 bg-slate-50 text-xs font-semibold uppercase text-slate-500">
                      <tr>
                        <th className="px-5 py-3">User</th>
                        <th className="px-5 py-3">Role</th>
                        <th className="px-5 py-3">Status</th>
                        <th className="px-5 py-3 text-right">Actions</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-slate-100">
                      {profiles.map((p) => {
                        const isSelf = p.id === user?.id;
                        return (
                          <tr key={p.id} className="hover:bg-slate-50/70">
                            <td className="px-5 py-3.5">
                              <div className="font-semibold text-slate-900">
                                {p.name || "Unnamed User"}{" "}
                                {isSelf && (
                                  <Badge variant="neutral" className="ml-1">
                                    You
                                  </Badge>
                                )}
                              </div>
                              <div className="text-xs text-slate-500">{p.email}</div>
                            </td>
                            <td className="px-5 py-3.5">
                              <Badge variant={p.role === "admin" ? "navy" : "blue"}>
                                {formatRoleLabel(p.role)}
                              </Badge>
                            </td>
                            <td className="px-5 py-3.5">
                              <StatusBadge status={p.status} />
                            </td>
                            <td className="px-5 py-3.5 text-right">
                              <div className="inline-flex items-center gap-1.5">
                                <Button
                                  variant="outline"
                                  size="sm"
                                  onClick={() => openEditUser(p)}
                                >
                                  <Pencil className="h-3.5 w-3.5" />
                                  Edit
                                </Button>
                                {!isSelf && (
                                  <>
                                    <Button
                                      variant="outline"
                                      size="sm"
                                      onClick={() => handleToggleStatus(p)}
                                    >
                                      <Power className="h-3.5 w-3.5" />
                                      {p.status === "active" ? "Disable" : "Enable"}
                                    </Button>
                                    <Button
                                      variant="ghost"
                                      size="icon"
                                      onClick={() => setUserToDelete(p)}
                                      title="Delete user"
                                    >
                                      <Trash2 className="h-4 w-4 text-red-600" />
                                    </Button>
                                  </>
                                )}
                              </div>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                </div>

                {/* Mobile Cards */}
                <div className="divide-y divide-slate-100 md:hidden">
                  {profiles.map((p) => {
                    const isSelf = p.id === user?.id;
                    return (
                      <div key={p.id} className="p-4">
                        <div className="flex items-start justify-between gap-2">
                          <div className="min-w-0">
                            <p className="truncate text-sm font-semibold text-slate-900">
                              {p.name || "Unnamed User"}{" "}
                              {isSelf && (
                                <Badge variant="neutral" className="ml-1">
                                  You
                                </Badge>
                              )}
                            </p>
                            <p className="truncate text-xs text-slate-500">
                              {p.email}
                            </p>
                          </div>
                          <StatusBadge status={p.status} />
                        </div>
                        <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
                          <Badge variant={p.role === "admin" ? "navy" : "blue"}>
                            {formatRoleLabel(p.role)}
                          </Badge>
                          <div className="flex items-center gap-1.5">
                            <Button
                              variant="outline"
                              size="sm"
                              onClick={() => openEditUser(p)}
                            >
                              <Pencil className="h-3.5 w-3.5" />
                              Edit
                            </Button>
                            {!isSelf && (
                              <>
                                <Button
                                  variant="outline"
                                  size="sm"
                                  onClick={() => handleToggleStatus(p)}
                                >
                                  <Power className="h-3.5 w-3.5" />
                                  {p.status === "active" ? "Disable" : "Enable"}
                                </Button>
                                <Button
                                  variant="ghost"
                                  size="icon"
                                  onClick={() => setUserToDelete(p)}
                                  title="Delete user"
                                >
                                  <Trash2 className="h-4 w-4 text-red-600" />
                                </Button>
                              </>
                            )}
                          </div>
                        </div>
                      </div>
                    );
                  })}
                </div>
              </>
            )}
          </CardContent>
        </Card>
      )}

      {/* TAB 2: Activity Audit Log */}
      {tab === "logs" && (
        <Card>
          <CardHeader>
            <div>
              <CardTitle>Immutable Activity Audit Log</CardTitle>
              <CardDescription>
                Tamper-evident log — client UPDATE and DELETE are permanently disabled
              </CardDescription>
            </div>
            <Button
              variant="outline"
              size="sm"
              onClick={() => exportActivityLogPdf(filteredLogs)}
              disabled={filteredLogs.length === 0}
            >
              <FileDown className="h-3.5 w-3.5" />
              Export PDF
            </Button>
          </CardHeader>
          <CardContent>
            <div className="mb-4 grid grid-cols-1 gap-3 sm:grid-cols-3">
              <div className="relative">
                <Search className="pointer-events-none absolute top-1/2 left-3 h-4 w-4 -translate-y-1/2 text-slate-400" />
                <input
                  type="text"
                  value={logSearch}
                  onChange={(e) => setLogSearch(e.target.value)}
                  placeholder="Search action, user, description…"
                  className="h-10 w-full rounded-lg border border-slate-300 bg-white pr-3 pl-9 text-sm text-slate-900 focus:border-[#2563EB] focus:outline-none"
                />
              </div>
              <Input
                type="date"
                aria-label="From date"
                value={fromDate}
                onChange={(e) => setFromDate(e.target.value)}
              />
              <Input
                type="date"
                aria-label="To date"
                value={toDate}
                onChange={(e) => setToDate(e.target.value)}
              />
            </div>

            <div className="mb-4 flex flex-wrap gap-1.5">
              {LOG_MODULES.map((mod) => (
                <button
                  key={mod}
                  type="button"
                  onClick={() => setLogModule(mod)}
                  className={`rounded-md px-2.5 py-1 text-xs font-medium transition-colors cursor-pointer ${
                    logModule === mod
                      ? "bg-[#2563EB] text-white"
                      : "border border-slate-200 bg-white text-slate-600 hover:bg-slate-50"
                  }`}
                >
                  {mod}
                </button>
              ))}
            </div>

            {filteredLogs.length === 0 ? (
              <p className="py-10 text-center text-xs text-slate-500">
                No audit log entries match the selected filters.
              </p>
            ) : (
              <div className="divide-y divide-slate-100 rounded-lg border border-slate-200">
                {filteredLogs.map((log) => (
                  <div
                    key={log.id}
                    className="flex flex-col justify-between gap-2 px-4 py-3 sm:flex-row sm:items-center"
                  >
                    <div className="min-w-0">
                      <div className="flex flex-wrap items-center gap-2">
                        <Badge variant="blue">{log.module}</Badge>
                        <span className="text-sm font-semibold text-slate-900">
                          {log.action}
                        </span>
                      </div>
                      {log.description && (
                        <p className="mt-1 text-xs text-slate-600">
                          {log.description}
                        </p>
                      )}
                      <p className="mt-0.5 text-[11px] text-slate-400">
                        {log.user_name || "Unknown"}
                      </p>
                    </div>
                    <span className="shrink-0 text-xs text-slate-400">
                      {formatDisplayDateTime(log.created_at)}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
      )}

      {/* Create / Edit User Modal */}
      <Modal
        open={userModalOpen}
        onClose={() => setUserModalOpen(false)}
        title={editingUser ? "Edit User Account" : "Create Staff Account"}
        description="Executed securely on the server via admin-manage-user."
      >
        <form onSubmit={handleSaveUser} className="space-y-4">
          <Input
            label="Full Name *"
            required
            error={userErrors.name}
            value={formName}
            onChange={(e) => setFormName(e.target.value)}
            placeholder="e.g., Karthik Raja"
          />
          {!editingUser && (
            <>
              <Input
                label="Email Address *"
                type="email"
                required
                error={userErrors.email}
                value={formEmail}
                onChange={(e) => setFormEmail(e.target.value)}
                placeholder="name@tsrbuilders.com"
              />
              <Input
                label="Initial Password (min 8 chars) *"
                type="password"
                required
                minLength={8}
                error={userErrors.password}
                value={formPassword}
                onChange={(e) => setFormPassword(e.target.value)}
                placeholder="Minimum 8 characters"
              />
            </>
          )}
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
            <Select
              label="Role *"
              value={formRole}
              onChange={(e) => setFormRole(e.target.value as AppRole)}
            >
              <option value="supervisor">Site Supervisor</option>
              <option value="projectManager">Project Manager</option>
              <option value="admin">Administrator</option>
            </Select>
            <Select
              label="Account Status *"
              value={formStatus}
              onChange={(e) => setFormStatus(e.target.value as AccountStatus)}
            >
              <option value="active">Active</option>
              <option value="disabled">Disabled</option>
            </Select>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setUserModalOpen(false)}>
              Cancel
            </Button>
            <Button type="submit" loading={savingUser}>
              {editingUser ? "Update User" : "Create User"}
            </Button>
          </div>
        </form>
      </Modal>

      <ConfirmDialog
        open={Boolean(userToDelete)}
        onClose={() => setUserToDelete(null)}
        onConfirm={confirmDeleteUser}
        loading={deletingUser}
        title="Permanently Delete User"
        description={`Delete ${userToDelete?.name || userToDelete?.email || "this user"}? This permanently removes both their Supabase Auth login account and user_profiles record via the admin-manage-user Edge Function.`}
        confirmLabel="Delete User"
      />
    </div>
  );
}

