/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string;
  readonly VITE_SUPABASE_ANON_KEY?: string;
  readonly VITE_COMPANY_EMAIL?: string;
  readonly VITE_COMPANY_PHONE?: string;
  readonly VITE_WHATSAPP_NUMBER?: string;
  readonly VITE_COMPANY_ADDRESS?: string;
  readonly VITE_SITE_URL?: string;
}
interface ImportMeta { readonly env: ImportMetaEnv }
