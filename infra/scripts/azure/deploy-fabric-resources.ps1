<#
.SYNOPSIS
    Clones repository and deploys Microsoft Fabric items via Azure Deployment Script.

.DESCRIPTION
    This script is designed to run in an Azure Deployment Script (Azure PowerShell kind).
    It clones the specified repository, checks out the target branch, and invokes the 
    provision_fabric_items.ps1 script to deploy Fabric resources.

.PARAMETER GitBaseUrl
    The base URL of the git repository to clone (e.g., 'https://github.com/alguadam/udffsa.git')

.PARAMETER BranchName
    The name of the branch to checkout after cloning the repository

.PARAMETER FabricCapacityName
    The name of the Microsoft Fabric capacity to use for workspace creation.
    If not provided, will use AZURE_FABRIC_CAPACITY_NAME environment variable.

.PARAMETER FabricWorkspaceName
    The name of the Microsoft Fabric workspace. If not provided, will use 
    AZURE_FABRIC_WORKSPACE_NAME environment variable or auto-generate.

.EXAMPLE
    .\deploy-fabric-resources.ps1 -GitBaseUrl "https://github.com/alguadam/udffsa.git" -BranchName "main" -FabricCapacityName "MyCapacity"

.NOTES
    This script is intended to run within Azure Deployment Scripts with:
    - Azure PowerShell kind
    - Managed identity with appropriate permissions
    - Internet access for git operations
#>

param(
    [Parameter(Mandatory = $true, HelpMessage = "Git repository base URL")]
    [string]$GitBaseUrl,
    
    [Parameter(Mandatory = $true, HelpMessage = "Branch name to checkout")]
    [string]$BranchName,
    
    [Parameter(Mandatory = $false, HelpMessage = "Fabric capacity name")]
    [string]$FabricCapacityName,
    
    [Parameter(Mandatory = $false, HelpMessage = "Fabric workspace name")]
    [string]$FabricWorkspaceName
)

# Set error action preference
$ErrorActionPreference = "Stop"

# Set execution policy for current process
# Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force

Write-Host "Starting Azure Deployment Script for Fabric resources..." -ForegroundColor Green
Write-Host "Git Base URL: $GitBaseUrl" -ForegroundColor Cyan
Write-Host "Branch Name: $BranchName" -ForegroundColor Cyan

try {
    # Create a temporary directory for the repository
    $TempDir = Join-Path $env:TEMP "fabric-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "Creating temporary directory: $TempDir" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

    # Change to temporary directory
    Push-Location $TempDir

    # Clone the repository
    Write-Host "Cloning repository from: $GitBaseUrl" -ForegroundColor Yellow
    git clone $GitBaseUrl repo
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone repository from $GitBaseUrl"
    }
    Write-Host "Repository cloned successfully" -ForegroundColor Green

    # Change to repository directory
    Set-Location "repo"

    # Checkout the specified branch
    Write-Host "Checking out branch: $BranchName" -ForegroundColor Yellow
    git checkout $BranchName
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to checkout branch: $BranchName"
    }
    Write-Host "Successfully checked out branch: $BranchName" -ForegroundColor Green

    # Verify the provision script exists
    $ProvisionScriptPath = "infra\scripts\fabric\provision_fabric_items.ps1"
    if (-not (Test-Path $ProvisionScriptPath)) {
        throw "Provision script not found at: $ProvisionScriptPath"
    }
    Write-Host "Found provision script at: $ProvisionScriptPath" -ForegroundColor Green

    # Change to the script directory
    Set-Location "infra\scripts\fabric"

    # Prepare parameters for the provision script
    $ProvisionParams = @{}
    
    if ($FabricCapacityName) {
        $ProvisionParams['FabricCapacityName'] = $FabricCapacityName
        Write-Host "Using provided Fabric capacity name: $FabricCapacityName" -ForegroundColor Cyan
    }
    
    if ($FabricWorkspaceName) {
        $ProvisionParams['FabricWorkspaceName'] = $FabricWorkspaceName
        Write-Host "Using provided Fabric workspace name: $FabricWorkspaceName" -ForegroundColor Cyan
    }

    # Execute the provision script
    Write-Host "Invoking provision_fabric_items.ps1..." -ForegroundColor Yellow
    Write-Host "This may take several minutes to complete..." -ForegroundColor Cyan
    
    if ($ProvisionParams.Count -gt 0) {
        & ".\provision_fabric_items.ps1" @ProvisionParams
    }
    else {
        & ".\provision_fabric_items.ps1"
    }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Fabric deployment completed successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Deployment Summary:" -ForegroundColor Cyan
        Write-Host "- Repository: $GitBaseUrl" -ForegroundColor White
        Write-Host "- Branch: $BranchName" -ForegroundColor White
        if ($FabricCapacityName) {
            Write-Host "- Fabric Capacity: $FabricCapacityName" -ForegroundColor White
        }
        if ($FabricWorkspaceName) {
            Write-Host "- Fabric Workspace: $FabricWorkspaceName" -ForegroundColor White
        }
    }
    else {
        throw "Provision script execution failed with exit code: $LASTEXITCODE"
    }
}
catch {
    Write-Host "❌ Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting information:" -ForegroundColor Yellow
    Write-Host "- Git Base URL: $GitBaseUrl" -ForegroundColor White
    Write-Host "- Branch Name: $BranchName" -ForegroundColor White
    Write-Host "- Current Location: $(Get-Location)" -ForegroundColor White
    Write-Host "- Error Details: $($_.Exception.Message)" -ForegroundColor White
    
    # Re-throw to ensure deployment script fails
    throw
}
finally {
    # Clean up: return to original location and remove temp directory
    try {
        if (Get-Location -Stack -ErrorAction SilentlyContinue) {
            Pop-Location
        }
        
        if (Test-Path $TempDir) {
            Write-Host "Cleaning up temporary directory: $TempDir" -ForegroundColor Yellow
            Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Failed to clean up temporary directory: $($_.Exception.Message)"
    }
}

Write-Host "Azure Deployment Script execution completed." -ForegroundColor Green