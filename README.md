# scripts

Windows and Microsoft endpoint admin scripts. Use at your own risk, read before you run.

## Win10-Home-to-Pro-Remote.ps1

Automated Windows 10/11 Home to Pro edition upgrade. Built for the case where you need Pro to do something Home blocks (Intune/MDM enrollment, Entra join, domain join, BitLocker, Hyper-V, Group Policy) and you want the whole upgrade to run hands-off, local or remote.

It runs in two stages around a reboot. Stage 1 stages the edition change with the generic key, registers a SYSTEM scheduled task, drops the network, and reboots. Stage 2 runs after the reboot, restores the network, waits for the edition to read as Professional, installs your licensed key, activates, and removes its own task.

Uses `changepk.exe`, not `DISM /Set-Edition` (the latter returns error 50 on a running OS).

### Usage

```powershell
# Normal run: edition change + activation
.\Win10-Home-to-Pro-Remote.ps1 -RealKey 'XXXXX-XXXXX-XXXXX-XXXXX-XXXXX'

# Test run in a VM: edition change only, no licensed key consumed
.\Win10-Home-to-Pro-Remote.ps1 -SkipActivation
```

| Parameter | Purpose |
|---|---|
| `-GenericKey` | Edition-change trigger. Defaults to Microsoft's public generic Pro key. Does not activate. |
| `-RealKey` | Your licensed Pro key. Required for activation. |
| `-KeepNetwork` | Stay online during the change. Off by default. |
| `-SkipActivation` | Edition change only. Skips installing/activating the licensed key. For testing. |

Log: `C:\ProgramData\Win10ProUpgrade\upgrade.log`

### Notes

- You need a valid Windows Pro license. The generic key only triggers the edition change, it does not license the machine. Nothing here bypasses licensing.
- The edition change is not cleanly reversible without a reinstall. Test in a snapshotted VM first.

Writeup: https://mrolof.dev/blog/home-to-pro-remote
