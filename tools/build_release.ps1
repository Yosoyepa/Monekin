<#
.SYNOPSIS
Builds the signed release APKs of Finanzas IA and copies them with their distribution names.

.DESCRIPTION
--split-debug-info moves the Dart debug symbols out of the APK. That keeps the arm64 APK under
40 MiB (criterion C1 in docs/tasks/T002_apk-finanzas-ia.md). Keep the symbols folder, because
`flutter symbolize` needs it to read the stack trace of a release crash.

The release key stays outside the repository: android/keys/key.properties points to it. Without
that file the APK would be signed with the debug key, so Google sign-in would fail and it could
not update the app already installed on a phone.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File tools\build_release.ps1
#>
param(
    [string]$Defines = 'D:\Dev\keys\release-defines.json',
    [string]$Symbols = '',
    [string]$Out = 'D:\Dev\apk',
    [double]$MaxMiB = 40
)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

if (Test-Path 'D:\Dev\dev-env.ps1') { . 'D:\Dev\dev-env.ps1' }
if (-not (Test-Path 'android\keys\key.properties')) {
    throw 'android\keys\key.properties is missing, so the APK would be signed with the debug key.'
}
if (-not (Test-Path $Defines)) { throw "Missing $Defines (it must hold GOOGLE_SERVER_CLIENT_ID)." }

$version = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
if (-not $Symbols) { $Symbols = "D:\Dev\symbols\finanzas-$version" }

flutter build apk --release --split-per-abi "--split-debug-info=$Symbols" "--dart-define-from-file=$Defines"
if ($LASTEXITCODE -ne 0) { throw "flutter build apk failed with exit code $LASTEXITCODE" }

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$names = [ordered]@{
    'app-arm64-v8a-release.apk'   = 'FinanzasIA-arm64.apk'
    'app-armeabi-v7a-release.apk' = 'FinanzasIA-armv7.apk'
}
foreach ($built in $names.Keys) {
    $target = Join-Path $Out $names[$built]
    Copy-Item (Join-Path 'build\app\outputs\flutter-apk' $built) $target -Force
    '{0,-22} {1,6:N2} MiB' -f $names[$built], ((Get-Item $target).Length / 1MB)
}

$arm64 = (Get-Item (Join-Path $Out 'FinanzasIA-arm64.apk')).Length / 1MB
if ($arm64 -gt $MaxMiB) { throw ('The arm64 APK is {0:N2} MiB, over the {1} MiB limit (C1).' -f $arm64, $MaxMiB) }

$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { 'D:\Dev\Android\Sdk' }
$tools = Get-ChildItem (Join-Path $sdk 'build-tools') -Directory | Sort-Object { [version]$_.Name } | Select-Object -Last 1
$apksigner = Join-Path $tools.FullName 'apksigner.bat'
if (Test-Path $apksigner) {
    & $apksigner verify --print-certs (Join-Path $Out 'FinanzasIA-arm64.apk') | Select-String 'SHA-1'
}
"Symbols: $Symbols (keep them to read release stack traces with flutter symbolize)"
