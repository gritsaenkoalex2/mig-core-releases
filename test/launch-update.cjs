const fs=require('node:fs');const {launchUpdate}=require('../src/update-launcher.cjs');
const [script,config,directory]=process.argv.slice(2);
const {child,pidFile,controllerStderr}=launchUpdate({script,config,directory});
child.once('error',error=>{console.error(error.message);process.exitCode=1;});
child.once('exit',code=>{if(code!==0){console.error(fs.readFileSync(controllerStderr,'utf8'));process.exitCode=1;return;}const pid=Number(fs.readFileSync(pidFile,'utf8'));if(!Number.isInteger(pid)||pid<1)throw Error('Missing bootstrap process');console.log(JSON.stringify({pid}));});
