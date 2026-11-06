import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return Response.json({ error: 'Method not allowed' }, { status: 405, headers: cors });
  const apiKey = Deno.env.get('RESEND_API_KEY');
  const to = Deno.env.get('INQUIRY_NOTIFICATION_TO');
  const from = Deno.env.get('INQUIRY_NOTIFICATION_FROM');
  if (!apiKey || !to || !from) return Response.json({ error: 'Email delivery is not configured' }, { status: 503, headers: cors });
  try {
    const body = await req.json();
    let subject: string;
    let recipients = [to];
    let html: string;
    if (body?.type === 'quote_sent') {
      const authorization = req.headers.get('Authorization');
      const supabaseUrl = Deno.env.get('SUPABASE_URL');
      const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
      if (!authorization || !supabaseUrl || !anonKey || typeof body.quotation_id !== 'string') {
        return Response.json({ error: 'Invalid quotation notification' }, { status: 400, headers: cors });
      }
      const client = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } } });
      const { data: { user }, error: authError } = await client.auth.getUser();
      if (authError || !user) return Response.json({ error: 'Authentication required' }, { status: 401, headers: cors });
      const { data: profile } = await client.from('profiles').select('role').eq('id', user.id).single();
      if (profile?.role !== 'admin') return Response.json({ error: 'Administrator role required' }, { status: 403, headers: cors });
      const { data: quotation, error } = await client.from('quotations').select('quote_number,currency,total_amount,valid_until,inquiries(name,email,company,service)').eq('id', body.quotation_id).single();
      if (error || !quotation) return Response.json({ error: 'Quotation not found' }, { status: 404, headers: cors });
      const inquiry = quotation.inquiries as { name: string; email: string; company: string; service: string } | null;
      if (!inquiry?.email) return Response.json({ error: 'This inquiry has no customer email' }, { status: 422, headers: cors });
      recipients = [inquiry.email];
      subject = `PipeMaster quotation ${quotation.quote_number}`;
      html = `<h2>Your PipeMaster quotation is ready</h2><p>Hello ${escapeHtml(inquiry.name)},</p><p>Quotation <b>${escapeHtml(quotation.quote_number)}</b> for ${escapeHtml(inquiry.service)} is available in your client portal.</p><p><b>Total:</b> ${escapeHtml(quotation.currency)} ${Number(quotation.total_amount).toLocaleString()}${quotation.valid_until ? `<br><b>Valid until:</b> ${escapeHtml(quotation.valid_until)}` : ''}</p><p>Sign in to review the quotation and accept or decline it.</p>`;
    } else {
      if (typeof body?.inquiry_id !== 'string' || typeof body?.name !== 'string' || typeof body?.email !== 'string') {
        return Response.json({ error: 'Invalid inquiry notification' }, { status: 400, headers: cors });
      }
      subject = `New PipeMaster ${body.kind === 'quote' ? 'quote request' : 'inquiry'} — ${body.company || body.name}`;
      html = `<h2>New PipeMaster ${body.kind === 'quote' ? 'quote request' : 'inquiry'}</h2><p><b>Contact:</b> ${escapeHtml(body.name)} (${escapeHtml(body.email)})</p><p><b>Company:</b> ${escapeHtml(String(body.company || 'Not provided'))}</p><p><b>Inquiry ID:</b> ${escapeHtml(body.inquiry_id)}</p><p>Review the request in the PipeMaster admin portal.</p>`;
    }
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from, to: recipients, subject, html }),
    });
    if (!response.ok) return Response.json({ error: 'Email provider rejected the notification' }, { status: 502, headers: cors });
    return Response.json({ sent: true }, { headers: cors });
  } catch {
    return Response.json({ error: 'Unable to process notification' }, { status: 400, headers: cors });
  }
});

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (character) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character] || character);
}
