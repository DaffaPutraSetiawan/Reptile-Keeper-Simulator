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
const VERSION={v:26,date:'2026-11-19'};
const BUYER_COUNT=60;     // jumlah nama pembeli di kamus bahasa (30 orang + 30 toko/komunitas)

/* ========= DATA GENETIKA ========= */
// Kunci gen dibuat unik untuk semua spesies, jadi spesies sebuah genotipe bisa dikenali dari kuncinya.
// t: 'id' = co-dominan (2 salinan = bentuk super sk) · 'dom' = dominan · 'rec' = resesif · 'bel' = kompleks BEL
const BALL_LOCI=[
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
// Leopard gecko. Tiga strain albino ada di lokus berbeda, jadi Tremper × Bell tidak menghasilkan albino.
const LEO_LOCI=[
 {k:'tremper',t:'rec',a:'Tremper Albino'},
 {k:'bell',t:'rec',a:'Bell Albino'},
 {k:'rainwater',t:'rec',a:'Rainwater Albino'},
 {k:'eclipse',t:'rec',a:'Eclipse'},
 {k:'blizzard',t:'rec',a:'Blizzard'},
 {k:'murphy',t:'rec',a:'Murphy Patternless'},
 {k:'marble',t:'rec',a:'Marble Eye'},
 {k:'macksnow',t:'id',a:'Mack Snow',sk:'supersnow'},
 {k:'giant',t:'id',a:'Giant',sk:'supergiant'},
 {k:'lemonfrost',t:'id',a:'Lemon Frost',sk:'superlemonfrost'},
 {k:'enigma',t:'dom',a:'Enigma'},
 {k:'wy',t:'dom',a:'White & Yellow'},
];
// Axolotl (amfibi). Gen warna alaminya resesif; GFP & RFP adalah gen hasil rekayasa (protein berpendar) yang dominan.
// Kuncinya diberi awalan ax supaya tidak bentrok dengan Albino/Axanthic milik ball python.
const AXO_LOCI=[
 {k:'axleu',t:'rec',a:'Leucistic'},
 {k:'axalb',t:'rec',a:'Albino'},
 {k:'axmel',t:'rec',a:'Melanoid'},
 {k:'axaxa',t:'rec',a:'Axanthic'},
 {k:'axcop',t:'rec',a:'Copper'},
 {k:'gfp',t:'dom',a:'GFP'},
 {k:'rfp',t:'dom',a:'RFP'},
];
const LOCI=BALL_LOCI;     // nama lama, tetap dipakai untuk ball python
const TL={pastel:'Pastel',superpastel:'Super Pastel',mojave:'Mojave',lesser:'Lesser',bel:'BEL',enchi:'Enchi',superenchi:'Super Enchi',yb:'Yellow Belly',ivory:'Ivory',cinnamon:'Cinnamon',supercinnamon:'Super Cinnamon',banana:'Banana',superbanana:'Super Banana',spider:'Spider',pinstripe:'Pinstripe',albino:'Albino',piebald:'Piebald',clown:'Clown',axanthic:'Axanthic',
 tremper:'Tremper Albino',bell:'Bell Albino',rainwater:'Rainwater Albino',eclipse:'Eclipse',blizzard:'Blizzard',murphy:'Murphy Patternless',marble:'Marble Eye',macksnow:'Mack Snow',supersnow:'Super Snow',giant:'Giant',supergiant:'Super Giant',lemonfrost:'Lemon Frost',superlemonfrost:'Super Lemon Frost',enigma:'Enigma',wy:'White & Yellow',
 axleu:'Leucistic',axalb:'Albino',axmel:'Melanoid',axaxa:'Axanthic',axcop:'Copper',gfp:'GFP',rfp:'RFP'};
const TV={pastel:45,superpastel:150,mojave:55,lesser:55,bel:600,enchi:60,superenchi:260,yb:40,ivory:280,cinnamon:50,supercinnamon:260,banana:140,superbanana:500,spider:70,pinstripe:60,albino:280,piebald:380,clown:520,axanthic:300,
 tremper:45,bell:55,rainwater:55,eclipse:60,blizzard:50,murphy:55,marble:70,macksnow:30,supersnow:120,giant:40,supergiant:140,lemonfrost:120,superlemonfrost:360,enigma:45,wy:45,
 axleu:6,axalb:9,axmel:6,axaxa:12,axcop:15,gfp:10,rfp:15};
const TLOC={pastel:'pastel',superpastel:'pastel',mojave:'bel',lesser:'bel',bel:'bel',enchi:'enchi',superenchi:'enchi',yb:'yb',ivory:'yb',cinnamon:'cinnamon',supercinnamon:'cinnamon',banana:'banana',superbanana:'banana',spider:'spider',pinstripe:'pinstripe',albino:'albino',piebald:'piebald',clown:'clown',axanthic:'axanthic',
 tremper:'tremper',bell:'bell',rainwater:'rainwater',eclipse:'eclipse',blizzard:'blizzard',murphy:'murphy',marble:'marble',macksnow:'macksnow',supersnow:'macksnow',giant:'giant',supergiant:'giant',lemonfrost:'lemonfrost',superlemonfrost:'lemonfrost',enigma:'enigma',wy:'wy',
 axleu:'axleu',axalb:'axalb',axmel:'axmel',axaxa:'axaxa',axcop:'axcop',gfp:'gfp',rfp:'rfp'};
const ALLT=Object.keys(TL);

/* ========= SPESIES ========= */
// Semua angka yang berbeda antarspesies ada di sini. 1 turn = 1 bulan; berat dalam gram.
//  fAge/mAge: umur minimal kawin · recover: jeda bulan setelah bertelur · ovul: peluang ovulasi setelah kawin
//  layIn: bulan dari ovulasi sampai bertelur · K/r: pertumbuhan logistik (H = bayi yang belum diketahui kelaminnya)
//  wBonus: [berat awal, pembagi] untuk bonus harga dari berat · inc: lama inkubasi · temp: pilihan suhu inkubator
//  clutches: jumlah clutch dari sekali kawin (betina menyimpan sperma) · minLayW: musim bertelur berhenti lebih awal
//  kalau berat betina turun di bawah angka ini · slugStep: tambahan peluang telur tidak subur di tiap clutch berikutnya
//  temp: null = suhu tidak menentukan jenis kelamin (50:50) · brood: bayi menetas sebagai satu kelompok, pemain memilih
//  maksimal sekian ekor untuk disimpan dan sisanya otomatis dijual cepat (60% nilai)
const SPECIES={
 ball:{name:'ball python',orderBonus:60,code:'BP',loci:BALL_LOCI,maxAge:360,base:40,fAge:24,mAge:10,recover:8,ovul:.55,layIn:2,slug:.12,layLoss:.72,gravidLoss:.99,clutches:[1,1],minLayW:0,slugStep:0,
  K:{F:2300,M:1400,H:1850},r:{F:.14,M:.18,H:.16},hatchW:[55,95],wBonus:[80,1100],foodBase:2,inc:2,
  temp:{min:29,max:33,mid:31,step:.5},
  eggs:f=>clamp(Math.round(2+(f.w-1300)/170+R()*2.5-1),2,11),
  mk:{baby:{a:[1,3],w:[70,180]},F:{a:[24,30],w:[1500,1900]},M:{a:[10,16],w:[550,900]}},
  pool:[['normal',8],['pastel',10],['mojave',6],['lesser',6],['enchi',6],['yb',7],['cinnamon',6],['banana',4],['spider',6],['pinstripe',6],['albino',5],['piebald',4],['clown',3],['axanthic',4]],
  orderBase:['pastel','spider','albino','enchi'],orderSkip:['bel','superbanana','supercinnamon']},
 leo:{name:'leopard gecko',orderBonus:30,code:'LG',loci:LEO_LOCI,maxAge:240,base:25,fAge:10,mAge:9,recover:3,ovul:.7,layIn:1,slug:.1,layLoss:.94,gravidLoss:1,clutches:[4,6],minLayW:40,slugStep:.04,
  K:{F:65,M:75,H:70},r:{F:.4,M:.4,H:.4},hatchW:[3,5],wBonus:[4,40],foodBase:1,inc:2,
  temp:{min:26,max:34,mid:30,step:.5},
  eggs:()=>R()<.1?1:2,
  mk:{baby:{a:[1,3],w:[6,15]},F:{a:[10,14],w:[50,62]},M:{a:[9,13],w:[55,70]}},
  pool:[['normal',8],['tremper',9],['bell',6],['rainwater',5],['eclipse',6],['blizzard',6],['murphy',5],['marble',3],['macksnow',9],['giant',6],['lemonfrost',3],['enigma',5],['wy',5]],
  orderBase:['macksnow','tremper','eclipse','giant'],orderSkip:['superlemonfrost','supergiant']},
 axo:{name:'axolotl',orderBonus:10,code:'AX',loci:AXO_LOCI,maxAge:180,base:5,fAge:18,mAge:12,recover:4,ovul:.6,layIn:1,slug:.15,layLoss:.9,gravidLoss:1,clutches:[1,1],minLayW:0,slugStep:0,
  K:{F:110,M:95,H:100},r:{F:.5,M:.5,H:.5},hatchW:[2,3],wBonus:[2,60],foodBase:1,inc:1,
  temp:null,brood:3,
  eggs:f=>clamp(Math.round(50+(f.w-70)*1.2+R()*20-10),30,100),
  mk:{baby:{a:[2,4],w:[6,15]},F:{a:[18,24],w:[85,110]},M:{a:[12,18],w:[70,95]}},
  pool:[['normal',8],['axleu',10],['axalb',8],['axmel',7],['axaxa',5],['axcop',4],['gfp',5],['rfp',3]],
  orderBase:['axleu','axalb','axmel','gfp'],orderSkip:[]},
};
const SPECIES_LIST=Object.keys(SPECIES);
const TSP={};for(const sp of SPECIES_LIST)for(const l of SPECIES[sp].loci){TSP[l.k]=sp;if(l.sk)TSP[l.sk]=sp}
TSP.mojave=TSP.lesser='ball';
for(const sp of SPECIES_LIST)SPECIES[sp].traits=ALLT.filter(t=>TSP[t]===sp);
// spesies sebuah objek (ular, clutch, listing pasar, pesanan); data lama tanpa sp = ball python
const spOf=x=>(x&&x.sp&&SPECIES[x.sp])?x.sp:'ball';
const spOfG=g=>!g?'ball':g.tremper!==undefined?'leo':g.axalb!==undefined?'axo':'ball';
const spOfTr=tr=>{for(const t of tr||[])if(TSP[t]&&TSP[t]!=='ball')return TSP[t];return 'ball'};
const lociOf=g=>SPECIES[spOfG(g)].loci;
const isRec=k=>[...BALL_LOCI,...LEO_LOCI,...AXO_LOCI].some(l=>l.k===k&&l.t==='rec');
// label gen untuk pesan event pasar: gen spesies selain ball python diberi nama spesiesnya
const tlabel=t=>TL[t]+(TSP[t]&&TSP[t]!=='ball'?' ('+SPECIES[TSP[t]].name+')':'');

/* ========= UTIL ========= */
const R=Math.random;
const pick=a=>a[Math.floor(R()*a.length)];
const clamp=(x,a,b)=>Math.max(a,Math.min(b,x));
const money=n=>(n<0?'-$':'$')+Math.abs(Math.round(n)).toLocaleString('en-US');
const fmt=n=>Math.round(n).toLocaleString('en-US');
const rint=([a,b])=>a+Math.floor(R()*(b-a+1));

/* ========= STATE ========= */
const mi=()=>(8+S.turn)%12;
const yr=()=>1+Math.floor((8+S.turn)/12);
const cap=()=>S.racks*10;
// Harga rak naik 2× setiap pembelian: rak ke-3 $10.000, ke-4 $20.000, ke-5 $40.000, dst. (2 rak pertama gratis dari awal)
const RACK_BASE=10000,RACK_MULT=2,START_RACKS=2;
const rackPrice=()=>RACK_BASE*Math.pow(RACK_MULT,Math.max(0,S.racks-START_RACKS));
// Catatan disimpan sebagai kunci + parameter supaya ikut berganti bahasa.
// Catatan breeder maksimal LOG_MAX entri: entri baru masuk di atas, yang paling lama terhapus.
const LOG_MAX=50;
function trimLog(){if(!Array.isArray(S.log))S.log=[];if(S.log.length>LOG_MAX)S.log.length=LOG_MAX}
function log(m,p,k){S.log.unshift({w:S.turn,m,p:p||{},k:k||'info'});trimLog()}

/* ========= GENETIKA ========= */
const emptyGeno=sp=>Object.fromEntries(SPECIES[sp||'ball'].loci.map(l=>[l.k,[0,0]]));
function G(spec,sp){const g=emptyGeno(sp);for(const k in spec)g[k]=spec[k].slice();return g}
function locusTraits(l,a){const n=(a[0]?1:0)+(a[1]?1:0);
 if(l.t==='id')return n===1?[l.k]:n===2?[l.sk]:[];
 if(l.t==='bel')return n===1?[(a[0]||a[1])===1?'mojave':'lesser']:n===2?['bel']:[];
 if(l.t==='dom')return n?[l.k]:[];
 return n===2?[l.k]:[]}
function traitsOf(g){const o=[];for(const l of lociOf(g))o.push(...locusTraits(l,g[l.k]||[0,0]));return o}
const INC_ORDER=['superpastel','pastel','superenchi','enchi','superbanana','banana','supercinnamon','cinnamon','mojave','lesser','bel','yb','ivory'];
const BLABEL={'1,1':'Super Mojave','2,2':'Super Lesser','1,2':'Mojave Lesser','2,1':'Mojave Lesser'};
const LEO_ORDER=['supergiant','giant','supersnow','macksnow','superlemonfrost','lemonfrost','wy','enigma','murphy','blizzard','marble','eclipse','tremper','bell','rainwater'];
function nameBall(tr,g){
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
// Nama kombinasi leopard gecko (RAPTOR = Tremper Albino + Eclipse, dst.)
function nameLeo(tr){
 const s=new Set(tr);let combo='';
 const take=(...k)=>{if(k.every(x=>s.has(x))){k.forEach(x=>s.delete(x));return true}return false};
 if(take('tremper','eclipse')){
  if(take('macksnow','enigma'))combo='Dreamsicle';
  else if(take('blizzard'))combo='Diablo Blanco';
  else if(take('murphy'))combo='Ember';
  else if(take('enigma'))combo='Nova';
  else if(take('supersnow'))combo='Super RAPTOR';
  else combo='RAPTOR';
 }
 else if(take('bell','eclipse'))combo='RADAR';
 else if(take('rainwater','eclipse'))combo='Typhoon';
 else if(take('supersnow','eclipse'))combo='Total Eclipse';
 if(!combo&&s.has('blizzard')){const a=['tremper','bell','rainwater'].find(x=>s.has(x));
  if(a){s.delete('blizzard');s.delete(a);combo=(a==='tremper'?'':TL[a].replace(' Albino','')+' ')+'Blazing Blizzard'}}
 const out=[];for(const k of LEO_ORDER)if(s.has(k))out.push(TL[k]);
 if(combo)out.push(combo);
 return out.length?out.join(' '):'Normal'}
// Nama axolotl: albino digabung dengan gen lain jadi White / Axanthic / Melanoid / Golden Albino; tanpa gen = Wild Type.
function nameAxo(tr){
 const s=new Set(tr);let alb='';
 if(s.has('axalb')){s.delete('axalb');
  if(s.has('axleu')){s.delete('axleu');alb='White Albino'}
  else if(s.has('axaxa')){s.delete('axaxa');alb='Axanthic Albino'}
  else if(s.has('axmel')){s.delete('axmel');alb='Melanoid Albino'}
  else alb='Golden Albino'}
 const out=[];for(const k of ['gfp','rfp','axcop','axleu','axaxa','axmel'])if(s.has(k))out.push(TL[k]);
 if(alb)out.push(alb);
 return out.length?out.join(' '):'Wild Type'}
function nameOf(tr,g,sp){sp=sp||(g?spOfG(g):spOfTr(tr));return sp==='leo'?nameLeo(tr):sp==='axo'?nameAxo(tr):nameBall(tr,g)}
const fullName=s=>nameOf(traitsOf(s.g),s.g,spOfG(s.g));
const code=s=>SPECIES[spOfG(s.g)].code+'-'+String(s.id).padStart(4,'0');
function hetText(s){const v=new Set(traitsOf(s.g));const o=[];for(const l of lociOf(s.g)){if(l.t!=='rec'||v.has(l.k))continue;const p=(s.hp||{})[l.k]||0;if(p<0.01)continue;o.push(p>=0.999?'het '+l.a:Math.round(p*100)+'% pos het '+l.a)}return o.join(', ')}
// peluang (sepengetahuan pemain) induk menurunkan alel resesif
function transmitP(s,l){return traitsOf(s.g).includes(l.k)?1:((s.hp||{})[l.k]||0)*0.5}
function childHp(m,f){const hp={};for(const l of lociOf(f.g)){if(l.t!=='rec')continue;const a=transmitP(m,l),b=transmitP(f,l),pv=a*b;hp[l.k]=pv>=1?1:(a*(1-b)+b*(1-a))/(1-pv)}return hp}
function breedGeno(m,f){const g={};for(const l of lociOf(f.g))g[l.k]=[pick(m.g[l.k]||[0,0]),pick(f.g[l.k]||[0,0])];return g}
function odds(m,f){
 let dist=[{tr:[],p:1}];
 for(const l of lociOf(f.g)){
  let oc;
  if(l.t==='rec'){const pv=transmitP(m,l)*transmitP(f,l);oc=[];if(pv>0)oc.push({tr:[l.k],p:pv});if(pv<1)oc.push({tr:[],p:1-pv})}
  else{const mp=new Map();for(const x of m.g[l.k]||[0,0])for(const y of f.g[l.k]||[0,0]){const tr=locusTraits(l,[x,y]);const k=tr.join();const e=mp.get(k);if(e)e.p+=.25;else mp.set(k,{tr,p:.25})}oc=[...mp.values()]}
  const nd=new Map();
  for(const d of dist)for(const o of oc){const tr=d.tr.concat(o.tr),k=tr.join('|'),e=nd.get(k);if(e)e.p+=d.p*o.p;else nd.set(k,{tr,p:d.p*o.p})}
  dist=[...nd.values()];
 }
 return dist.sort((a,b)=>b.p-a.p)}

/* ========= EKONOMI ========= */
const mm=t=>S.mm[t]||1;
function baseValue(tr,sp){let sum=0;for(const t of tr)sum+=TV[t]*mm(t);return SPECIES[sp||spOfTr(tr)].base+sum*(1+0.35*Math.max(0,tr.length-1))}
function value(s){const sp=spOfG(s.g),P=SPECIES[sp],tr=traitsOf(s.g),vs=new Set(tr);let v=baseValue(tr,sp);
 for(const l of P.loci)if(l.t==='rec'&&!vs.has(l.k))v+=((s.hp||{})[l.k]||0)*TV[l.k]*0.18*mm(l.k);
 if(s.sex==='F')v*=1.35;v*=1+Math.min(1.6,Math.max(0,(s.w-P.wBonus[0])/P.wBonus[1]));return Math.round(v/5)*5}

/* ========= ULAR ========= */
// Asal-usul: s.src = cara pemilik sekarang mendapatkannya {t:'starter'|'market'|'bred'|'trade', turn, from?}.
// s.origin = {u, how} origin keeper (pemain pertama) & s.keepers = pemilik sebelumnya; keduanya diisi server saat trade.
function newSnake(o){return Object.assign({id:null,sex:'M',age:0,w:70,g:emptyGeno(),hp:{},sire:null,dam:null,gen:0,seed:Math.floor(R()*1e9),lastLaid:-99,listed:false,pairedWith:null,pairs:0,gravid:null,nick:''},o)}
function addSnake(s){s.id=S.nextId++;S.snakes.push(s);return s}
const byId=id=>S.snakes.find(s=>s.id===id);
// Batas umur per spesies (SPECIES[sp].maxAge, dalam bulan). Ular mati karena tua begitu umurnya mencapai batas ini.
const OLD_WARN=12;                   // label "Tua" muncul saat sisa umur <= 12 bulan
const maxAge=s=>SPECIES[spOf(s)].maxAge;
const lifeLeft=s=>Math.max(0,maxAge(s)-s.age);
// Syarat kawin: cukup umur (tidak ada musim kawin & syarat berat).
function femaleReady(s){const sp=spOf(s),P=SPECIES[sp];if(s.gravid)return 'r_gravid';if(s.age<P.fAge)return sp==='ball'?'r_fage':'r_fage_'+sp;if(S.turn-s.lastLaid<P.recover)return 'r_recover';if(s.listed)return 'r_listed';return ''}
function maleReady(s){const sp=spOf(s);if(s.age<SPECIES[sp].mAge)return sp==='ball'?'r_mage':'r_mage_'+sp;if(s.pairs>=4)return 'r_mpairs';if(s.listed)return 'r_listed';return ''}
const readyMsg=s=>s.sex==='M'?maleReady(s):femaleReady(s);
function snap(s){return{id:s.id,g:JSON.parse(JSON.stringify(s.g)),hp:{...s.hp},label:code(s)+' '+fullName(s),gen:s.gen,pn:pedNode(s),ar:ancRec(s)}}
/* ========= SILSILAH ========= */
// Setiap anak menyimpan ringkasan induknya di s.ped = {s: induk jantan, d: induk betina}, dan tiap induk membawa
// ringkasan orang tuanya sendiri. Jadi pohon 3 generasi (hewan, induk, kakek-nenek) tetap utuh walaupun induknya
// sudah dijual, mati, atau di-trade, dan ikut pindah saat hewannya di-trade.
// Simpul: {k: seed hewan, c: kode saat itu, n: nama morph, x: kelamin, h: het (khusus induk), s/d: kakek & nenek}.
// k dipakai untuk mengenali induk yang masih kamu miliki (id berganti saat trade, seed tidak).
const pedLite=p=>p?{k:p.k,c:p.c,n:p.n,x:p.x}:null;
// hewan lama tanpa s.ped: induknya hanya dikenal dari label teks, mis. "BP-0002 Pastel"
function labelNode(l,x){if(!l||typeof l!=='string')return null;const i=l.indexOf(' ');return{c:i<0?l:l.slice(0,i),n:i<0?'':l.slice(i+1),x}}
function pedParents(s){return s.ped?{s:s.ped.s||null,d:s.ped.d||null}:{s:labelNode(s.sire,'M'),d:labelNode(s.dam,'F')}}
function pedNode(s){const o={k:s.seed,c:code(s),n:fullName(s),x:s.sex},h=hetText(s),pp=pedParents(s);if(h)o.h=h;
 if(pp.s)o.s=pedLite(pp.s);if(pp.d)o.d=pedLite(pp.d);return o}

/* ========= KAWIN SEDARAH (INBREEDING) ========= */
// Di belakang layar setiap hewan menyimpan seed leluhurnya sampai 5 generasi di s.anc (penomoran Ahnentafel:
// 2 = induk jantan, 3 = induk betina, 4–7 = kakek-nenek, ... sampai 63), nilai inbreeding-nya sendiri di s.inb,
// dan s.af = {seed: F} untuk leluhur yang inbred. Dari situ dihitung koefisien inbreeding (F) calon anak dengan
// rumus kekerabatan (kinship) standar, jadi kawin sedarah berulang ikut menumpuk: 25% → 37,5% → 50% → 59%.
// Efek (versi berat): telur tidak subur +0,8×F, gagal menetas +0,8×F; hewan yang inbred tumbuh (1−F/2)× lebih cepat
// dan betina inbred berovulasi (1−F)× peluang biasanya.
const ANC_MAX=64;                         // posisi < 64 = 5 generasi leluhur
const INB_SLUG=.8,INB_DEAD=.8,HATCH_DEAD=.04;
// Peta posisi → seed untuk hewan (atau snapshot induk). Hewan v24 tanpa s.anc: dibaca dari s.ped.
function ancMap(x){const A={1:x.seed};
 if(Array.isArray(x.anc)){x.anc.forEach((k,i)=>{if(i>=2&&i<ANC_MAX&&k)A[i]=k});return A}
 const ped=x.ped;if(!ped)return A;
 const put=(i,n)=>{if(n&&n.k)A[i]=n.k};
 put(2,ped.s);put(3,ped.d);if(ped.s){put(4,ped.s.s);put(5,ped.s.d)}if(ped.d){put(6,ped.d.s);put(7,ped.d.d)}
 return A}
// Ringkasan silsilah tersembunyi sebuah hewan, dipakai untuk menghitung kekerabatan (juga disimpan di snapshot jantan).
function ancRec(x){const A=ancMap(x),arr=[];for(const i in A)if(+i>=2)arr[+i]=A[i];
 return{k:x.seed,a:arr,inb:x.inb||0,af:x.af||{}}}
// Koefisien kekerabatan dua hewan = koefisien inbreeding anak mereka.
function kinship(X,Y){
 if(!X||!Y||!X.k||!Y.k)return 0;
 const P={},Fs={};
 for(const R of [X,Y]){const A={1:R.k};(R.a||[]).forEach((k,i)=>{if(i>=2&&i<ANC_MAX&&k)A[i]=k});
  for(const i in A){const k=A[i],n=P[k]||(P[k]={s:0,d:0});const s=A[2*i],d=A[2*i+1];if(s&&!n.s)n.s=s;if(d&&!n.d)n.d=d}
  for(const k in R.af||{})Fs[k]=R.af[k];if(R.inb)Fs[R.k]=R.inb}
 const am=new Map();
 const isAnc=(a,b)=>{const key=a+'>'+b;if(am.has(key))return am.get(key);am.set(key,false);   // apakah a leluhur b?
  const n=P[b];const r=!!n&&(n.s===a||n.d===a||(!!n.s&&isAnc(a,n.s))||(!!n.d&&isAnc(a,n.d)));am.set(key,r);return r};
 const km=new Map();
 const Fof=k=>{if(Fs[k]!=null)return Fs[k];const n=P[k];return n&&n.s&&n.d?kin(n.s,n.d):0};
 function kin(a,b){if(!a||!b)return 0;if(a===b)return .5*(1+Fof(a));
  const key=a<b?a+'|'+b:b+'|'+a;if(km.has(key))return km.get(key);km.set(key,0);   // penjaga putaran
  const has=k=>!!(P[k]&&(P[k].s||P[k].d));let r=0;
  if(has(b)&&!isAnc(b,a))r=.5*(kin(a,P[b].s)+kin(a,P[b].d));
  else if(has(a)&&!isAnc(a,b))r=.5*(kin(P[a].s,b)+kin(P[a].d,b));
  km.set(key,r);return r}
 return Math.round(kin(X.k,Y.k)*1e4)/1e4}
// Data leluhur & inbreeding untuk anak dari pasangan ini (jantan boleh berupa snapshot dengan .ar).
function childAnc(mr,fr,F){const arr=[];
 const put=(R,top)=>{arr[top]=R.k;(R.a||[]).forEach((k,p)=>{if(p<2||!k)return;const g=31-Math.clz32(p),c=(top<<g)|(p-(1<<g));if(c<ANC_MAX)arr[c]=k})};
 put(mr,2);put(fr,3);
 const keep=new Set(arr.filter(Boolean)),af={};
 for(const R of [mr,fr]){for(const k in R.af||{})if(keep.has(+k)&&R.af[k]>0)af[k]=R.af[k];if(R.inb>0)af[R.k]=R.inb}
 const o={anc:arr.map(x=>x||0)};if(F>0)o.inb=F;if(Object.keys(af).length)o.af=af;return o}
// Hubungan keluarga yang paling dekat antara dua hewan (untuk peringatan); null kalau tidak berkerabat.
function relation(m,f){const F=kinship(ancRec(m),ancRec(f));if(F<=0)return null;
 const A=ancMap(m),B=ancMap(f),inR=(M,k,a,b)=>{for(let i=a;i<=b;i++)if(M[i]&&M[i]===k)return true;return false};
 const par=M=>[M[2],M[3]].filter(Boolean),gp=M=>[4,5,6,7].map(i=>M[i]).filter(Boolean);
 const pa=par(A),pb=par(B),sharedP=pa.filter(k=>pb.includes(k)).length,sharedG=gp(A).filter(k=>gp(B).includes(k)).length;
 let r='rel_far';
 if(inR(B,m.seed,2,3)||inR(A,f.seed,2,3))r='rel_parent';
 else if(sharedP===2)r='rel_full';
 else if(inR(B,m.seed,4,7)||inR(A,f.seed,4,7))r='rel_grand';
 else if(sharedP===1)r='rel_half';
 else if(pa.some(k=>gp(B).includes(k))||pb.some(k=>gp(A).includes(k)))r='rel_uncle';
 else if(sharedG)r='rel_cousin';
 return{F,r}}
const inbOf=s=>(s&&s.inb)||0;
function removeSnake(s){if(s.sex==='M')S.snakes.forEach(f=>{if(f.pairedWith===s.id)f.pairedWith=null});if(s.pairedWith){const m=byId(s.pairedWith);if(m)m.pairs=Math.max(0,m.pairs-1)}S.snakes=S.snakes.filter(x=>x!==s)}
// Morph Dex: kunci ball python = nama morph (seperti dulu); spesies lain diberi awalan, mis. "leo:RAPTOR".
const dexKey=(tr,sp)=>(sp&&sp!=='ball'?sp+':':'')+nameOf(tr,null,sp||spOfTr(tr));
function dexAdd(tr,sp){sp=sp||spOfTr(tr);const k=dexKey(tr,sp);if(S.dex[k])return false;S.dex[k]=sp==='ball'?{tr,wt:S.turn}:{tr,wt:S.turn,sp};return true}
// Gen Giant membuat tubuh lebih besar (1 salinan ×1,25, Super Giant ×1,6).
function sizeMult(g){if(!g||!g.giant)return 1;const n=(g.giant[0]?1:0)+(g.giant[1]?1:0);return n===2?1.6:n===1?1.25:1}
const kOf=(sp,sex,g)=>SPECIES[sp].K[sex==='F'||sex==='M'?sex:'H']*sizeMult(g);
function growW(sp,sex,w,g,rf){const P=SPECIES[sp],r=P.r[sex==='F'||sex==='M'?sex:'H']*rf;return Math.round(w+r*w*(1-w/kOf(sp,sex,g)))}
function grow(s){const sp=spOf(s);if(s.gravid){s.w=Math.round(s.w*SPECIES[sp].gravidLoss);return}s.w=growW(sp,s.sex,s.w,s.g,(0.85+R()*0.3)*(1-inbOf(s)/2))}

/* ========= PASAR & PESANAN ========= */
// Pasar: tiap spesies punya 3 hewan bergen tunggal (atau Normal), gennya tidak boleh sama, stok berganti tiap 50 turn.
// Tiap hewan di pasar bisa dibeli berkali-kali: bayi (10× harga dasar) atau siap kawin (20× harga dasar), ♂ atau ♀.
const MARKET_SIZE=3,MARKET_EVERY=50,BUY_MULT={baby:10,adult:20};
const MARKET_POOL=SPECIES.ball.pool;
const POOL=MARKET_POOL;
function wpick(pool){const tot=pool.reduce((a,b)=>a+b[1],0);let r=R()*tot;for(const p of pool){r-=p[1];if(r<=0)return p[0]}return pool[0][0]}
function listingGeno(gene,sp){const g=emptyGeno(sp),hp={};if(gene==='normal')return{g,hp};
 if(gene==='mojave'){g.bel=[1,0];return{g,hp}}if(gene==='lesser'){g.bel=[2,0];return{g,hp}}
 const l=SPECIES[sp].loci.find(x=>x.k===gene);if(l.t==='rec'){g[gene]=[1,1];hp[gene]=1}else g[gene]=[1,0];return{g,hp}}
const listingTraits=L=>L.gene==='normal'?[]:[L.gene];
const marketBase=L=>Math.round(baseValue(listingTraits(L),spOf(L))/5)*5;     // harga dasar (ikut harga pasar morph)
const marketPrice=(L,age)=>marketBase(L)*(BUY_MULT[age]||0);
const marketLeft=()=>Math.max(0,MARKET_EVERY-(S.turn-(S.marketAt||0)));   // turn sampai stok berganti
// Isi ulang stok satu spesies saja (listing ball python tanpa sp, sama seperti format lama).
function fillMarket(sp){S.market=(Array.isArray(S.market)?S.market:[]).filter(L=>L&&spOf(L)!==sp);const pool=SPECIES[sp].pool.slice();let n=0;
 while(n<MARKET_SIZE&&pool.length){const k=wpick(pool);pool.splice(pool.findIndex(p=>p[0]===k),1);const L={lid:Math.floor(R()*1e9),gene:k};if(sp!=='ball')L.sp=sp;S.market.push(L);n++}}
function refreshMarket(){S.market=[];for(const sp of SPECIES_LIST)fillMarket(sp);S.marketAt=S.turn}
const spMarketOk=sp=>{const L=S.market.filter(x=>spOf(x)===sp);return L.length===MARKET_SIZE&&new Set(L.map(x=>x.gene)).size===L.length&&L.every(x=>SPECIES[sp].pool.some(p=>p[0]===x.gene))};
const marketOk=()=>Array.isArray(S.market)&&S.marketAt!=null&&S.market.every(L=>L&&L.gene&&(!L.sp||SPECIES[L.sp]))&&SPECIES_LIST.every(spMarketOk);
// Save lama: format pasar lama diganti total; spesies baru yang belum punya stok ditambahkan tanpa mengganti stok lain.
function ensureMarket(){if(marketOk())return;
 if(!Array.isArray(S.market)||S.marketAt==null||!S.market.every(L=>L&&L.gene&&(!L.sp||SPECIES[L.sp]))){refreshMarket();return}
 for(const sp of SPECIES_LIST)if(!spMarketOk(sp))fillMarket(sp)}
function makeMarketSnake(L,age,sex){const sp=spOf(L),{g,hp}=listingGeno(L.gene,sp),M=SPECIES[sp].mk[age==='baby'?'baby':sex];
 const s=newSnake({sex,age:rint(M.a),w:rint(M.w),g,hp});if(sp!=='ball')s.sp=sp;return s}
function genOrder(){
 // pesanan untuk spesies lain lebih sering muncul kalau pemain memeliharanya
 let sp='ball';for(const x of SPECIES_LIST)if(x!=='ball'&&R()<(S.snakes.some(s=>spOf(s)===x)?.35:.1)){sp=x;break}
 const P=SPECIES[sp];
 const own=new Set();
 S.snakes.filter(s=>spOf(s)===sp).forEach(s=>{traitsOf(s.g).forEach(t=>own.add(t));P.loci.forEach(l=>{if(l.t==='rec'&&((s.hp||{})[l.k]||0)>.4)own.add(l.k)})});
 let pool=[...own];if(pool.length<2)pool=P.orderBase.slice();
 if(R()<.35)pool.push(pick(P.traits.filter(t=>!P.orderSkip.includes(t))));
 const n=R()<.45?1:2;const tr=[];const locs=new Set();let tries=0;
 while(tr.length<n&&tries++<30){const t=pick(pool);if(locs.has(TLOC[t]))continue;locs.add(TLOC[t]);tr.push(t)}
 tr.sort((a,b)=>ALLT.indexOf(a)-ALLT.indexOf(b));
 const sex=R()<.4?'F':R()<.3?'M':null;
 const reward=Math.round((baseValue(tr,sp)*(sex==='F'?1.35:1)*2.1+P.orderBonus)/5)*5;
 const o={oid:Math.floor(R()*1e9),tr,sex,reward,left:8+Math.floor(R()*7),bi:Math.floor(R()*BUYER_COUNT)};if(sp!=='ball')o.sp=sp;return o}
// Bentuk super ikut memenuhi pesanan gen aslinya (Super Cinnamon untuk pesanan Cinnamon, Ivory untuk Yellow Belly, dst.);
// BEL memenuhi pesanan Mojave/Lesser kalau membawa alel itu. Pesanan bentuk super tetap butuh bentuk super.
const SUPER_OF={};for(const sp of SPECIES_LIST)for(const l of SPECIES[sp].loci)if(l.sk)SUPER_OF[l.k]=l.sk;
function hasTrait(s,tr,t){if(tr.includes(t))return true;if(SUPER_OF[t]&&tr.includes(SUPER_OF[t]))return true;
 if((t==='mojave'||t==='lesser')&&tr.includes('bel'))return s.g.bel.includes(t==='mojave'?1:2);return false}
// Bayaran pesanan: hadiah tetap pesanan, atau ORDER_PREMIUM × nilai hewan yang dikirim kalau itu lebih tinggi.
// Dengan begitu mengirim ke pembeli selalu lebih untung daripada iklan (100% nilai) dan jual cepat (60%).
const ORDER_PREMIUM=1.25;
const orderPay=(o,s)=>Math.max(o.reward,Math.ceil(value(s)*ORDER_PREMIUM/5)*5);   // dibulatkan ke atas: selalu ≥125%
function matches(o){const sp=spOf(o);return S.snakes.filter(s=>{const tr=traitsOf(s.g);return spOf(s)===sp&&o.tr.every(t=>hasTrait(s,tr,t))&&(!o.sex||s.sex===o.sex)&&!s.gravid&&!s.listed})}

/* ========= GAME BARU ========= */
function newGame(){
 S={v:2,rev:0,turn:0,money:5000,racks:2,nextId:1,snakes:[],clutches:[],broods:[],market:[],orders:[],dex:{},mm:{},log:[],event:null,stats:{hatched:0,sold:0,earned:0,clutches:0}};
 // Ular awal: sepasang yang sudah cukup umur untuk langsung dikawinkan
 addSnake(newSnake({sex:'M',age:14,w:760,g:G({albino:[1,0]}),hp:{albino:1}}));   // jantan Normal het Albino
 addSnake(newSnake({sex:'F',age:30,w:1750,g:G({albino:[1,1]}),hp:{albino:1}}));   // betina Albino
 S.snakes.forEach(s=>{s.src={t:'starter',turn:0};dexAdd(traitsOf(s.g),'ball')});
 refreshMarket();S.orders=[genOrder(),genOrder()];
 log('l_welcome',{v:money(5000)},'star');
 return S;
}

/* ========= INKUBATOR: SUHU & JENIS KELAMIN ========= */
// Suhu inkubasi tiap clutch menentukan peluang jenis kelamin anak, dibatasi 80% / 20%. Suhu hanya bisa diubah
// selama sepertiga pertama masa inkubasi (incTotal disimpan per clutch supaya tiap spesies bisa berbeda).
//  Ball python: lebih dingin = lebih banyak betina (31 °C = 50:50).
//  Leopard gecko: 26–27 °C hampir semua betina, 30 °C = 50:50, 32–33 °C kebanyakan jantan,
//  dan di 34 °C kembali kebanyakan betina (pola "hot female" seperti di dunia nyata).
const INC_MONTHS=2,TEMP_MIN=29,TEMP_MAX=33,TEMP_MID=31,TEMP_STEP=.5;   // nilai ball python (nama lama)
//  Axolotl: jenis kelamin ditentukan kromosom, bukan suhu, jadi selalu 50:50 dan suhunya tidak bisa diatur.
const tempRange=sp=>SPECIES[sp||'ball'].temp;
function femaleChance(temp,sp){sp=sp||'ball';if(!tempRange(sp))return .5;const x=temp==null?tempRange(sp).mid:temp;
 if(sp==='leo')return x>33?clamp(0.2+(x-33)*0.6,0.2,0.8):clamp(0.5+(30-x)*0.1,0.2,0.8);
 return clamp(0.5+(TEMP_MID-x)*0.15,0.2,0.8)}
const incTotal=c=>c.incTotal||INC_MONTHS;
const incElapsed=c=>incTotal(c)-c.hatchIn;
const tempOpen=c=>incElapsed(c)<incTotal(c)/3;                         // masih bisa diatur?
const tempMonthsLeft=c=>Math.max(0,Math.ceil(incTotal(c)/3)-incElapsed(c)); // sisa bulan yang masih bisa diatur
const validTemp=(tp,sp)=>{const T=tempRange(sp);return !!T&&Number.isFinite(tp)&&tp>=T.min&&tp<=T.max&&Math.round(tp/T.step)*T.step===tp};

/* ========= BIAYA BULANAN ========= */
// Satu rumus untuk potongan saat "Lanjut bulan" dan untuk pratinjau saldo.
// pakan: $2 (ball python) / $1 (gecko & axolotl) + $1 per 250 g tiap hewan (x1.5 saat harga pakan naik)
// listrik & rak: $8/rak · space darurat: $15/hewan di atas kapasitas
function monthlyCosts(snakes,racks,ev){
 const food=Math.round(snakes.reduce((a,s)=>a+SPECIES[spOf(s)].foodBase+s.w/250,0)*((ev&&ev.food)||1));
 const util=racks*8,over=Math.max(0,snakes.length-racks*10)*15;
 return{food,util,over,total:food+util+over}}
// Perkiraan biaya bulan depan: meniru urutan advance() dengan nilai rata-rata (tanpa acak).
// Belum termasuk penjualan dari iklan & event baru (keduanya acak).
function previewNext(){
 const ev=S.event||{};let born=0,laying=0;
 const alive=S.snakes.filter(s=>s.age+1<maxAge(s)),dying=S.snakes.length-alive.length;
 const list=alive.map(s=>({sp:spOf(s),w:s.w,sex:s.sex,g:s.g,gravid:s.gravid?{layIn:s.gravid.layIn,more:(s.gravid.no||1)<(s.gravid.tot||1)}:null,pairs:s.pairs||0,inb:inbOf(s)}));
 for(const b of S.broods||[]){const P=SPECIES[b.sp],n=Math.min(P.brood,b.items.length);born+=n;for(let i=0;i<n;i++)list.push({sp:b.sp,w:(P.hatchW[0]+P.hatchW[1])/2,sex:'H',g:null,gravid:null,pairs:0})}
 for(const c of S.clutches)if(c.hatchIn<=1&&!SPECIES[spOf(c)].brood){const sp=spOf(c),hw=SPECIES[sp].hatchW,n=Math.round(c.eggs.length*0.96);born+=n;for(let i=0;i<n;i++)list.push({sp,w:(hw[0]+hw[1])/2,sex:'H',g:null,gravid:null,pairs:0})}
 for(const s of list){if(s.gravid&&s.gravid.layIn<=1){const P=SPECIES[s.sp];s.w=Math.round(s.w*P.layLoss);laying++;s.gravid=s.gravid.more&&s.w>=P.minLayW?{layIn:1}:null}}
 for(const s of list){if(s.sex==='M'&&s.pairs)s.w=Math.round(s.w*(1-.015*s.pairs))}
 for(const s of list){if(s.gravid){s.w=Math.round(s.w*SPECIES[s.sp].gravidLoss);continue}s.w=growW(s.sp,s.sex,s.w,s.g,1-(s.inb||0)/2)}
 const c=monthlyCosts(list,S.racks,ev);
 return{...c,count:list.length,born,laying,dying,racks:S.racks,cap:cap(),overN:Math.max(0,list.length-cap()),foodx:ev.food||1,
  listed:S.snakes.filter(s=>s.listed).length,money:S.money,after:S.money-c.total}}

/* ========= BROOD AXOLOTL ========= */
// Bayi axolotl menetas sebagai satu kelompok (brood). Pemain memilih maksimal SPECIES[sp].brood ekor untuk disimpan;
// sisanya otomatis dijual cepat (60% nilai). Brood yang belum dipilih saat "Lanjut bulan" diproses otomatis:
// bayi yang paling bernilai disimpan.
function broodSnake(b,it){const P=SPECIES[b.sp],o={sp:b.sp,sex:it.sex,age:0,w:P.hatchW[0],g:it.g,hp:{...b.hp},sire:b.sireLabel,dam:b.damLabel,gen:b.gen,src:{t:'bred',turn:b.turn}};
 if(b.ped)o.ped=b.ped;if(b.ca)Object.assign(o,b.ca);const tr=traitsOf(it.g);for(const l of P.loci)if(l.t==='rec'&&tr.includes(l.k))o.hp[l.k]=1;return newSnake(o)}
const broodValue=(b,i)=>value(broodSnake(b,b.items[i]));
function resolveBrood(b,keep,auto){const P=SPECIES[b.sp];let total=0,sold=0;const sat=new Set();
 b.items.forEach((it,i)=>{const s=broodSnake(b,it);if(keep.includes(i))addSnake(s);else{total+=Math.round(value(s)*.6);sold++;traitsOf(it.g).forEach(t=>sat.add(t))}});
 sat.forEach(t=>S.mm[t]=mm(t)*.95);   // jual banyak sekaligus: harga morph itu sedikit turun (sekali per gen)
 S.money+=total;S.stats.sold+=sold;S.stats.earned+=total;S.broods=S.broods.filter(x=>x!==b);
 log(auto?'l_brood_auto':'l_brood_done',{d:b.damLabel.split(' ')[0],k:keep.length,n:sold,v:money(total)},'good');return{kept:keep.length,sold,total}}
function autoBrood(b){const P=SPECIES[b.sp];return b.items.map((_,i)=>[i,broodValue(b,i)]).sort((x,y)=>y[1]-x[1]).slice(0,P.brood).map(x=>x[0])}

/* ========= MAJU SATU BULAN ========= */
function advance(){
 const ev=S.event||{};const head=[];
 if(!Array.isArray(S.broods))S.broods=[];
 // 0. brood axolotl yang belum dipilih bulan lalu: simpan yang paling bernilai, sisanya dijual
 for(const b of S.broods.slice())resolveBrood(b,autoBrood(b),true);
 S.turn++;
 // 1. inkubator
 for(const c of S.clutches.slice()){
  c.hatchIn--;if(c.hatchIn>0)continue;
  const sp=spOf(c),P=SPECIES[sp];
  let born=0,dead=0,nm=0,nf=0;const vis=new Set();const newNames=[];
  const brood=P.brood?{bid:Math.floor(R()*1e9),sp,damLabel:c.damLabel,sireLabel:c.sireLabel,gen:c.gen,hp:{...c.hp},items:[],turn:S.turn}:null;if(brood&&c.ped)brood.ped=c.ped;if(brood&&c.ca)brood.ca=c.ca;
  const deadP=HATCH_DEAD+INB_DEAD*(c.inb||0);
  for(const g of c.eggs){if(R()<deadP){dead++;continue}
   const sex=R()<femaleChance(c.temp,sp)?'F':'M';
   if(brood)brood.items.push({g,sex});
   else{const o={sex,w:rint(P.hatchW),g,hp:{...c.hp},sire:c.sireLabel,dam:c.damLabel,gen:c.gen,src:{t:'bred',turn:S.turn}};if(sp!=='ball')o.sp=sp;if(c.ped)o.ped=c.ped;if(c.ca)Object.assign(o,c.ca);
    const s=addSnake(newSnake(o));const tr=traitsOf(g);for(const l of P.loci)if(l.t==='rec'&&tr.includes(l.k))s.hp[l.k]=1}
   const tr=traitsOf(g);tr.forEach(t=>{if(isRec(t))vis.add(t)});
   if(sex==='F')nf++;else nm++;
   if(dexAdd(tr,sp))newNames.push(nameOf(tr,null,sp));born++;}
  S.stats.hatched+=born;
  if(brood&&brood.items.length){S.broods.push(brood);log('l_brood',{dam:c.damLabel.split(' ')[0],sire:c.sireLabel.split(' ')[0],born,dead,nm,nf,k:P.brood},'star');head.push(['h_brood',{n:born,k:P.brood}])}
  else{log('l_hatch',{dam:c.damLabel.split(' ')[0],sire:c.sireLabel.split(' ')[0],born,dead,nm,nf},'good');head.push(['h_born',{n:born}])}
  newNames.forEach(n=>{log('l_newmorph',{n},'star');head.push(['h_new',{n}])});
  for(const k of vis)for(const pid of [c.sireId,c.damId]){const p=byId(pid);if(p&&!traitsOf(p.g).includes(k)&&(p.hp[k]||0)<1){p.hp[k]=1;log('l_proven',{c:code(p),g:TL[k]},'star')}}
  S.clutches=S.clutches.filter(x=>x!==c);
 }
 // 2. bertelur. Leopard gecko: sekali kawin menghasilkan beberapa clutch berturut-turut (1 clutch per bulan),
 //    sampai jatah clutch musim itu habis atau berat betina terlalu rendah; setelah itu betina istirahat.
 for(const f of S.snakes){if(!f.gravid)continue;f.gravid.layIn--;if(f.gravid.layIn>0)continue;
  const sp=spOf(f),P=SPECIES[sp],no=f.gravid.no||1,tot=f.gravid.tot||1;
  const m=f.gravid.sire,F=f.gravid.inb||0;const n=P.eggs(f),slugP=Math.min(.95,P.slug+P.slugStep*(no-1)+INB_SLUG*F);
  const eggs=[];let slugs=0;for(let i=0;i<n;i++){if(R()>=slugP)eggs.push(breedGeno(m,f));else slugs++}
  const c={cid:Math.floor(R()*1e9),damId:f.id,sireId:m.id,damLabel:code(f)+' '+fullName(f),sireLabel:m.label,eggs,slugs,hatchIn:P.inc,incTotal:P.inc,temp:P.temp?P.temp.mid:null,hp:childHp(m,f),gen:Math.max(f.gen,m.gen)+1,ped:{s:m.pn||labelNode(m.label,'M'),d:pedNode(f)},inb:F,ca:m.ar?childAnc(m.ar,ancRec(f),F):null};
  if(sp!=='ball')c.sp=sp;S.clutches.push(c);
  S.stats.clutches++;
  log('l_laid',tot>1?{c:code(f),n,good:eggs.length,slug:slugs,m:P.inc,no,tot}:{c:code(f),n,good:eggs.length,slug:slugs,m:P.inc},'good');head.push(['h_laid',{c:code(f),n:eggs.length}]);
  f.lastLaid=S.turn;f.w=Math.round(f.w*P.layLoss);
  if(no<tot&&f.w>=P.minLayW)f.gravid={sire:m,layIn:1,no:no+1,tot};
  else{f.gravid=null;if(no<tot)log('l_season_light',{c:code(f),n:no},'info');else if(tot>1)log('l_season_end',{c:code(f),n:tot,r:P.recover},'info')}}
 // 3. ovulasi dari perkawinan bulan lalu
 for(const f of S.snakes){if(!f.pairedWith)continue;const m=byId(f.pairedWith),P=SPECIES[spOf(f)];
  if(m&&R()<P.ovul*(1-inbOf(f))){const sm=snap(m);f.gravid={sire:sm,layIn:P.layIn,no:1,tot:rint(P.clutches),inb:kinship(sm.ar,ancRec(f))};log('l_ovul',{f:code(f),m:code(m),n:P.layIn},'good');head.push(['h_gravid',{c:code(f)}])}
  else log('l_noovul',{f:code(f)},'info');
  f.pairedWith=null}
 S.snakes.forEach(s=>{if(s.sex==='M'&&s.pairs){s.w=Math.round(s.w*(1-.015*s.pairs));s.pairs=0}});
 // 4. pertumbuhan
 S.snakes.forEach(s=>{s.age++;grow(s)});
 // 4b. mati karena tua (betina yang sedang bunting ikut mati bersama telurnya)
 for(const s of S.snakes.slice())if(s.age>=maxAge(s)){log('l_oldage',{c:code(s),n:fullName(s),a:s.age,gr:s.gravid?1:0},'bad');head.push(['h_oldage',{c:code(s)}]);removeSnake(s)}
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
  else if(r<.5){const g=pick(ALLT);S.mm[g]=mm(g)*.8;S.event={e:'ev_flood',g:tlabel(g)}}
  else if(r<.75){const g=pick(ALLT);S.mm[g]=mm(g)*1.25;S.event={e:'ev_trend',g:tlabel(g)}}
  else S.event={food:1.5,e:'ev_food'};
  log('l_event',{e:S.event.e,g:S.event.g},'star')}
 if(S.money<0)log('l_debt',null,'bad');
 return head;
}

/* ========= AKSI PEMAIN (semua divalidasi) ========= */
function fail(code){throw new Error(code)}
const toId=x=>{const n=Number(x);if(!Number.isInteger(n))fail('bad_action');return n};
function mustSnake(id){const s=byId(toId(id));if(!s)fail('snake_not_found');return s}
// Pastikan hewan yang baru masuk (mis. dari trade) tercatat di Morph Dex.
function syncDex(){for(const s of S.snakes){s.hp=s.hp||{};dexAdd(traitsOf(s.g),spOf(s))}}
const ACTIONS={
 advance(){return{head:advance()}},
 pair(a){const m=mustSnake(a.m),f=mustSnake(a.f);
  if(m.sex!=='M'||f.sex!=='F')fail('bad_action');
  if(spOf(m)!==spOf(f))fail('species_mismatch');
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
  S.money-=price;const s=addSnake(makeMarketSnake(L,a.age,a.sex));s.src={t:'market',turn:S.turn};const nw=dexAdd(traitsOf(s.g),spOf(s));   // listing tetap ada: bisa dibeli lagi
  log('l_buy',{c:code(s),n:fullName(s),h:hetText(s),v:money(price)});if(nw)log('l_newmorph',{n:nameOf(traitsOf(s.g),null,spOf(s))},'star');return{}},
 clearlog(){S.log=[];return{toast:'t_logcleared'}},
 brood(a){const b=S.broods.find(x=>x.bid===toId(a.bid));if(!b)fail('brood_gone');
  if(!Array.isArray(a.keep)||a.keep.length>SPECIES[b.sp].brood)fail('bad_action');
  const keep=a.keep.map(toId);if(new Set(keep).size!==keep.length||keep.some(i=>i<0||i>=b.items.length))fail('bad_action');
  resolveBrood(b,keep,false);return{toast:'t_brood'}},
 incubate(a){const c=S.clutches.find(x=>x.cid===toId(a.cid));if(!c)fail('clutch_not_found');
  if(!tempOpen(c))fail('temp_locked');
  const tp=Number(a.temp);if(!validTemp(tp,spOf(c)))fail('bad_temp');
  c.temp=tp;return{}},
 rack(){const price=rackPrice();if(S.money<price)fail('not_enough_money');S.money-=price;S.racks++;log('l_rack',{cap:cap(),v:money(price)});return{}},
 fulfill(a){const o=S.orders.find(x=>x.oid===toId(a.oid));if(!o)fail('order_gone');const s=mustSnake(a.sid);
  if(!matches(o).includes(s))fail('order_mismatch');
  const pay=orderPay(o,s);S.money+=pay;S.stats.sold++;S.stats.earned+=pay;log('l_fulfill',{c:code(s),n:fullName(s),bi:o.bi,b:o.buyer,r:money(pay)},'star');
  removeSnake(s);S.orders=S.orders.filter(x=>x!==o);return{}},
};
// Jalankan satu aksi pada state (state diubah langsung). Melempar Error(kode) kalau tidak sah.
function applyAction(state,a){
 if(!a||typeof a!=='object'||typeof a.type!=='string'||!Object.prototype.hasOwnProperty.call(ACTIONS,a.type))fail('bad_action');
 S=state;if(!Array.isArray(S.broods))S.broods=[];syncDex();trimLog();ensureMarket();
 return ACTIONS[a.type](a)||{};
}
function isState(x){return !!(x&&typeof x==='object'&&Array.isArray(x.snakes)&&typeof x.turn==='number'&&typeof x.money==='number')}

root.MorphCore={
 VERSION,LOCI,BALL_LOCI,LEO_LOCI,AXO_LOCI,tlabel,broodSnake,broodValue,autoBrood,TL,TV,TLOC,ALLT,INC_ORDER,BLABEL,POOL,BUYER_COUNT,
 SPECIES,SPECIES_LIST,spOf,spOfG,spOfTr,lociOf,isRec,
 R,pick,clamp,money,fmt,
 use(s){S=s},state(){return S},
 mi,yr,cap,log,rackPrice,RACK_MULT,
 emptyGeno,G,locusTraits,traitsOf,nameOf,fullName,code,hetText,transmitP,childHp,breedGeno,odds,
 OLD_WARN,maxAge,lifeLeft,sizeMult,kOf,growW,
 pedNode,pedParents,labelNode,ancRec,kinship,relation,inbOf,INB_SLUG,INB_DEAD,HATCH_DEAD,
 mm,baseValue,value,newSnake,addSnake,byId,femaleReady,maleReady,readyMsg,removeSnake,dexAdd,dexKey,matches,ORDER_PREMIUM,orderPay,
 monthlyCosts,previewNext,
 MARKET_SIZE,MARKET_EVERY,BUY_MULT,MARKET_POOL,listingTraits,marketBase,marketPrice,marketLeft,refreshMarket,ensureMarket,marketOk,makeMarketSnake,
 INC_MONTHS,TEMP_MIN,TEMP_MAX,TEMP_MID,TEMP_STEP,tempRange,femaleChance,incTotal,tempOpen,tempMonthsLeft,validTemp,
 newGame,advance,applyAction,syncDex,isState,ACTION_TYPES:Object.keys(ACTIONS)
};
})(typeof globalThis!=='undefined'?globalThis:this);
