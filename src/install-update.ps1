param([Parameter(Mandatory=$true)][string]$Config)
$ErrorActionPreference = 'Stop'
$c = $null
function HashFile([string]$file) {
  $algorithm = [Security.Cryptography.SHA256]::Create()
  $stream = [IO.File]::OpenRead($file)
  try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-','').ToLowerInvariant() }
  finally { $stream.Dispose(); $algorithm.Dispose() }
}
function Record([string]$stage, [string]$message='') {
  $state = @{stage=$stage;message=$message;version=$c.version;at=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json
  [IO.File]::WriteAllText($c.journal+'.tmp',$state,[Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath ($c.journal+'.tmp') -Destination $c.journal -Force
}
try {
  $c = Get-Content -LiteralPath $Config -Raw -Encoding UTF8 | ConvertFrom-Json
  if ((HashFile $c.installer) -ne $c.hash) { throw 'Update hash mismatch' }
  if (-not (Test-Path -LiteralPath $c.exe)) { throw 'Installed application missing' }
  Record 'ready'
  # Do not start until the app explicitly authorizes this particular transaction.
  $deadline = [DateTime]::UtcNow.AddSeconds(40)
  while (-not (Test-Path -LiteralPath $c.go)) {
    if ([DateTime]::UtcNow -gt $deadline) { throw 'Application did not authorize installation' }
    Start-Sleep -Milliseconds 200
  }
  $parent = Get-Process -Id $c.parent -ErrorAction SilentlyContinue
  if ($parent -and -not $parent.WaitForExit(60000)) { throw 'Application did not exit' }
  Record 'installing'
  # NSIS /D must be the last argument, unquoted, even when its path contains spaces.
  $installer = Start-Process -FilePath $c.installer -ArgumentList ('/S /D='+$c.directory) -PassThru
  if (-not $installer.WaitForExit(240000)) { throw 'Installer timed out' }
  if ($installer.ExitCode -ne 0) { throw ('Installer failed: '+$installer.ExitCode) }
  # Compare the actual packaged app bytes, not the UI label or installer exit alone.
  $asar = Join-Path $c.directory 'resources/app.asar'
  if ($c.appHash -and (HashFile $asar) -ne $c.appHash) { throw 'Installed application verification failed' }
  Record 'installed'
  Start-Process -FilePath $c.exe | Out-Null
  Record 'restarted'
} catch {
  if ($c) {
    [IO.File]::WriteAllText($c.error,$_.Exception.Message,[Text.UTF8Encoding]::new($false))
    Record 'error' $_.Exception.Message
    if ((Test-Path -LiteralPath $c.go) -and (Test-Path -LiteralPath $c.exe)) { Start-Process -FilePath $c.exe | Out-Null }
  }
  exit 1
}
