param([int]$BuildNumber = 1)
$ErrorActionPreference = 'Stop'
$taskRepo = Split-Path $PSScriptRoot -Parent
$taskConfigPath = Join-Path $taskRepo '.tool-state/beta/client.json'
if (-not (Test-Path -LiteralPath $taskConfigPath)) { throw 'Start backend/beta_runtime.py before building the beta APK.' }
$taskConfig = Get-Content -LiteralPath $taskConfigPath -Raw | ConvertFrom-Json
$allowed = @('BETA_BUILD','API_BASE_URL','SUPABASE_URL','SUPABASE_PUBLISHABLE_KEY')
foreach ($property in $taskConfig.PSObject.Properties.Name) { if ($property -notin $allowed) { throw 'Unexpected client config field; never embed backend secrets.' } }
foreach ($name in @('API_BASE_URL', 'SUPABASE_URL')) {
    $uri = [uri]$taskConfig.$name
    if ($uri.Scheme -ne 'https' -or $uri.IsLoopback -or $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.Host -notmatch '\.') { throw 'Beta requires public HTTPS endpoints.' }
}
if ($taskConfig.BETA_BUILD -ne 'true') { throw 'Beta release validation must be enabled.' }
$key = $taskConfig.SUPABASE_PUBLISHABLE_KEY
if ($key -notlike 'sb_publishable_*') {
    try {
        $payload = $key.Split('.')[1].Replace('-', '+').Replace('_', '/')
        $payload = $payload.PadRight($payload.Length + ((4 - $payload.Length % 4) % 4), '=')
        $role = ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json).role
        if ($role -ne 'anon') { throw 'Invalid role' }
    } catch { throw 'Only a Supabase publishable or anon key may enter the APK.' }
}
& (Join-Path $taskRepo 'backend/.venv/Scripts/python.exe') (Join-Path $taskRepo 'backend/beta_runtime.py') check $taskConfig.API_BASE_URL.TrimEnd('/')
if ($LASTEXITCODE -ne 0) { throw 'Public beta gateway is not ready.' }
Push-Location (Join-Path $taskRepo 'frontend')
try {
    flutter build apk --release --build-name=0.1.0-beta.1 "--build-number=$BuildNumber" "--dart-define-from-file=$taskConfigPath"
    if ($LASTEXITCODE -ne 0) { throw 'APK build failed.' }
    $taskOutput = Join-Path $taskRepo 'output/beta'
    New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
    $taskApk = Join-Path $taskOutput "modellyng-0.1.0-beta.1-$BuildNumber.apk"
    Copy-Item -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Destination $taskApk
    $hash = (Get-FileHash -LiteralPath $taskApk -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText("$taskApk.sha256", "$hash  $([IO.Path]::GetFileName($taskApk))`n")
    Write-Output "APK: $taskApk"
    Write-Output "SHA256: $hash"
} finally { Pop-Location }
