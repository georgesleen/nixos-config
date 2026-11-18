#Requires -Version 5.1
#Requires -RunAsAdministrator
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Public keys authorize the administrator account created in normal Windows OOBE.
$publicKeys = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'authorized_keys') |
    Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })
if ($publicKeys.Count -eq 0) {
    throw 'The provisioning disc contains no authorized public keys.'
}
$capabilityName = 'OpenSSH.Server~~~~0.0.1.0'
$capability = Get-WindowsCapability -Online -Name $capabilityName
if ($capability.State -ne 'Installed') {
    $installation = Add-WindowsCapability -Online -Name $capabilityName
    if ($installation.RestartNeeded) {
        throw 'OpenSSH installation requires a reboot. Restart Windows and rerun this script.'
    }
}

Start-Service sshd
$sshDirectory = Join-Path $env:ProgramData 'ssh'
$keysPath = Join-Path $sshDirectory 'administrators_authorized_keys'
$existingKeys = @()
if (Test-Path -LiteralPath $keysPath) {
    $existingKeys = @(Get-Content -LiteralPath $keysPath)
}
$mergedKeys = @($existingKeys + $publicKeys | Select-Object -Unique)
[System.IO.File]::WriteAllLines($keysPath, [string[]]$mergedKeys, [System.Text.Encoding]::ASCII)

# OpenSSH requires this file to be writable only by SYSTEM and Administrators.
$administrators = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544')
$system = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')
$access = New-Object System.Security.AccessControl.FileSecurity
$access.SetOwner($administrators)
$access.SetAccessRuleProtection($true, $false)
foreach ($principal in @($administrators, $system)) {
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $principal, [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.AccessControlType]::Allow)
    $access.AddAccessRule($rule)
}
Set-Acl -LiteralPath $keysPath -AclObject $access

$configurationPath = Join-Path $sshDirectory 'sshd_config'
$configuration = [System.IO.File]::ReadAllText($configurationPath)
$managedHeader = '(?ms)\A# BEGIN workstation key access\r?\n.*?^# END workstation key access\r?\n'
$configuration = [regex]::Replace($configuration, $managedHeader, '')
$header = @'
# BEGIN workstation key access
PubkeyAuthentication yes
PasswordAuthentication no
# END workstation key access
'@
# The Windows default Match Group administrators block selects the ACL-protected file above.
if ($configuration -notmatch '(?im)^\s*AuthorizedKeysFile\s+__PROGRAMDATA__/ssh/administrators_authorized_keys\s*$') {
    throw "The OpenSSH configuration is not the Windows default: restore its administrators AuthorizedKeysFile block in $configurationPath and rerun."
}
[System.IO.File]::WriteAllText($configurationPath, $header + "`r`n" + $configuration,
    [System.Text.Encoding]::ASCII)
Set-Service -Name sshd -StartupType Automatic
$firewallRule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
if ($null -eq $firewallRule) {
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 | Out-Null
} else {
    Enable-NetFirewallRule -Name 'OpenSSH-Server-In-TCP'
}
Restart-Service sshd
Write-Host "SSH public-key access is enabled for the existing Windows administrator account. Username: $env:USERNAME"

# Install signed upstream guest components interactively; no unattended driver flags or downloads.
$winFspRegistryPaths = @(
    'HKLM:\SOFTWARE\WinFsp',
    'HKLM:\SOFTWARE\WOW6432Node\WinFsp'
)
$winFspInstalled = @($winFspRegistryPaths | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0
if (-not $winFspInstalled) {
    throw 'SSH is ready, but sharing needs WinFsp. Download the official stable MSI from https://github.com/winfsp/winfsp/releases, run it interactively with Core enabled, then run virtio-win-guest-tools.exe from the attached VirtIO disc with VirtIO-FS, QEMU guest agent and SPICE agent selected. Reboot and rerun this script. See INSTALL.txt on this disc.'
}
$virtioFsService = Get-Service -Name VirtioFsSvc -ErrorAction SilentlyContinue
$qemuAgentService = Get-Service -Name 'QEMU-GA' -ErrorAction SilentlyContinue
$spiceAgentService = Get-Service -Name 'vdservice' -ErrorAction SilentlyContinue
if ($null -eq $virtioFsService -or $null -eq $qemuAgentService -or $null -eq $spiceAgentService) {
    throw 'SSH is ready, but guest tools are incomplete. Run the attached VirtIO disc root virtio-win-guest-tools.exe interactively. Select VirtIO-FS (driver and service), QEMU guest agent and SPICE agent; install the signed Windows 11 amd64 drivers, reboot, then rerun. Do not enable test signing or disable Secure Boot. See INSTALL.txt.'
}

Stop-Service VirtioFsSvc
if (Test-Path -LiteralPath 'W:\') {
    throw 'W: is already assigned after stopping VirtioFsSvc. Free that drive letter before rerunning; no unrelated drive will be replaced.'
}
$virtioFsRegistry = 'HKLM:\SOFTWARE\VirtIO-FS'
New-Item -Path $virtioFsRegistry -Force | Out-Null
New-ItemProperty -Path $virtioFsRegistry -Name MountPoint -PropertyType String -Value 'W:' -Force | Out-Null
New-ItemProperty -Path $virtioFsRegistry -Name FileSystemName -PropertyType String -Value 'NTFS' -Force | Out-Null
New-ItemProperty -Path $virtioFsRegistry -Name Owner -PropertyType String -Value '1000:100' -Force | Out-Null
foreach ($serviceName in @('VirtioFsSvc', 'QEMU-GA', 'vdservice')) {
    Set-Service -Name $serviceName -StartupType Automatic
    Start-Service -Name $serviceName
}
if (-not (Test-Path -LiteralPath 'W:\')) {
    throw 'VirtioFsSvc started but W:\ is unavailable. Check Device Manager for the signed VirtIO-FS driver, and ensure W: is not already assigned. See INSTALL.txt; sharing is not ready.'
}
Write-Host 'Guest setup complete: SSH keys, QEMU agent, SPICE clipboard/resizing, and the host work folder at W:\.'
Write-Host 'Export documents into W:\ to retain them independently of the guest system disk.'