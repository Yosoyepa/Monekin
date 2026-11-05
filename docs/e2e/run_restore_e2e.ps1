# E004 test 3 on the emulator: a restore killed halfway (`am force-stop`) and the restore lock against WorkManager.
# Runs integration_test/finanzas_ia/restore_interrupt_test.dart and answers its markers.
# Usage: .\docs\e2e\run_restore_e2e.ps1 -Mode kill-swap|kill-commit|kill-bringPhotos|lock|bgflag -OutDir <folder>
param(
  [Parameter(Mandatory)] [string] $Mode,
  [Parameter(Mandatory)] [string] $OutDir,
  [string] $AppApk = 'D:\Dev\e2e-build\evidence\final-debug.apk',
  [string] $Device = 'emulator-5554'
)
. D:\Dev\dev-env.ps1
$root = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$package = 'com.yosoyepa.finanzas'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$log = Join-Path $OutDir "$Mode.flutter.log"
$py = 'D:\Dev\venvs\plantilla\Scripts\python.exe'

function Save-Listing([string] $name) {
  $file = Join-Path $OutDir "$Mode.$name.txt"
  adb -s $Device shell "run-as $package ls -l app_flutter" | Set-Content $file -Encoding utf8
  Write-Host "== listing $name"; Get-Content $file | ForEach-Object { Write-Host "   $_" }
}

function Save-Logcat([string] $name, [string] $pattern) {
  $file = Join-Path $OutDir "$Mode.$name.logcat.txt"
  adb -s $Device logcat -d | Select-String -Pattern $pattern | ForEach-Object { $_.Line } | Set-Content $file -Encoding utf8
  Write-Host "== logcat $name"; Get-Content $file | Select-Object -Last 12 | ForEach-Object { Write-Host "   $_" }
}

function Pull-Db([string] $name) {
  $base = Join-Path $OutDir "$Mode.$name"
  foreach ($f in 'database.db', 'database.db-wal') {
    cmd /c "adb -s $Device exec-out run-as $package cat app_flutter/$f > `"$base.$f`" 2>nul"
    if ((Get-Item "$base.$f").Length -eq 0) { Remove-Item "$base.$f" }
  }
  $script = @'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
print('user_version', c.execute('PRAGMA user_version').fetchone()[0])
print('transactions', c.execute('SELECT COUNT(*) FROM transactions').fetchone()[0])
print('titles', [r[0] for r in c.execute("SELECT title FROM transactions WHERE title LIKE 'E2E-RST %' ORDER BY title")])
print('accounts', c.execute('SELECT COUNT(*) FROM accounts').fetchone()[0])
'@
  $tmp = Join-Path $OutDir 'dbcount.py'; Set-Content $tmp $script -Encoding utf8
  $target = if (Test-Path "$base.database.db-wal") { Copy-Item "$base.database.db" "$base.sql.db" -Force; Copy-Item "$base.database.db-wal" "$base.sql.db-wal" -Force; "$base.sql.db" } else { "$base.database.db" }
  $out = & $py -I $tmp $target
  $out | Set-Content (Join-Path $OutDir "$Mode.$name.counts.txt") -Encoding utf8
  Write-Host "== db $name"; $out | ForEach-Object { Write-Host "   $_" }
}

function Get-AppJobIds {
  $text = (adb -s $Device shell dumpsys jobscheduler) -join "`n"
  # Android 16 prints `JOB <tag>:u0a217/1: ...`; older releases `JOB #u0a217/1: ...`.
  [regex]::Matches($text, "JOB (?:#|\S+:)u\d+a\d+/(\d+): .*?$([regex]::Escape($package))") | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique
}

# The AVD data partition is almost full: free the caches of the preinstalled Google apps (as run_e2e.ps1 does).
function Free-Space {
  foreach ($pkg in 'com.android.chrome', 'com.google.android.googlequicksearchbox', 'com.android.vending',
    'com.google.android.apps.maps', 'com.google.android.youtube', 'com.google.android.apps.photos',
    'com.google.android.gm', 'com.google.android.apps.messaging', 'com.google.android.apps.youtube.music',
    'com.google.android.gms', 'com.google.android.apps.restore') {
    adb -s $Device shell pm clear $pkg 2>$null | Out-Null
  }
  Write-Host ('free space: ' + ((adb -s $Device shell df -h /data | Select-Object -Last 1) -join ' '))
}

Free-Space
adb -s $Device uninstall $package | Out-Null
adb -s $Device logcat -c
$proc = Start-Process -FilePath flutter -WorkingDirectory $root -PassThru -NoNewWindow `
  -ArgumentList @('test', 'integration_test/finanzas_ia/restore_interrupt_test.dart', '-d', $Device, '--no-pub', "--dart-define=E2E_MODE=$Mode") `
  -RedirectStandardOutput $log -RedirectStandardError "$log.err"

$seen = 0; $handledJobs = @()
$deadline = (Get-Date).AddMinutes(14)
while ((Get-Date) -lt $deadline) {
  Start-Sleep -Milliseconds 400
  if (Test-Path $log) {
    $lines = @(Get-Content $log -ErrorAction SilentlyContinue)
    for ($i = $seen; $i -lt $lines.Count; $i++) {
      $line = $lines[$i]
      if ($line -notmatch 'E2E_MARKER (.*)$') { continue }
      $m = $Matches[1].Trim(); Write-Host "[marker] $m"
      # The logcat has device time and the markers do not: print it to line them up.
      if ($m -match '^(lock-held|lock-hold-ended|bg-scheduled|bg-flag|restore returned)') { Write-Host "[host] device time: $((adb -s $Device shell "date '+%m-%d %H:%M:%S'") -join '')" }
      # The copy is read while the app still exists: once `flutter test` ends it may be uninstalled.
      if ($m -match '^restore returned: done=true') { Pull-Db 'after-restore' }
      if ($m -match '^hold (\w+)$') {
        $stage = $Matches[1]
        Save-Listing "before-kill-$stage"
        Start-Sleep -Seconds 2
        # Stop `flutter test` first: when the app dies under it, it uninstalls the app and the data goes with it.
        cmd /c "taskkill /T /F /PID $($proc.Id)" | Out-Null
        Start-Sleep -Seconds 1
        Write-Host "[host] force-stop at stage $stage ($(Get-Date -Format 'HH:mm:ss.fff'))"
        adb -s $Device shell am force-stop $package
        Start-Sleep -Seconds 1
        Save-Listing "after-kill-$stage"
        # The APK that `flutter test` installs has the test as its entry point: put the normal debug build of the same
        # commit over it (same key, the data stays) and open the app again. The recovery runs before the database opens.
        Free-Space
        Write-Host ('[host] install: ' + ((adb -s $Device install -r $AppApk) -join ' '))
        adb -s $Device logcat -c
        adb -s $Device shell monkey -p $package -c android.intent.category.LAUNCHER 1 | Out-Null
        Start-Sleep -Seconds 30
        Save-Listing 'after-reopen'
        Pull-Db 'after-reopen'
        cmd /c "adb -s $Device exec-out screencap -p > `"$(Join-Path $OutDir "$Mode.after-reopen.png")`""
        Save-Logcat 'reopen-errors' 'FATAL|AndroidRuntime|Unhandled|Exception|DB found|DB Opened|Migrat|restore'
        adb -s $Device logcat -b crash -d | Set-Content (Join-Path $OutDir "$Mode.reopen.crashbuffer.txt")
        exit 0
      }
      if ($m -match '^bg-scheduled (\S+)$') {
        $work = $Matches[1]
        Start-Sleep -Seconds 3
        Save-Listing "before-job-$work"
        (adb -s $Device shell dumpsys jobscheduler) | Select-String $package | ForEach-Object { $_.Line.Trim() } | Set-Content (Join-Path $OutDir "$Mode.jobscheduler-$work.txt") -Encoding utf8
        $ids = @(Get-AppJobIds | Where-Object { $handledJobs -notcontains $_ })
        Write-Host "[host] jobs of the app: $($ids -join ', ')"
        foreach ($id in $ids) {
          adb -s $Device shell cmd jobscheduler run -f $package $id
          $handledJobs += $id
        }
        Start-Sleep -Seconds 12
        Save-Listing "after-job-$work"
        Save-Logcat "job-$work" 'dev.fluttercommunity.workmanager.BackgroundWorker|Background task|restore is running|DB found|DB Opened|E2E_MARKER (lock|isHeld|bg-|restore returned)'
      }
      if ($m -eq 'test end') { Start-Sleep -Seconds 5 }
    }
    $seen = $lines.Count
  }
  if ($proc.HasExited) { break }
}
Pull-Db 'final'
Save-Logcat 'final' 'Restore waiting|E2E_MARKER|Background task|restore is running|DB found|DB Opened'
Write-Host "flutter test exit code: $($proc.ExitCode)"
exit $proc.ExitCode






