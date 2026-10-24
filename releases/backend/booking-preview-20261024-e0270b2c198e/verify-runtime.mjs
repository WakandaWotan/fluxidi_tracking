import fs from'node:fs';import path from'node:path';import a from'node:assert/strict';import{createHash}from'node:crypto';
const{build,version}=await import(process.env.FLUXIDI_ESBUILD_MODULE||'esbuild');a.equal(version,'0.27.0');
const root=import.meta.dirname,src=root+'/candidate/source-closure',release=JSON.parse(fs.readFileSync(root+'/RELEASE.json')),sha=b=>createHash('sha256').update(b).digest('hex');
for(const f of JSON.parse(fs.readFileSync(root+'/SOURCE-HASHES.json')).files)a.equal(sha(fs.readFileSync(root+'/'+f.path)),f.sha256,'SOURCE_HASH '+f.path);
const opts={bundle:true,format:'esm',platform:'neutral',target:'es2022',metafile:true,logLevel:'silent',external:['node:*','cloudflare:*'],write:false,absWorkingDir:src,plugins:[{name:'sealed-resolution',setup(b){
 b.onResolve({filter:/reliable_national_publication_policy_v1\.mjs$/},x=>x.kind==='entry-point'?null:{path:'./operational-publication-policy.mjs',external:true});
 b.onResolve({filter:/financial_route_batch_v1\.mjs$/},()=>({path:src+'/retained-source/workers/booking/modules/financial_route_batch_candidate.mjs'}));
 b.onResolve({filter:/(reliable_national_points_v1|reliable_national_publication_v1|product_estimated_eta_v1)\.mjs$/},x=>({path:src+'/workers/booking/cache-correction/'+path.basename(x.path)}));
 b.onResolve({filter:/fluxidi_booking_worker\.js$/},x=>x.importer.replaceAll('\\','/').includes('/retained-source/')?{path:src+'/retained-source/workers/booking/quote_handler_candidate.js'}:null);
}}]};
const b=await build({...opts,entryPoints:[src+'/workers/booking/launch_entry_candidate.mjs'],outfile:root+'/candidate/booking/entry.mjs'}),booking=sha(b.outputFiles[0].contents);a.equal(booking,release.artifacts.booking);
for(const[k,pin]of[['booking',booking],['tracking',release.preservedTrackingCompanionBuildInput]]){const r=await build({...opts,entryPoints:[src+'/retained-source/workers/booking/modules/reliable_national_publication_policy_v1.mjs'],outfile:root+'/candidate/'+k+'/operational-publication-policy.mjs',define:{__FLUXIDI_NATIONAL_RUNTIME_SHA256__:JSON.stringify(pin)}});a.equal(sha(r.outputFiles[0].contents),release.artifacts[k==='booking'?'companion':'trackingCompanion'],k+' companion');}
const t=await build({...opts,entryPoints:[src+'/retained-source/workers/tracking/entry_candidate.mjs'],outfile:root+'/candidate/tracking/entry.mjs'});a.equal(sha(t.outputFiles[0].contents),release.artifacts.tracking);
for(const[k,files]of Object.entries({booking:{'entry.mjs':'booking','operational-publication-policy.mjs':'companion'},tracking:{'entry.mjs':'tracking','operational-publication-policy.mjs':'trackingCompanion'},navigation:{'navigation.mjs':'navigation'}}))for(const[name,key]of Object.entries(files))a.equal(sha(fs.readFileSync(root+'/candidate/'+k+'/'+name)),release.artifacts[key],k+'/'+name);
console.log(JSON.stringify({sourceFiles:403,exactActiveRuntimeReproduced:true,artifacts:release.artifacts,productionCalls:0,artifactWrites:0}));
