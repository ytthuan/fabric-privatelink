<#
.SYNOPSIS
    Configures a Windows Server as a DNS forwarder that resolves Microsoft Fabric /
    Power BI Private Link names through an Azure DNS Private Resolver inbound endpoint.

.DESCRIPTION
    Installs the DNS Server role, sets a default forwarder to the Azure-provided DNS
    (168.63.129.16) so non-Fabric names still resolve, and adds conditional forwarders
    for the Fabric/Power BI public parent domains pointing at the Private Resolver
    inbound endpoint IP. Grounded in:
    https://learn.microsoft.com/fabric/enterprise/powerbi/service-security-private-links-on-premises

.PARAMETER ResolverIp
    Private IP of the Azure DNS Private Resolver inbound endpoint in the hub VNet.

.PARAMETER Domains
    Comma-separated list of public parent domains to conditionally forward.
#>
param(
    [Parameter(Mandatory = $true)] [string] $ResolverIp,
    [Parameter(Mandatory = $true)] [string] $Domains
)

$ErrorActionPreference = 'Stop'
$logDir = 'C:\Windows\Temp'
Start-Transcript -Path (Join-Path $logDir 'setup-dns-forwarder.log') -Append -Force | Out-Null

Write-Output "Installing DNS Server role..."
Install-WindowsFeature -Name DNS -IncludeManagementTools | Out-Null
Import-Module DnsServer -ErrorAction Stop

# Default forwarder to Azure-provided DNS so the server can resolve everything else
# (public internet, Azure control-plane). Without this, only the conditional zones
# below would resolve and on-premises clients would lose general name resolution.
Write-Output "Setting default forwarder to 168.63.129.16..."
Set-DnsServerForwarder -IPAddress '168.63.129.16' -UseRootHint $false

# Conditional forwarders: send Fabric/Power BI public parent domains to the
# Private Resolver inbound endpoint, which resolves the CNAME -> privatelink chain
# against the private DNS zones linked to the hub VNet (returns private IPs).
$zones = $Domains -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
foreach ($zone in $zones) {
    Write-Output "Configuring conditional forwarder for '$zone' -> $ResolverIp"
    $existing = Get-DnsServerZone -Name $zone -ErrorAction SilentlyContinue
    if ($existing) {
        Remove-DnsServerZone -Name $zone -Force -ErrorAction SilentlyContinue
    }
    Add-DnsServerConditionalForwarderZone -Name $zone -MasterServers $ResolverIp -ErrorAction Stop
}

Write-Output "Restarting DNS service..."
Restart-Service -Name DNS -Force

Write-Output "DNS forwarder configuration complete."
Stop-Transcript | Out-Null
