# Runs one integration_test file on the emulator and answers the markers the test prints.
# `E2E_MARKER shot <name>`      -> `adb exec-out screencap -p` into docs/e2e/screens/<name>.png
# `E2E_MARKER grant-listener`   -> grants POST_NOTIFICATIONS and notification access to the app
# `E2E_MARKER post-notices`     -> posts the Bancolombia and Nequi notices (cmd notification post, from com.android.shell)
# `E2E_MARKER dump-notifications` -> saves the shade as text in docs/e2e/notifications_dump.txt
# `E2E_MARKER tap-notification <text>` -> opens the shade and taps the notification that contains <text>
# Usage: .\docs\e2e\run_e2e.ps1 -TestFile integration_test/finanzas_ia/setup_ai_settings_test.dart -Log <path> [-Name <word>]
param(
  [Parameter(Mandatory)] [string] $TestFile,
  [Parameter(Mandatory)] [string] $Log,
  [string] $Defines = 'D:\Dev\secrets\e2e-defines.json',
  [string] $Device = 'emulator-5554',
  [string] $Name = ''
)
. D:\Dev\dev-env.ps1
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$screens = Join-Path $root 'docs\e2e\screens'
$package = 'com.yosoyepa.finanzas'
New-Item -ItemType Directory -Force $screens | Out-Null
Remove-Item $Log, "$Log.err" -ErrorAction SilentlyContinue

function Send-Notices {
  # \$ keeps the dollar sign for the device shell; the here-string is literal.
  $script = @'
cmd notification post -S bigtext -t 'Bancolombia' bc1 "Compraste \$32.500,00 en UBER RIDES con tu T.Deb *1234, el 04/11/2026 a las 10:15."
cmd notification post -S bigtext -t 'Nequi' nq1 "Pagaste \$45.900 en EXITO"
'@
  $tmp = Join-Path $env:TEMP 'e2e_notices.sh'
  [IO.File]::WriteAllText($tmp, ($script -replace "`r`n", "`n"))
  adb -s $Device push $tmp /data/local/tmp/e2e_notices.sh | Out-Null
  adb -s $Device shell sh /data/local/tmp/e2e_notices.sh
}

function Get-UiNodes {
  adb -s $Device shell uiautomator dump /sdcard/e2e_ui.xml | Out-Null
  ([xml](adb -s $Device exec-out cat /sdcard/e2e_ui.xml)).SelectNodes('//node')
}

function Tap-Node($node, [string] $what) {
  if ($node -and $node.bounds -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
    $x = [int](([int]$Matches[1] + [int]$Matches[3]) / 2); $y = [int](([int]$Matches[2] + [int]$Matches[4]) / 2)
    adb -s $Device shell input tap $x $y | Out-Null
    Write-Host "tapped $what at $x,$y"
    return $true
  }
  Write-Host "$what not found in the shade"
  return $false
}

# Taps one bank notification. The system groups several of them: expand the group first so the tap
# reaches the notification itself and not the group summary (which only launches the app).
function Tap-Notification([string] $text) {
  adb -s $Device shell cmd statusbar expand-notifications | Out-Null
  Start-Sleep -Seconds 2
  $expander = Get-UiNodes | Where-Object { $_.'resource-id' -like '*expand_button*' } | Select-Object -First 1
  if ($expander) { Tap-Node $expander 'group expander' | Out-Null; Start-Sleep -Seconds 1 }
  $node = Get-UiNodes | Where-Object { ($_.text -like "*$text*" -or $_.'content-desc' -like "*$text*") } | Select-Object -First 1
  Tap-Node $node "notification '$text'" | Out-Null
}

function Invoke-Marker([string] $kind, [string] $arg) {
  switch ($kind) {
    'shot' { cmd /c "adb -s $Device exec-out screencap -p > `"$(Join-Path $screens "$arg.png")`"" }
    'grant-listener' {
      adb -s $Device shell pm grant $package android.permission.POST_NOTIFICATIONS
      adb -s $Device shell cmd notification allow_listener "$package/notification.listener.service.NotificationListener"
    }
    'post-notices' { Send-Notices }
    'dump-notifications' {
      adb -s $Device shell dumpsys notification --noredact | Select-String -Pattern 'pkg=|android.title|android.text|Nuevo|detectado' |
        ForEach-Object { $_.Line.Trim() } | Set-Content (Join-Path $root 'docs\e2e\notifications_dump.txt') -Encoding utf8
    }
    'tap-notification' { Tap-Notification $arg }
  }
}

# The headless emulator sometimes dies (qemu access violation) right when a run starts: restart it and retry.
function Ensure-Emulator {
  if ((adb devices) -match "$Device\s+device") { return }
  Write-Host 'emulator not running: starting it'
  $env:ANDROID_AVD_HOME = 'D:\Dev\Android\user\avd'
  Start-Process -FilePath D:\Dev\Android\Sdk\emulator\emulator.exe -WindowStyle Hidden `
    -ArgumentList '-avd', 'Medium_Phone_API_36.0', '-no-window', '-no-audio', '-no-snapshot', '-no-boot-anim', '-gpu', 'swangle_indirect', '-memory', '3072'
  for ($i = 0; $i -lt 40; $i++) {
    Start-Sleep -Seconds 10
    if (((adb -s $Device shell getprop sys.boot_completed 2>$null) -join '').Trim() -eq '1') { break }
  }
  Start-Sleep -Seconds 20
}

$extra = @(); if ($Name) { $extra = @("--plain-name=$Name") }
$exitCode = 1
for ($attempt = 1; $attempt -le 3; $attempt++) {
  Ensure-Emulator
  Remove-Item $Log, "$Log.err" -ErrorAction SilentlyContinue
  $started = Get-Date
  $proc = Start-Process -FilePath flutter -WorkingDirectory $root -PassThru -NoNewWindow `
    -ArgumentList (@('test', $TestFile, '-d', $Device, '--no-pub', "--dart-define-from-file=$Defines") + $extra) `
    -RedirectStandardOutput $Log -RedirectStandardError "$Log.err"

  $seen = 0
  while ($true) {
    Start-Sleep -Milliseconds 400
    if (Test-Path $Log) {
      $lines = @(Get-Content $Log -ErrorAction SilentlyContinue)
      for ($i = $seen; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'E2E_MARKER (\S+)\s*(.*)$') { Invoke-Marker $Matches[1] $Matches[2].Trim() }
      }
      $seen = $lines.Count
    }
    if ($proc.HasExited) { break }
  }
  $exitCode = $proc.ExitCode
  $crashed = (Test-Path $Log) -and (Select-String -Path $Log -Pattern 'did not complete' -Quiet) -and -not ((adb devices) -match "$Device\s+device")
  if (-not $crashed) { break }
  Write-Host "attempt ${attempt}: the emulator died during the run, retrying"
}
exit $exitCode
