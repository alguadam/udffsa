#!/bin/bash

# Azure Deployment Script for Fabric Resources - Python-based download
# This script downloads repository files using Python (which is available in Azure CLI)

set -euo pipefail

# Function to display usage
usage() {
    echo "Usage: $0 -b <base_url> -c <capacity_name> [-r <git_repo>] [-n <branch>]"
    echo "  -b: Base URL for the deployment"
    echo "  -c: Capacity name for Fabric resources"
    echo "  -r: Git repository URL (optional, defaults to https://github.com/alguadam/udffsa.git)"
    echo "  -n: Git branch name (optional, defaults to main)"
    exit 1
}

# Default values
GIT_REPO="https://github.com/alguadam/udffsa.git"
BRANCH="main"
BASE_URL=""
CAPACITY_NAME=""

# Parse command line arguments
while getopts "b:c:r:n:h" opt; do
    case $opt in
        b)
            BASE_URL="$OPTARG"
            ;;
        c)
            CAPACITY_NAME="$OPTARG"
            ;;
        r)
            GIT_REPO="$OPTARG"
            ;;
        n)
            BRANCH="$OPTARG"
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Check required parameters
if [[ -z "$BASE_URL" || -z "$CAPACITY_NAME" ]]; then
    echo "Error: Base URL and Capacity Name are required parameters."
    usage
fi

echo "Starting Azure Fabric deployment script (Python-based download)..."
echo "Base URL: $BASE_URL"
echo "Capacity Name: $CAPACITY_NAME"
echo "Git Repository: $GIT_REPO"
echo "Branch: $BRANCH"

# Create a temporary directory
TEMP_DIR="/tmp/fabric-deployment-$(date +%Y%m%d-%H%M%S)"
echo "Creating temporary directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR"

# Cleanup function
cleanup() {
    echo "Cleaning up temporary directory: $TEMP_DIR"
    rm -rf "$TEMP_DIR" || echo "Warning: Failed to cleanup temporary directory"
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Change to temp directory
cd "$TEMP_DIR"

# Extract GitHub user/repo from URL
if [[ "$GIT_REPO" =~ github\.com[/:]([^/]+)/([^/]+)(.git)?$ ]]; then
    GITHUB_USER="${BASH_REMATCH[1]}"
    GITHUB_REPO="${BASH_REMATCH[2]}"
    GITHUB_REPO=${GITHUB_REPO%.git}  # Remove .git suffix if present
else
    echo "Error: Could not parse GitHub repository URL: $GIT_REPO"
    exit 1
fi

echo "Downloading repository archive from GitHub using Python..."
ARCHIVE_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/${BRANCH}.tar.gz"
echo "Archive URL: $ARCHIVE_URL"

# Create a Python script to download the file
cat > download_repo.py << 'EOF'
import sys
import urllib.request
import tarfile
import os

def download_and_extract(url, filename):
    try:
        print(f"Downloading {url}...")
        urllib.request.urlretrieve(url, filename)
        print(f"Downloaded {filename}")
        
        print(f"Extracting {filename}...")
        with tarfile.open(filename, 'r:gz') as tar:
            # Get the top-level directory name
            members = tar.getnames()
            if members:
                top_dir = members[0].split('/')[0]
                
                # Extract all files
                tar.extractall()
                
                # Move contents from the subdirectory to current directory
                for item in os.listdir(top_dir):
                    src = os.path.join(top_dir, item)
                    dst = item
                    if os.path.exists(dst):
                        # If destination exists, remove it first
                        if os.path.isdir(dst):
                            import shutil
                            shutil.rmtree(dst)
                        else:
                            os.remove(dst)
                    os.rename(src, dst)
                
                # Remove the now-empty top directory
                os.rmdir(top_dir)
                
        # Clean up the tar file
        os.remove(filename)
        print("Extraction completed successfully")
        return True
        
    except Exception as e:
        print(f"Error downloading/extracting: {e}")
        return False

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python download_repo.py <url> <filename>")
        sys.exit(1)
    
    url = sys.argv[1]
    filename = sys.argv[2]
    
    success = download_and_extract(url, filename)
    sys.exit(0 if success else 1)
EOF

# Run the Python download script
python3 download_repo.py "$ARCHIVE_URL" "repo.tar.gz"

if [[ $? -ne 0 ]]; then
    echo "Failed to download repository archive"
    exit 1
fi

# Navigate to the fabric scripts directory
FABRIC_SCRIPTS_PATH="./infra/scripts/fabric"
if [[ ! -d "$FABRIC_SCRIPTS_PATH" ]]; then
    echo "Error: Fabric scripts directory not found at: $FABRIC_SCRIPTS_PATH"
    echo "Available directories:"
    find . -name "fabric" -type d 2>/dev/null || echo "No 'fabric' directories found"
    echo "Current directory contents:"
    ls -la
    exit 1
fi

cd "$FABRIC_SCRIPTS_PATH"

# Install Python requirements
echo "Installing Python requirements..."
if [[ -f "requirements.txt" ]]; then
    # Use pip3 if available, otherwise pip
    if command -v pip3 &> /dev/null; then
        pip3 install -r requirements.txt
    elif command -v pip &> /dev/null; then
        pip install -r requirements.txt
    else
        echo "Neither pip nor pip3 found, trying to install packages manually..."
        # Try to install common packages that might be needed
        python3 -m pip install requests || echo "Could not install requests"
    fi
else
    echo "Warning: requirements.txt not found in fabric scripts directory"
fi

# Make the provision script executable
if [[ -f "./provision_fabric_items.sh" ]]; then
    chmod +x ./provision_fabric_items.sh
    echo "Running bash provisioning script..."
    ./provision_fabric_items.sh -b "$BASE_URL" -c "$CAPACITY_NAME"
elif [[ -f "./provision_fabric_items.ps1" ]]; then
    echo "Running PowerShell provisioning script..."
    pwsh -File "./provision_fabric_items.ps1" -FabricCapacityName "$CAPACITY_NAME"
else
    echo "Error: No provisioning script found (neither .ps1 nor .sh)"
    echo "Available files in fabric scripts directory:"
    ls -la
    exit 1
fi

echo "Fabric deployment completed successfully!"
echo "Azure Fabric deployment script completed."