#requires -RunAsAdministrator
<#
    Win10/11 Home -> Pro upgrade for remote sessions you can't sit and watch.

    Two stages around a reboot. Stage 1 kicks off the edition change, drops a
    startup task to finish up, takes the network down and reboots. Stage 2 runs
    after the reboot, puts the network back, waits for the edition to actually be
    Pro, then installs the real key and activates.

    Uses changepk.exe, not DISM /Set-Edition - the latter throws error 50 on a
    running OS.

    Params:
      -GenericKey      edition-change trigger key (does not activate)
      -RealKey         licensed Pro key, used to activate
      -KeepNetwork     stay online during the change (off by default)
      -SkipActivation  edition change only, leaves the licensed key alone (testing)

    Log:    C:\ProgramData\Win10ProUpgrade\upgrade.log
    Author: Kosta Wadenfalk
    Website: https://mrolof.dev/
#>

param(
    [string]$GenericKey = 'VK7JG-NPHTM-C97JM-9MPGT-3V66T',
    [string]$RealKey    = 'YPMTF-KPN8T-67GVQ-DX67Y-F9CKM',
    [switch]$KeepNetwork,
    [switch]$SkipActivation
)

$ErrorActionPreference = 'Stop'
$base = 'C:\ProgramData\Win10ProUpgrade'
New-Item -ItemType Directory -Force -Path $base | Out-Null
$log = Join-Path $base 'upgrade.log'
function Log($m){ $l = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m; Add-Content $log $l; Write-Host $l }

Log 'Stage 1 start'
Log ('Current edition: ' + ((DISM /online /Get-CurrentEdition) -join ' '))

# Stage 2: written now, executed by the scheduled task after the reboot.
$stage2 = @"
`$base = 'C:\ProgramData\Win10ProUpgrade'
`$log  = Join-Path `$base 'upgrade.log'
function Log(`$m){ Add-Content `$log ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), `$m) }
Log 'Stage 2 start'

# Restore the adapters disabled in Stage 1.
`$nicFile = Join-Path `$base 'disabled-nics.txt'
if (Test-Path `$nicFile) {
    foreach (`$nic in (Get-Content `$nicFile)) {
        if ([string]::IsNullOrWhiteSpace(`$nic)) { continue }
        try { Enable-NetAdapter -Name `$nic -Confirm:`$false; Log ('Enabled adapter: ' + `$nic) }
        catch { Log ('Failed to enable adapter ' + `$nic + ': ' + `$_) }
    }
    Remove-Item `$nicFile -Force
}

# Wait for the edition change to finish.
`$ed = ''
for (`$i = 0; `$i -lt 90; `$i++) {
    `$ed = (DISM /online /Get-CurrentEdition) -join ' '
    if (`$ed -match 'Professional') { break }
    Start-Sleep -Seconds 10
}
Log ('Edition: ' + `$ed)
if (`$ed -notmatch 'Professional') { Log 'Edition is not Professional; stopping before key install.'; return }

# Wait for internet before activating.
for (`$i = 0; `$i -lt 60; `$i++) {
    if (Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { `$_.IPv4Connectivity -eq 'Internet' }) { break }
    Start-Sleep -Seconds 10
}

if (Test-Path (Join-Path `$base 'skip-activation.flag')) {
    Log 'Activation skipped (SkipActivation).'
} else {
    Log (cscript //nologo C:\Windows\System32\slmgr.vbs /ipk $RealKey 2>&1 | Out-String)
    Start-Sleep -Seconds 5
    Log (cscript //nologo C:\Windows\System32\slmgr.vbs /ato 2>&1 | Out-String)
    Start-Sleep -Seconds 5
    Log (cscript //nologo C:\Windows\System32\slmgr.vbs /dli 2>&1 | Out-String)
}

schtasks /delete /tn 'Win10ProActivate' /f | Out-Null
Log 'Stage 2 done'
"@
$stage2Path = Join-Path $base 'stage2.ps1'
Set-Content -Path $stage2Path -Value $stage2 -Encoding UTF8

# Resume task: SYSTEM, every boot, removes itself on success.
$action = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$stage2Path`""
schtasks /create /tn 'Win10ProActivate' /tr $action /sc onstart /ru SYSTEM /rl HIGHEST /f | Out-Null
Log 'Resume task registered.'

if ($SkipActivation) {
    Set-Content (Join-Path $base 'skip-activation.flag') 'test'
    Log 'SkipActivation set; licensed key will not be installed.'
}

# Disable connected adapters, recording which ones so Stage 2 restores only those.
if (-not $KeepNetwork) {
    $upNics = @(Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Select-Object -ExpandProperty Name)
    if ($upNics.Count -gt 0) {
        Set-Content (Join-Path $base 'disabled-nics.txt') $upNics
        Log ('Disabling adapters: ' + ($upNics -join ', '))
        Disable-NetAdapter -Name $upNics -Confirm:$false
    } else {
        Log 'No connected adapters to disable.'
    }
}

# Stage the edition change and reboot.
Log 'Starting edition change.'
Start-Process -FilePath "$env:windir\System32\changepk.exe" -ArgumentList "/ProductKey $GenericKey" -Wait -ErrorAction SilentlyContinue

Log 'Rebooting in 60s.'
shutdown /r /t 60 /c 'Windows edition upgrade in progress.'
