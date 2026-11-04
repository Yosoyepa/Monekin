# Runs one integration_test file on the emulator and takes the screenshots the test asks for.
# The test prints `E2E_MARKER shot <name>`; this script answers with `adb exec-out screencap -p`.
# Other markers (`E2E_MARKER post-notices`, ...) are handled by the -OnMarker hook.
# Usage: .\docs\e2e\run_e2e.ps1 -TestFile integration_test/finanzas_ia/setup_ai_settings_test.dart -Log <path>
param(
  [Parameter(Mandatory)] [string] $TestFile,
  [Parameter(Mandatory)] [string] $Log,
  [string] $Defines = 'D:\Dev\secrets\e2e-defines.json',
  [string] $Device = 'emulator-5554',
  [scriptblock] $OnMarker = $null
)
. D:\Dev\dev-env.ps1
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$screens = Join-Path $root 'docs\e2e\screens'
New-Item -ItemType Directory -Force $screens | Out-Null
Remove-Item $Log -ErrorAction SilentlyContinue

$proc = Start-Process -FilePath flutter -WorkingDirectory $root -PassThru -NoNewWindow `
  -ArgumentList 'test', $TestFile, '-d', $Device, '--no-pub', "--dart-define-from-file=$Defines" `
  -RedirectStandardOutput $Log -RedirectStandardError "$Log.err"

$seen = 0
while ($true) {
  Start-Sleep -Milliseconds 400
  if (Test-Path $Log) {
    $lines = @(Get-Content $Log -ErrorAction SilentlyContinue)
    for ($i = $seen; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match 'E2E_MARKER (\S+)\s*(.*)$') {
        $kind = $Matches[1]; $arg = $Matches[2].Trim()
        if ($kind -eq 'shot') {
          $target = Join-Path $screens "$arg.png"
          cmd /c "adb -s $Device exec-out screencap -p > `"$target`""
        } elseif ($OnMarker) {
          & $OnMarker $kind $arg
        }
      }
    }
    $seen = $lines.Count
  }
  if ($proc.HasExited) { break }
}
exit $proc.ExitCode
