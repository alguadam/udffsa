#!/bin/bash

#
# provision_fabric_items.sh
#
# SYNOPSIS
#     Deploys Microsoft Fabric items (lakehouses, notebooks, folders, reports) to a Fabric workspace.
#
# DESCRIPTION
#     This script automates the deployment of UDFF (Unified Data Foundation with Fabric) components 
#     to Microsoft Fabric including folder structure, lakehouses, sample data, notebooks, and Power BI reports.
#
# USAGE
#     ./provision_fabric_items.sh [options]
#
# OPTIONS
#     -c, --capacity-name <name>     Microsoft Fabric capacity name (optional, will use AZURE_FABRIC_CAPACITY_NAME env var if not provided)
#     -w, --workspace-name <name>    Microsoft Fabric workspace name (optional, will use AZURE_FABRIC_WORKSPACE_NAME env var if not provided)
#     -h, --help                     Show this help message
#
# EXAMPLES
#     ./provision_fabric_items.sh -c "MyCapacity" -w "UDFF-Workspace"
#     ./provision_fabric_items.sh -c "MyCapacity"
#     export AZURE_FABRIC_CAPACITY_NAME="MyCapacity" && ./provision_fabric_items.sh
#     export AZURE_FABRIC_CAPACITY_NAME="MyCapacity" AZURE_FABRIC_WORKSPACE_NAME="MyWorkspace" && ./provision_fabric_items.sh
#
# PREREQUISITES
#     - Azure CLI installed and authenticated (az login)
#     - Python 3.9+ with pip
#     - Appropriate permissions in the Fabric capacity and workspace
#

# Set strict error handling
set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Functions for colored output
print_info() {
    echo -e "${CYAN}$1${NC}"
}

print_success() {
    echo -e "${GREEN}$1${NC}"
}

print_warning() {
    echo -e "${YELLOW}$1${NC}"
}

print_error() {
    echo -e "${RED}$1${NC}"
}

print_step() {
    echo -e "${YELLOW}$1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --capacity-name <name>     Microsoft Fabric capacity name (optional, will use AZURE_FABRIC_CAPACITY_NAME env var if not provided)"
    echo "  -w, --workspace-name <name>    Microsoft Fabric workspace name (optional, will use AZURE_FABRIC_WORKSPACE_NAME env var if not provided)"
    echo "  -h, --help                     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -c \"MyCapacity\" -w \"UDFF-Workspace\""
    echo "  $0 -c \"MyCapacity\""
    echo "  export AZURE_FABRIC_CAPACITY_NAME=\"MyCapacity\" && $0"
    echo "  export AZURE_FABRIC_CAPACITY_NAME=\"MyCapacity\" AZURE_FABRIC_WORKSPACE_NAME=\"MyWorkspace\" && $0"
    echo ""
    echo "Prerequisites:"
    echo "  - Azure CLI installed and authenticated (az login)"
    echo "  - Python 3.9+ with pip"
    echo "  - Appropriate permissions in the Fabric capacity and workspace"
}

# Main script starts here
print_success "Starting Microsoft Fabric deployment script..."

# Download function with retry
# download() {
#     local url="$1" file="$2" max_attempts=3 attempt=1
#     while [[ $attempt -le $max_attempts ]]; do
#         if curl -fsSL "$url" -o "$file" 2>/dev/null; then
#             return 0
#         fi
#         ((attempt++))
#         [[ $attempt -le $max_attempts ]] && sleep 1
#     done
#     return 1
# }

# # Base URL
# BASE="https://raw.githubusercontent.com/alguadam/udffsa/deployement-pipeline"

# info "📥 Creating directory structure..."
# mkdir -p udffsa/{infra/{scripts/fabric,data/samples_fabric/{finance,sales,shared}},src/fabric/Notebooks/{bronze_to_silver,silver_to_gold,data_management,schema,test_report},reports}

# info "📦 Downloading Python scripts..."
# {
#     download "$BASE/infra/scripts/fabric/create_fabric_items.py" "udffsa/infra/scripts/fabric/create_fabric_items.py" &
#     download "$BASE/infra/scripts/fabric/fabric_api.py" "udffsa/infra/scripts/fabric/fabric_api.py" &
#     download "$BASE/infra/scripts/fabric/powerbi_api.py" "udffsa/infra/scripts/fabric/powerbi_api.py" &
#     download "$BASE/infra/scripts/fabric/requirements.txt" "udffsa/infra/scripts/fabric/requirements.txt" &
#     wait
# }

# info "📊 Downloading sample data..."
# {
#     # Finance samples
#     download "$BASE/infra/data/samples_fabric/finance/Account_Samples_Fabric.csv" "udffsa/infra/data/samples_fabric/finance/Account_Samples_Fabric.csv" &
#     download "$BASE/infra/data/samples_fabric/finance/Invoice_Samples_Fabric.csv" "udffsa/infra/data/samples_fabric/finance/Invoice_Samples_Fabric.csv" &
#     download "$BASE/infra/data/samples_fabric/finance/Payment_Samples_Fabric.csv" "udffsa/infra/data/samples_fabric/finance/Payment_Samples_Fabric.csv" &
    
#     # Sales samples
#     download "$BASE/infra/data/samples_fabric/sales/Order_Samples_Fabric.csv" "udffsa/infra/data/samples_fabric/sales/Order_Samples_Fabric.csv" &
#     download "$BASE/infra/data/samples_fabric/sales/OrderLine_Samples_Fabric.csv" "udffsa/infra/data/samples_fabric/sales/OrderLine_Samples_Fabric.csv" &
#     download "$BASE/infra/data/samples_fabric/sales/OrderPayment_Fabric.csv" "udffsa/infra/data/samples_fabric/sales/OrderPayment_Fabric.csv" &
    
#     wait
    
#     # Shared samples
#     download "$BASE/infra/data/samples_fabric/shared/Customer_Samples.csv" "udffsa/infra/data/samples_fabric/shared/Customer_Samples.csv" &
#     download "$BASE/infra/data/samples_fabric/shared/CustomerAccount_Samples.csv" "udffsa/infra/data/samples_fabric/shared/CustomerAccount_Samples.csv" &
#     download "$BASE/infra/data/samples_fabric/shared/CustomerRelationshipType_Samples.csv" "udffsa/infra/data/samples_fabric/shared/CustomerRelationshipType_Samples.csv" &
#     download "$BASE/infra/data/samples_fabric/shared/CustomerTradeName_Samples.csv" "udffsa/infra/data/samples_fabric/shared/CustomerTradeName_Samples.csv" &
#     download "$BASE/infra/data/samples_fabric/shared/Location_Samples.csv" "udffsa/infra/data/samples_fabric/shared/Location_Samples.csv" &
#     download "$BASE/infra/data/samples_fabric/shared/Product_Samples_Fabric.csv" "udffsa/infra/data/samples_fabric/shared/Product_Samples_Fabric.csv" &
#     download "$BASE/infra/data/samples_fabric/shared/ProductCategory_Samples.csv" "udffsa/infra/data/samples_fabric/shared/ProductCategory_Samples.csv" &
    
#     wait
# }

# info "📓 Downloading essential notebooks..."
# {
#     # Main notebooks
#     download "$BASE/src/fabric/Notebooks/run_bronze_to_silver.ipynb" "udffsa/src/fabric/Notebooks/run_bronze_to_silver.ipynb" &
#     download "$BASE/src/fabric/Notebooks/run_silver_to_gold.ipynb" "udffsa/src/fabric/Notebooks/run_silver_to_gold.ipynb" &
    
#     # Bronze to silver notebooks
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_finance_account.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_finance_account.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_finance_invoice.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_finance_invoice.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_finance_payment.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_finance_payment.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_salesadb_order.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_salesadb_order.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_salesadb_orderLine.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_salesadb_orderLine.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_salesadb_orderPayment.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_salesadb_orderPayment.ipynb" &
    
#     wait
    
#     # More bronze to silver
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_salesfabric_order.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_salesfabric_order.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_salesfabric_orderLine.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_salesfabric_orderLine.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_salesfabric_orderPayment.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_salesfabric_orderPayment.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_customer.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_customer.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_customeraccount.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_customeraccount.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_customerRelationshipType.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_customerRelationshipType.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_customerTradeName.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_customerTradeName.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_location.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_location.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_product.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_product.ipynb" &
#     download "$BASE/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_productCategory.ipynb" "udffsa/src/fabric/Notebooks/bronze_to_silver/bronze_to_silver_shared_productCategory.ipynb" &
    
#     wait
    
#     # Data management notebooks
#     download "$BASE/src/fabric/Notebooks/data_management/drop_all_tables_gold.ipynb" "udffsa/src/fabric/Notebooks/data_management/drop_all_tables_gold.ipynb" &
#     download "$BASE/src/fabric/Notebooks/data_management/drop_all_tables_silver.ipynb" "udffsa/src/fabric/Notebooks/data_management/drop_all_tables_silver.ipynb" &
#     download "$BASE/src/fabric/Notebooks/data_management/truncate_all_tables_gold.ipynb" "udffsa/src/fabric/Notebooks/data_management/truncate_all_tables_gold.ipynb" &
#     download "$BASE/src/fabric/Notebooks/data_management/truncate_all_tables_silver.ipynb" "udffsa/src/fabric/Notebooks/data_management/truncate_all_tables_silver.ipynb" &
    
#     wait
# }

# info "📈 Downloading reports..."
# {
#     download "$BASE/reports/sales_dashboard.pbix" "udffsa/reports/sales_dashboard.pbix" &
#     download "$BASE/reports/sales_dashboard.pbit" "udffsa/reports/sales_dashboard.pbit" &
#     wait
# }

# success "✅ All files downloaded"

# Variables
REPO_URL="https://github.com/alguadam/udffsa.git"
BRANCH="deployement-pipeline"
CLONE_DIR="udffsa"

# Get current working directory
WORK_DIR=$(pwd)

# Clone repository (shallow clone for speed)
print_step "Cloning repository (shallow clone for speed)..."
if [ ! -d "$CLONE_DIR" ]; then
    git clone --depth 1 --single-branch --branch "$BRANCH" "$REPO_URL" "$CLONE_DIR" --quiet
    print_success "Repository cloned successfully"
else
    print_info "Repository directory already exists"
fi

# Set up paths relative to the cloned repository
SCRIPT_DIR="$CLONE_DIR/infra/scripts/fabric"
REQUIREMENTS_PATH="$CLONE_DIR/infra/scripts/fabric/requirements.txt"

print_info "Working directory: $WORK_DIR"
print_info "Script directory: $SCRIPT_DIR"
print_info "Requirements path: $REQUIREMENTS_PATH"

# Initialize variables
fabricCapacityName=""
fabricWorkspaceName=""
baseUrl=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--capacity-name)
            fabricCapacityName="$2"
            shift 2
            ;;
        -w|--workspace-name)
            fabricWorkspaceName="$2"
            shift 2
            ;;
        -b|--base-url)
            baseUrl="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "❌ Unknown option: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
done

# Validate parameters
if [[ -z "$fabricCapacityName" ]]; then
    # Check if environment variable exists
    if [[ -n "${AZURE_FABRIC_CAPACITY_NAME:-}" ]]; then
        fabricCapacityName="$AZURE_FABRIC_CAPACITY_NAME"
        print_info "Using Fabric capacity name from environment variable: $fabricCapacityName"
    else
        print_error "❌ Error: Capacity name is required"
        exit 1
    fi
fi

# Check if workspace name is provided, otherwise use environment variable
if [[ -z "$fabricWorkspaceName" ]]; then
    if [[ -n "${AZURE_FABRIC_WORKSPACE_NAME:-}" ]]; then
        fabricWorkspaceName="$AZURE_FABRIC_WORKSPACE_NAME"
        print_info "Using Fabric workspace name from environment variable: $fabricWorkspaceName"
    fi
fi

print_info "Fabric Capacity Name: $fabricCapacityName"
if [[ -n "$fabricWorkspaceName" ]]; then
    print_info "Fabric Workspace Name: $fabricWorkspaceName"
    print_warning "Mode: Create/use workspace with specified name"
else
    print_warning "Mode: Create workspace with auto-generated name"
fi

# Validate that Python is available
print_step "Checking Python installation..."
if ! command_exists python && ! command_exists python3; then
    print_error "❌ Python is not installed or not available in PATH."
    exit 1
fi

PYTHON_CMD="python3"
if ! command_exists python3; then
    PYTHON_CMD="python"
fi

python_version=$($PYTHON_CMD --version 2>&1)
print_success "Found: $python_version"

# Validate that pip is available
print_step "Checking pip installation..."
PIP_CMD="pip3"
if ! command_exists pip3; then
    PIP_CMD="pip"
fi

if ! command_exists "$PIP_CMD"; then
    print_error "❌ pip is not available."
    exit 1
fi

print_success "pip is available"

# Verify required files exist
print_step "Verifying required files..."
if [[ ! -f "$REQUIREMENTS_PATH" ]]; then
    print_error "❌ requirements.txt not found at: $REQUIREMENTS_PATH"
    exit 1
fi

print_success "All required files found"

# Install Python dependencies
print_step "Installing Python dependencies..."
if ! $PIP_CMD install -r "$REQUIREMENTS_PATH" --quiet; then
    print_error "❌ Failed to install Python dependencies."
    exit 1
fi
print_success "Dependencies installed successfully"

# Change to the cloned repository directory
# cd "$CLONE_DIR"

# Run the Python deployment script
print_step "Starting Fabric items deployment..."
print_info "Working from directory: $(pwd)"

# Build command arguments
python_args=(--capacityName "$fabricCapacityName")
if [[ -n "$fabricWorkspaceName" ]]; then
    python_args+=(--workspaceName "$fabricWorkspaceName")
fi
exit 1
# Run Python script from the correct location
if $PYTHON_CMD -u infra/scripts/fabric/create_fabric_items.py "${python_args[@]}"; then
    echo ""
    print_success "✅ Fabric deployment completed successfully!"
else
    exit_code=$?
    print_error "❌ Deployment failed with exit code: $exit_code"
    exit 1
fi