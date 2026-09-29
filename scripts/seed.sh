#!/usr/bin/env bash
# =============================================================
#  seed.sh - Mengisi konten contoh ke Directus lewat REST API
#
#  Membuat:
#     - Koleksi "categories" (Kategori)
#     - Koleksi "articles"   (Artikel) + relasi ke kategori
#     - Beberapa data contoh
#     - Izin publik: siapa pun boleh MEMBACA artikel & kategori
#       (Catatan: filter "hanya published" di level izin butuh lisensi Directus 12,
#        jadi di tier Core filter dilakukan di sisi frontend: ?filter[status][_eq]=published)
#
#  Pemakaian:
#     ./scripts/seed.sh                         # pakai PUBLIC_URL & admin dari .env
#     URL=http://localhost:8055 ./scripts/seed.sh
#  Butuh: curl, jq
# =============================================================
set -euo pipefail

cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
. ./.env

URL="${URL:-$PUBLIC_URL}"
command -v jq >/dev/null || { echo "Butuh jq: sudo apt install -y jq"; exit 1; }

echo "==> Login sebagai ${ADMIN_EMAIL} ke ${URL}"
TOKEN="$(curl -fsS -X POST "$URL/auth/login" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg e "$ADMIN_EMAIL" --arg p "$ADMIN_PASSWORD" '{email:$e,password:$p}')" \
  | jq -r '.data.access_token')"

api() { # api METHOD PATH [JSON]
  curl -fsS -X "$1" "$URL$2" -H "Authorization: Bearer $TOKEN" \
       -H 'Content-Type: application/json' ${3:+-d "$3"}
}

if api GET /collections/articles >/dev/null 2>&1; then
  echo "Koleksi 'articles' sudah ada. Seed dilewati."; exit 0
fi

echo "==> Mengatur nama & warna proyek"
api PATCH /settings '{"project_name":"Asqara CMS","project_descriptor":"Headless CMS","project_color":"#6644FF","default_language":"id-ID"}' >/dev/null

echo "==> Membuat koleksi categories"
api POST /collections '{
  "collection": "categories",
  "meta": {"icon": "label", "note": "Kategori artikel", "display_template": "{{name}}",
           "translations": [{"language":"id-ID","translation":"Kategori"}]},
  "schema": {},
  "fields": [
    {"field":"id","type":"integer","meta":{"hidden":true,"readonly":true},
     "schema":{"is_primary_key":true,"has_auto_increment":true}},
    {"field":"name","type":"string","meta":{"interface":"input","required":true,"width":"half"}},
    {"field":"slug","type":"string","meta":{"interface":"input","width":"half","options":{"slug":true}},
     "schema":{"is_unique":true}}
  ]
}' >/dev/null

echo "==> Membuat koleksi articles"
api POST /collections '{
  "collection": "articles",
  "meta": {"icon": "article", "note": "Artikel / berita website", "display_template": "{{title}}",
           "archive_field":"status","archive_value":"archived","unarchive_value":"draft",
           "sort_field": null,
           "translations": [{"language":"id-ID","translation":"Artikel"}]},
  "schema": {},
  "fields": [
    {"field":"id","type":"integer","meta":{"hidden":true,"readonly":true},
     "schema":{"is_primary_key":true,"has_auto_increment":true}},
    {"field":"status","type":"string","schema":{"default_value":"draft","is_nullable":false},
     "meta":{"interface":"select-dropdown","width":"half","display":"labels",
       "options":{"choices":[
         {"text":"Published","value":"published","color":"#2ECDA7"},
         {"text":"Draft","value":"draft","color":"#A2B5CD"},
         {"text":"Archived","value":"archived","color":"#F7971C"}]},
       "display_options":{"showAsDot":true,"choices":[
         {"text":"Published","value":"published","foreground":"#FFFFFF","background":"#2ECDA7"},
         {"text":"Draft","value":"draft","foreground":"#18222F","background":"#D3DAE4"},
         {"text":"Archived","value":"archived","foreground":"#FFFFFF","background":"#F7971C"}]}}},
    {"field":"date_created","type":"timestamp",
     "meta":{"special":["date-created"],"interface":"datetime","readonly":true,"width":"half","display":"datetime","display_options":{"relative":true}}},
    {"field":"title","type":"string","meta":{"interface":"input","required":true,"width":"full"}},
    {"field":"slug","type":"string","meta":{"interface":"input","width":"half","options":{"slug":true}},
     "schema":{"is_unique":true}},
    {"field":"category","type":"integer","meta":{"interface":"select-dropdown-m2o","special":["m2o"],"width":"half",
       "display":"related-values","display_options":{"template":"{{name}}"},"options":{"template":"{{name}}"}}},
    {"field":"summary","type":"text","meta":{"interface":"input-multiline","width":"full"}},
    {"field":"content","type":"text","meta":{"interface":"input-rich-text-html","width":"full"}}
  ]
}' >/dev/null

echo "==> Membuat relasi articles.category -> categories"
api POST /relations '{"collection":"articles","field":"category","related_collection":"categories",
  "schema":{"on_delete":"SET NULL"}}' >/dev/null

echo "==> Mengisi data kategori"
api POST /items/categories '[
  {"name":"Teknologi","slug":"teknologi"},
  {"name":"Tutorial","slug":"tutorial"},
  {"name":"Pengumuman","slug":"pengumuman"}
]' >/dev/null

echo "==> Mengisi data artikel"
api POST /items/articles '[
  {"status":"published","title":"Selamat Datang di CMS Asqara","slug":"selamat-datang",
   "category":3,"summary":"CMS baru berbasis Directus kini resmi berjalan di cms.asqara.tech.",
   "content":"<p>Mulai hari ini seluruh konten website dikelola melalui <strong>Directus</strong>. Konten dapat diakses melalui REST API maupun GraphQL.</p>"},
  {"status":"published","title":"Apa Itu Headless CMS?","slug":"apa-itu-headless-cms",
   "category":1,"summary":"Memisahkan pengelolaan konten dari tampilan website.",
   "content":"<p><em>Headless CMS</em> hanya mengurus penyimpanan dan pengelolaan konten, lalu menyajikannya lewat API. Tampilan (frontend) bebas dibuat dengan Next.js, Nuxt, Flutter, atau apa pun.</p>"},
  {"status":"published","title":"Mengambil Data Directus dengan fetch()","slug":"fetch-data-directus",
   "category":2,"summary":"Contoh singkat memanggil API Directus dari JavaScript.",
   "content":"<pre><code>const res = await fetch(\"https://cms.asqara.tech/items/articles\");\nconst { data } = await res.json();</code></pre>"},
  {"status":"draft","title":"Rencana Fitur Berikutnya (Draft)","slug":"rencana-fitur",
   "category":3,"summary":"Artikel ini masih draft, frontend hanya menampilkan yang berstatus published.",
   "content":"<p>Draft internal.</p>"}
]' >/dev/null

echo "==> Memberi izin baca publik"
PUBLIC_POLICY="$(api GET '/access?filter%5Brole%5D%5B_null%5D=true&filter%5Buser%5D%5B_null%5D=true&fields=policy' \
  | jq -r '.data[0].policy')"
api POST /permissions "$(jq -n --arg p "$PUBLIC_POLICY" '[
  {policy:$p, collection:"articles",   action:"read", fields:["*"]},
  {policy:$p, collection:"categories", action:"read", fields:["*"]}
]')" >/dev/null

echo
echo "Seed selesai! Coba buka:"
echo "   $URL/items/articles?fields=title,summary,category.name&filter[status][_eq]=published"
