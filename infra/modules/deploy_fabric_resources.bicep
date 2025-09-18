@description('Specifies the location for resources.')
param location string
param scriptUri string // Full absolute https URI the script to be run.
param baseUrl string // Base URL for the script
param capacityName string // Workspace ID for the Fabric resources
param identity string // Fully qualified resource ID for the managed identity.
param gitRepo string = 'https://github.com/alguadam/udffsa.git' // Git repository URL
param gitBranch string = 'main' // Git branch to clone

resource create_fabric_resources 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  kind:'AzureCLI'
  name: 'create-fabric-resources-${uniqueString(deployment().name)}'
  location: location
  identity:{
    type:'UserAssigned'
    userAssignedIdentities: {
      '${identity}' : {}
    }
  }
  properties: {
    azCliVersion: '2.55.0'
    primaryScriptUri: scriptUri
    arguments: '-b "${baseUrl}" -c "${capacityName}" -r "${gitRepo}" -n "${gitBranch}"'
    timeout: 'PT1H'
    retentionInterval: 'PT1H'  // Retain for 1 hour for troubleshooting
    cleanupPreference:'OnSuccess'  // Keep resources until retention expires
  }
}

// resource create_fabric_resources 'Microsoft.ContainerInstance/containerGroups@2021-09-01' = {
//   name: 'create-fabric-resources-${uniqueString(deployment().name)}'
//   location: location
//   identity: {
//     type: 'UserAssigned'
//     userAssignedIdentities: {
//       '${identity}': {}
//     }
//   }
//   properties: {
//     containers: [
//       {
//         name: 'fabric-deployer'
//         properties: {
//           image: 'mcr.microsoft.com/azure-cli:2.55.0'
//           resources: {
//             requests: {
//               cpu: 1
//               memoryInGB: 1
//             }
//           }
//           command: [
//             'bash'
//             '-lc'
//             'set -euo pipefail; curl -fsSL "${scriptUri}" -o /tmp/deploy.sh; chmod +x /tmp/deploy.sh; /tmp/deploy.sh "${baseUrl}" "${capacityName}"'
//           ]
//         }
//       }
//     ]
//     restartPolicy: 'Never'
//     osType: 'Linux'
//   }
// }
