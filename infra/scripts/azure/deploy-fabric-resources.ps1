<#
.SYNOPSIS
    Clones repository and deploys Microsoft Fabric items via Azure Deployment Script on Ubuntu 24.04.

.DESCRIPTION
    This script is designed to run in an Azure Deployment Script (Azure PowerShell kind) on Ubuntu 24.04.
    It clones the specified repository, checks out the target branch, installs Python 3.13 with pip,
    and invokes the provision_fabric_items.sh script to deploy Fabric resources.

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
    This script is intended to run within Azure Deployment Scripts on Ubuntu 24.04 with:
    - Azure PowerShell kind
    - Managed identity with appropriate permissions
    - Internet access for git operations
    - Ubuntu 24.04 with apt package manager
    - Python 3.13 with pip for Fabric API operations
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

Write-Host "Starting Azure Deployment Script for Fabric resources..." -ForegroundColor Green
Write-Host "Git Base URL: $GitBaseUrl" -ForegroundColor Cyan
Write-Host "Branch Name: $BranchName" -ForegroundColor Cyan

# Helper function to run commands with privilege escalation
function Invoke-PackageCommand {
    param(
        [string[]]$Command,
        [string]$Description
    )
    
    Write-Host $Description -ForegroundColor Cyan
    $currentUser = whoami
    
    if ($currentUser -eq "root") {
        & $Command[0] $Command[1..($Command.Length - 1)]
    }
    else {
        & "sudo" @Command
    }
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed: $Description"
    }
}

# Helper function to check if a command exists
function Test-Command {
    param([string]$CommandName)
    try {
        Get-Command $CommandName -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

try {
    # Update package list once at the beginning
    Write-Host "Updating package list..." -ForegroundColor Yellow
    Invoke-PackageCommand @("apt-get", "update", "-y") "Updating package repositories"

    # Check and install Git
    Write-Host "Checking Git installation..." -ForegroundColor Yellow
    if (Test-Command "git") {
        $gitVersion = git --version 2>&1
        Write-Host "Git is already installed: $gitVersion" -ForegroundColor Green
    }
    else {
        Write-Host "Installing Git..." -ForegroundColor Yellow
        Invoke-PackageCommand @("apt-get", "install", "-y", "git") "Installing Git"
        
        $gitVersion = git --version 2>&1
        Write-Host "Installed Git version: $gitVersion" -ForegroundColor Green
    }

    # Install Python 3.13
    Write-Host "Installing Python 3.13..." -ForegroundColor Yellow
    
    # Install software-properties-common for add-apt-repository
    Invoke-PackageCommand @("apt-get", "install", "-y", "software-properties-common") "Installing software-properties-common"
    
    # Add deadsnakes PPA for Python 3.13
    Invoke-PackageCommand @("add-apt-repository", "-y", "ppa:deadsnakes/ppa") "Adding deadsnakes PPA"
    
    # Update package list after adding PPA
    Invoke-PackageCommand @("apt-get", "update", "-y") "Updating package repositories after PPA addition"
    
    # Install Python 3.13 and related packages (pip may not be available directly for 3.13)
    Invoke-PackageCommand @("apt-get", "install", "-y", "python3.13", "python3.13-venv", "python3.13-dev", "python3.13-distutils") "Installing Python 3.13 and essential packages"
    
    # Install pip for Python 3.13 using get-pip.py if python3.13-pip is not available
    Write-Host "Setting up pip for Python 3.13..." -ForegroundColor Yellow
    try {
        # Try to install python3.13-pip first
        Invoke-PackageCommand @("apt-get", "install", "-y", "python3.13-pip") "Installing python3.13-pip package"
    }
    catch {
        Write-Host "python3.13-pip not available, installing pip manually..." -ForegroundColor Yellow
        
        # Download and install pip manually
        curl -sS https://bootstrap.pypa.io/get-pip.py | python3.13
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install pip for Python 3.13"
        }
    }
    
    # Verify installation
    $pythonVersion = python3.13 --version 2>&1
    $pipVersion = python3.13 -m pip --version 2>&1
    Write-Host "Installed Python version: $pythonVersion" -ForegroundColor Green
    Write-Host "Installed pip version: $pipVersion" -ForegroundColor Green

    # Clone repository and checkout branch
    Write-Host "Cloning repository from: $GitBaseUrl" -ForegroundColor Yellow
    git clone $GitBaseUrl repo
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone repository from $GitBaseUrl"
    }
    
    Push-Location "repo"
    try {
        Write-Host "Checking out branch: $BranchName" -ForegroundColor Yellow
        git checkout $BranchName
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to checkout branch: $BranchName"
        }
        Write-Host "Successfully checked out branch: $BranchName" -ForegroundColor Green

        # Navigate to script directory and prepare execution
        $ScriptDirectory = Join-Path "infra" "scripts" "fabric"
        $ProvisionScriptPath = Join-Path $ScriptDirectory "provision_fabric_items.sh"
        
        if (-not (Test-Path $ProvisionScriptPath)) {
            throw "Provision script not found at: $ProvisionScriptPath"
        }
        Write-Host "Found provision script at: $ProvisionScriptPath" -ForegroundColor Green

        Set-Location $ScriptDirectory

        # Make script executable and prepare arguments
        chmod +x provision_fabric_items.sh
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to make script executable, but continuing..."
        }

        # Build arguments array
        $ProvisionArgs = @()
        if ($FabricCapacityName) {
            $ProvisionArgs += @("--capacityName", $FabricCapacityName)
            Write-Host "Using Fabric capacity name: $FabricCapacityName" -ForegroundColor Cyan
        }
        if ($FabricWorkspaceName) {
            $ProvisionArgs += @("--workspaceName", $FabricWorkspaceName)
            Write-Host "Using Fabric workspace name: $FabricWorkspaceName" -ForegroundColor Cyan
        }

        # Execute the provision script with Python 3.13
        Write-Host "Invoking provision_fabric_items.sh..." -ForegroundColor Yellow
        Write-Host "This may take several minutes to complete..." -ForegroundColor Cyan
        
        # Set Python 3.13 environment variable for the script
        $env:PYTHON_CMD = "python3.13"
        
        if ($ProvisionArgs.Count -gt 0) {
            & bash ./provision_fabric_items.sh @ProvisionArgs
        }
        else {
            & bash ./provision_fabric_items.sh
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
    finally {
        # Always return from the repo directory
        Pop-Location
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

Write-Host "Azure Deployment Script execution completed." -ForegroundColor Green