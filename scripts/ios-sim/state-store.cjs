#!/usr/bin/env node
"use strict";
const fs=require("node:fs"),path=require("node:path"),os=require("node:os"),crypto=require("node:crypto"),cp=require("node:child_process");
const {pipeline}=require("node:stream/promises"),{Readable}=require("node:stream");
const {DefaultArtifactClient}=require(path.join(process.env.RUNNER_TEMP,"ios-sim-artifacts/node_modules/@actions/artifact"));
const namePrefix="ios-sim-state-v1-", magic=Buffer.from("IOSSTATE1"), HEADER=magic.length+16+12, TAG=16;
const secret=process.env.SIMULATOR_STATE_PASSPHRASE, temp=process.env.RUNNER_TEMP;
const get=(name)=>fs.readFileSync(path.join(temp,name),"utf8").trim();
const udid=get("ios-simulator.udid"),runtime=get("ios-simulator.runtime"),type=get("ios-simulator.type");
const data=path.join(os.homedir(),"Library/Developer/CoreSimulator/Devices",udid,"data");
const tweaks=path.join(os.homedir(),".remote-ios-simulator/tweaks");
function exec(cmd,...args){const v=cp.spawnSync(cmd,args,{stdio:"inherit"});if(v.status!==0)throw Error(cmd+" failed (exit "+v.status+")");}
function requireSecret(){if(!secret||secret.length<16)throw Error("SIMULATOR_STATE_PASSPHRASE must be 16+ characters");}
async function encrypt(src,dest){
 const salt=crypto.randomBytes(16),nonce=crypto.randomBytes(12);
 const cipher=crypto.createCipheriv("aes-256-gcm",crypto.scryptSync(secret,salt,32),nonce);
 fs.writeFileSync(dest,Buffer.concat([magic,salt,nonce]),{mode:0o600});
 await pipeline(fs.createReadStream(src),cipher,fs.createWriteStream(dest,{flags:"a",mode:0o600}));
 fs.appendFileSync(dest,cipher.getAuthTag());
}
async function decrypt(src,dest){
 const f=fs.openSync(src,"r"), size=fs.fstatSync(f).size,header=Buffer.alloc(HEADER),tag=Buffer.alloc(TAG);
 try{if(size<=HEADER+TAG)throw Error("snapshot is truncated");fs.readSync(f,header,0,HEADER,0);fs.readSync(f,tag,0,TAG,size-TAG);}
 finally{fs.closeSync(f);}
 if(!header.subarray(0,magic.length).equals(magic))throw Error("invalid snapshot header");
 const decipher=crypto.createDecipheriv("aes-256-gcm",crypto.scryptSync(secret,header.subarray(magic.length,magic.length+16),32),header.subarray(magic.length+16));
 decipher.setAuthTag(tag);
 try{await pipeline(fs.createReadStream(src,{start:HEADER,end:size-TAG-1}),decipher,fs.createWriteStream(dest,{mode:0o600}));}
 catch(e){fs.rmSync(dest,{force:true});throw Error("snapshot authentication failed: "+e.message);}
}
async function save(){
 requireSecret();
 const dir=fs.mkdtempSync(path.join(temp,"sim-save-"));
 try{
  const payload=path.join(dir,"payload");
  fs.mkdirSync(payload);fs.mkdirSync(path.join(payload,"data"));fs.mkdirSync(path.join(payload,"tweaks"));
  fs.writeFileSync(path.join(payload,"manifest.json"),JSON.stringify({schema:1,runtime,type,sourceRun:process.env.GITHUB_RUN_ID,time:new Date().toISOString()}));
  if(!fs.existsSync(data))throw Error("simulator data directory missing");
  exec("rsync","-a",data+"/",path.join(payload,"data/"));
  if(fs.existsSync(tweaks))exec("rsync","-a",tweaks+"/",path.join(payload,"tweaks/"));
  const tar=path.join(dir,"state.tgz"),enc=path.join(dir,"state.enc");
  exec("tar","-czf",tar,"-C",payload,".");
  await encrypt(tar,enc);
  const label=namePrefix+process.env.GITHUB_RUN_ID+"-"+Date.now();
  const result=await new DefaultArtifactClient().uploadArtifact(label,[enc],{retentionDays:30,compressionLevel:0});
  console.log("Encrypted simulator state uploaded:",label,"artifact",result.id);
 }finally{fs.rmSync(dir,{recursive:true,force:true});}
}
async function getUrl(url){
 const res=await fetch(url,{headers:{Authorization:"Bearer "+process.env.GH_TOKEN,Accept:"application/vnd.github+json","X-GitHub-Api-Version":"2022-11-28"},redirect:"follow"});
 if(!res.ok)throw Error("GitHub API HTTP "+res.status+" "+url);return res;
}
async function restore(){
 requireSecret();if(!process.env.GH_TOKEN)throw Error("Missing GH_TOKEN");
 const base=(process.env.GITHUB_API_URL||"https://api.github.com")+"/repos/"+process.env.GITHUB_REPOSITORY;
 const index=await(await getUrl(base+"/actions/artifacts?per_page=100")).json();
 const found=(index.artifacts||[]).filter(a=>!a.expired&&a.name.startsWith(namePrefix)).sort((a,b)=>Date.parse(b.created_at)-Date.parse(a.created_at));
 if(!found.length){console.log("No checkpoint found: clean simulator.");return;}
 for(const entry of found.slice(0,12)){
  const dir=fs.mkdtempSync(path.join(temp,"sim-restore-"));
  try{
   console.log("Trying checkpoint",entry.name);
   const resp=await getUrl(base+"/actions/artifacts/"+entry.id+"/zip");
   const zip=path.join(dir,"snapshot.zip");
   await pipeline(Readable.fromWeb(resp.body),fs.createWriteStream(zip));
   exec("unzip","-q",zip,"-d",dir);
   const tar=path.join(dir,"state.tgz");
   await decrypt(path.join(dir,"state.enc"),tar);
   const payload=path.join(dir,"payload");fs.mkdirSync(payload);
   exec("tar","-xzf",tar,"-C",payload);
   const manifest=JSON.parse(fs.readFileSync(path.join(payload,"manifest.json"),"utf8"));
   if(manifest.schema!==1||manifest.runtime!==runtime||manifest.type!==type)throw Error("runtime/device type mismatch");
   if(!fs.existsSync(path.join(payload,"data")))throw Error("missing device data");
   fs.mkdirSync(data,{recursive:true});
   exec("rsync","-a","--delete",path.join(payload,"data/"),data+"/");
   fs.mkdirSync(tweaks,{recursive:true});
   exec("rsync","-a","--delete",path.join(payload,"tweaks/"),tweaks+"/");
   console.log("Restored authenticated simulator state from",entry.name);
   if(process.env.GITHUB_STEP_SUMMARY)fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY,"Checkpoint restored: \`"+entry.name+"\`\n");
   return;
  }catch(e){console.warn("Checkpoint rejected:",entry.name,e.message);}
  finally{fs.rmSync(dir,{recursive:true,force:true});}
 }
 throw Error("No valid compatible checkpoint; verify passphrase and runtime or disable restore.");
}
(async()=>{if(process.argv[2]==="save")await save();else if(process.argv[2]==="restore")await restore();else throw Error("Expected save or restore");})().catch(e=>{console.error(e.message);process.exitCode=1;});
