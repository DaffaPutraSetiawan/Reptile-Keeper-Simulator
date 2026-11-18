// Konfigurasi MorphLab.
// Isi dua nilai di bawah dari Supabase Dashboard → Project Settings → API Keys.
// Publishable key (sb_publishable_...) memang aman untuk ditaruh di kode publik;
// yang melindungi data adalah Row Level Security di supabase/schema.sql.
// JANGAN PERNAH menaruh secret key (sb_secret_...) atau service_role key di sini.
// Kalau dibiarkan kosong, game tetap jalan dalam mode offline (save lokal saja).
window.MORPHLAB_CONFIG = {
  supabaseUrl: '',            // contoh: 'https://abcdefghijklm.supabase.co'
  supabasePublishableKey: ''  // contoh: 'sb_publishable_xxxxxxxxxxxxxxxx'
};
