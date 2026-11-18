/* =====================================================================
   Morph Lab — logika inti game (dipakai bersama oleh browser & server)
   Browser memakainya untuk mode offline; Edge Function "game" memakainya
   untuk mode online sehingga hasil breeding, pasar, dan uang dihitung server.
   Tidak boleh bergantung pada DOM, bahasa, atau penyimpanan.
   ===================================================================== */
(function(root){
'use strict';
let S=null;               // state game yang sedang diproses
// Versi logika game. Naikkan setiap kali Edge Function "game" di-deploy ulang (sama dengan nomor versi di Supabase).
const VERSION={v:12,date:'2026-11-19'};
const BUYER_COUNT=8;      // jumlah nama pembeli di kamus bahasa

/* ========= DATA GENETIKA ========= */
const LOCI=[
 {k:'pastel',t:'id',a:'Pastel',sk:'superpastel'},
 {k:'bel',t:'bel',a:'Mojave/Lesser'},
 {k:'enchi',t:'id',a:'Enchi',sk:'superenchi'},
 {k:'yb',t:'id',a:'Yellow Belly',sk:'ivory'},
 {k:'cinnamon',t:'id',a:'Cinnamon',sk:'supercinnamon'},
 {k:'banana',t:'id',a:'Banana',sk:'superbanana'},
 {k:'spider',t:'dom',a:'Spider'},
 {k:'pinstripe',t:'dom',a:'Pinstripe'},
 {k:'albino',t:'rec',a:'Albino'},
 {k:'piebald',t:'rec',a:'Piebald'},
 {k:'clown',t:'rec',a:'Clown'},
 {k:'axanthic',t:'rec',a:'Axanthic'},
];
const TL={pastel:'Pastel',superpastel:'Super Pastel',mojave:'Mojave',lesser:'Lesser',bel:'BEL',enchi:'Enchi',superenchi:'Super Enchi',yb:'Yellow Belly',ivory:'Ivory',cinnamon:'Cinnamon',supercinnamon:'Super Cinnamon',banana:'Banana',superbanana:'Super Banana',spider:'Spider',pinstripe:'Pinstripe',albino:'Albino',piebald:'Piebald',clown:'Clown',axanthic:'Axanthic'};
const TV={pastel:45,superpastel:150,mojave:55,lesser:55,bel:600,enchi:60,superenchi:260,yb:40,ivory:280,cinnamon:50,supercinnamon:260,banana:140,superbanana:500,spider:70,pinstripe:60,albino:280,piebald:380,clown:520,axanthic:300};
const TLOC={pastel:'pastel',superpastel:'pastel',mojave:'bel',lesser:'bel',bel:'bel',enchi:'enchi',superenchi:'enchi',yb:'yb',ivory:'yb',cinnamon:'cinnamon',supercinnamon:'cinnamon',banana:'banana',superbanana:'banana',spider:'spider',pinstripe:'pinstripe',albino:'albino',piebald:'piebald',clown:'clown',axanthic:'axanthic'};
const ALLT=Object.keys(TL);

/* ========= UTIL ========= */
const R=Math.random;
const pick=a=>a[Math.floor(R()*a.length)];
const clamp=(x,a,b)=>Math.max(a,Math.min(b,x));
const money=n=>(n<0?'-$':'$')+Math.abs(Math.round(n)).toLocaleString('en-US');
const fmt=n=>Math.round(n).toLocaleString('en-US');

/* ========= STATE ========= */
const mi=()=>(8+S.turn)%12;
const yr=()=>1+Math.floor((8+S.turn)/12);
const cap=()=>S.racks*10;
// Harga rak naik 2× setiap pembelian: rak ke-3 $250, ke-4 $500, ke-5 $1.000, dst. (2 rak pertama gratis dari awal)
const RACK_BASE=250,START_RACKS=2;
const rackPrice=()=>RACK_BASE*Math.pow(2,Math.max(0,S.racks-START_RACKS));
// Catatan disimpan sebagai kunci + parameter supaya ikut berganti bahasa.
// Catatan breeder maksimal LOG_MAX entri: entri baru masuk di atas, yang paling lama terhapus.
const LOG_MAX=50;
function trimLog(){if(!Array.isArray(S.log))S.log=[];if(S.log.length>LOG_MAX)S.log.length=LOG_MAX}
function log(m,p,k){S.log.unshift({w:S.turn,m,p:p||{},k:k||'info'});trimLog()}

/* ========= GENETIKA ========= */
const emptyGeno=()=>Object.fromEntries(LOCI.map(l=>[l.k,[0,0]]));
function G(spec){const g=emptyGeno();for(const k in spec)g[k]=spec[k].slice();return g}
function locusTraits(l,a){const n=(a[0]?1:0)+(a[1]?1:0);
 if(l.t==='id')return n===1?[l.k]:n===2?[l.sk]:[];
 if(l.t==='bel')return n===1?[(a[0]||a[1])===1?'mojave':'lesser']:n===2?['bel']:[];
 if(l.t==='dom')return n?[l.k]:[];
 return n===2?[l.k]:[]}
function traitsOf(g){const o=[];for(const l of LOCI)o.push(...locusTraits(l,g[l.k]));return o}
const INC_ORDER=['superpastel','pastel','superenchi','enchi','superbanana','banana','supercinnamon','cinnamon','mojave','lesser','bel','yb','ivory'];
const BLABEL={'1,1':'Super Mojave','2,2':'Super Lesser','1,2':'Mojave Lesser','2,1':'Mojave Lesser'};
function nameOf(tr,g){
 const s=new Set(tr);let combo='';
 const take=(...k)=>{if(k.every(x=>s.has(x))){k.forEach(x=>s.delete(x));return true}return false};
 if(take('pastel','spider','pinstripe'))combo='Spinnerblast';
 else if(take('superpastel','spider'))combo='Killer Bee';
 else if(take('pastel','spider'))combo='Bumblebee';
 else if(take('pastel','pinstripe'))combo='Lemon Blast';
 else if(take('spider','pinstripe'))combo='Spinner';
 const out=[];
 for(const k of INC_ORDER)if(s.has(k))out.push(k==='bel'&&g?BLABEL[g.bel.join(',')]+' (BEL)':TL[k]);
 if(s.has('spider'))out.push('Spider');if(s.has('pinstripe'))out.push('Pinstripe');
 if(combo)out.push(combo);
 if(s.has('clown'))out.push('Clown');if(s.has('piebald'))out.push('Piebald');
 if(s.has('albino')&&s.has('axanthic'))out.push('Snow');else{if(s.has('axanthic'))out.push('Axanthic');if(s.has('albino'))out.push('Albino')}
 return out.length?out.join(' '):'Normal'}
const fullName=s=>nameOf(traitsOf(s.g),s.g);
const code=s=>'BP-'+String(s.id).padStart(4,'0');
function hetText(s){const v=new Set(traitsOf(s.g));const o=[];for(const l of LOCI){if(l.t!=='rec'||v.has(l.k))continue;const p=(s.hp||{})[l.k]||0;if(p<0.01)continue;o.push(p>=0.999?'het '+l.a:Math.round(p*100)+'% pos het '+l.a)}return o.join(', ')}
// peluang (sepengetahuan pemain) induk menurunkan alel resesif
function transmitP(s,l){return traitsOf(s.g).includes(l.k)?1:((s.hp||{})[l.k]||0)*0.5}
function childHp(m,f){const hp={};for(const l of LOCI){if(l.t!=='rec')continue;const a=transmitP(m,l),b=transmitP(f,l),pv=a*b;hp[l.k]=pv>=1?1:(a*(1-b)+b*(1-a))/(1-pv)}return hp}
function breedGeno(m,f){const g={};for(const l of LOCI)g[l.k]=[pick(m.g[l.k]),pick(f.g[l.k])];return g}
function odds(m,f){
 let dist=[{tr:[],p:1}];
 for(const l of LOCI){
  let oc;
  if(l.t==='rec'){const pv=transmitP(m,l)*transmitP(f,l);oc=[];if(pv>0)oc.push({tr:[l.k],p:pv});if(pv<1)oc.push({tr:[],p:1-pv})}
  else{const mp=new Map();for(const x of m.g[l.k])for(const y of f.g[l.k]){const tr=locusTraits(l,[x,y]);const k=tr.join();const e=mp.get(k);if(e)e.p+=.25;else mp.set(k,{tr,p:.25})}oc=[...mp.values()]}
  const nd=new Map();
  for(const d of dist)for(const o of oc){const tr=d.tr.concat(o.tr),k=tr.join('|'),e=nd.get(k);if(e)e.p+=d.p*o.p;else nd.set(k,{tr,p:d.p*o.p})}
  dist=[...nd.values()];
 }
 return dist.sort((a,b)=>b.p-a.p)}

/* ========= EKONOMI ========= */
const mm=t=>S.mm[t]||1;
function baseValue(tr){let sum=0;for(const t of tr)sum+=TV[t]*mm(t);return 40+sum*(1+0.35*Math.max(0,tr.length-1))}
function value(s){const tr=traitsOf(s.g),vs=new Set(tr);let v=baseValue(tr);
 for(const l of LOCI)if(l.t==='rec'&&!vs.has(l.k))v+=((s.hp||{})[l.k]||0)*TV[l.k]*0.18*mm(l.k);
 if(s.sex==='F')v*=1.35;v*=1+Math.min(1.6,Math.max(0,(s.w-80)/1100));return Math.round(v/5)*5}

/* ========= ULAR ========= */
// Asal-usul: s.src = cara pemilik sekarang mendapatkannya {t:'starter'|'market'|'bred'|'trade', turn, from?}.
// s.origin = {u, how} origin keeper (pemain pertama) & s.keepers = pemilik sebelumnya; keduanya diisi server saat trade.
function newSnake(o){return Object.assign({id:null,sex:'M',age:0,w:70,g:emptyGeno(),hp:{},sire:null,dam:null,gen:0,seed:Math.floor(R()*1e9),lastLaid:-99,listed:false,pairedWith:null,pairs:0,gravid:null,nick:''},o)}
function addSnake(s){s.id=S.nextId++;S.snakes.push(s);return s}
const byId=id=>S.snakes.find(s=>s.id===id);
// Syarat kawin: cukup umur (tidak ada musim kawin & syarat berat).
function femaleReady(s){if(s.gravid)return 'r_gravid';if(s.age<24)return 'r_fage';if(S.turn-s.lastLaid<8)return 'r_recover';if(s.listed)return 'r_listed';return ''}
function maleReady(s){if(s.age<10)return 'r_mage';if(s.pairs>=4)return 'r_mpairs';if(s.listed)return 'r_listed';return ''}
const readyMsg=s=>s.sex==='M'?maleReady(s):femaleReady(s);
function snap(s){return{id:s.id,g:JSON.parse(JSON.stringify(s.g)),hp:{...s.hp},label:code(s)+' '+fullName(s),gen:s.gen}}
function removeSnake(s){if(s.sex==='M')S.snakes.forEach(f=>{if(f.pairedWith===s.id)f.pairedWith=null});if(s.pairedWith){const m=byId(s.pairedWith);if(m)m.pairs=Math.max(0,m.pairs-1)}S.snakes=S.snakes.filter(x=>x!==s)}
function dexAdd(tr){const k=nameOf(tr);if(S.dex[k])return false;S.dex[k]={tr,wt:S.turn};return true}
function grow(s){if(s.gravid){s.w=Math.round(s.w*0.99);return}const K=s.sex==='F'?2300:1400,r=(s.sex==='F'?0.14:0.18)*(0.85+R()*0.3);s.w=Math.round(s.w+r*s.w*(1-s.w/K))}

/* ========= PASAR & PESANAN ========= */
// Pasar: 3 ular bergen tunggal (atau Normal), gennya tidak boleh sama, stok berganti tiap 50 turn.
// Tiap ular di pasar bisa dibeli berkali-kali: bayi (2× harga dasar) atau siap kawin (4× harga dasar), ♂ atau ♀.
const MARKET_SIZE=3,MARKET_EVERY=50,BUY_MULT={baby:2,adult:4};
const MARKET_POOL=[['normal',8],['pastel',10],['mojave',6],['lesser',6],['enchi',6],['yb',7],['cinnamon',6],['banana',4],['spider',6],['pinstripe',6],['albino',5],['piebald',4],['clown',3],['axanthic',4]];
const POOL=MARKET_POOL;
function wpick(pool){const tot=pool.reduce((a,b)=>a+b[1],0);let r=R()*tot;for(const p of pool){r-=p[1];if(r<=0)return p[0]}return pool[0][0]}
function listingGeno(gene){const g=emptyGeno(),hp={};if(gene==='normal')return{g,hp};
 if(gene==='mojave'){g.bel=[1,0];return{g,hp}}if(gene==='lesser'){g.bel=[2,0];return{g,hp}}
 const l=LOCI.find(x=>x.k===gene);if(l.t==='rec'){g[gene]=[1,1];hp[gene]=1}else g[gene]=[1,0];return{g,hp}}
const listingTraits=L=>L.gene==='normal'?[]:[L.gene];
const marketBase=L=>Math.round(baseValue(listingTraits(L))/5)*5;          // harga dasar (ikut harga pasar morph)
const marketPrice=(L,age)=>marketBase(L)*(BUY_MULT[age]||0);
const marketLeft=()=>Math.max(0,MARKET_EVERY-(S.turn-(S.marketAt||0)));   // turn sampai stok berganti
function refreshMarket(){const pool=MARKET_POOL.slice();S.market=[];
 while(S.market.length<MARKET_SIZE&&pool.length){const k=wpick(pool);pool.splice(pool.findIndex(p=>p[0]===k),1);S.market.push({lid:Math.floor(R()*1e9),gene:k})}
 S.marketAt=S.turn}
// Save lama (8 ular, ganti tiap bulan) diubah ke format pasar baru.
const marketOk=()=>Array.isArray(S.market)&&S.market.length===MARKET_SIZE&&S.market.every(L=>L&&L.gene)&&S.marketAt!=null;
function ensureMarket(){if(!marketOk())refreshMarket()}
function makeMarketSnake(L,age,sex){const{g,hp}=listingGeno(L.gene);let a,w;
 if(age==='baby'){a=1+Math.floor(R()*3);w=Math.round(70+R()*110)}
 else if(sex==='F'){a=24+Math.floor(R()*7);w=Math.round(1500+R()*400)}
 else{a=10+Math.floor(R()*7);w=Math.round(550+R()*350)}
 return newSnake({sex,age:a,w,g,hp})}
function genOrder(){
 const own=new Set();
 S.snakes.forEach(s=>{traitsOf(s.g).forEach(t=>own.add(t));LOCI.forEach(l=>{if(l.t==='rec'&&((s.hp||{})[l.k]||0)>.4)own.add(l.k)})});
 let pool=[...own];if(pool.length<2)pool=['pastel','spider','albino','enchi'];
 if(R()<.35)pool.push(pick(ALLT.filter(t=>!['bel','superbanana','supercinnamon'].includes(t))));
 const n=R()<.45?1:2;const tr=[];const locs=new Set();let tries=0;
 while(tr.length<n&&tries++<30){const t=pick(pool);if(locs.has(TLOC[t]))continue;locs.add(TLOC[t]);tr.push(t)}
 tr.sort((a,b)=>ALLT.indexOf(a)-ALLT.indexOf(b));
 const sex=R()<.4?'F':R()<.3?'M':null;
 const reward=Math.round((baseValue(tr)*(sex==='F'?1.35:1)*2.1+60)/5)*5;
 return{oid:Math.floor(R()*1e9),tr,sex,reward,left:8+Math.floor(R()*7),bi:Math.floor(R()*BUYER_COUNT)}}
function matches(o){return S.snakes.filter(s=>{const tr=traitsOf(s.g);return o.tr.every(t=>tr.includes(t))&&(!o.sex||s.sex===o.sex)&&!s.gravid&&!s.listed})}

/* ========= GAME BARU ========= */
function newGame(){
 S={v:2,rev:0,turn:0,money:2000,racks:2,nextId:1,snakes:[],clutches:[],market:[],orders:[],dex:{},mm:{},log:[],event:null,stats:{hatched:0,sold:0,earned:0,clutches:0}};
 // Ular awal: sepasang yang sudah cukup umur untuk langsung dikawinkan
 addSnake(newSnake({sex:'M',age:14,w:760,g:G({albino:[1,0]}),hp:{albino:1}}));   // jantan Normal het Albino
 addSnake(newSnake({sex:'F',age:30,w:1750,g:G({albino:[1,1]}),hp:{albino:1}}));   // betina Albino
 S.snakes.forEach(s=>{s.src={t:'starter',turn:0};dexAdd(traitsOf(s.g))});
 refreshMarket();S.orders=[genOrder(),genOrder()];
 log('l_welcome',{v:money(2000)},'star');
 return S;
}

/* ========= INKUBATOR: SUHU & JENIS KELAMIN ========= */
// Suhu inkubasi tiap clutch menentukan peluang jenis kelamin anak: lebih dingin = lebih banyak betina,
// lebih hangat = lebih banyak jantan, dibatasi 80% / 20%. Suhu hanya bisa diubah selama sepertiga
// pertama masa inkubasi (incTotal disimpan per clutch supaya reptil lain bisa punya masa inkubasi berbeda).
const INC_MONTHS=2,TEMP_MIN=29,TEMP_MAX=33,TEMP_MID=31,TEMP_STEP=.5;
const femaleChance=temp=>clamp(0.5+(TEMP_MID-(temp==null?TEMP_MID:temp))*0.15,0.2,0.8);
const incTotal=c=>c.incTotal||INC_MONTHS;
const incElapsed=c=>incTotal(c)-c.hatchIn;
const tempOpen=c=>incElapsed(c)<incTotal(c)/3;                         // masih bisa diatur?
const tempMonthsLeft=c=>Math.max(0,Math.ceil(incTotal(c)/3)-incElapsed(c)); // sisa bulan yang masih bisa diatur

/* ========= BIAYA BULANAN ========= */
// Satu rumus untuk potongan saat "Lanjut bulan" dan untuk pratinjau saldo.
// pakan: $2 + $1 per 250 g tiap ular (x1.5 saat harga pakan naik) · listrik & rak: $8/rak · tub darurat: $15/ular di atas kapasitas
function monthlyCosts(snakes,racks,ev){
 const food=Math.round(snakes.reduce((a,s)=>a+2+s.w/250,0)*((ev&&ev.food)||1));
 const util=racks*8,over=Math.max(0,snakes.length-racks*10)*15;
 return{food,util,over,total:food+util+over}}
// Perkiraan biaya bulan depan: meniru urutan advance() dengan nilai rata-rata (tanpa acak).
// Belum termasuk penjualan dari iklan & event baru (keduanya acak).
function previewNext(){
 const ev=S.event||{};let born=0,laying=0;
 const list=S.snakes.map(s=>({w:s.w,sex:s.sex,gravid:s.gravid?{layIn:s.gravid.layIn}:null,pairs:s.pairs||0}));
 for(const c of S.clutches)if(c.hatchIn<=1){const n=Math.round(c.eggs.length*0.96);born+=n;for(let i=0;i<n;i++)list.push({w:75,sex:'H',gravid:null,pairs:0})}
 for(const s of list){if(s.gravid&&s.gravid.layIn<=1){s.w=Math.round(s.w*.72);s.gravid=null;laying++}}
 for(const s of list){if(s.sex==='M'&&s.pairs)s.w=Math.round(s.w*(1-.015*s.pairs))}
 for(const s of list){if(s.gravid){s.w=Math.round(s.w*0.99);continue}
  const K=s.sex==='F'?2300:s.sex==='M'?1400:1850,r=s.sex==='F'?0.14:s.sex==='M'?0.18:0.16;s.w=Math.round(s.w+r*s.w*(1-s.w/K))}
 const c=monthlyCosts(list,S.racks,ev);
 return{...c,count:list.length,born,laying,racks:S.racks,cap:cap(),overN:Math.max(0,list.length-cap()),foodx:ev.food||1,
  listed:S.snakes.filter(s=>s.listed).length,money:S.money,after:S.money-c.total}}

/* ========= MAJU SATU BULAN ========= */
function advance(){
 const ev=S.event||{};const head=[];
 S.turn++;
 // 1. inkubator
 for(const c of S.clutches.slice()){
  c.hatchIn--;if(c.hatchIn>0)continue;
  let born=0,dead=0,nm=0,nf=0;const vis=new Set();const newNames=[];
  for(const g of c.eggs){if(R()<.04){dead++;continue}
   const s=addSnake(newSnake({sex:R()<femaleChance(c.temp)?'F':'M',w:Math.round(55+R()*40),g,hp:{...c.hp},sire:c.sireLabel,dam:c.damLabel,gen:c.gen,src:{t:'bred',turn:S.turn}}));
   const tr=traitsOf(g);tr.forEach(t=>{if(['albino','piebald','clown','axanthic'].includes(t))vis.add(t)});
   for(const l of LOCI)if(l.t==='rec'&&tr.includes(l.k))s.hp[l.k]=1;
   if(s.sex==='F')nf++;else nm++;
   if(dexAdd(tr))newNames.push(nameOf(tr));born++;}
  S.stats.hatched+=born;
  log('l_hatch',{dam:c.damLabel.split(' ')[0],sire:c.sireLabel.split(' ')[0],born,dead,nm,nf},'good');
  head.push(['h_born',{n:born}]);
  newNames.forEach(n=>{log('l_newmorph',{n},'star');head.push(['h_new',{n}])});
  for(const k of vis)for(const pid of [c.sireId,c.damId]){const p=byId(pid);if(p&&!traitsOf(p.g).includes(k)&&(p.hp[k]||0)<1){p.hp[k]=1;log('l_proven',{c:code(p),g:TL[k]},'star')}}
  S.clutches=S.clutches.filter(x=>x!==c);
 }
 // 2. bertelur
 for(const f of S.snakes){if(!f.gravid)continue;f.gravid.layIn--;if(f.gravid.layIn>0)continue;
  const m=f.gravid.sire;const n=clamp(Math.round(2+(f.w-1300)/170+R()*2.5-1),2,11);
  const eggs=[];let slugs=0;for(let i=0;i<n;i++){if(R()<.88)eggs.push(breedGeno(m,f));else slugs++}
  S.clutches.push({cid:Math.floor(R()*1e9),damId:f.id,sireId:m.id,damLabel:code(f)+' '+fullName(f),sireLabel:m.label,eggs,slugs,hatchIn:INC_MONTHS,incTotal:INC_MONTHS,temp:TEMP_MID,hp:childHp(m,f),gen:Math.max(f.gen,m.gen)+1});
  S.stats.clutches++;
  log('l_laid',{c:code(f),n,good:eggs.length,slug:slugs},'good');head.push(['h_laid',{c:code(f),n:eggs.length}]);
  f.gravid=null;f.lastLaid=S.turn;f.w=Math.round(f.w*.72);}
 // 3. ovulasi dari perkawinan bulan lalu
 for(const f of S.snakes){if(!f.pairedWith)continue;const m=byId(f.pairedWith);
  if(m&&R()<.55){f.gravid={sire:snap(m),layIn:2};log('l_ovul',{f:code(f),m:code(m)},'good');head.push(['h_gravid',{c:code(f)}])}
  else log('l_noovul',{f:code(f)},'info');
  f.pairedWith=null}
 S.snakes.forEach(s=>{if(s.sex==='M'&&s.pairs){s.w=Math.round(s.w*(1-.015*s.pairs));s.pairs=0}});
 // 4. pertumbuhan
 S.snakes.forEach(s=>{s.age++;grow(s)});
 // 5. iklan
 for(const s of S.snakes.slice()){if(!s.listed)continue;if(R()<(ev.expo?.7:.35)){const v=value(s);S.money+=v;S.stats.sold++;S.stats.earned+=v;traitsOf(s.g).forEach(t=>S.mm[t]=mm(t)*.97);log('l_soldad',{c:code(s),n:fullName(s),v:money(v)},'good');head.push(['h_sold',{c:code(s),v:money(v)}]);removeSnake(s)}}
 // 6. biaya
 const{food,util,over,total}=monthlyCosts(S.snakes,S.racks,ev);
 S.money-=total;
 log('l_costs',{food:money(food),util:money(util),over:over?money(over):''},over?'bad':'info');
 // 7. pesanan
 for(const o of S.orders.slice()){o.left--;if(o.left<=0){S.orders=S.orders.filter(x=>x!==o);log('l_orderexp',{bi:o.bi,b:o.buyer,n:nameOf(o.tr)},'bad')}}
 if(S.orders.length<3&&R()<.5){const o=genOrder();S.orders.push(o);log('l_ordernew',{bi:o.bi,sx:o.sex?(o.sex==='F'?'♀ ':'♂ '):'',n:nameOf(o.tr),r:money(o.reward)},'star')}
 // 8. pasar
 ALLT.forEach(t=>{S.mm[t]=clamp(mm(t)+(1-mm(t))*.06+(R()-.5)*.05,.5,1.6)});
 ensureMarket();if(S.turn-S.marketAt>=MARKET_EVERY)refreshMarket();
 S.event=null;
 if(R()<.3){const r=R();
  if(r<.25)S.event={expo:true,e:'ev_expo'};
  else if(r<.5){const g=pick(ALLT);S.mm[g]=mm(g)*.8;S.event={e:'ev_flood',g:TL[g]}}
  else if(r<.75){const g=pick(ALLT);S.mm[g]=mm(g)*1.25;S.event={e:'ev_trend',g:TL[g]}}
  else S.event={food:1.5,e:'ev_food'};
  log('l_event',{e:S.event.e,g:S.event.g},'star')}
 if(S.money<0)log('l_debt',null,'bad');
 return head;
}

/* ========= AKSI PEMAIN (semua divalidasi) ========= */
function fail(code){throw new Error(code)}
const toId=x=>{const n=Number(x);if(!Number.isInteger(n))fail('bad_action');return n};
function mustSnake(id){const s=byId(toId(id));if(!s)fail('snake_not_found');return s}
// Pastikan ular yang baru masuk (mis. dari trade) tercatat di Morph Dex.
function syncDex(){for(const s of S.snakes){s.hp=s.hp||{};dexAdd(traitsOf(s.g))}}
const ACTIONS={
 advance(){return{head:advance()}},
 pair(a){const m=mustSnake(a.m),f=mustSnake(a.f);
  if(m.sex!=='M'||f.sex!=='F')fail('bad_action');
  if(maleReady(m)||femaleReady(f))fail('not_ready');
  if(f.pairedWith)fail('already_paired');
  f.pairedWith=m.id;m.pairs++;log('l_paired',{m:code(m),f:code(f)});return{toast:'t_paired'}},
 unpair(a){const f=mustSnake(a.f);if(!f.pairedWith)return{};const m=byId(f.pairedWith);if(m)m.pairs=Math.max(0,m.pairs-1);f.pairedWith=null;return{}},
 list(a){const s=mustSnake(a.id);if(s.gravid)fail('gravid_locked');
  s.listed=!s.listed;
  if(s.listed&&s.pairedWith){const m=byId(s.pairedWith);if(m)m.pairs=Math.max(0,m.pairs-1);s.pairedWith=null}
  if(s.listed&&s.sex==='M'){S.snakes.forEach(f=>{if(f.pairedWith===s.id)f.pairedWith=null});s.pairs=0}
  log(s.listed?'l_listed':'l_unlisted',{c:code(s)});return{}},
 quicksell(a){const s=mustSnake(a.id);if(s.gravid)fail('gravid_locked');
  const v=Math.round(value(s)*.6);S.money+=v;S.stats.sold++;S.stats.earned+=v;traitsOf(s.g).forEach(g=>S.mm[g]=mm(g)*.97);
  log('l_quick',{c:code(s),n:fullName(s),v:money(v)},'good');removeSnake(s);return{}},
 nick(a){const s=mustSnake(a.id);s.nick=String(a.name==null?'':a.name).replace(/[\u0000-\u001f\u007f]/g,'').trim().slice(0,24);return{}},
 buy(a){const lid=toId(a.lid);const L=S.market.find(x=>x.lid===lid);if(!L)fail('listing_gone');
  if(!Object.prototype.hasOwnProperty.call(BUY_MULT,a.age)||(a.sex!=='M'&&a.sex!=='F'))fail('bad_action');
  const price=marketPrice(L,a.age);if(S.money<price)fail('not_enough_money');
  S.money-=price;const s=addSnake(makeMarketSnake(L,a.age,a.sex));s.src={t:'market',turn:S.turn};const nw=dexAdd(traitsOf(s.g));   // listing tetap ada: bisa dibeli lagi
  log('l_buy',{c:code(s),n:fullName(s),h:hetText(s),v:money(price)});if(nw)log('l_newmorph',{n:nameOf(traitsOf(s.g))},'star');return{}},
 clearlog(){S.log=[];return{toast:'t_logcleared'}},
 incubate(a){const c=S.clutches.find(x=>x.cid===toId(a.cid));if(!c)fail('clutch_not_found');
  if(!tempOpen(c))fail('temp_locked');
  const tp=Number(a.temp);if(!Number.isFinite(tp)||tp<TEMP_MIN||tp>TEMP_MAX||Math.round(tp/TEMP_STEP)*TEMP_STEP!==tp)fail('bad_temp');
  c.temp=tp;return{}},
 rack(){const price=rackPrice();if(S.money<price)fail('not_enough_money');S.money-=price;S.racks++;log('l_rack',{cap:cap(),v:money(price)});return{}},
 fulfill(a){const o=S.orders.find(x=>x.oid===toId(a.oid));if(!o)fail('order_gone');const s=mustSnake(a.sid);
  if(!matches(o).includes(s))fail('order_mismatch');
  S.money+=o.reward;S.stats.sold++;S.stats.earned+=o.reward;log('l_fulfill',{c:code(s),n:fullName(s),bi:o.bi,b:o.buyer,r:money(o.reward)},'star');
  removeSnake(s);S.orders=S.orders.filter(x=>x!==o);return{}},
};
// Jalankan satu aksi pada state (state diubah langsung). Melempar Error(kode) kalau tidak sah.
function applyAction(state,a){
 if(!a||typeof a!=='object'||typeof a.type!=='string'||!Object.prototype.hasOwnProperty.call(ACTIONS,a.type))fail('bad_action');
 S=state;syncDex();trimLog();ensureMarket();
 return ACTIONS[a.type](a)||{};
}
function isState(x){return !!(x&&typeof x==='object'&&Array.isArray(x.snakes)&&typeof x.turn==='number'&&typeof x.money==='number')}

root.MorphCore={
 VERSION,LOCI,TL,TV,TLOC,ALLT,INC_ORDER,BLABEL,POOL,BUYER_COUNT,
 R,pick,clamp,money,fmt,
 use(s){S=s},state(){return S},
 mi,yr,cap,log,rackPrice,
 emptyGeno,G,locusTraits,traitsOf,nameOf,fullName,code,hetText,transmitP,childHp,breedGeno,odds,
 mm,baseValue,value,newSnake,addSnake,byId,femaleReady,maleReady,readyMsg,removeSnake,dexAdd,matches,
 monthlyCosts,previewNext,
 MARKET_SIZE,MARKET_EVERY,BUY_MULT,MARKET_POOL,listingTraits,marketBase,marketPrice,marketLeft,refreshMarket,ensureMarket,marketOk,
 INC_MONTHS,TEMP_MIN,TEMP_MAX,TEMP_MID,TEMP_STEP,femaleChance,incTotal,tempOpen,tempMonthsLeft,
 newGame,advance,applyAction,syncDex,isState,ACTION_TYPES:Object.keys(ACTIONS)
};
})(typeof globalThis!=='undefined'?globalThis:this);
