$ErrorActionPreference = 'Stop'
$installer = (Get-ChildItem 'dist/MIG-Core-Setup-*-x64.exe' | Select-Object -First 1).FullName
if (-not $installer) { throw 'Installer missing' }
$installDir = Join-Path $env:RUNNER_TEMP 'mig-core-installed'
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
  $uninstaller = Join-Path $installDir 'Uninstall MIG Core.exe'
  if (-not (Test-Path $uninstaller)) { throw 'Uninstaller missing' }
  $remove = Start-Process $uninstaller -ArgumentList '/S' -PassThru
  if (-not $remove.WaitForExit(60000)) { throw 'Uninstaller timed out' }
  if ($remove.ExitCode -ne 0) { throw 'Uninstaller failed' }
  for ($i=0; $i -lt 40 -and (Test-Path $exe); $i++) { Start-Sleep -Milliseconds 250 }
  if (Test-Path $exe) { throw 'Application still present after uninstall' }
} finally { if (-not $mock.HasExited) { Stop-Process -Id $mock.Id -Force } }
