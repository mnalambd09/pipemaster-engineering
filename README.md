# PipeMaster Engineering

PipeMaster is a responsive React + Vite + TypeScript website for an industrial piping contractor. The application includes public company pages, a service and project catalog, project galleries, inquiry and quotation forms, customer accounts, and an administrator workspace. It lives at the workspace root; existing sibling project folders are unchanged.

## Requirements

- Node.js 20.19+ or 22.12+
- npm 10+
- A Supabase project for authentication, persistent forms, private file storage, customer/admin portal actions, newsletter records, and content management

## Run locally

```bash
npm install
Copy-Item .env.example .env.local
npm run dev
```

The public pages work without credentials and use fictional sample company content. Form submissions, newsletter persistence, accounts, uploads, customer portal and admin actions require a configured Supabase project. Forms explain when the backend is unavailable; the app does not pretend that an offline submission was saved.

Useful commands:

```bash
npm run typecheck
npm run build
npm run preview
```

## Supabase setup

1. Create a Supabase project and copy its Project URL and publishable/anon key into `.env.local` as `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. Only the publishable key belongs in the browser. Never add a service-role key to a Vite variable.
2. Install the Supabase CLI, then run these commands from this project directory:

   ```bash
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   ```

   The migrations create the requested relational tables, indexes, private inquiry storage, public project-media storage, RLS policies and sample services, projects, team members and posts. The SQL is safe to apply repeatedly for its seed records.
3. In Supabase Auth, keep email confirmation enabled and configure an SMTP provider before allowing real customer registration. Add your production site and callback URLs under Auth URL Configuration.
4. Register your own account through `/register`. Promote that account to the first administrator in the SQL editor, using its verified auth UUID:

   ```sql
   update public.profiles set role = 'admin' where id = 'YOUR_AUTH_USER_UUID';
   ```

   Role changes are deliberately unavailable through the browser. The role guard trigger and RLS policies prevent customer self-promotion.
5. The `inquiry-files` bucket is private. Customer and administrator downloads use short-lived signed URLs. `project-media` is public so published portfolio images can be served by the website; uploads require an administrator session.
6. To send notification emails, deploy the included Edge Function and configure its secrets:

   ```bash
   supabase functions deploy notify-inquiry
   supabase secrets set RESEND_API_KEY=re_... INQUIRY_NOTIFICATION_TO=projects@yourdomain.com INQUIRY_NOTIFICATION_FROM='PipeMaster <notifications@yourdomain.com>'
   ```

   Inquiry notifications go to the configured company address. When an admin marks a quotation as sent, the function verifies the caller's admin role, looks up the associated customer, and sends a portal notification. Email delivery is not active until the function and a verified Resend sender are configured and tested.

### Data access and roles

- Anonymous visitors can submit contact/quote inquiries and newsletter signups. Public reads are limited to active services, published projects/posts, active testimonials/team, and public settings.
- Customers can read their own profile, inquiries, quotations, messages, visible project updates and inquiry files. They can update profile fields and accept/reject a sent quotation; database triggers prevent changes to quote amounts or roles.
- Administrators are identified by `profiles.role='admin'`; RLS controls access to inquiries, customer records, quotation creation, project updates, content and settings.
- Never disable RLS on exposed tables. Keep the Supabase service-role key and email provider key server-side.

## Integrations and configuration

Set optional public values in `.env.local`:

```env
VITE_COMPANY_EMAIL=projects@yourdomain.com
VITE_COMPANY_PHONE=+1 713 555 0148
VITE_WHATSAPP_NUMBER=17135550148
VITE_COMPANY_ADDRESS=Houston, Texas, United States
VITE_SITE_URL=https://your-domain.example
```

The WhatsApp button appears only when `VITE_WHATSAPP_NUMBER` is set in international digits without a `+`. The map embed uses the configured address. Google Maps, WhatsApp, external image hosting and email notifications should each be verified with the real business values before launch. Remote Unsplash imagery and sample projects are demonstration assets; replace them with approved PipeMaster photography and verified project information.

## Vercel deployment

1. Import the repository into Vercel and set the project root to this workspace directory.
2. Use the Vite defaults: `npm run build` and output directory `dist`. `vercel.json` rewrites client routes to the SPA entry point.
3. Add `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, company contact settings, WhatsApp number and site URL in the Vercel environment settings.
4. Apply Supabase migrations and deploy `notify-inquiry` independently. Configure Auth redirect URLs and SMTP for the Vercel domain.
5. Replace `pipemaster.example` in `public/robots.txt` and `public/sitemap.xml` with the final domain. Confirm social metadata, business details, image rights, actual certifications and project approvals before publication.

## Included routes

`/`, `/about`, `/services`, `/services/:slug`, `/projects`, `/projects/:slug`, `/team`, `/certifications`, `/insights`, `/insights/:slug`, `/contact`, `/request-a-quote`, `/faq`, `/privacy`, `/terms`, `/register`, `/login`, `/portal`, `/admin`.

## Verification

`npm run typecheck` checks TypeScript and `npm run build` produces the deployable Vite bundle. The app was also reviewed locally across public routes and mobile/desktop layouts. Supabase authentication, row policies, storage, email delivery and database mutations require credentials and a live project; those external flows are not represented as tested here.
