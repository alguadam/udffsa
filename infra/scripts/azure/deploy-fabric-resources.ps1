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

Write-Host "Starting Azure Deployment Script for Fabric resources..." -ForegroundColor Green
Write-Host "Git Base URL: $GitBaseUrl" -ForegroundColor Cyan
Write-Host "Branch Name: $BranchName" -ForegroundColor Cyan

try {
    # Detect operating system
    $IsLinux = $PSVersionTable.Platform -eq 'Unix' -or $PSVersionTable.OS -like '*Linux*'
    $IsWindows = $PSVersionTable.Platform -eq 'Win32NT' -or $PSVersionTable.PSEdition -eq 'Desktop' -or (-not $IsLinux)
    
    Write-Host "Detected OS: $(if ($IsLinux) { 'Linux' } else { 'Windows' })" -ForegroundColor Cyan
    
    # Check if Git is installed, install if not present
    Write-Host "Checking Git installation..." -ForegroundColor Yellow
    try {
        $gitVersion = git --version 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Git is already installed: $gitVersion" -ForegroundColor Green
        }
        else {
            throw "Git not found"
        }
    }
    catch {
        Write-Host "Git not found. Installing Git..." -ForegroundColor Yellow
        
        if ($IsLinux) {
            # Install Git on Linux using apt-get
            Write-Host "Installing Git on Linux using apt-get..." -ForegroundColor Cyan
            
            # Check if we're running as root or have sudo access
            $currentUser = whoami
            Write-Host "Current user: $currentUser" -ForegroundColor Cyan
            
            if ($currentUser -eq "root") {
                # Running as root, no need for sudo
                Write-Host "Running as root, installing Git directly..." -ForegroundColor Cyan
                
                # Update package list
                apt-get update -y
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to update package list"
                }
                
                # Install git
                apt-get install -y git
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to install Git using apt-get"
                }
            }
            else {
                # Try with sudo
                Write-Host "Attempting to install Git with sudo..." -ForegroundColor Cyan
                
                # Update package list
                sudo apt-get update -y
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to update package list with sudo"
                }
                
                # Install git
                sudo apt-get install -y git
                if ($LASTEXITCODE -ne 0) {
                    throw "Failed to install Git using sudo apt-get"
                }
            }
            
            # Verify installation
            $gitVersion = git --version 2>&1
            Write-Host "Installed Git version: $gitVersion" -ForegroundColor Green
        }
        else {
            # Install Git on Windows
            $gitDownloadUrl = "https://github.com/git-for-windows/git/releases/download/v2.42.0.windows.2/Git-2.42.0.2-64-bit.exe"
            $gitInstallerPath = ".\GitInstaller.exe"
            
            Write-Host "Downloading Git installer from: $gitDownloadUrl" -ForegroundColor Cyan
            Invoke-WebRequest -Uri $gitDownloadUrl -OutFile $gitInstallerPath -UseBasicParsing
            
            Write-Host "Installing Git silently..." -ForegroundColor Cyan
            Start-Process -FilePath $gitInstallerPath -ArgumentList "/VERYSILENT", "/NORESTART", "/NOCANCEL", "/SP-", "/CLOSEAPPLICATIONS", "/RESTARTAPPLICATIONS", "/COMPONENTS=icons,ext\reg\shellhere,assoc,assoc_sh" -Wait
            
            # Add Git to PATH for current session
            $gitPath = "${env:ProgramFiles}\Git\bin"
            if (Test-Path $gitPath) {
                $env:PATH = "$gitPath;$env:PATH"
                Write-Host "Git installed successfully and added to PATH" -ForegroundColor Green
                
                # Verify installation
                $gitVersion = git --version 2>&1
                Write-Host "Installed Git version: $gitVersion" -ForegroundColor Green
            }
            else {
                throw "Git installation failed - Git directory not found at $gitPath"
            }
            
            # Clean up installer
            if (Test-Path $gitInstallerPath) {
                Remove-Item $gitInstallerPath -Force -ErrorAction SilentlyContinue
            }
        }
    }

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
    $ProvisionScriptPath = Join-Path "infra" "scripts" | Join-Path -ChildPath "fabric" | Join-Path -ChildPath "provision_fabric_items.ps1"
    if (-not (Test-Path $ProvisionScriptPath)) {
        throw "Provision script not found at: $ProvisionScriptPath"
    }
    Write-Host "Found provision script at: $ProvisionScriptPath" -ForegroundColor Green

    # Change to the script directory
    $ScriptDirectory = Join-Path "infra" "scripts" | Join-Path -ChildPath "fabric"
    Set-Location $ScriptDirectory

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
    # Clean up: return to original location
    try {
        if (Get-Location -Stack -ErrorAction SilentlyContinue) {
            Pop-Location
        }
        
        # Clean up cloned repository if it exists
        if (Test-Path "repo") {
            Write-Host "Cleaning up cloned repository..." -ForegroundColor Yellow
            Remove-Item -Path "repo" -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Warning "Failed to clean up: $($_.Exception.Message)"
    }
}

Write-Host "Azure Deployment Script execution completed." -ForegroundColor Green