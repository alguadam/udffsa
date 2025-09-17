@description('Specifies the location for resources.')
param location string
param scriptUri string // Full absolute https URI the script to be run.
param baseUrl string // Base URL for the script
param fabricWorkspaceId string // Workspace ID for the Fabric resources
param identity string // Fully qualified resource ID for the managed identity.

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
    arguments: '${baseUrl} ${fabricWorkspaceId}'
    timeout: 'PT1H'
    retentionInterval: 'PT1H'  // Retain for 1 hour for troubleshooting
    cleanupPreference:'OnSuccess'  // Keep resources until retention expires
  }
}
