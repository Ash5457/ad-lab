# 02-ou-structure.ps1
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$base = (Get-ADDomain).DistinguishedName

'HR','IT','Consultants','Groups' | ForEach-Object {
    $name = $_
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$name'" -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $name -Path $base -ProtectedFromAccidentalDeletion $true
        Write-Host "Created OU: $name"
    } else { Write-Host "OU exists: $name" }
}
