#!/bin/bash

# Azure Deployment Script for Fabric Resources - Python-based download
# This script downloads repository files using Python (which is available in Azure CLI)

set -euo pipefail

# Enable debug mode
set -x

# Function to log with timestamps
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Function to handle errors
error_exit() {
    log "ERROR: $1"
    exit 1
}

# Debug: Print all arguments
log "=== DEBUGGING ARGUMENTS ==="
log "Total arguments: $#"
log "All arguments: $*"
for i in $(seq 1 $#); do
    eval "arg=\${$i}"
    log "Argument $i: '$arg'"
done
log "=== END ARGUMENTS DEBUG ==="

# Log all arguments received
log "=== SCRIPT ARGUMENTS DEBUG ==="
log "Total arguments received: $#"
log "All arguments: $*"
for i in {1..10}; do
    if [[ -n "${!i:-}" ]]; then
        log "Argument $i: ${!i}"
    fi
done
log "=== END ARGUMENTS DEBUG ==="

# Function to display usage
usage() {
    log "Usage: $0 -b <base_url> -c <capacity_name> [-r <git_repo>] [-n <branch>]"
    log "  -b: Base URL for the deployment"
    log "  -c: Capacity name for Fabric resources"
    log "  -r: Git repository URL (optional, defaults to https://github.com/alguadam/udffsa.git)"
    log "  -n: Git branch name (optional, defaults to main)"
    exit 1
}

# Default values
GIT_REPO="https://github.com/alguadam/udffsa.git"
BRANCH="deployement-pipeline"
BASE_URL=""
CAPACITY_NAME=""

# Parse command line arguments
log "Starting argument parsing..."
while getopts "b:c:r:n:h" opt; do
    log "Processing option: -$opt with value: $OPTARG"
    case $opt in
        b)
            BASE_URL="$OPTARG"
            log "Set BASE_URL to: $BASE_URL"
            ;;
        c)
            CAPACITY_NAME="$OPTARG"
            log "Set CAPACITY_NAME to: $CAPACITY_NAME"
            ;;
        r)
            GIT_REPO="$OPTARG"
            log "Set GIT_REPO to: $GIT_REPO"
            ;;
        n)
            BRANCH="$OPTARG"
            log "Set BRANCH to: $BRANCH"
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
log "Completed argument parsing"

log "Final parameter values:"
log "  BASE_URL: $BASE_URL"
log "  CAPACITY_NAME: $CAPACITY_NAME"  
log "  GIT_REPO: $GIT_REPO"
log "  BRANCH: $BRANCH"

# Check required parameters
if [[ -z "$BASE_URL" || -z "$CAPACITY_NAME" ]]; then
    error_exit "Base URL and Capacity Name are required parameters."
fi

log "Starting Azure Fabric deployment script (Python-based download)..."
log "Base URL: $BASE_URL"
log "Capacity Name: $CAPACITY_NAME"
log "Git Repository: $GIT_REPO"
log "Branch: $BRANCH"

# Verify Python is available
log "Checking Python availability..."
if ! command -v python3 &> /dev/null; then
    error_exit "Python3 is not available in this environment"
fi

python3 --version
log "Python3 is available"

# Create a temporary directory
TEMP_DIR="/tmp/fabric-deployment-$(date +%Y%m%d-%H%M%S)"
log "Creating temporary directory: $TEMP_DIR"
mkdir -p "$TEMP_DIR" || error_exit "Failed to create temporary directory"

# Cleanup function
cleanup() {
    log "Cleaning up temporary directory: $TEMP_DIR"
    rm -rf "$TEMP_DIR" || log "Warning: Failed to cleanup temporary directory"
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Change to temp directory
cd "$TEMP_DIR" || error_exit "Failed to change to temporary directory"
log "Changed to temporary directory: $(pwd)"

# Extract GitHub user/repo from URL
if [[ "$GIT_REPO" =~ github\.com[/:]([^/]+)/([^/]+)(.git)?$ ]]; then
    GITHUB_USER="${BASH_REMATCH[1]}"
    GITHUB_REPO="${BASH_REMATCH[2]}"
    GITHUB_REPO=${GITHUB_REPO%.git}  # Remove .git suffix if present
    log "Parsed GitHub repository: $GITHUB_USER/$GITHUB_REPO"
else
    error_exit "Could not parse GitHub repository URL: $GIT_REPO"
fi

log "Downloading repository archive from GitHub using Python..."
ARCHIVE_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/archive/refs/heads/${BRANCH}.tar.gz"
log "Archive URL: $ARCHIVE_URL"

# Create a Python script to download the file
log "Creating Python download script..."
cat > download_repo.py << 'EOF'
import sys
import urllib.request
import tarfile
import os
import traceback

def download_and_extract(url, filename):
    try:
        print(f"[PYTHON] Downloading {url}...")
        
        # Create a request with proper headers
        req = urllib.request.Request(url)
        req.add_header('User-Agent', 'Azure-Deployment-Script/1.0')
        
        # Download the file
        with urllib.request.urlopen(req) as response:
            if response.getcode() != 200:
                print(f"[PYTHON] HTTP Error: {response.getcode()}")
                return False
                
            with open(filename, 'wb') as f:
                f.write(response.read())
                
        print(f"[PYTHON] Downloaded {filename}")
        
        # Verify file exists and has content
        if not os.path.exists(filename):
            print(f"[PYTHON] Error: Downloaded file {filename} does not exist")
            return False
            
        file_size = os.path.getsize(filename)
        if file_size == 0:
            print(f"[PYTHON] Error: Downloaded file {filename} is empty")
            return False
            
        print(f"[PYTHON] File size: {file_size} bytes")
        
        print(f"[PYTHON] Extracting {filename}...")
        with tarfile.open(filename, 'r:gz') as tar:
            # Get the top-level directory name
            members = tar.getnames()
            if not members:
                print("[PYTHON] Error: Archive is empty")
                return False
                
            print(f"[PYTHON] Archive contains {len(members)} files")
            top_dir = members[0].split('/')[0]
            print(f"[PYTHON] Top level directory: {top_dir}")
            
            # Extract all files
            tar.extractall()
            
            # Move contents from the subdirectory to current directory
            if os.path.exists(top_dir):
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
                    print(f"[PYTHON] Moved {src} -> {dst}")
                
                # Remove the now-empty top directory
                os.rmdir(top_dir)
                print(f"[PYTHON] Removed temporary directory: {top_dir}")
        
        # Clean up the tar file
        os.remove(filename)
        print("[PYTHON] Extraction completed successfully")
        
        # List contents to verify
        print("[PYTHON] Current directory contents:")
        for item in os.listdir('.'):
            print(f"  - {item}")
            
        return True
        
    except Exception as e:
        print(f"[PYTHON] Error downloading/extracting: {e}")
        traceback.print_exc()
        return False

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("[PYTHON] Usage: python download_repo.py <url> <filename>")
        sys.exit(1)
    
    url = sys.argv[1]
    filename = sys.argv[2]
    
    print(f"[PYTHON] Starting download process...")
    print(f"[PYTHON] URL: {url}")
    print(f"[PYTHON] Filename: {filename}")
    
    success = download_and_extract(url, filename)
    
    if success:
        print("[PYTHON] Download and extraction completed successfully")
        sys.exit(0)
    else:
        print("[PYTHON] Download and extraction failed")
        sys.exit(1)
EOF

# Run the Python download script
log "Running Python download script..."
python3 download_repo.py "$ARCHIVE_URL" "repo.tar.gz"

if [[ $? -ne 0 ]]; then
    error_exit "Failed to download repository archive"
fi

log "Repository download completed successfully"
log "Current directory contents after extraction:"
ls -la
log "Directory structure after extraction (first 50 entries):"
find . -type d 2>/dev/null | head -50
log "Files in root directory:"
find . -maxdepth 1 -type f 2>/dev/null
log "Looking for fabric directories anywhere in the extracted content:"
find . -name "*fabric*" -type d 2>/dev/null || log "No fabric-related directories found"

# Navigate to the fabric scripts directory - try multiple possible locations
FABRIC_SCRIPTS_PATH=""
POSSIBLE_PATHS=(
    "./infra/scripts/fabric"
    "./scripts/fabric"
    "./fabric"
    "$(find . -name "fabric" -type d -path "*/scripts/*" | head -1)"
    "$(find . -name "fabric" -type d | head -1)"
)

log "Looking for fabric scripts directory..."
log "Available directories in current location:"
find . -type d -maxdepth 4 2>/dev/null | head -30

for path in "${POSSIBLE_PATHS[@]}"; do
    if [[ -n "$path" && -d "$path" ]]; then
        FABRIC_SCRIPTS_PATH="$path"
        log "Found fabric scripts directory at: $FABRIC_SCRIPTS_PATH"
        break
    else
        log "Checked path: $path - not found"
    fi
done

if [[ -z "$FABRIC_SCRIPTS_PATH" ]]; then
    log "Error: Fabric scripts directory not found in any expected location"
    log "Available directories:"
    find . -name "fabric" -type d 2>/dev/null || log "No 'fabric' directories found"
    log "Current directory structure:"
    find . -type d -maxdepth 4 2>/dev/null | head -30
    log "All contents in current directory:"
    ls -la
    error_exit "Fabric scripts directory not found"
fi

cd "$FABRIC_SCRIPTS_PATH" || error_exit "Failed to change to fabric scripts directory"
log "Successfully changed to fabric scripts directory: $(pwd)"
log "Fabric scripts directory contents:"
ls -la

# Install Python requirements
log "Installing Python requirements..."
if [[ -f "requirements.txt" ]]; then
    log "Found requirements.txt, contents:"
    cat requirements.txt
    
    # Use pip3 if available, otherwise pip
    if command -v pip3 &> /dev/null; then
        log "Using pip3 to install requirements..."
        pip3 install -r requirements.txt || error_exit "Failed to install requirements with pip3"
    elif command -v pip &> /dev/null; then
        log "Using pip to install requirements..."
        pip install -r requirements.txt || error_exit "Failed to install requirements with pip"
    else
        log "Neither pip nor pip3 found, trying python -m pip..."
        python3 -m pip install -r requirements.txt || error_exit "Failed to install requirements with python -m pip"
    fi
    log "Python requirements installed successfully"
else
    log "Warning: requirements.txt not found in fabric scripts directory"
fi

# Make the provision script executable and run it
if [[ -f "./provision_fabric_items.sh" ]]; then
    chmod +x ./provision_fabric_items.sh
    log "Running bash provisioning script with parameters: -b '$BASE_URL' -c '$CAPACITY_NAME'"
    ./provision_fabric_items.sh -b "$BASE_URL" -c "$CAPACITY_NAME"
    SCRIPT_EXIT_CODE=$?
    
    if [[ $SCRIPT_EXIT_CODE -ne 0 ]]; then
        error_exit "Bash provisioning script failed with exit code: $SCRIPT_EXIT_CODE"
    fi
    log "Bash provisioning script completed successfully"
    
elif [[ -f "./provision_fabric_items.ps1" ]]; then
    log "Running PowerShell provisioning script with parameter: -FabricCapacityName '$CAPACITY_NAME'"
    pwsh -File "./provision_fabric_items.ps1" -FabricCapacityName "$CAPACITY_NAME"
    SCRIPT_EXIT_CODE=$?
    
    if [[ $SCRIPT_EXIT_CODE -ne 0 ]]; then
        error_exit "PowerShell provisioning script failed with exit code: $SCRIPT_EXIT_CODE"
    fi
    log "PowerShell provisioning script completed successfully"
    
else
    log "Error: No provisioning script found (neither .ps1 nor .sh)"
    log "Available files in fabric scripts directory:"
    ls -la
    error_exit "No provisioning script found"
fi

log "Fabric deployment completed successfully!"
log "Azure Fabric deployment script completed successfully."

# Ensure we exit with success
exit 0