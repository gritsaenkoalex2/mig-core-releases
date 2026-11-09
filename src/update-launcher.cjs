'use strict';
const fs=require('node:fs');const path=require('node:path');const {spawn}=require('node:child_process');
function launchUpdate({script,config,directory,systemRoot=process.env.SystemRoot||process.env.WINDIR,spawnProcess=spawn}){
 if(!systemRoot||!path.isAbsolute(directory))throw Error('Не удалось определить системную папку Windows или папку журнала.');
 const executable=path.join(systemRoot,'System32','WindowsPowerShell','v1.0','powershell.exe');
 const quote=s=>"'"+s.replace(/'/g,"''")+"'";
 const actual=Buffer.from(`& ${quote(script)} -Config ${quote(config)}; exit $LASTEXITCODE`,'utf16le').toString('base64');
 const out=path.join(directory,'update-launch.stdout.txt'),err=path.join(directory,'update-launch.stderr.txt'),pidFile=path.join(directory,'update-launch.pid');
 // Start-Process creates the independent hidden Windows process. Node's detached mode
 // can silently skip execution; a directly attached PowerShell can die with its console.
 const command=`$ErrorActionPreference='Stop'; try { $p=Start-Process -FilePath ${quote(executable)} -ArgumentList @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand','${actual}') -WindowStyle Hidden -RedirectStandardOutput ${quote(out)} -RedirectStandardError ${quote(err)} -PassThru; [IO.File]::WriteAllText(${quote(pidFile)},[string]$p.Id) } catch { [Console]::Error.WriteLine($_.Exception.Message); exit 1 }`;
 const encoded=Buffer.from(command,'utf16le').toString('base64');
 const env={...process.env};for(const key of Object.keys(env))if(key.toLowerCase()==='psmodulepath')delete env[key];
 const controllerOut=path.join(directory,'update-launch.controller.stdout.txt'),controllerStderr=path.join(directory,'update-launch.controller.stderr.txt');
 const stdout=fs.openSync(controllerOut,'w'),stderr=fs.openSync(controllerStderr,'w');
 try{return {child:spawnProcess(executable,['-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',encoded],{env,cwd:directory,detached:false,stdio:['ignore',stdout,stderr],windowsHide:true}),stderr:err,controllerStderr,pidFile};}
 finally{fs.closeSync(stdout);fs.closeSync(stderr);}
}
module.exports={launchUpdate};
