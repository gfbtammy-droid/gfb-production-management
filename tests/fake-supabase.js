(function(){
const td=new Date().toLocaleDateString("en-CA",{timeZone:"Asia/Kuala_Lumpur"});
const dd=n=>{const d=new Date(td+"T00:00:00Z");d.setUTCDate(d.getUTCDate()-n);return d.toISOString().slice(0,10)};
const job=(id,o)=>Object.assign({id,job_no:"W-"+(1000+id),machine:"AUTOPACK 1",plan_date:dd(5),product:"CHOCOLATE PREMIX "+id,customer:"Demo Cafe",batch_qty:100,batches:2,uom:"KG",total_planned:200,jo_mix:[String(5000+id*2),String(5001+id*2)],jo_pack:[String(7000+id)],bulk_packing:false,notes:null,status:"IN PROCESS",date_released:dd(4),date_mixing:null,mixing_output:null,date_packing:null,packing_output:null,variance_kg:null,date_qc:null,qc_result:null,date_transferred:null,to_req_no:null,date_closed:null,remarks:null,wastage_cause:null,created_at:new Date().toISOString(),pack_plan:null,packing_complete:null,item_code:"FG-"+id,date_done:null},o);
const T={
 job_orders:[
  job(1,{mixing_output:200,date_mixing:dd(3)}),
  job(2,{mixing_output:150,date_mixing:dd(1),packing_output:100,date_packing:dd(0),packing_complete:false,jo_pack:["7101","7102","7103"],pack_plan:[50,50,50]}),
  job(3,{status:"DONE",mixing_output:200,packing_output:198,date_packing:dd(1),date_done:dd(1),variance_kg:2}),
  job(4,{status:"TRANSFERRED",mixing_output:200,packing_output:197,date_packing:dd(2),date_done:dd(2),date_transferred:dd(1),to_req_no:"TO-1"}),
  job(5,{status:"DONE",mixing_output:200,packing_output:199,date_packing:dd(1),date_done:dd(1),qc_result:"PASS",date_qc:dd(1)}),
  job(6,{status:"RELEASED"}),
  job(7,{status:"IN PROCESS",bulk_packing:true,mixing_output:300,date_mixing:dd(2),jo_pack:[]}),
  job(8,{status:"CLOSED",mixing_output:200,packing_output:null})],
 job_batches:[{id:1,job_id:1,jo_no:"5002",seq:1,mix_kg:100,mix_date:dd(4)},{id:2,job_id:1,jo_no:"5003",seq:2,mix_kg:100,mix_date:dd(3)}],
 loss_reports:[], machines:[{id:1,name:"AUTOPACK 1",active:true,sort_order:1}], app_settings:[],
 role_permissions:[], app_users:[{user_id:"u1",active:true,username:"admin",full_name:"Demo Admin",role:"admin"}], access_log:[]};
let nid=100;
function Q(tb){this.tb=tb;this.f=[];this.op="select";this.row=null;this.one=false;this.mode=null}
Q.prototype.select=function(){return this};Q.prototype.order=function(){return this};Q.prototype.limit=function(){return this};
Q.prototype.range=function(a,b){this.r=[a,b];return this};Q.prototype.eq=function(k,v){this.f.push([k,v]);return this};
Q.prototype.insert=function(r){this.op="insert";this.row=r;return this};Q.prototype.update=function(r){this.op="update";this.row=r;return this};
Q.prototype.single=function(){this.one=true;return this};Q.prototype.maybeSingle=function(){this.one=true;return this};
Q.prototype.then=function(res,rej){try{const t=T[this.tb]||(T[this.tb]=[]);let out;
 if(this.op==="insert"){const r=Object.assign({id:++nid},this.row);if(this.tb==="loss_reports"){r.report_no="LOSS-"+String(nid).padStart(4,"0");r.status="OPEN";r.reporter_name="Demo Admin"}t.push(r);out=r}
 else if(this.op==="update"){const rs=t.filter(x=>this.f.every(([k,v])=>x[k]===v));rs.forEach(x=>Object.assign(x,this.row));out=this.one?rs[0]:rs}
 else{let rs=t.filter(x=>this.f.every(([k,v])=>x[k]===v));if(this.r)rs=rs.slice(this.r[0],this.r[1]+1);out=this.one?(rs[0]||null):rs}
 res({data:JSON.parse(JSON.stringify(out)),error:null})}catch(e){rej(e)}};
const ch={on(){return ch},subscribe(cb){cb&&cb("SUBSCRIBED");return ch}};
window.__T=T;
window.supabase={createClient(){return{from:t=>new Q(t),rpc:()=>Promise.resolve({data:null,error:null}),channel:()=>ch,removeChannel(){},
 storage:{from:()=>({upload:()=>Promise.resolve({error:null}),createSignedUrl:()=>Promise.resolve({data:{signedUrl:""}})})},
 auth:{getSession:()=>Promise.resolve({data:{session:{user:{id:"u1"}}}}),onAuthStateChange(){},signOut:()=>Promise.resolve({}),signInWithPassword:()=>Promise.resolve({error:null})}}}};
})();
