# scripts/00-prep.ps1
# Run on any fresh VM before anything else. Reboots at the end.
param(
  [Parameter(Mandatory)][string]  $ComputerName,
  [Parameter(Mandatory)][string]  $IPAddress,
  [Parameter(Mandatory)][string[]]$DnsServers,
  [int]$PrefixLength = 24
)
$ErrorActionPreference = 'Stop'

$nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
Write-Host "Configuring adapter: $($nic.Name)"

Set-NetIPInterface -InterfaceIndex $nic.ifIndex -Dhcp Disabled
Get-NetIPAddress -InterfaceIndex $nic.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Remove-NetIPAddress -Confirm:$false
# No -DefaultGateway on purpose: this network has no route out.
New-NetIPAddress -InterfaceIndex $nic.ifIndex -IPAddress $IPAddress -PrefixLength $PrefixLength | Out-Null
Set-DnsClientServerAddress -InterfaceIndex $nic.ifIndex -ServerAddresses $DnsServers

Write-Host "IP $IPAddress, DNS $($DnsServers -join ', '). Renaming to $ComputerName and rebooting."
Rename-Computer -NewName $ComputerName -Restart
