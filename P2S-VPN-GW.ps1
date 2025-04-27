<#
.SYNOPSIS
Automates the deployment of Azure infrastructure for a Point-to-Site (P2S) VPN lab (Gateway Only).

.DESCRIPTION
Creates a Resource Group, VNet, Subnets (Workload & GatewaySubnet),
Public IP for VPN Gateway, and initiates VPN Gateway creation (as job).
P2S configuration on the gateway (address pool, certificates) and Test VM creation are left manual.

.NOTES
Author: AI Assistant Automation Based on user request
Date:   [Current Date]
Prerequisites: Azure PowerShell Az module installed, logged in via Connect-AzAccount.
#>

# --- Configuration Variables ---
# Customize these values for your environment

$resourceGroupName = "P2S-Lab-RG"
$location = "eastus" # Choose an Azure region near you
$vnetName = "P2S-Lab-VNet"
$vnetAddressPrefix = "10.55.0.0/16" # Main address space for the VNet
$workloadSubnetName = "WorkloadSubnet" # Subnet where you will MANUALLY create your test VM
$workloadSubnetPrefix = "10.55.1.0/24"
$gatewaySubnetPrefix = "10.55.255.0/27" # MUST be /27 or larger for GatewaySubnet
$p2sAddressPool = "172.16.55.0/24" # IMPORTANT: Choose a range NOT overlapping VNet or your LOCAL network. Needed for manual P2S config.
$gwName = "P2S-Lab-GW"
$gwPipName = "$($gwName)-PIP"
$gwSku = "VpnGw1" # VpnGw1 is suitable for testing. Basic SKU is NOT recommended for P2S.

# --- Script Execution ---

Write-Host "Starting Azure P2S Lab Infrastructure Deployment (Gateway Only)..." -ForegroundColor Yellow

# 1. Create Resource Group
Write-Host "Creating Resource Group: $resourceGroupName..."
New-AzResourceGroup -Name $resourceGroupName -Location $location -ErrorAction Stop

# 2. Create Virtual Network
Write-Host "Creating Virtual Network: $vnetName..."
$vnet = New-AzVirtualNetwork `
    -Name $vnetName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -AddressPrefix $vnetAddressPrefix `
    -ErrorAction Stop

# 3. Create Workload Subnet Configuration
Write-Host "Defining Workload Subnet: $workloadSubnetName..."
$subnetWorkloadConfig = New-AzVirtualNetworkSubnetConfig `
    -Name $workloadSubnetName `
    -AddressPrefix $workloadSubnetPrefix `
    -ErrorAction Stop

# 4. Create Gateway Subnet Configuration (MUST be named GatewaySubnet)
Write-Host "Defining Gateway Subnet..."
$subnetGatewayConfig = New-AzVirtualNetworkSubnetConfig `
    -Name "GatewaySubnet" `
    -AddressPrefix $gatewaySubnetPrefix `
    -ErrorAction Stop

# 5. Add Subnet configurations to the local VNet object
Write-Host "Adding Subnet configurations to local VNet object..."
$vnet.Subnets.Add($subnetWorkloadConfig)
$vnet.Subnets.Add($subnetGatewayConfig)

# 6. Update the Virtual Network in Azure with the new subnets
Write-Host "Updating VNet $vnetName in Azure with new subnets..."
$vnet | Set-AzVirtualNetwork -ErrorAction Stop

# Refresh VNet variable AFTER updating it in Azure to ensure it has the latest state including IDs
Write-Host "Refreshing local VNet variable..."
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroupName

# 7. Create Public IP Address for the VPN Gateway (Standard SKU Static is required/recommended for P2S)
Write-Host "Creating Public IP for VPN Gateway: $gwPipName..."
$gwPip = New-AzPublicIpAddress `
    -Name $gwPipName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -AllocationMethod Static `
    -Sku Standard `
    -ErrorAction Stop

# 8. Prepare VPN Gateway IP Configuration
Write-Host "Preparing VPN Gateway IP Configuration..."
# Retrieve the GatewaySubnet object directly from Azure after VNet update
$gatewaySubnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroupName | Get-AzVirtualNetworkSubnetConfig -Name "GatewaySubnet" -ErrorAction Stop
$gwIpConfig = New-AzVirtualNetworkGatewayIpConfig `
    -Name "gwIpConfig" `
    -SubnetId $gatewaySubnet.Id `
    -PublicIpAddressId $gwPip.Id `
    -ErrorAction Stop

# 9. Create Virtual Network Gateway (This takes ~30-45 minutes - Run as Job)
Write-Host "Creating Virtual Network Gateway: $gwName (This will take 30-45 minutes)..." -ForegroundColor Yellow
Write-Host "Using -AsJob. Check job status with 'Get-Job | Format-List' and 'Receive-Job -Id <JobId>'"
New-AzVirtualNetworkGateway `
    -Name $gwName `
    -ResourceGroupName $resourceGroupName `
    -Location $location `
    -IpConfigurations $gwIpConfig `
    -GatewayType Vpn `
    -VpnType RouteBased `
    -GatewaySku $gwSku `
    -AsJob # Run in background as it takes long
# Note: We are NOT configuring P2S settings here.

# --- VM Creation Steps Removed ---
# Steps for NSG, VM PIP, VM NIC, and VM creation are removed as requested.

# --- Completion ---
Write-Host ""
Write-Host "---------------------------------------------------------------------" -ForegroundColor Green
Write-Host "Azure P2S Lab Infrastructure Deployment Initiated (Gateway Only)!" -ForegroundColor Green
Write-Host ""
Write-Host "Resource Group: $resourceGroupName"
Write-Host "VNet: $vnetName ($vnetAddressPrefix)"
Write-Host "Workload Subnet: $workloadSubnetName ($workloadSubnetPrefix) - Ready for manual VM deployment."
Write-Host "Gateway Subnet: GatewaySubnet ($gatewaySubnetPrefix)"
Write-Host "VPN Gateway: $gwName (Creation started as background job, takes ~30-45 mins)"
Write-Host ""
Write-Host "IMPORTANT NEXT STEPS:" -ForegroundColor Yellow
Write-Host "1. Wait for the Virtual Network Gateway '$gwName' background job to complete (check with 'Get-Job')."
Write-Host "2. Manually configure the Point-to-site configuration on the '$gwName' gateway in the Azure Portal:"
Write-Host "   - Set the Address pool (e.g., $p2sAddressPool)."
Write-Host "   - Choose Tunnel type (e.g., IKEv2 & SSTP)."
Write-Host "   - Choose Authentication type: Azure certificate."
Write-Host "   - Generate Root & Client certificates (using PowerShell/OpenSSL)."
Write-Host "   - Upload the Root certificate public key data to the P2S configuration."
Write-Host "   - Save the P2S configuration."
Write-Host "3. Manually create your Test VM (e.g., Windows Server 2022) in the '$workloadSubnetName' subnet within '$vnetName'."
Write-Host "   - Ensure its Network Security Group allows necessary traffic (e.g., RDP for access, ICMP from $p2sAddressPool for testing)."
Write-Host "4. Download the VPN client configuration from the gateway."
Write-Host "5. Install the Client certificate (.pfx) on your P2S client VM (the one connecting TO Azure)."
Write-Host "6. Install and configure the VPN client on your P2S client VM."
Write-Host "7. Connect the VPN client."
Write-Host "8. Test connectivity by pinging the private IP address of the Test VM you created manually."
Write-Host "---------------------------------------------------------------------" -ForegroundColor Green
