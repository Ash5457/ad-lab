# 04-gpos.ps1  -- example: registry-backed policy, the clean cmdlet path
$ErrorActionPreference = 'Stop'
Import-Module GroupPolicy

$gpo = 'U_Restrict_TaskMgr'
if (-not (Get-GPO -Name $gpo -ErrorAction SilentlyContinue)) { New-GPO -Name $gpo | Out-Null }

Set-GPRegistryValue -Name $gpo `
  -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System' `
  -ValueName 'DisableTaskMgr' -Type DWord -Value 1

New-GPLink -Name $gpo -Target 'OU=HR,DC=deadeye5457,DC=com' -LinkEnabled Yes -ErrorAction SilentlyContinue
