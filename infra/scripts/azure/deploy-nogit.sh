#!/bin/bash

# Azure Deployment Script for Fabric Resources - No Git Version
# This script downloads repository files directly without requiring git

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

echo "Starting Azure Fabric deployment script (no-git version)..."
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

echo "Downloading repository archive from GitHub..."
ARCHIVE_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/${BRANCH}.tar.gz"
echo "Archive URL: $ARCHIVE_URL"

# Download and extract the repository archive
curl -fsSL "$ARCHIVE_URL" -o repo.tar.gz
tar -xzf repo.tar.gz --strip-components=1

# Navigate to the fabric scripts directory
FABRIC_SCRIPTS_PATH="./infra/scripts/fabric"
if [[ ! -d "$FABRIC_SCRIPTS_PATH" ]]; then
    echo "Error: Fabric scripts directory not found at: $FABRIC_SCRIPTS_PATH"
    exit 1
fi

cd "$FABRIC_SCRIPTS_PATH"

# Install Python requirements
echo "Installing Python requirements..."
if [[ -f "requirements.txt" ]]; then
    # Ensure pip is available
    if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
        echo "Installing pip..."
        apt-get update -qq
        apt-get install -y python3-pip
    fi
    
    # Use pip3 if pip is not available
    if command -v pip3 &> /dev/null; then
        pip3 install -r requirements.txt
    else
        pip install -r requirements.txt
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
    exit 1
fi

echo "Fabric deployment completed successfully!"
echo "Azure Fabric deployment script completed."