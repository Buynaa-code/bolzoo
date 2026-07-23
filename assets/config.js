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
  supabaseUrl: 'https://bhcjaemcrqyfhjejotcg.supabase.co',
  supabaseAnonKey: 'sb_publishable_Ft9Zjy4AvQ1ww6BTuMsWkg_SSPphUTc'
};
