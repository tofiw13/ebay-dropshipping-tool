#!/usr/bin/env bash
set -e
echo "📦 magaza/ layihəsi yaradılır..."
mkdir -p magaza/public magaza/downloads
cd magaza

cat > package.json <<'EOF'
{
  "name": "reqemsal-magaza",
  "version": "1.0.0",
  "main": "server.js",
  "type": "commonjs",
  "scripts": { "start": "node server.js" },
  "engines": { "node": ">=18" },
  "dependencies": { "dotenv": "^16.4.5", "express": "^4.19.2", "stripe": "^14.25.0" }
}
EOF

cat > products.json <<'EOF'
[
  { "id": "cv-template", "name": "Professional CV / Rezüme Şablonu", "description": "ATS-uyğun, müasir dizaynlı CV şablonu (Word + Canva).", "price": 499, "currency": "usd", "emoji": "📄", "file": "cv-template.txt" },
  { "id": "notion-student", "name": "Tələbə Notion Planlayıcısı", "description": "Dərs cədvəli, tapşırıq izləyici, imtahan planlayıcı.", "price": 699, "currency": "usd", "emoji": "▪", "file": "notion-student.txt" },
  { "id": "budget-sheet", "name": "Şəxsi Büdcə Excel Şablonu", "description": "Avtomatik hesablamalı aylıq gəlir/xərc izləyici.", "price": 399, "currency": "usd", "emoji": "💰", "file": "budget-sheet.txt" },
  { "id": "instagram-pack", "name": "Instagram Post Şablon Dəsti (30 ədəd)", "description": "Canva-da redaktə oluna bilən 30 müasir post şablonu.", "price": 899, "currency": "usd", "emoji": "🎨", "file": "instagram-pack.txt" },
  { "id": "ebook-freelance", "name": "E-kitab: Sıfırdan Frilanser", "description": "Onlayn pul qazanmağın praktiki bələdçisi (PDF).", "price": 599, "currency": "usd", "emoji": "📖", "file": "ebook-freelance.txt" }
]
EOF

cat > server.js <<'EOF'
require('dotenv').config();
const express = require('express');
const path = require('path');
const crypto = require('crypto');
const fs = require('fs');
const app = express();
const PORT = process.env.PORT || 3000;
const PRODUCTS = JSON.parse(fs.readFileSync(path.join(__dirname, 'products.json'), 'utf8'));
const DOWNLOAD_SECRET = process.env.DOWNLOAD_SECRET || crypto.randomBytes(16).toString('hex');
const DOWNLOAD_TTL_MS = 24 * 60 * 60 * 1000;
const stripeKey = process.env.STRIPE_SECRET_KEY;
const stripe = stripeKey ? require('stripe')(stripeKey) : null;
const DEMO = !stripe;
if (DEMO) console.log('\x1b[33m%s\x1b[0m', 'DEMO REJIM: STRIPE_SECRET_KEY tapilmadi.');
else console.log('\x1b[32m%s\x1b[0m', 'Stripe aktivdir.');
app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));
function sign(d){return crypto.createHmac('sha256',DOWNLOAD_SECRET).update(d).digest('hex');}
function makeDownloadToken(id){const exp=Date.now()+DOWNLOAD_TTL_MS;const p=`${id}:${exp}`;return Buffer.from(`${p}:${sign(p)}`).toString('base64url');}
function verifyDownloadToken(t){try{const d=Buffer.from(t,'base64url').toString('utf8');const i=d.lastIndexOf(':');const p=d.slice(0,i);const s=d.slice(i+1);if(sign(p)!==s)return null;const[id,exp]=p.split(':');if(Date.now()>Number(exp))return null;return id;}catch{return null;}}
function makeOrderToken(ids){const exp=Date.now()+60*60*1000;const p=`${ids.join('|')}:${exp}`;return Buffer.from(`${p}:${sign(p)}`).toString('base64url');}
function verifyOrderToken(t){try{const d=Buffer.from(t,'base64url').toString('utf8');const i=d.lastIndexOf(':');const p=d.slice(0,i);const s=d.slice(i+1);if(sign(p)!==s)return null;const[ids,exp]=p.split(':');if(Date.now()>Number(exp))return null;return ids?ids.split('|'):[];}catch{return null;}}
app.get('/api/products',(req,res)=>res.json(PRODUCTS.map(({file,...pub})=>pub)));
app.post('/api/checkout',async(req,res)=>{try{const items=Array.isArray(req.body.items)?req.body.items:[];if(!items.length)return res.status(400).json({error:'Sebet bosdur.'});const lineItems=items.map((it)=>{const p=PRODUCTS.find((x)=>x.id===it.id);if(!p)throw new Error('Mehsul tapilmadi: '+it.id);return{quantity:Math.max(1,parseInt(it.qty,10)||1),price_data:{currency:p.currency,unit_amount:p.price,product_data:{name:p.name,description:p.description}}};});const base=`${req.protocol}://${req.get('host')}`;const ids=items.map((i)=>i.id);if(DEMO){const orderToken=makeOrderToken(ids);return res.json({url:`${base}/success.html?demo=1&order=${encodeURIComponent(orderToken)}`});}const session=await stripe.checkout.sessions.create({mode:'payment',line_items:lineItems,success_url:`${base}/success.html?session_id={CHECKOUT_SESSION_ID}`,cancel_url:`${base}/cancel.html`,metadata:{product_ids:ids.join(',')}});res.json({url:session.url});}catch(e){console.error('checkout error:',e.message);res.status(500).json({error:e.message});}});
app.get('/api/order',async(req,res)=>{const{session_id,order}=req.query;let ids=[];if(order){ids=verifyOrderToken(order);if(!ids)return res.status(403).json({error:'Sifaris etibarsizdir.'});}else if(session_id){if(!stripe)return res.status(400).json({error:'Stripe konfiqurasiya olunmayib.'});try{const s=await stripe.checkout.sessions.retrieve(session_id);if(s.payment_status!=='paid')return res.status(402).json({error:'Odenis hele tamamlanmayib.'});ids=(s.metadata?.product_ids||'').split(',').filter(Boolean);}catch(e){return res.status(404).json({error:'Sifaris tapilmadi.'});}}else return res.status(400).json({error:'session_id ve ya order lazimdir.'});const downloads=ids.map((id)=>{const p=PRODUCTS.find((x)=>x.id===id);if(!p)return null;return{name:p.name,emoji:p.emoji,url:`/download/${makeDownloadToken(id)}`};}).filter(Boolean);res.json({downloads});});
app.get('/download/:token',(req,res)=>{const productId=verifyDownloadToken(req.params.token);if(!productId)return res.status(403).send('Kecersiz link.');const p=PRODUCTS.find((x)=>x.id===productId);if(!p)return res.status(404).send('Mehsul tapilmadi.');const filePath=path.join(__dirname,'downloads',p.file);if(!fs.existsSync(filePath))return res.status(404).send('Fayl yoxdur.');res.download(filePath,p.file);});
app.get('/healthz',(req,res)=>res.json({ok:true,demo:DEMO}));
app.listen(PORT,()=>console.log(`Magaza isleyir: http://localhost:${PORT}`));
EOF

printf 'STRIPE_SECRET_KEY=
DOWNLOAD_SECRET=
PORT=3000
' > .env.example
printf 'node_modules/
.env
*.log
.DS_Store
' > .gitignore

cat > public/index.html <<'EOF'
<!DOCTYPE html>
<html lang="az"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Rəqəmsal Mağaza</title><style>
:root{--bg:#0b1120;--card:#161f33;--card2:#1f2a44;--accent:#22c55e;--accent2:#6366f1;--text:#e8edf6;--muted:#94a3b8;--border:#2a3650}
*{box-sizing:border-box;margin:0;padding:0;font-family:'Segoe UI',system-ui,sans-serif}
body{background:var(--bg);color:var(--text);line-height:1.55;padding-bottom:120px}
header{padding:48px 20px 32px;text-align:center;background:radial-gradient(900px 300px at 50% -50px,rgba(99,102,241,.25),transparent)}
header h1{font-size:2rem;margin-bottom:8px}header p{color:var(--muted);max-width:560px;margin:0 auto}
.demo-banner{background:rgba(245,158,11,.15);border:1px solid rgba(245,158,11,.4);color:#fcd34d;max-width:760px;margin:18px auto 0;padding:10px 14px;border-radius:10px;font-size:.86rem;text-align:center;display:none}
.wrap{max-width:1000px;margin:0 auto;padding:0 20px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(260px,1fr));gap:18px;margin-top:30px}
.prod{background:var(--card);border:1px solid var(--border);border-radius:16px;padding:22px;display:flex;flex-direction:column}
.prod .emoji{font-size:2.6rem;margin-bottom:10px}.prod h3{font-size:1.08rem;margin-bottom:8px}
.prod p{color:var(--muted);font-size:.88rem;flex:1;margin-bottom:16px}
.price{font-size:1.4rem;font-weight:700;margin-bottom:14px}.price span{font-size:.85rem;color:var(--muted);font-weight:400}
.btn{border:none;border-radius:10px;padding:11px 16px;font-size:.95rem;font-weight:600;cursor:pointer;width:100%}
.btn-add{background:var(--accent2);color:#fff}.btn-add.in{background:var(--card2);color:var(--accent)}
.cartbar{position:fixed;bottom:0;left:0;right:0;background:var(--card);border-top:1px solid var(--border);padding:14px 20px;display:flex;align-items:center;justify-content:space-between;gap:14px;flex-wrap:wrap}
.cartbar .total{font-size:1.25rem;font-weight:700}
.checkout{background:var(--accent);color:#06231a;border:none;border-radius:11px;padding:13px 26px;font-size:1rem;font-weight:700;cursor:pointer}
.checkout:disabled{opacity:.45;cursor:not-allowed}
.trust{display:flex;gap:18px;justify-content:center;flex-wrap:wrap;margin-top:26px;color:var(--muted);font-size:.85rem}
footer{text-align:center;color:var(--muted);font-size:.8rem;margin-top:40px;padding:0 20px}
</style></head><body>
<header><h1>🛍️ Rəqəmsal Mağaza</h1><p>Hazır şablonlar, planlayıcılar və e-kitablar. Ödənişdən dərhal sonra yüklə.</p>
<div class="demo-banner" id="demoBanner">⚠️ DEMO REJİM: real pul tutulmur.</div></header>
<div class="wrap"><div class="grid" id="grid">Yüklənir...</div>
<div class="trust"><span>🔒 Təhlükəsiz ödəniş</span><span>⚡ Dərhal yükləmə</span><span>♻️ Sonsuz istifadə</span></div>
<footer>© <span id="year"></span> Rəqəmsal Mağaza</footer></div>
<div class="cartbar"><div><span id="cartCount">0</span> məhsul səbətdə</div><div class="total" id="cartTotal">$0.00</div>
<button class="checkout" id="checkoutBtn" disabled>Ödənişə keç →</button></div>
<script>
const $=s=>document.querySelector(s);const money=c=>'$'+(c/100).toFixed(2);let PRODUCTS=[],cart={};
$('#year').textContent=new Date().getFullYear();
async function load(){try{const[p,h]=await Promise.all([fetch('/api/products').then(r=>r.json()),fetch('/healthz').then(r=>r.json()).catch(()=>({demo:false}))]);PRODUCTS=p;if(h.demo)$('#demoBanner').style.display='block';renderProducts();}catch(e){$('#grid').innerHTML='<p style="color:#f87171">Məhsullar yüklənmədi.</p>';}}
function renderProducts(){$('#grid').innerHTML='';PRODUCTS.forEach(p=>{const inC=cart[p.id]>0;const el=document.createElement('div');el.className='prod';el.innerHTML=`<div class="emoji">${p.emoji||'📦'}</div><h3>${p.name}</h3><p>${p.description||''}</p><div class="price">${money(p.price)} <span>birdəfəlik</span></div><button class="btn btn-add ${inC?'in':''}">${inC?'✓ Səbətdə (çıxar)':'Səbətə at'}</button>`;el.querySelector('button').addEventListener('click',()=>toggle(p.id));$('#grid').appendChild(el);});}
function toggle(id){if(cart[id])delete cart[id];else cart[id]=1;renderProducts();updateCart();}
function updateCart(){const ids=Object.keys(cart);const total=ids.reduce((s,id)=>{const p=PRODUCTS.find(x=>x.id===id);return s+(p?p.price:0);},0);$('#cartCount').textContent=ids.length;$('#cartTotal').textContent=money(total);$('#checkoutBtn').disabled=ids.length===0;}
$('#checkoutBtn').addEventListener('click',async()=>{const items=Object.keys(cart).map(id=>({id,qty:1}));if(!items.length)return;$('#checkoutBtn').disabled=true;$('#checkoutBtn').textContent='Yönləndirilir...';try{const r=await fetch('/api/checkout',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({items})});const d=await r.json();if(d.url)location.href=d.url;else throw new Error(d.error||'Xəta');}catch(e){alert('Xəta: '+e.message);$('#checkoutBtn').disabled=false;$('#checkoutBtn').textContent='Ödənişə keç →';}});
load();
</script></body></html>
EOF

cat > public/success.html <<'EOF'
<!DOCTYPE html>
<html lang="az"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Təşəkkürlər!</title><style>
:root{--bg:#0b1120;--card:#161f33;--accent:#22c55e;--text:#e8edf6;--muted:#94a3b8;--border:#2a3650}
*{box-sizing:border-box;margin:0;padding:0;font-family:'Segoe UI',system-ui,sans-serif}
body{background:var(--bg);color:var(--text);min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}
.card{background:var(--card);border:1px solid var(--border);border-radius:18px;padding:38px;max-width:520px;width:100%;text-align:center}
.check{width:74px;height:74px;border-radius:50%;background:rgba(34,197,94,.15);border:2px solid var(--accent);display:flex;align-items:center;justify-content:center;font-size:2.2rem;margin:0 auto 18px}
h1{font-size:1.5rem;margin-bottom:8px}.sub{color:var(--muted);margin-bottom:24px}
.dl{display:flex;flex-direction:column;gap:10px;margin-bottom:24px}
.dl a{display:flex;align-items:center;gap:10px;background:#1f2a44;border:1px solid var(--border);border-radius:11px;padding:14px 16px;color:var(--text);text-decoration:none;font-weight:600}
.dl a .arrow{margin-left:auto;color:var(--accent)}.home{color:var(--muted);text-decoration:none;font-size:.9rem}.err{color:#f87171}
</style></head><body>
<div class="card"><div class="check">✓</div><h1>Təşəkkürlər! Ödəniş alındı 🎉</h1>
<p class="sub">Aşağıdan məhsullarınızı yükləyin. Linklər 24 saat etibarlıdır.</p>
<div class="dl" id="downloads"><p class="sub">Yükləmələr hazırlanır...</p></div>
<a class="home" href="/">← Mağazaya qayıt</a></div>
<script>
const params=new URLSearchParams(location.search);const sessionId=params.get('session_id');const order=params.get('order');const box=document.getElementById('downloads');
async function loadOrder(){let qs='';if(order)qs='order='+encodeURIComponent(order);else if(sessionId)qs='session_id='+encodeURIComponent(sessionId);else{box.innerHTML='<p class="err">Sifariş tapılmadı.</p>';return;}
try{const r=await fetch('/api/order?'+qs);const d=await r.json();if(!r.ok)throw new Error(d.error||'Xəta');if(!d.downloads||!d.downloads.length){box.innerHTML='<p class="err">Yükləmə tapılmadı.</p>';return;}box.innerHTML=d.downloads.map(x=>`<a href="${x.url}">${x.emoji||'📦'} ${x.name}<span class="arrow">↓ Yüklə</span></a>`).join('');}catch(e){box.innerHTML='<p class="err">Xəta: '+e.message+'</p>';}}
loadOrder();
</script></body></html>
EOF

cat > public/cancel.html <<'EOF'
<!DOCTYPE html>
<html lang="az"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Ləğv olundu</title><style>
:root{--bg:#0b1120;--card:#161f33;--accent2:#6366f1;--text:#e8edf6;--muted:#94a3b8;--border:#2a3650}
*{box-sizing:border-box;margin:0;padding:0;font-family:'Segoe UI',system-ui,sans-serif}
body{background:var(--bg);color:var(--text);min-height:100vh;display:flex;align-items:center;justify-content:center;padding:20px}
.card{background:var(--card);border:1px solid var(--border);border-radius:18px;padding:38px;max-width:440px;text-align:center}
.icon{font-size:2.6rem;margin-bottom:14px}h1{font-size:1.4rem;margin-bottom:8px}p{color:var(--muted);margin-bottom:22px}
a{display:inline-block;background:var(--accent2);color:#fff;text-decoration:none;border-radius:10px;padding:12px 22px;font-weight:600}
</style></head><body>
<div class="card"><div class="icon">🛒</div><h1>Ödəniş ləğv olundu</h1><p>Heç bir pul tutulmadı.</p><a href="/">← Mağazaya qayıt</a></div>
</body></html>
EOF

echo "CV SABLONU - placeholder, oz mehsulunla evez et." > downloads/cv-template.txt
echo "NOTION PLANLAYICI - placeholder." > downloads/notion-student.txt
echo "BUDCE SABLONU - placeholder." > downloads/budget-sheet.txt
echo "INSTAGRAM DESTI - placeholder." > downloads/instagram-pack.txt
echo "E-KITAB - placeholder." > downloads/ebook-freelance.txt

echo ""
echo "Hazirdir! Indi: cd magaza && npm install && npm start"
