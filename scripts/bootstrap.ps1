# bootstrap.ps1  -- run elevated on the fresh server
$ErrorActionPreference = 'Stop'
& "$PSScriptRoot\01-install-adds.ps1"
# reboot happens here after promotion; re-run bootstrap to continue,
# or run phases 02-05 manually after the box comes back up.
& "$PSScriptRoot\02-ou-structure.ps1"
& "$PSScriptRoot\03-users-groups.ps1"
& "$PSScriptRoot\04-gpos.ps1"
& "$PSScriptRoot\05-shares.ps1"
