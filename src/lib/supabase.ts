import { createClient } from '@supabase/supabase-js';
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;
export const supabase = url && key && !url.includes('YOUR_PROJECT') && !key.includes('YOUR_SUPABASE') ? createClient(url, key) : null;
export const isConfigured = Boolean(supabase);
export const uploadAllowed = (file:File) => {
  const allowed = ['application/pdf','image/png','image/jpeg','image/webp','application/acad','application/dxf','application/octet-stream'];
  const ext = file.name.split('.').pop()?.toLowerCase();
  return file.size <= 10 * 1024 * 1024 && (allowed.includes(file.type) || ['dwg','dxf'].includes(ext || ''));
};
export async function uploadInquiryFile(file:File, inquiryId:string) {
  if (!supabase) throw new Error('File storage requires a configured Supabase project.');
  if (!uploadAllowed(file)) throw new Error('Choose a PDF, DWG, DXF, PNG, JPG or WEBP file up to 10 MB.');
  const path = `${inquiryId}/${crypto.randomUUID()}-${file.name.replace(/[^a-zA-Z0-9._-]/g,'_')}`;
  const {error} = await supabase.storage.from('inquiry-files').upload(path,file,{contentType:file.type || 'application/octet-stream',upsert:false});
  if (error) throw error;
  const {error: rowError} = await supabase.from('inquiry_files').insert({inquiry_id:inquiryId,storage_path:path,file_name:file.name,mime_type:file.type || null,size_bytes:file.size});
  if (rowError) throw rowError;
}
export function notifyTeam(payload:Record<string,unknown>):Promise<{configured:boolean;sent:boolean}> {
  if (!supabase) return Promise.resolve({configured:false,sent:false});
  return supabase.functions.invoke('notify-inquiry',{body:payload}).then(({error})=>{
    if (error) return {configured:true,sent:false};
    return {configured:true,sent:true};
  });
}
