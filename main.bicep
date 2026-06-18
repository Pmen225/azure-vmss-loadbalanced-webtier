// Azure highly-available, load-balanced VM Scale Set
// Exported from a live deployment and parameterised for reuse.
// NOTE: secrets (SSH key, subscription IDs, source IPs) removed and replaced with parameters.

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('SSH public key for the VMSS admin user')
param sshPublicKey string

@description('CIDR allowed to reach the management port (e.g. 1.2.3.4/32)')
param adminSourceAddressPrefix string

var vnetName = 'vnet-eastus'
var subnetName = 'snet-eastus-1'
var nsgName = 'basicNsg-vnet-eastus-nic01'
var lbName = 'LB-01'
var publicIpName = 'LB-01-publicip'
var vmssName = 'VMSS1'

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTP'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 300
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-Mgmt-8080'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '8080'
          sourceAddressPrefix: adminSourceAddressPrefix
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 310
          direction: 'Inbound'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['172.16.0.0/16'] }
    subnets: [
      {
        name: subnetName
        properties: { addressPrefix: '172.16.0.0/24' }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: publicIpName
  location: location
  sku: { name: 'Standard', tier: 'Regional' }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 15
  }
}

resource lb 'Microsoft.Network/loadBalancers@2024-05-01' = {
  name: lbName
  location: location
  sku: { name: 'Standard', tier: 'Regional' }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'frontendconfig01'
        properties: { publicIPAddress: { id: publicIp.id } }
      }
    ]
    backendAddressPools: [ { name: 'bepool' } ]
    probes: [
      {
        name: 'probe01'
        properties: { protocol: 'Tcp', port: 80, intervalInSeconds: 15, numberOfProbes: 2 }
      }
    ]
    loadBalancingRules: [
      {
        name: 'lbrule01'
        properties: {
          frontendIPConfiguration: { id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', lbName, 'frontendconfig01') }
          backendAddressPool: { id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bepool') }
          probe: { id: resourceId('Microsoft.Network/loadBalancers/probes', lbName, 'probe01') }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          idleTimeoutInMinutes: 15
        }
      }
    ]
  }
}

resource vmss 'Microsoft.Compute/virtualMachineScaleSets@2024-11-01' = {
  name: vmssName
  location: location
  sku: { name: 'Standard_DC1ds_v3', tier: 'Standard', capacity: 2 }
  properties: {
    orchestrationMode: 'Uniform'
    overprovision: false
    upgradePolicy: { mode: 'Manual' }
    virtualMachineProfile: {
      osProfile: {
        computerNamePrefix: 'vmss1'
        adminUsername: 'azureuser'
        linuxConfiguration: {
          disablePasswordAuthentication: true
          ssh: {
            publicKeys: [
              { path: '/home/azureuser/.ssh/authorized_keys', keyData: sshPublicKey }
            ]
          }
        }
      }
      storageProfile: {
        imageReference: { publisher: 'canonical', offer: 'ubuntu-24_04-lts', sku: 'server', version: 'latest' }
        osDisk: { osType: 'Linux', createOption: 'FromImage', caching: 'ReadWrite', managedDisk: { storageAccountType: 'Premium_LRS' }, diskSizeGB: 30 }
      }
      networkProfile: {
        networkInterfaceConfigurations: [
          {
            name: 'vnet-eastus-nic01'
            properties: {
              primary: true
              enableAcceleratedNetworking: true
              networkSecurityGroup: { id: nsg.id }
              ipConfigurations: [
                {
                  name: 'ipconfig1'
                  properties: {
                    primary: true
                    subnet: { id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, subnetName) }
                    loadBalancerBackendAddressPools: [ { id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', lbName, 'bepool') } ]
                  }
                }
              ]
            }
          }
        ]
      }
      securityProfile: {
        securityType: 'TrustedLaunch'
        uefiSettings: { secureBootEnabled: true, vTpmEnabled: true }
      }
    }
  }
  dependsOn: [ vnet, lb ]
}
