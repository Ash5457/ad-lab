# 03-users-groups.ps1
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$users      = Import-Csv "$PSScriptRoot\data\users.csv"
$defaultPwd = ConvertTo-SecureString 'ChangeMe!2026' -AsPlainText -Force
$domain     = (Get-ADDomain).DNSRoot

foreach ($u in $users) {
    if (Get-ADUser -Filter "SamAccountName -eq '$($u.SamAccountName)'" -ErrorAction SilentlyContinue) {
        Write-Host "Skip (exists): $($u.SamAccountName)"; continue
    }
    New-ADUser `
      -Name                  $u.DisplayName `
      -GivenName             $u.FirstName `
      -Surname               $u.LastName `
      -SamAccountName        $u.SamAccountName `
      -UserPrincipalName     "$($u.SamAccountName)@$domain" `
      -Path                  $u.OUPath `
      -Department            $u.Department `
      -Title                 $u.Title `
      -AccountPassword       $defaultPwd `
      -ChangePasswordAtLogon $true `
      -Enabled               $true
    Write-Host "Created: $($u.SamAccountName)"
}

# Security groups live in their own OU (a group can't share a name with an OU in the same container)
$groupOU = "OU=Groups,$((Get-ADDomain).DistinguishedName)"
foreach ($g in 'HR','Personal') {
    if (-not (Get-ADGroup -Filter "Name -eq '$g'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $g -GroupScope Global -GroupCategory Security -Path $groupOU
        Write-Host "Created group: $g"
    }
}
Add-ADGroupMember -Identity HR       -Members areyes
Add-ADGroupMember -Identity Personal -Members areyes
