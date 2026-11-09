$ErrorActionPreference = 'Stop'
$installer = (Get-ChildItem 'dist/MIG-Core-Setup-*-x64.exe' | Select-Object -First 1).FullName
if (-not $installer) { throw 'Installer missing' }
$installDir = Join-Path $env:RUNNER_TEMP 'mig core installed'
$report = Join-Path $env:RUNNER_TEMP 'mig-core-smoke.json'
$env:MIG_SMOKE_USER_DATA = Join-Path $env:RUNNER_TEMP 'mig-core-test-data'
$env:MIG_SMOKE_ENDPOINT = 'http://127.0.0.1:17777'
$env:MIG_MOCK_REPORT = Join-Path $env:RUNNER_TEMP 'mig-core-mock.json'
$mock = Start-Process node -ArgumentList 'test/mock-server.cjs' -PassThru -RedirectStandardOutput (Join-Path $env:RUNNER_TEMP 'mig-mock.log')
try {
  $install = Start-Process -FilePath $installer -ArgumentList "/S /D=$installDir" -PassThru
  if (-not $install.WaitForExit(90000)) { $install.Kill(); throw 'Installer timed out' }
  if ($install.ExitCode -ne 0) { throw "Installer failed: $($install.ExitCode)" }
  $exe = Join-Path $installDir 'MIG Core.exe'
  if (-not (Test-Path $exe)) { throw 'Installed executable missing' }
  $proc = Start-Process -FilePath $exe -ArgumentList "--smoke-test --report=$report" -PassThru
  if (-not $proc.WaitForExit(90000)) { $proc.Kill(); throw 'Application smoke test timed out' }
  if ($proc.ExitCode -ne 0) { if(Test-Path $report){Get-Content $report}; throw "Application failed: $($proc.ExitCode)" }
  $result = Get-Content $report -Raw | ConvertFrom-Json
  if (-not $result.ok -or -not $result.ui -or -not $result.chat -or -not $result.instructions) { throw 'Installed UI chat smoke failed' }
  $model = Get-Content $env:MIG_MOCK_REPORT -Raw | ConvertFrom-Json
  if ($model.chats -lt 1) { throw 'No actual HTTP chat from installed application' }
  Copy-Item $report 'dist/windows-smoke.json'
  Copy-Item $env:MIG_MOCK_REPORT 'dist/mock-chat-proof.json'
  # Exercise the exact packaged detached bootstrap, including parent-exit handshake.
  $bootstrapDir = Join-Path $env:RUNNER_TEMP "mig обновление User's folder"
  New-Item -ItemType Directory -Force -Path $bootstrapDir | Out-Null
  $script = Join-Path $bootstrapDir 'install-update.ps1'
  Copy-Item 'src/install-update.ps1' $script
  $journal = Join-Path $bootstrapDir 'journal.json'
  $go = Join-Path $bootstrapDir 'go'
  $config = Join-Path $bootstrapDir 'config.json'
  $parent = Start-Process powershell.exe -ArgumentList '-NoProfile -Command "Start-Sleep -Seconds 120"' -PassThru
  @{parent=$parent.Id;installer=$installer;hash=(Get-FileHash $installer -Algorithm SHA256).Hash.ToLower();appHash=(Get-FileHash (Join-Path $installDir 'resources/app.asar') -Algorithm SHA256).Hash.ToLower();version=$result.version;exe=$exe;directory=$installDir;journal=$journal;go=$go;error=(Join-Path $bootstrapDir 'error.txt')} | ConvertTo-Json | Set-Content $config -Encoding UTF8
  $launched = node test/launch-update.cjs $script $config $bootstrapDir | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0 -or -not $launched.pid) { throw 'Production bootstrap launcher failed' }
  try { $bootstrap = [System.Diagnostics.Process]::GetProcessById($launched.pid) } catch { Get-Content (Join-Path $bootstrapDir 'update-launch.stderr.txt'); if(Test-Path $journal){Get-Content $journal};throw }
  for($i=0;$i -lt 150 -and -not (Test-Path $journal);$i++){Start-Sleep -Milliseconds 200}
  $ready = Get-Content $journal -Raw | ConvertFrom-Json
  if($ready.stage -ne 'ready' -or $parent.HasExited){Write-Host ($ready | ConvertTo-Json);Write-Host ('parentExited='+$parent.HasExited);if(Test-Path (Join-Path $bootstrapDir 'error.txt')){Get-Content (Join-Path $bootstrapDir 'error.txt')};throw 'Bootstrap handshake failed'}
  'authorized' | Set-Content $go
  Stop-Process -Id $parent.Id -Force
  if(-not $bootstrap.WaitForExit(300000)){throw 'Bootstrap did not finish'}
  $installed = Get-Content $journal -Raw | ConvertFrom-Json
  $bootstrapCode = $bootstrap.ExitCode
  Write-Host ('Bootstrap exit code: '+$bootstrapCode)
  if(($null -ne $bootstrapCode -and $bootstrapCode -ne 0) -or $installed.stage -ne 'restarted'){throw ('Bootstrap installation failed: exit='+$bootstrapCode+' '+($installed | ConvertTo-Json))}
  if((Get-FileHash (Join-Path $installDir 'resources/app.asar') -Algorithm SHA256).Hash.ToLower() -ne (Get-Content $config -Raw | ConvertFrom-Json).appHash){throw 'Installed application hash changed'}
  Start-Sleep -Seconds 3
  $restarted = @(Get-Process | Where-Object { try { $_.Path -eq $exe } catch { $false } })
  if(-not $restarted.Count){throw 'Application did not remain running after bootstrap restart'}
  $restarted | Stop-Process -Force
  Copy-Item $journal 'dist/bootstrap-proof.json'
  $uninstaller = Join-Path $installDir 'Uninstall MIG Core.exe'
  if (-not (Test-Path $uninstaller)) { throw 'Uninstaller missing' }
  $remove = Start-Process $uninstaller -ArgumentList '/S' -PassThru
  if (-not $remove.WaitForExit(60000)) { throw 'Uninstaller timed out' }
  if ($remove.ExitCode -ne 0) { throw 'Uninstaller failed' }
  for ($i=0; $i -lt 40 -and (Test-Path $exe); $i++) { Start-Sleep -Milliseconds 250 }
  if (Test-Path $exe) { throw 'Application still present after uninstall' }
} finally { if (-not $mock.HasExited) { Stop-Process -Id $mock.Id -Force } }

