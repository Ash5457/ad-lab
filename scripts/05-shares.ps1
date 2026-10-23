# 05-shares.ps1
# Creates HR and Personal shares, scoped to their security groups (never Everyone).
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$netbios = (Get-ADDomain).NetBIOSName

$shares = @(
  @{ Name = 'HR';       Path = 'C:\Shares\HR';       Group = 'HR' },
  @{ Name = 'Personal'; Path = 'C:\Shares\Personal'; Group = 'Personal' }
)

foreach ($s in $shares) {
  New-Item -ItemType Directory -Path $s.Path -Force | Out-Null

  # NTFS: break inheritance (keeping copies), drop broad Users, give the group Modify
  icacls $s.Path /inheritance:d | Out-Null
  icacls $s.Path /remove:g "BUILTIN\Users" | Out-Null
  icacls $s.Path /grant "${netbios}\$($s.Group):(OI)(CI)M" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "icacls grant failed on $($s.Path)" }

  if (-not (Get-SmbShare -Name $s.Name -ErrorAction SilentlyContinue)) {
    New-SmbShare -Name $s.Name -Path $s.Path `
      -ChangeAccess "$netbios\$($s.Group)" `
      -FullAccess 'BUILTIN\Administrators' | Out-Null
    Write-Host "Shared: $($s.Name)"
  } else {
    Write-Host "Share exists: $($s.Name)"
  }
}
