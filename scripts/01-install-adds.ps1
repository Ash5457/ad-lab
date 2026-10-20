# 01-install-adds.ps1
$ErrorActionPreference = 'Stop'

$DomainName  = 'deadeye5457.com'
$NetbiosName = 'DEADEYE5457'
$SafeModePwd = Read-Host -AsSecureString -Prompt 'DSRM password'

if (-not (Get-WindowsFeature AD-Domain-Services).Installed) {
    Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
}

Import-Module ADDSDeployment
Install-ADDSForest `
  -DomainName                    $DomainName `
  -DomainNetbiosName             $NetbiosName `
  -SafeModeAdministratorPassword $SafeModePwd `
  -InstallDns `
  -DomainMode 'WinThreshold' `
  -ForestMode 'WinThreshold' `
  -Force
# WinThreshold = Server 2016 functional level. We start legacy on purpose
# so the migration has somewhere to go.
