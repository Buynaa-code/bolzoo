/**
 * Bolzoo backend config.
 *
 * Хоосон үлдээвэл app localStorage-д fallback хийнэ (backend байхгүй ажиллана).
 * Supabase project үүсгэсний дараа доорх утгуудыг бөглөнө:
 *
 *   1. https://supabase.com  → New project
 *   2. Settings → API → URL болон anon/public key-г хуулаад доор тавь
 *   3. SQL editor руу орж sql/schema.sql-ийг ажиллуулах
 */
window.BOLZOO_CONFIG = {
  supabaseUrl: 'https://chmxjljudmwttwhemdri.supabase.co',
  supabaseAnonKey: 'sb_publishable_arrXY92vzLxUIKrb5SKenQ_fM7Y7vKR'
};
