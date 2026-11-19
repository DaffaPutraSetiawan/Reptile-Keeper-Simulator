// Simulasi ekonomi Morph Lab: bot bermain banyak game dengan core.js asli (konstanta bisa diganti per skenario).
// Contoh: node scripts/sim-economy.cjs nama '{"policy":{"reserve":3000,"outcross":300,"listAt":6,"buy":3000},"over":{"start":5000,"rack":[10000,2]}}' 200
//  policy: reserve = uang cadangan sebelum beli rak · outcross = beli jantan tak berkerabat (sisa uang minimal) ·
//          listAt = umur (bulan) anakan mulai diiklankan · inbreed = batas F yang masih mau dikawinkan · buy = beli pasangan bergen baru
//  over:   start = uang awal · buy = [kali bayi, kali siap kawin] · rack = [harga rak ke-3, kelipatan]
const fs=require('fs'),vm=require('vm');
const SRC=fs.readFileSync(require('path').join(__dirname,'..','core.js'),'utf8');
function loadCore(over={}){let s=SRC;
 if(over.start)s=s.replace(/money:\d+,racks/,'money:'+over.start+',racks').replace(/l_welcome',\{v:money\(\d+\)/,"l_welcome',{v:money("+over.start+")");
 if(over.buy)s=s.replace(/BUY_MULT=\{baby:\d+,adult:\d+\}/,'BUY_MULT={baby:'+over.buy[0]+',adult:'+over.buy[1]+'}');
 if(over.rack)s=s.replace(/RACK_BASE=\d+,RACK_MULT=\d+/,'RACK_BASE='+over.rack[0]+',RACK_MULT='+over.rack[1]);
 const ctx={Math,JSON,Object,Array,Set,Map,Number,String,Error,console};ctx.globalThis=ctx;vm.createContext(ctx);vm.runInContext(s,ctx);return ctx.MorphCore}
function play(C,policy,T=240){
 const S=C.newGame();C.use(S);const A=a=>{try{return C.applyAction(S,a)}catch(e){return null}};
 const out={big:0,rep:0,rack3:null,rack4:null,rack5:null,debt:false,minMoney:S.money,money:{},racks:{},animals:{},sold:0,orders:0,earned:{}};
 for(let t=0;t<T;t++){
  // 1. brood axolotl: simpan 3 terbaik
  for(const b of S.broods.slice())A({type:'brood',bid:b.bid,keep:C.autoBrood(b)});
  // 2. tentukan indukan: per spesies 4 betina + 2 jantan bernilai tertinggi (sudah/hampir dewasa diutamakan)
  const breeders=new Set();
  for(const sp of C.SPECIES_LIST){const L=S.snakes.filter(s=>C.spOf(s)===sp&&!s.listed);const P=C.SPECIES[sp];
   // jantan hasil beli/awal didahulukan (tidak berkerabat dengan anak-anaknya sendiri), lalu yang lebih dewasa & bernilai
   const bought=s=>s.src&&(s.src.t==='market'||s.src.t==='starter')?1:0;
   const rank=(sex,n,ma)=>L.filter(s=>s.sex===sex).sort((a,b)=>(sex==='M'?bought(b)-bought(a):0)||(b.age>=ma*0.6)-(a.age>=ma*0.6)||C.value(b)-C.value(a)).slice(0,n).forEach(s=>breeders.add(s.id));
   rank('F',4,P.fAge);rank('M',2,P.mAge)}
  // 3. pesanan: kirim hewan non-indukan yang cocok (bayaran tertinggi)
  for(const o of S.orders.slice()){
   if(C.isBig&&C.isBig(o)){const a0=C.matches(o.items[0]).filter(s=>!breeders.has(s.id)),a1=C.matches(o.items[1]).filter(s=>!breeders.has(s.id));
    const x=a0[0],y=a1.find(s=>s!==x);if(x&&y&&A({type:'fulfill',oid:o.oid,sids:[x.id,y.id]})){out.orders++;out.big=(out.big||0)+1}continue}
   const c=C.matches(o).filter(s=>!breeders.has(s.id));if(!c.length)continue;
   c.sort((a,b)=>C.orderPay(o,b)-C.orderPay(o,a));const pay=C.orderPay(o,c[0]);if(A({type:'fulfill',oid:o.oid,sid:c[0].id})){out.orders++}}
  // 4. kawinkan indukan yang siap (pilih jantan tak berkerabat bernilai tinggi)
  for(const f of S.snakes.filter(s=>s.sex==='F'&&breeders.has(s.id)&&!C.femaleReady(s)&&!s.pairedWith)){
   const ms=S.snakes.filter(m=>m.sex==='M'&&C.spOf(m)===C.spOf(f)&&!C.maleReady(m)).map(m=>[m,(C.relation(m,f)||{F:0}).F]).sort((a,b)=>a[1]-b[1]||C.value(b[0])-C.value(a[0]));
   const lim=policy.inbreed||0.1;
   if(ms.length&&ms[0][1]<lim){A({type:'pair',m:ms[0][0].id,f:f.id});continue}
   // tidak ada jantan tak berkerabat: beli jantan dewasa termurah dari pasar (outcross)
   if(policy.outcross){const L=S.market.filter(x=>C.spOf(x)===C.spOf(f)).sort((a,b)=>C.marketPrice(a,'adult')-C.marketPrice(b,'adult'))[0];
    if(L&&S.money-C.marketPrice(L,'adult')>=policy.outcross&&S.snakes.length<C.cap()){const n0=S.snakes.length;A({type:'buy',lid:L.lid,age:'adult',sex:'M'});
     if(S.snakes.length>n0){const m=S.snakes[S.snakes.length-1];breeders.add(m.id);out.bought=(out.bought||0)+1;if(!C.maleReady(m))A({type:'pair',m:m.id,f:f.id})}}}}
  // 5. stok (bukan indukan): iklankan; kalau melebihi kapasitas, jual cepat yang termurah
  for(const s of S.snakes)if(!breeders.has(s.id)&&!s.listed&&!s.gravid&&(policy.listAt==null||s.age>=policy.listAt))A({type:'list',id:s.id});
  let over=S.snakes.length-C.cap();
  if(over>0){const st=S.snakes.filter(s=>!breeders.has(s.id)&&!s.gravid).sort((a,b)=>C.value(a)-C.value(b));for(const s of st.slice(0,over))A({type:'quicksell',id:s.id})}
  // 6. beli rak kalau uang cukup + cadangan
  while(S.money>=C.rackPrice()+policy.reserve&&S.snakes.length>=C.cap()-2){if(!A({type:'rack'}))break;const n=S.racks;if(n===3&&out.rack3==null)out.rack3=S.turn;if(n===4&&out.rack4==null)out.rack4=S.turn;if(n===5&&out.rack5==null)out.rack5=S.turn}
  if(S.racks>=3&&out.rack3==null)out.rack3=S.turn;
  // 7. (aktif) beli sepasang hewan pasar dengan gen yang belum dimiliki kalau uang berlebih
  if(policy.buy){for(const L of S.market){const sp=C.spOf(L);const owned=S.snakes.some(s=>C.spOf(s)===sp&&C.traitsOf(s.g).includes(L.gene));if(owned||L.gene==='normal')continue;
   const pr=C.marketPrice(L,'adult')*2;if(S.money-pr<policy.buy)continue;if(S.snakes.length+2>C.cap())continue;
   A({type:'buy',lid:L.lid,age:'adult',sex:'F'});A({type:'buy',lid:L.lid,age:'adult',sex:'M'});break}}
  A({type:'advance'});
  if(S.money<0)out.debt=true;out.minMoney=Math.min(out.minMoney,S.money);
  if((S.turn)%12===0){const y=S.turn/12;out.money[y]=S.money;out.racks[y]=S.racks;out.animals[y]=S.snakes.length;out.earned[y]=S.stats.earned}
 }
 out.sold=S.stats.sold;out.rep=S.rep;return out}
function pct(a,p){const b=a.slice().sort((x,y)=>x-y);return b[Math.min(b.length-1,Math.floor(p*b.length))]}
function summarize(name,R){const yrs=[1,2,3,5,10,20];const f=n=>n==null?'—':Math.round(n).toLocaleString('id-ID');
 const rk=k=>{const v=R.map(r=>r[k]).filter(x=>x!=null);return {share:Math.round(v.length/R.length*100),med:v.length?pct(v,.5):null,p10:v.length?pct(v,.1):null,p90:v.length?pct(v,.9):null}};
 const res={name,n:R.length,debt:Math.round(R.filter(r=>r.debt).length/R.length*100),orders:Math.round(R.reduce((a,r)=>a+r.orders,0)/R.length),big:Math.round(R.reduce((a,r)=>a+(r.big||0),0)/R.length*10)/10,rep:pct(R.map(r=>r.rep||0),.5),
  money:Object.fromEntries(yrs.map(y=>[y,[pct(R.map(r=>r.money[y]),.1),pct(R.map(r=>r.money[y]),.5),pct(R.map(r=>r.money[y]),.9)]])),
  racks:Object.fromEntries(yrs.map(y=>[y,pct(R.map(r=>r.racks[y]),.5)])),animals:Object.fromEntries(yrs.map(y=>[y,pct(R.map(r=>r.animals[y]),.5)])),
  rack3:rk('rack3'),rack4:rk('rack4'),rack5:rk('rack5')};return res}
module.exports={loadCore,play,summarize};
if(require.main===module){const [name,json,n]=process.argv.slice(2);const sc=JSON.parse(json);const C=loadCore(sc.over||{});
 const R=[];for(let i=0;i<(+n||200);i++)R.push(play(C,sc.policy));console.log(JSON.stringify(summarize(name,R)))}
