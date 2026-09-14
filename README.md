# La Tavola

A multi-restaurant Italian QR menu app built with React, TypeScript, Vite and Supabase.

## Backend setup

1. Create a Supabase project.
2. In the Supabase SQL Editor, run [`supabase/schema.sql`](supabase/schema.sql).
	Do this before signing in locally; the app will refuse to show a default restaurant if these tables are missing.
3. In Authentication > Providers, enable Email and keep **Confirm email** enabled.
4. Configure the project email provider. Supabase's default email service is for development; use custom SMTP for production delivery and rate limits.
5. Copy `.env.example` to `.env.local` and fill in the project URL and public anon key:

```env
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-public-key
VITE_PUBLIC_APP_URL=http://192.168.1.9:5173
```

Only the public anon key belongs in this frontend. Never put a Supabase service-role key in `.env.local` or browser code.

## Security model

- Supabase Auth handles password hashing, sessions, refresh tokens and email verification.
- Every restaurant row has an `owner_id` linked to `auth.users`.
- Row-level security policies prevent owners from reading or mutating another restaurant's menu, deal or orders.
- Public customers can read published menu data and create orders, but cannot read other customers' orders.
- Customer order status is exposed through the restricted `get_order_status(tracking_token)` function.

## Run locally

```bash
npm install
npm run dev
```

Then open `http://localhost:5173`.

## QR testing

The QR code uses the restaurant's real `menu_slug` and opens `/?restaurant=<slug>`.
For local testing, set `VITE_PUBLIC_APP_URL` to the computer's current LAN address, so the phone can reach the Vite server. The phone must be on the same Wi-Fi and Windows Firewall must allow port `5173`. In production, set this variable to the public HTTPS domain.

Without Supabase environment variables, the app intentionally refuses authentication. This prevents fake browser-only accounts from being used as production auth.

## Checks

```bash
npm run lint
npm run build
```
