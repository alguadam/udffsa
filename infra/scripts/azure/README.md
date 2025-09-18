# Azure Deployment Scripts

This directory contains wrapper scripts for deploying Fabric resources in Azure environments.

## Problem Solved

The original deployment approach was directly downloading and executing Python scripts from GitHub using raw URLs. This caused internal server errors because:

1. Not all required files were being downloaded
2. Dependencies and imports were missing
3. The script execution environment lacked proper context
4. Azure CLI environments may not have git installed by default

## Solution

The new approach uses Azure deployment wrapper scripts that:

1. **Download the entire repository** locally in the Azure deployment environment
2. **Ensure all files and dependencies are available**
3. **Run the fabric provisioning scripts** with full repository context
4. **Clean up** temporary files after completion

## Files

### `deploy-nogit.sh` (Primary deployment script)
- **Purpose**: Bash script that downloads repository files without requiring git
- **Usage**: Called by Azure deployment scripts (bicep templates)
- **Method**: Downloads and extracts GitHub repository archive using curl and tar
- **Benefits**: Works in minimal Azure CLI environments without git dependency
- **Parameters**:
  - `-b <base_url>`: Base URL for the deployment
  - `-c <capacity_name>`: Capacity name for Fabric resources
  - `-r <git_repo>`: Git repository URL (optional)
  - `-n <branch>`: Git branch name (optional)

### `deploy.sh` (Alternative deployment script with git)
- **Purpose**: Bash script for environments where git is available
- **Usage**: Alternative approach using git clone
- **Requirements**: Requires git to be installed or will attempt to install it
- **Parameters**: Same as deploy-nogit.sh

### `deploy.ps1` (PowerShell deployment script)
- **Purpose**: PowerShell script for Windows-based environments or testing
- **Usage**: Alternative to the bash scripts
- **Parameters**:
  - `-BaseUrl`: Base URL for the deployment
  - `-CapacityName`: Capacity name for Fabric resources
  - `-GitRepo`: Git repository URL (optional)
  - `-Branch`: Git branch name (optional)

## How It Works (No-Git Version)

1. **Azure Deployment Script** resource executes `deploy-nogit.sh`
2. **Script creates** a temporary directory `/tmp/fabric-deployment-<timestamp>`
3. **Downloads repository archive** from GitHub using curl
4. **Extracts archive** using tar to get all repository files
5. **Navigates** to `./infra/scripts/fabric/` directory
6. **Installs** Python requirements from `requirements.txt`
7. **Executes** the appropriate fabric provisioning script
8. **Cleans up** temporary directory on completion

## Bicep Integration

The deployment is integrated with Bicep templates:

- **`deploy_fabric_resources.bicep`**: Defines the Azure deployment script resource
- **`main.bicep`**: Calls the deployment module with required parameters

## Benefits

✅ **No git dependency**: Uses curl and tar which are available in Azure CLI environments  
✅ **Reliable**: All files and dependencies are available locally  
✅ **Complete**: Entire repository context is available during execution  
✅ **Flexible**: Supports multiple deployment approaches  
✅ **Clean**: Automatic cleanup of temporary files  
✅ **Traceable**: Clear logging and error handling  
✅ **Version-controlled**: Uses specific git branches for reproducible deployments  

## Error Handling

- Repository download failures are caught and reported
- Missing provisioning scripts are detected
- Python requirements installation is validated
- Script execution results are checked
- Cleanup occurs regardless of success/failure

## Security

- Uses managed identity authentication in Azure
- Temporary directories are cleaned up automatically
- Repository access uses public GitHub URLs (no credentials stored)
- Downloads specific branches for controlled deployments