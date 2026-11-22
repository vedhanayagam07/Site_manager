# TSR Builders — Web Application (Next.js App Router)

Enterprise construction operations web platform migrated from the existing Flutter app (`site_manager_pro/lib`) while preserving the existing Supabase database, authentication, Edge Functions, and Row Level Security (RLS) policies.

## Preserved Backend Architecture
- Connects directly to the existing TSR Builders Supabase project via `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`.
- **Never** embeds `SUPABASE_SERVICE_ROLE_KEY` in client code.
- All user management mutations execute server-side through the existing `admin-manage-user` Supabase Edge Function.
- Respects existing RLS policies across all 8 tables (`sites`, `workers`, `site_attendance`, `materials`, `material_transactions`, `loading_memos`, `activity_logs`, `user_profiles`).
- Original Flutter project in `../lib` remains completely intact.

## Local Development

```bash
cd web-app
npm install
cp .env.example .env.local # Fill NEXT_PUBLIC_SUPABASE_URL and NEXT_PUBLIC_SUPABASE_ANON_KEY
npm run dev
```

Open http://localhost:3000 in your browser.

## Production Build & Typecheck

```bash
npm run typecheck
npm run build
npm run start
```

## Optional Additive Migration: Daily Workforce Category Counts
To enable saving daily temporary labourer headcounts (e.g., Masons: 3, Helpers: 5, Carpenters: 2, Electricians: 1) without altering existing `site_attendance` or `workers` records, review and run:

- `../supabase/migrations/20261118_daily_workforce_counts_PROPOSAL.sql`

## Deployment (Vercel / Self-Hosted Node)
1. Set root directory to `web-app`.
2. Configure environment variables:
   - `NEXT_PUBLIC_SUPABASE_URL`
   - `NEXT_PUBLIC_SUPABASE_ANON_KEY`
3. Build command: `npm run build`
4. Ensure your Supabase project's **Authentication → URL Configuration** includes your deployed web domain in Site URL / Redirect URLs.

