// Exercise the actual Lua transmitter and producer, not a reimplementation.
const {createLuaEnv}=require('./test_sync_network_load');
const fs=require('fs'), path=require('path');
const {lua,lauxlib,to_luastring}=require('fengari');
function run(L,code){if(lauxlib.luaL_dostring(L,to_luastring(code))!==lua.LUA_OK)throw Error(lua.lua_tojsstring(L,-1));}
function env(){
 const L=createLuaEnv(`
 clock=1000;function GetTime() return clock end
 tickers={};scheduled={};attempts={};rejectType=nil;rejectCount=0;alwaysReject=false
 C_Timer.NewTicker=function(interval,fn) tickers[interval]=fn;return {Cancel=function() end} end
 C_Timer.After=function(delay,fn) scheduled[#scheduled+1]={at=clock+delay,fn=fn} end
 C_Timer.NewTimer=function(delay,fn) return {Cancel=function() end} end
 C_ChatInfo.SendAddonMessage=function(prefix,payload,channel)
  local kind=payload:match('^([^;]+)');local result=0
  if alwaysReject or (kind==rejectType and rejectCount>0) then result=3;rejectCount=rejectCount-1 end
  attempts[#attempts+1]={prefix=prefix,payload=payload,channel=channel,result=result,at=clock}
  return result
 end
 hooksecurefunc=function(t,k,fn)
  local original=t[k]
  t[k]=function(...) local result=original(...);fn(...);return result end
 end
 `);
 for(const file of ['Config.lua','Sync.lua'])run(L,fs.readFileSync(path.join(__dirname,'../MarketSync',file),'utf8'));
 run(L,`
 MarketSync.myRealm='Faerlina'
 local db={PersonalData={},GuildData={},NeutralData={},NeutralSwarmTSF=1000}
 for i=1,80 do db.NeutralData[tostring(i)]={vd=100,vm=i*100,vq=2} end
 MarketSync.GetRealmDB=function() return db end
 MarketSync.GetMyLatestNeutralScanDay=function() return 100 end
 MarketSync.GetAddOnMetadata=function() return '0.9.7-rc6' end
 MarketSync.IsLocalSyncIdentity=function(name) return name=='LocalPlayer' end
 MarketSync.GetLocalSyncIdentity=function() return 'LocalPlayer' end
 MarketSync.CanSync=function() return true end
 function Start() assert(MarketSync.StartDirectedBroadcast('N',0,100,1000,'LocalPlayer','Peer')) end
 function Tick(n,step)
  for _=1,n do clock=clock+(step or .35);tickers[.35]() end
 end
 function Accepted(kind)
  local out={};for _,a in ipairs(attempts) do if a.result==0 and a.payload:match('^([^;]+)')==kind then out[#out+1]=a.payload end end;return out
 end
 `);return L;
}
for(const kind of ['BEGIN','DATA','END']){
 const L=env();run(L,`
 rejectType='${kind}';rejectCount=2;Start();Tick(300)
 local refused={};for _,a in ipairs(attempts) do if a.result~=0 then refused[#refused+1]=a end end
 assert(#refused==2 and refused[1].payload==refused[2].payload,'Retry must preserve exact frame')
 local found=false;for _,a in ipairs(attempts) do if a.result==0 and a.payload==refused[1].payload then found=true end end
 assert(found,'Refused frame eventually accepted')
 assert(refused[2].at-refused[1].at>=.7,'Backoff prevents per-tick retry spam')
 assert(#Accepted('BEGIN')==1 and #Accepted('END')==1,'BEGIN and END accepted once')
 local sequence=0
 for _,payload in ipairs(Accepted('DATA')) do
  local encoded=payload:match('^DATA;[^;]+;([^;]+);')
  local n=MarketSync.FromBase36(encoded);assert(n==sequence+1,'No skipped or duplicate accepted sequence');sequence=n
 end
 assert(MarketSync.TxCount==80,'Only accepted records counted')
 assert(not MarketSync.GetSyncTaskStatus().outbound and MarketSync.SyncSendStats.refused==2)
 `);
 console.log('PASS retained '+kind+' frame, backoff, accepted sequence and completion');
}
{
 const L=env();run(L,`
 alwaysReject=true;Start();Tick(140)
 assert(not MarketSync.GetSyncTaskStatus().outbound,'Permanent refusal must release sender lane')
 assert(#Accepted('END')==0 and MarketSync.TxCount==0,'Refused sends must not claim success')
 assert(MarketSync.SyncQueueStats.aborted==1)
 local begin=0;for _,a in ipairs(attempts) do if a.payload:match('^BEGIN;') then begin=begin+1 end end
 assert(begin<=6,'Attempts bounded')
 `);console.log('PASS permanent refusal aborts without false completion');
}
{
 const L=env();run(L,`
 Start();Tick(1);assert(#Accepted('BEGIN')==1)
 clock=clock+40;Tick(1)
 assert(not MarketSync.GetSyncTaskStatus().outbound and #Accepted('DATA')==0,'Do not resume an expired receiver lease after a long client hitch')
 `);console.log('PASS expired receiver lease cannot be revived by late progress');
}
{
 const L=env();run(L,`
 MarketSync.OtherTxBytesRate=1000;MarketSync.OtherTxAPIRate=5
 Start();Tick(40)
 assert(#Accepted('DATA')==0,'Initially yields to external pressure')
 Tick(12);assert(#Accepted('DATA')==1,'Sparse fair probe allows progress')
 Tick(30);assert(#Accepted('DATA')==1,'No probe burst under continued pressure')
 Tick(20);assert(#Accepted('DATA')==2,'Progress can continue without ignoring pressure')
 local before=#Accepted('DATA');MarketSync.OtherTxAPIRate=45;Tick(400)
 assert(#Accepted('DATA')==before and not MarketSync.GetSyncTaskStatus().outbound,'API flood pauses and ultimately expires transfer')
 `);console.log('PASS sparse progress probes, API flood gate and bounded stall');
}
{
 const L=env();run(L,`
 rejectType='NPULL';rejectCount=1
 assert(MarketSync.ScheduleDirectedPull('N',100,'Peer',101,1001))
 while #scheduled>0 do
  table.sort(scheduled,function(a,b) return a.at<b.at end)
  local timer=table.remove(scheduled,1);clock=timer.at;timer.fn()
 end
 assert(#attempts==1 and attempts[1].result==3 and MarketSync.GetSyncTaskStatus().controlQueued==1)
 Tick(20)
 assert(#Accepted('NPULL')==1 and MarketSync.GetSyncTaskStatus().controlQueued==0,'Refused immediate pull retries without losing request')
 `);console.log('PASS immediate directed PULL refusal enters bounded retry queue');
}
{
 const L=env();run(L,`
 for i=1,100 do MarketSync.QueueSyncControl('ADV;'..i,'ADV'..i) end
 assert(MarketSync.GetSyncTaskStatus().controlQueued==64,'Control queue bounded')
 assert(MarketSync.SyncQueueStats.dropped==36)
 clock=clock+31;Tick(1)
 assert(MarketSync.GetSyncTaskStatus().controlQueued==0 and #attempts==0,'Stale controls expire before sending')
 rejectType='ADV';rejectCount=2
 MarketSync.QueueSyncControl('ADV;latest','ADV');Tick(30)
 assert(#Accepted('ADV')==1 and MarketSync.GetSyncTaskStatus().controlQueued==0,'Control frame retained through refusal')
 `);console.log('PASS control queue size, expiry and retry retention');
}
{
 const L=env();run(L,`
 C_ChatInfo.SendAddonMessage('OverlordF',string.rep('x',400),'WHISPER')
 C_ChatInfo.SendAddonMessage('Other',string.rep('y',200),'GUILD')
 MarketSync.SendAddonMessageChecked(MarketSync.PREFIX,'READY','GUILD')
 clock=clock+4;tickers[1]()
 assert(math.abs(MarketSync.OtherTxBytesRate-150)<.001,'Normalize actual elapsed time')
 assert(math.abs(MarketSync.OtherTxAPIRate-.5)<.001)
 assert(MarketSync.OtherTransportRates.WHISPER.rate==100 and MarketSync.OtherTransportRates.GUILD.rate==50)
 assert(MarketSync.SyncSendRates.accepted==.25,'Own result rates separate from attempts')
 alwaysReject=true;local ok=MarketSync.SendAddonMessageChecked(MarketSync.PREFIX,'X','GUILD');assert(not ok)
 clock=clock+2;tickers[1]()
 assert(MarketSync.SyncSendRates.refused==.5 and MarketSync.OtherTxBytesRate==0,'Refusal measured without misclassifying own load')
 alwaysReject=false
 C_ChatInfo.SendAddonMessage(MarketSync.DATA_PREFIXES[2],'LEGACY','GUILD')
 clock=clock+1;tickers[1]();assert(MarketSync.OtherTxBytesRate==0,'All own data prefixes excluded from external traffic')
 MarketSync.SendAddonMessage=function() return nil end;assert(MarketSync.SendAddonMessageChecked('MSync','X','GUILD'))
 MarketSync.SendAddonMessage=function() return true end;assert(MarketSync.SendAddonMessageChecked('MSync','X','GUILD'))
 MarketSync.SendAddonMessage=function() return false end;assert(not MarketSync.SendAddonMessageChecked('MSync','X','GUILD'))
 MarketSync.SendAddonMessage=function() error('send failure') end;assert(not MarketSync.SendAddonMessageChecked('MSync','X','GUILD'))
 assert(MarketSync.SyncSendStats.errors==1)
 `);console.log('PASS elapsed-time/transport accounting, own prefixes, API results and legacy compatibility');
}
