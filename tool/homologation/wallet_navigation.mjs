import assert from 'node:assert/strict';
import {basename,dirname,join,resolve} from 'node:path';
import {existsSync,readFileSync,renameSync,writeFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
const [root, profile]=process.argv.slice(2);
assert.match(basename(root),/^se7e_persona_[a-f0-9]{12}_test$/);
assert.ok(['pagar','receber'].includes(profile));
const read=path=>JSON.parse(readFileSync(path,'utf8'));
const {sessionRoot}=read(join(root,'manual-ready.json'));
assert.equal(dirname(sessionRoot),root);
const hub=read(join(sessionRoot,'hub-ready.json')), agents=read(join(sessionRoot,'agents-ready.json'));
assert.equal(new URL(hub.hubUrl).hostname,'127.0.0.1');
const login=await fetch(hub.hubUrl+'/api/v1/client-auth/login',{method:'POST',redirect:'error',headers:{'content-type':'application/json'},body:JSON.stringify(hub.client)});
assert.equal(login.status,200); const {accessToken}=await login.json();
const party=profile==='pagar'?'fornecedor':'cliente', account='conta'+profile, code='cod'+party, name='nome'+party;
const scalar=(type,value)=>({type,value:String(value)}), integer=x=>scalar('integer',x), str=x=>scalar('string',x);
const people=Array.from({length:32},(_,i)=>({[code]:integer(i+1),[party==='cliente'?'nome':'razaosocial']:str(i===31?'Beta':'Alfa '+(i+1))}));
const titles=Array.from({length:62},(_,i)=>({codempresa:integer(1),codfilial:integer(3),['cod'+account]:integer(i+1),[code]:integer(i<31?1:i-29),moeda:str('BRL'),status:str('A'),datavencimento:scalar('date','2026-11-01'),['saldo'+profile]:scalar('decimal',10),numerotitulo:str('T'+i),parcela:str('1')}));
const seeds=[{table:'dbo.'+account,rows:titles},{table:'dbo.'+party,rows:people}];
async function job(kind,more={}) {
 const path=join(sessionRoot,randomUUID()+'.case-job.json');
 writeFileSync(path+'.tmp',JSON.stringify({engine:'mssql',kind,...more}),{flag:'wx'});renameSync(path+'.tmp',path);
 const until=Date.now()+90000;
 while(!existsSync(path+'.result')&&Date.now()<until) await new Promise(r=>setTimeout(r,150));
 assert.ok(existsSync(path+'.result'),'fixture job timed out');assert.equal(read(path+'.result').passed,true,kind);
}
const base=resolve('../mcp_test_agente/sql/campo-e-lavoura');
const candidate=readFileSync(join(base,'exemplos','candidatos-'+party+'-titulos-abertos.sql'),'utf8').trim();
const detail=readFileSync(join(base,'titulos-a-'+profile+'-em-aberto.sql'),'utf8').trim();
async function check(step,sql,filter,id,page,expected,next,cursor) {
 const requestId=randomUUID();
 const params={sql,database:basename(root),params:{[code]:id,[name]:filter,datainicio:null,datafim:null},client_token:agents.mssql.clientToken,options:{...(cursor?{cursor}:{page,page_size:30}),timeout_ms:15000,max_rows:100}};
 const r=await fetch(hub.hubUrl+'/api/v1/agents/commands',{method:'POST',redirect:'error',signal:AbortSignal.timeout(25000),headers:{authorization:'Bearer '+accessToken,'content-type':'application/json'},body:JSON.stringify({agentId:hub.engines.mssql.agentId,timeoutMs:20000,command:{jsonrpc:'2.0',id:requestId,method:'sql.execute',params}})});
 const body=await r.json(), envelope=body.response??body,item=envelope.item??envelope,result=item.result??item.data??item;
 const err=item.error??envelope.error??result.error;
 if(err) throw Error(JSON.stringify({profile,step,requestId,code:err.code,reason:err.data?.reason,detail:err.data?.technical_message??err.message}));
 assert.equal(r.status,200); const key=sql===candidate?code:'cod'+account;
 const actual=result.rows.map(row=>Number(row[key]));
 assert.deepEqual(actual,expected,step);
 assert.equal(result.pagination.page_size,30);assert.equal(result.pagination.page,page);
 assert.equal(result.pagination.has_next_page,next);assert.equal(result.pagination.has_previous_page,page>1);
 console.log(JSON.stringify({profile,step,requestId,rows:actual.length,identitiesVerified:true,page,hasNext:next}));
 return result.pagination.next_cursor;
}
const first=Array.from({length:30},(_,i)=>i+1);
await job('publication-prepare',{seeds});
try {
 for(const [sql,key,selected,changed,last,alt] of [[candidate,'candidate',null,null,31,32],[detail,'titles',1,32,31,62]]){
   const token=await check(key+' first',sql,'Alfa%',selected,1,first,true);
   assert.equal(typeof token,'string');
   await check(key+' next cursor',sql,'Alfa%',selected,2,[last],false,token);
   await check(key+' next page',sql,'Alfa%',selected,2,[last],false);
   await check(key+' previous',sql,'Alfa%',selected,1,first,true);
   await check(key+' changed',sql,'Beta%',changed,1,[alt],false);
   await check(key+' empty',sql,'Missing%',changed,1,[],false);
   await check(key+' restored',sql,'Alfa%',selected,1,first,true);
 }
} finally {await job('publication-clear');}
