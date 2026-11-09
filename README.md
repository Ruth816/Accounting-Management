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

## QuickBooks Online (Phases 2 and 3)

Code: `lib/qbo.ts` (sign-in, list sync, posting), `lib/qboExpense.ts` (fund request → Expense, tested in `lib/qboExpense.test.ts`), `app/api/quickbooks/*` (sign-in), migration `20261109000004_quickbooks_online.sql`.

Set it up, sandbox first:

1. At [developer.intuit.com](https://developer.intuit.com), sign in, **Create an app** → *QuickBooks Online and Payments*, scope **com.intuit.quickbooks.accounting**.
2. In the app's **Development → Keys & credentials**, add the Redirect URI `https://<your site>/api/quickbooks/callback` (for example `https://aspencom-finance.app/api/quickbooks/callback`).
3. In Vercel, add `QBO_CLIENT_ID`, `QBO_CLIENT_SECRET` (the Development keys), `QBO_ENVIRONMENT=sandbox` and a long random `QBO_TOKEN_KEY`, then redeploy.
4. In the portal, **Admin → QuickBooks Online → Connect to QuickBooks**, and pick the sandbox company. The dropdown lists sync straight away.
5. When it works, get the **Production** keys (Intuit asks for an app questionnaire, and privacy policy and terms links), add the same Redirect URI under Production, change the three QBO variables to the production values, redeploy, **Disconnect** and **Connect** again with the real company.

How it works:

- **Lists (Phase 2):** categories (Expense, Other Expense and Cost of Goods Sold accounts), payment accounts (Bank, Credit Card and Other Current Asset accounts), payment methods and purchase tax codes come from QuickBooks every morning and on **Sync lists now**. Values QuickBooks no longer has are hidden, not deleted.
- **Expenses (Phase 3):** the existing **Export to QuickBooks** / **Ready to import to QuickBooks** buttons create the Expense in QuickBooks once the request is funded: payee (found as a vendor, customer or employee, or added as a vendor), payment account and method, Ref no. as the reference number, memo, one line per item with its category and tax code (VAT-inclusive), the bank transfer fee as an extra *BANK CHARGES:Transfer & MC Fees* line with *No VAT (0%)*, and the attachments. The QuickBooks ID is stored and the request is locked.
- **Errors:** the request goes to **Sync Failed** with QuickBooks' reason, the Fund Approver and Admins are notified, and exporting again retries. A retry first looks for an Expense with the same Ref no. and total, so it never creates a duplicate.
- Without a connection, the buttons only mark requests as exported, as before.
- The sign-in tokens are stored encrypted (`QBO_TOKEN_KEY`) in `qb_connection`, which only the server can read.
