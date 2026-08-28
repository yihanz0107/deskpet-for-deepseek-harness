$ErrorActionPreference = 'Stop'
if (-not [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)) {
  throw 'install.ps1 is for Windows. On macOS or Linux, run ./install.sh.'
}
Write-Host 'Detected Windows. Installing the cross-platform desktop pet.'

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$installRoot = Join-Path $env:LOCALAPPDATA 'DeepSSPet'
$toolchainRoot = Join-Path $installRoot 'toolchain'
$nodeRoot = Join-Path $toolchainRoot 'node-current'
$pnpmRoot = Join-Path $toolchainRoot 'pnpm'
$binRoot = Join-Path $installRoot 'bin'
$petApp = Join-Path $installRoot 'app'
$configFile = Join-Path $env:APPDATA 'DeepSSPet\harness-path'

function Test-Node {
  try { node -e "const [a,b]=process.versions.node.split('.').map(Number);process.exit((a===22&&b>=19)||a>=24?0:1)"; return $LASTEXITCODE -eq 0 } catch { return $false }
}

if (-not (Test-Node)) {
  Write-Host 'Preparing Node.js 24...'
  $arch = if ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq 'Arm64') { 'arm64' } else { 'x64' }
  $versions = Invoke-RestMethod 'https://registry.npmmirror.com/-/binary/node/index.json'
  $version = ($versions | Where-Object { $_.version -like 'v24.*' } | Select-Object -First 1).version
  if (-not $version) { throw 'Could not determine the latest Node.js 24 version.' }
  $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("deepsshpet-node-" + [guid]::NewGuid())
  New-Item -ItemType Directory -Path $tempRoot | Out-Null
  try {
    $name = "node-$version-win-$arch"
    $archive = Join-Path $tempRoot 'node.zip'
    Invoke-WebRequest "https://registry.npmmirror.com/-/binary/node/$version/$name.zip" -OutFile $archive
    Expand-Archive $archive -DestinationPath $tempRoot
    if (Test-Path $nodeRoot) { Remove-Item $nodeRoot -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $toolchainRoot | Out-Null
    Move-Item (Join-Path $tempRoot $name) $nodeRoot
  } finally { Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
$env:PATH = "$nodeRoot;$pnpmRoot;$env:PATH"

$savedHarness = if (Test-Path $configFile) { (Get-Content $configFile -TotalCount 1).Trim() } else { '' }
$candidates = @($env:DEEPSEEK_HARNESS_HOME, $savedHarness, (Join-Path $env:USERPROFILE 'deepseek-harness'), (Join-Path $env:USERPROFILE 'Documents\deepseek-harness'), (Join-Path $env:USERPROFILE 'Desktop\deepseek-harness'))
$harnessRoot = $candidates | Where-Object { $_ -and (Test-Path (Join-Path $_ 'package.json')) -and (Test-Path (Join-Path $_ 'apps\web\index.html')) } | Select-Object -First 1
if (-not $harnessRoot) {
  $harnessRoot = Join-Path $env:USERPROFILE 'deepseek-harness'
  if (Test-Path $harnessRoot) { throw "$harnessRoot exists but is not a valid DeepSeek Harness checkout." }
  Write-Host 'DeepSeek Harness was not found. Installing the latest version...'
  git clone --depth 1 https://github.com/deepseek-ai/deepseek-harness.git $harnessRoot
}

try { pnpm.cmd --version | Out-Null } catch {
  $package = Get-Content (Join-Path $harnessRoot 'package.json') -Raw | ConvertFrom-Json
  $pnpmVersion = if ($package.packageManager -match '^pnpm@(.+)$') { $Matches[1] } else { 'latest' }
  New-Item -ItemType Directory -Force -Path $pnpmRoot | Out-Null
  npm.cmd install --global --prefix $pnpmRoot --registry=https://registry.npmmirror.com "pnpm@$pnpmVersion"
}

if (-not (Test-Path (Join-Path $harnessRoot 'node_modules'))) {
  Push-Location $harnessRoot
  try { pnpm.cmd install --frozen-lockfile } finally { Pop-Location }
}

New-Item -ItemType Directory -Force -Path $petApp | Out-Null
Copy-Item (Join-Path $projectRoot 'cross-platform\package.json'), (Join-Path $projectRoot 'cross-platform\main.cjs'), (Join-Path $projectRoot 'cross-platform\pet.html'), (Join-Path $projectRoot 'cross-platform\pet.css'), (Join-Path $projectRoot 'cross-platform\renderer.js') -Destination $petApp -Force
Copy-Item (Join-Path $projectRoot 'app\Assets\bongocat-spritesheet.png') (Join-Path $petApp 'bongocat-spritesheet.png') -Force
Copy-Item (Join-Path $projectRoot 'app\BundledPets') -Destination $petApp -Recurse -Force
Push-Location $petApp
try {
  $env:ELECTRON_MIRROR = 'https://npmmirror.com/mirrors/electron/'
  npm.cmd install --omit=dev --no-audit --no-fund --registry=https://registry.npmmirror.com
} finally { Pop-Location; Remove-Item Env:ELECTRON_MIRROR -ErrorAction SilentlyContinue }

$webPublic = Join-Path $harnessRoot 'apps\web\public'
New-Item -ItemType Directory -Force -Path $webPublic | Out-Null
Copy-Item (Join-Path $projectRoot 'web\deepss-pet.js') (Join-Path $webPublic 'deepss-pet.js') -Force
$indexFile = Join-Path $harnessRoot 'apps\web\index.html'
$env:INDEX_FILE = $indexFile
node -e "const fs=require('node:fs'),f=process.env.INDEX_FILE;let h=fs.readFileSync(f,'utf8'),t='<script src=\"/deepss-pet.js?v=20260828\"></script>',r=/<script src=\"\\/deepss-pet\\.js(?:\\?v=[^\"]*)?\"><\\/script>/g;h=r.test(h)?h.replace(r,t):h.replace('</body>','    '+t+'\n  </body>');fs.writeFileSync(f,h)"

New-Item -ItemType Directory -Force -Path (Split-Path $configFile), $binRoot | Out-Null
Set-Content -Path $configFile -Value $harnessRoot
Copy-Item (Join-Path $projectRoot 'bin\deepsshpet.ps1'), (Join-Path $projectRoot 'bin\deepsshpet.cmd') -Destination $binRoot -Force

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $binRoot) {
  [Environment]::SetEnvironmentVariable('Path', (($userPath.TrimEnd(';') + ';' + $binRoot).TrimStart(';')), 'User')
  Write-Host 'The deepsshpet command was added to your user PATH. Open a new terminal before running it.'
}

Push-Location $harnessRoot
try { pnpm.cmd run build } finally { Pop-Location }
Write-Host "DeepSeek Harness: $harnessRoot"
Write-Host 'Run: deepsshpet'
