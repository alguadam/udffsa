# Azure Deployment Script for Fabric Resources
# This script clones the repository and runs the fabric provisioning script

param(
    [Parameter(Mandatory=$true)]
    [string]$BaseUrl,
    
    [Parameter(Mandatory=$true)]
    [string]$CapacityName,
    
    [string]$GitRepo = "https://github.com/alguadam/udffsa.git",
    
    [string]$Branch = "main"
)

# Set error action preference
$ErrorActionPreference = "Stop"

Write-Output "Starting Azure Fabric deployment script..."
Write-Output "Base URL: $BaseUrl"
Write-Output "Capacity Name: $CapacityName"
Write-Output "Git Repository: $GitRepo"
Write-Output "Branch: $Branch"

try {
    # Create a temporary directory
    $tempDir = "/tmp/fabric-deployment-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Output "Creating temporary directory: $tempDir"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    
    # Change to temp directory
    Set-Location $tempDir
    
    # Check if git is available, install if needed (Linux environment)
    try {
        git --version | Out-Null
    } catch {
        Write-Output "Installing git..."
        if ($IsLinux) {
            Invoke-Expression "apt-get update -qq"
            Invoke-Expression "apt-get install -y git"
        } else {
            throw "Git is not available and cannot be automatically installed on this platform"
        }
    }
    
    # Clone the repository
    Write-Output "Cloning repository..."
    git clone --branch $Branch --depth 1 $GitRepo .
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to clone repository. Exit code: $LASTEXITCODE"
    }
    
    # Navigate to the fabric scripts directory
    $fabricScriptsPath = "./infra/scripts/fabric"
    if (-not (Test-Path $fabricScriptsPath)) {
        throw "Fabric scripts directory not found at: $fabricScriptsPath"
    }
    
    Set-Location $fabricScriptsPath
    
    # Install Python requirements
    Write-Output "Installing Python requirements..."
    if (Test-Path "requirements.txt") {
        # Check if pip is available, install if needed
        try {
            pip --version | Out-Null
        } catch {
            Write-Output "Installing pip..."
            if ($IsLinux) {
                Invoke-Expression "apt-get install -y python3-pip"
            } else {
                throw "pip is not available and cannot be automatically installed on this platform"
            }
        }
        
        pip install -r requirements.txt
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to install Python requirements. Exit code: $LASTEXITCODE"
        }
    } else {
        Write-Warning "requirements.txt not found in fabric scripts directory"
    }
    
    # Make the provision script executable (if on Linux/bash)
    if (Test-Path "./provision_fabric_items.sh") {
        chmod +x ./provision_fabric_items.sh
    }
    
    # Run the fabric provisioning script
    Write-Output "Running fabric provisioning script..."
    
    # Try PowerShell script first, then bash script
    if (Test-Path "./provision_fabric_items.ps1") {
        Write-Output "Running PowerShell provisioning script..."
        pwsh -File "./provision_fabric_items.ps1" -FabricCapacityName $CapacityName
        $exitCode = $LASTEXITCODE
    } elseif (Test-Path "./provision_fabric_items.sh") {
        Write-Output "Running bash provisioning script..."
        bash "./provision_fabric_items.sh" -b $BaseUrl -c $CapacityName
        $exitCode = $LASTEXITCODE
    } else {
        throw "No provisioning script found (neither .ps1 nor .sh)"
    }
    
    if ($exitCode -ne 0) {
        throw "Fabric provisioning script failed with exit code: $exitCode"
    }
    
    Write-Output "Fabric deployment completed successfully!"
    
} catch {
    Write-Error "Deployment failed: $($_.Exception.Message)"
    exit 1
} finally {
    # Cleanup - remove temporary directory
    if (Test-Path $tempDir) {
        Write-Output "Cleaning up temporary directory: $tempDir"
        try {
            Set-Location "/tmp"
            Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Failed to cleanup temporary directory: $($_.Exception.Message)"
        }
    }
}

Write-Output "Azure Fabric deployment script completed."