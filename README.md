# Finance Approval Portal

Internal portal for payment and fund request approvals: Payment Requestor → Payment Approver → Fund Requestor (QuickBooks Expense format) → Fund Approver, with liquidation for cash requests, SMS notifications through OneWaySMS, a status tracker and an audit log.

- **Hosting:** Vercel (Next.js 16, App Router)
- **Database, sign-in, files:** Supabase (Postgres with row-level security, Supabase Auth, Storage)
- **Spec:** the Finance Approval Portal specification in the project (version 1.1)

## How it is built

| Part | Where |
| --- | --- |
| Tables, visibility rules (row-level security) | `supabase/migrations/20261020000001_schema.sql` |
| Every workflow step (submit, approve, receive, cheques, return, liquidation, 30-day expiry) | `supabase/migrations/20261020000002_workflow.sql` |
| Attachment storage bucket and rules | `supabase/migrations/20261020000003_storage.sql` |
| Phase 1 dropdown values | `supabase/seed.sql` |
| Pages | `app/(portal)/…` |
| Buttons → database calls | `app/actions.ts` |
| SMS sending | `lib/sms.ts` |
| Daily reminders and expiry | `app/api/cron/daily/route.ts`, scheduled in `vercel.json` |

The browser can only **read** through row-level security. Every change goes through a database function that checks who is acting and the request's status, so the rules hold even if someone calls the API directly (for example, nobody can approve their own request, and a requestor cannot open someone else's request by URL).

## Set it up

### 1. Supabase

1. Create a project at [supabase.com](https://supabase.com) (region: Singapore is closest to the Philippines).
2. In **SQL Editor**, run these files in order, each as a new query:
   `supabase/migrations/20261020000001_schema.sql`, `…0002_workflow.sql`, `…0003_storage.sql`, then `supabase/seed.sql`.
   (Or with the Supabase CLI: `npx supabase link` then `npx supabase db push`, and run `seed.sql` in the SQL Editor.)
3. **Authentication → Sign In / Providers → Email:** turn **off** "Allow new users to sign up". Accounts are created by an Admin inside the portal.
4. **Authentication → Users → Add user:** create your own account (tick auto-confirm), then make yourself Admin in the SQL Editor:
   ```sql
   update profiles set roles = '{admin}', full_name = 'Your Name' where email = 'you@company.com';
   ```
5. **Project Settings → API:** copy the Project URL, the `anon` key and the `service_role` key for step 2.

### 2. Vercel

1. **Add New → Project**, import this GitHub repository. The defaults (Next.js) are right.
2. Add the environment variables listed in `.env.example` (Project URL, anon key, service role key, OneWaySMS username/password/sender ID, and a long random `CRON_SECRET`).
3. Deploy. Then in Supabase **Authentication → URL Configuration**, set the Site URL to your Vercel address.

The two cron jobs in `vercel.json` run once a day (08:00 and 09:00 Manila): reminders on day 23 and 28 for returned requests, deletion on day 30, and sending any SMS still queued. SMS is otherwise sent right after each action.

### 3. In the portal

Sign in as the Admin, open **Admin**, add each person with a temporary password, then tick their roles, mobile number (09… is converted to 63…), default payment approver and default fund approver. Replace the sample dropdown lists with the real QuickBooks lists.

## Local development

```bash
npm install
cp .env.example .env.local   # fill in a Supabase project's values
npm run dev
```

Tests:

```bash
npm test                                   # amount, Ref no. and memo calculations
PSQL="psql -h localhost -U postgres" npm run test:db   # the spec's acceptance checks against the database rules
```

`test:db` needs a plain Postgres 15+; it creates a scratch database `finance_portal_test` with stand-ins for Supabase's `auth` and `storage` schemas.

## Choices made where the spec leaves things open

- **Liquidation** applies to Cash requests only (role table in spec section 2), and the Fund Requestor does not have to confirm it.
- **Auto debit** uses prefix 1, and a cheque is optional.
- **Expired** requests are deleted with their versions and files; an "Expired" line stays in the audit log with the request number.
- **Voucher PDF** uses the browser's Print / Save as PDF on the voucher page.
- A Ref no. used by a **cancelled** fund request can be used again.
- New accounts start with **no roles** until an Admin assigns them.

QuickBooks Online (Phases 2 and 3) is not built yet; approved fund requests stop at "Approved – Ready for QuickBooks".
