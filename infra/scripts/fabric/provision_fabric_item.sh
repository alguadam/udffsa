#!/bin/bash

# Initialize variables
baseUrl="$1"
fabricCapacityName="$2"
fabricWorkspaceName=""

# Variables
requirementFile="requirements.txt"
requirementFileUrl=${baseUrl}"infra/scripts/fabric/requirements.txt"

echo "Downloading Python scripts..."
curl --output "create_fabric_items.py" ${baseUrl}"infra/scripts/fabric/create_fabric_items.py"
curl --output "fabric_api.py" ${baseUrl}"infra/scripts/fabric/fabric_api.py"
curl --output "powerbi_api.py" ${baseUrl}"infra/scripts/fabric/powerbi_api.py"

# Download the requirement file
curl --output "$requirementFile" "$requirementFileUrl"

# Check if workspace name is provided, otherwise use environment variable
if [[ -z "$fabricWorkspaceName" ]]; then
    if [[ -n "${AZURE_FABRIC_WORKSPACE_NAME:-}" ]]; then
        fabricWorkspaceName="$AZURE_FABRIC_WORKSPACE_NAME"
        echo "Using Fabric workspace name from environment variable: $fabricWorkspaceName"
    fi
fi

if ! pip install -r "$requirementFile" --quiet; then
    echo "❌ Failed to install Python dependencies. Please check requirements.txt and try again."
    exit 1
fi
echo "Dependencies installed successfully"

# Run the Python deployment script
echo "Starting Fabric items deployment..."
echo "This may take several minutes to complete..."
echo ""

# Build command arguments
python_args=(--capacityName "$fabricCapacityName")
if [[ -n "$fabricWorkspaceName" ]]; then
    python_args+=(--workspaceName "$fabricWorkspaceName")
fi

# Run Python unbuffered so prints show immediately
if python -u create_fabric_item.py --capacityName "$fabricCapacityName" --workspaceName "$fabricWorkspaceName"; then
    echo ""
    echo "✅ Fabric deployment completed successfully!"
    echo ""
else
    exit_code=$?
    echo "❌ Deployment failed with exit code: $exit_code"
    echo ""
    exit $exit_code
fi