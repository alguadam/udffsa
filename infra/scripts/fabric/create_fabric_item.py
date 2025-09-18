import os
import glob
import time
import argparse
import sys
import json
import base64
import re
import requests
from fabric_api import create_fabric_client, FabricApiError
from powerbi_api import *
import logging
from datetime import datetime

# Enhanced logging configuration
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler(f'fabric_deployment_{datetime.now().strftime("%Y%m%d_%H%M%S")}.log')
    ]
)
logger = logging.getLogger(__name__)

solution_name = "Unified Data Foundation with Fabric"

# Log deployment start
logger.info(f"=" * 80)
logger.info(f"Starting {solution_name} deployment")
logger.info(f"Deployment started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
logger.info(f"=" * 80)

####################
# Helper Functions #
####################

def build_folder_path_mapping(folders: list) -> dict:
    """Build a mapping of full folder paths to folder IDs."""
    logger.debug(f"Building folder path mapping for {len(folders)} folders")
    folder_lookup = {f['id']: f for f in folders}
    path_map = {}
    
    def build_path(folder_id: str) -> str:
        if folder_id not in folder_lookup:
            return ""
        
        folder = folder_lookup[folder_id]
        name = folder['displayName']
        parent_id = folder.get('parentFolderId')
        
        if not parent_id:
            return name
        
        parent_path = build_path(parent_id)
        return f"{parent_path}/{name}"
    
    for folder in folders:
        full_path = build_path(folder['id'])
        path_map[full_path] = folder['id']
    
    return path_map


def create_fabric_directory_structure(fabric_client, workspace_id: str, folder_path: str, existing_folder_map: dict) -> str:
    """Create a complete folder hierarchy."""
    logger.debug(f"Creating fabric directory structure: {folder_path}")
    
    # Check if folder already exists
    if folder_path in existing_folder_map:
        logger.debug(f"Folder '{folder_path}' already exists with ID: {existing_folder_map[folder_path]}")
        return existing_folder_map[folder_path]
    
    # Split path and create recursively
    path_parts = folder_path.split('/')
    logger.debug(f"Creating folder hierarchy with {len(path_parts)} levels")
    
    if len(path_parts) == 1:
        # Root folder
        folder_id = fabric_client.create_folder(workspace_id, path_parts[0])
        existing_folder_map[folder_path] = folder_id
        return folder_id
    else:
        # Ensure parent exists
        parent_path = '/'.join(path_parts[:-1])
        parent_id = create_fabric_directory_structure(fabric_client, workspace_id, parent_path, existing_folder_map)
        
        # Create this folder
        folder_name = path_parts[-1]
        folder_id = fabric_client.create_folder(workspace_id, folder_name, parent_id)
        existing_folder_map[folder_path] = folder_id
        return folder_id


def create_lakehouse_directory_structure(file_system_client, lakehouse_root_path: str, folder_path: str) -> None:
    """Create directory structure in a lakehouse for UDFF data organization."""
    if not folder_path or folder_path == '.':
        return
    
    full_path = f"{lakehouse_root_path}/{folder_path}".replace('\\', '/')
    logger.debug(f"Creating lakehouse directory: {full_path}")
    
    try:
        # Check if directory exists
        directory_client = file_system_client.get_directory_client(full_path)
        directory_client.get_directory_properties()
        logger.debug(f"Directory already exists: {full_path}")
    except Exception:
        try:
            # Create parent directories first
            parent_path = os.path.dirname(folder_path)
            if parent_path and parent_path != '.':
                create_lakehouse_directory_structure(file_system_client, lakehouse_root_path, parent_path)
            
            # Create the directory
            directory_client = file_system_client.get_directory_client(full_path)
            directory_client.create_directory()
            logger.info(f"✅ Created directory: {os.path.basename(folder_path)}")
        except Exception as e:
            logger.error(f"Failed to create directory {full_path}: {str(e)}")
            logger.error("Solution: Check OneLake connectivity and permissions")
            sys.exit(1)

####################
# Variables set up #
####################

workspace_default_name = "Unified Data Foundation with Fabric"
script_dir = os.path.dirname(os.path.abspath(__file__))
repo_root = os.path.dirname(os.path.dirname(os.path.dirname(script_dir)))  # Go up three levels from infra/scripts/fabric to repo root

logger.info(f"Script directory: {script_dir}")
logger.info(f"Repository root: {repo_root}")

##########################
# Command line arguments #
##########################

# Parse command line arguments
parser = argparse.ArgumentParser(description=f'Deploy {solution_name} to Microsoft Fabric')
parser.add_argument('--capacityName', required=True, help='Microsoft Fabric capacity name')
parser.add_argument('--workspaceName', required=False, help=f'Workspace name (if not provided, will use "{workspace_default_name}")')
args = parser.parse_args()

logger.info(f"🚀 Starting {solution_name} deployment to Microsoft Fabric")
logger.info(f"📋 Target capacity: {args.capacityName}")
if args.workspaceName:
    logger.info(f"📋 Target workspace name: {args.workspaceName}")
else:
    logger.info(f"📋 Will create new workspace with auto-generated name")
logger.info("-" * 60)

capacity_name = args.capacityName
workspace_name = args.workspaceName

# Initialize Fabric API client
logger.info("🔐 Initializing authentication...")
try:
    start_time = time.time()
    azure_credentials = DefaultAzureCredential()
    fabric_client = create_fabric_client(azure_credentials)
    auth_time = time.time() - start_time
    logger.info(f"✅ Authentication successful (took {auth_time:.2f}s)")
except Exception as e:
    logger.error(f"❌ Failed to authenticate with Fabric APIs")
    logger.error(f"Details: {str(e)}")
    logger.error("Solution: Please ensure you are logged in with Azure CLI: az login")
    sys.exit(1)

#############
# Workspace #
#############
# Docs: https://learn.microsoft.com/en-us/rest/api/fabric/admin/workspaces

logger.info("🏗️ Setting up workspace...")
try:
    # Get capacity ID from capacity name
    logger.info(f"🔍 Looking up capacity: '{capacity_name}'")
    start_time = time.time()
    capacities = fabric_client.get_capacities()
    capacity_lookup_time = time.time() - start_time
    logger.debug(f"Capacity lookup took {capacity_lookup_time:.2f}s, found {len(capacities)} capacities")
    
    capacity = next((c for c in capacities if c['displayName'].lower() == capacity_name.lower()), None)
    
    if not capacity:
        logger.error(f"❌ Capacity '{capacity_name}' not found")
        logger.error("Available capacities:")
        for cap in capacities:
            logger.error(f"   - {cap['displayName']} (ID: {cap['id']})")
        sys.exit(1)
    
    capacity_id = capacity['id']
    logger.info(f"✅ Found capacity: '{capacity['displayName']}' (ID: {capacity_id})")
    logger.info(f"   SKU: {capacity.get('sku', 'N/A')}")
    logger.info(f"   State: {capacity.get('state', 'N/A')}")
    logger.info(f"   Region: {capacity.get('region', 'N/A')}")
    
    # Handle workspace creation or lookup
    # If no workspace name provided, use default name
    if not workspace_name:
        workspace_name = workspace_default_name
        logger.info(f"📋 No workspace name provided, using default: '{workspace_name}'")
    
    logger.info(f"🔍 Looking for existing workspace: '{workspace_name}'")
    start_time = time.time()
    workspaces = fabric_client.get_workspaces()
    workspace_lookup_time = time.time() - start_time
    logger.debug(f"Workspace lookup took {workspace_lookup_time:.2f}s, found {len(workspaces)} workspaces")
    
    workspace = next((w for w in workspaces if w['displayName'].lower() == workspace_name.lower()), None)
    
    if workspace:
        workspace_id = workspace['id']
        logger.info(f"✅ Found existing workspace: '{workspace_name}' (ID: {workspace_id})")
        
        logger.info(f"🔄 Assigning workspace to capacity: '{capacity_name}'")
        start_time = time.time()
        fabric_client.assign_workspace_to_capacity(workspace_id, capacity_id)
        assignment_time = time.time() - start_time
        logger.info(f"✅ Workspace assigned to capacity: '{capacity_name}' (took {assignment_time:.2f}s)")
    else:
        logger.info(f"🏗️ Creating new workspace: '{workspace_name}'")
        start_time = time.time()
        workspace_id = fabric_client.create_workspace(workspace_name, capacity_id)
        creation_time = time.time() - start_time
        logger.info(f"✅ Created workspace: '{workspace_name}' (ID: {workspace_id}, took {creation_time:.2f}s)")
    
except FabricApiError as e:
    logger.error(f"❌ Fabric API error during workspace setup")
    logger.error(f"Status Code: {e.status_code}")
    logger.error(f"Details: {str(e)}")
    if e.status_code == 404:
        logger.error("Solution: Verify capacity name and ensure it exists")
    elif e.status_code == 403:
        logger.error("Solution: Ensure you have appropriate permissions")
    sys.exit(1)
except Exception as e:
    logger.error(f"❌ Unexpected error during workspace setup: {str(e)}")
    sys.exit(1)

####################
# Folder structure #
####################
# Docs: https://learn.microsoft.com/en-us/rest/api/fabric/core/folders

logger.info("📁 Setting up folder structure...")
# Prepare variables
fabric_folder_path_lakehouses = 'lakehouses'
fabric_folder_path_notebooks = 'notebooks'
fabric_folder_path_notebooks_bronze_to_silver = 'notebooks/bronze_to_silver'
fabric_folder_path_notebooks_data_management = 'notebooks/data_management'
fabric_folder_path_notebooks_schema = 'notebooks/schema'
fabric_folder_path_notebooks_silver_to_gold = 'notebooks/silver_to_gold'
fabric_folder_path_reports = 'reports'
udff_fabric_folders = [
    fabric_folder_path_lakehouses,
    fabric_folder_path_notebooks_bronze_to_silver,
    fabric_folder_path_notebooks_data_management,
    fabric_folder_path_notebooks_schema,
    fabric_folder_path_notebooks_silver_to_gold,
    fabric_folder_path_reports
]

try:
    logger.info(f"📁 Creating folder structure for '{solution_name}' solution")
    start_time = time.time()
    
    # Get existing folders and build path mapping
    logger.debug("Retrieving existing folders...")
    fabric_folders = build_folder_path_mapping(fabric_client.get_folders(workspace_id))
    logger.debug(f"Found {len(fabric_folders)} existing folders")
    
    # Create hierarchy of folders based on full path
    created_folders = 0
    for udff_folder_path in udff_fabric_folders:
        if udff_folder_path in fabric_folders:
            logger.info(f"  📁 Folder '{udff_folder_path}' already exists")
        else:
            try:
                folder_start_time = time.time()
                folder_id = create_fabric_directory_structure(fabric_client, workspace_id, udff_folder_path, fabric_folders)
                folder_creation_time = time.time() - folder_start_time
                logger.info(f"  ✅ Created folder '{udff_folder_path}' (took {folder_creation_time:.2f}s)")
                created_folders += 1
            except Exception as e:
                logger.error(f"❌ Failed to create folder '{udff_folder_path}': {str(e)}")
                sys.exit(1)
    
    total_folder_time = time.time() - start_time
    logger.info(f"✅ Folder setup complete: {created_folders} new folders created (took {total_folder_time:.2f}s)")
                
except FabricApiError as e:
    logger.error(f"❌ Failed to manage folders: {e}")
    sys.exit(1)
except Exception as e:
    logger.error(f"❌ Unexpected error managing folders: {str(e)}")
    sys.exit(1)

##############
# Lakehouses #
##############
# Docs: https://learn.microsoft.com/en-us/rest/api/fabric/lakehouse/items

logger.info("🏠 Setting up lakehouses...")
# Variables
udff_lakehouse_bronze_name = 'maag_bronze'
udff_lakehouse_silver_name = 'maag_silver'
udff_lakehouse_gold_name = 'maag_gold'
udff_lakehouses = {
    udff_lakehouse_bronze_name,
    udff_lakehouse_silver_name,
    udff_lakehouse_gold_name
}
lakehouse_folder_id = fabric_folders.get(fabric_folder_path_lakehouses)
fabric_lakehouses = {}

try:
    logger.info(f"🏠 Setting up lakehouses (Bronze, Silver, Gold)")
    start_time = time.time()
    
    logger.debug("Checking for existing lakehouses in workspace...")
    existing_lakehouses = fabric_client.get_lakehouses(workspace_id)
    
    # Build mapping of existing lakehouses by name
    for lakehouse in existing_lakehouses:
        fabric_lakehouses[lakehouse['displayName']] = lakehouse
    
    logger.info(f"📊 Found {len(existing_lakehouses)} existing lakehouse(s)")

    # Create UDFF lakehouses
    created_lakehouses = 0
    for lakehouse_name in udff_lakehouses:
        if lakehouse_name in fabric_lakehouses:
            logger.info(f"  🏠 Lakehouse '{lakehouse_name}' already exists")
        else:
            logger.info(f"  🏗️ Creating lakehouse '{lakehouse_name}'...")
            try:
                lakehouse_start_time = time.time()
                lakehouse = fabric_client.create_lakehouse(
                    workspace_id=workspace_id,
                    display_name=lakehouse_name,
                    description=f"UDFF {lakehouse_name.split('_')[-1].title()} layer lakehouse for data processing",
                    folder_id=lakehouse_folder_id,
                    enable_schemas=True,
                    wait_for_lro=True
                )
                lakehouse_creation_time = time.time() - lakehouse_start_time
                
                logger.info(f"  ✅ Lakehouse '{lakehouse_name}' created successfully (took {lakehouse_creation_time:.2f}s)")
                fabric_lakehouses[lakehouse_name] = fabric_client.get_lakehouse(workspace_id=workspace_id, lakehouse_id=lakehouse['id'])
                created_lakehouses += 1
                
            except FabricApiError as e:
                logger.error(f"❌ Failed to create lakehouse '{lakehouse_name}': {e}")
                logger.error("Solution: Check workspace permissions and quotas")
                sys.exit(1)
            except Exception as e:
                logger.error(f"❌ Unexpected error creating lakehouse '{lakehouse_name}': {str(e)}")
                logger.error("Solution: Verify workspace configuration and try again")
                sys.exit(1)
    
    total_lakehouse_time = time.time() - start_time
    logger.info(f"✅ Lakehouse setup complete: {created_lakehouses} new lakehouses created (took {total_lakehouse_time:.2f}s)")

except FabricApiError as e:
    logger.error(f"❌ Failed to manage lakehouses: {e}")
    sys.exit(1)
except Exception as e:
    logger.error(f"❌ Unexpected error managing lakehouses: {str(e)}")
    sys.exit(1)

#######################
# Lakehouse CSV files #
#######################
# Docs: https://learn.microsoft.com/en-us/fabric/onelake/onelake-access-python

logger.info("📊 Setting up sample data...")
# Prepare variables
samples_local_folder_path = os.path.join(repo_root, 'infra', 'data')
bronze_lakehouse = fabric_lakehouses[udff_lakehouse_bronze_name]
bronze_lakehouse_onelake_root_path = f"{bronze_lakehouse['displayName']}.Lakehouse/Files"

# Get all CSV files in 'infra/data/samples_fabric'
csv_pattern = os.path.join(samples_local_folder_path, '**', '*.csv')
csv_file_paths = glob.glob(csv_pattern, recursive=True)

# Connect to bronze lakehouse using the new API client
try:
    logger.info(f"📊 Uploading sample data to bronze lakehouse")
    start_time = time.time()
    
    logger.debug(f"Scanning for CSV files in: {samples_local_folder_path}")
    logger.info(f"Found {len(csv_file_paths)} CSV files to upload")
    
    udff_wfs_client = fabric_client.get_workspace_file_system_client(workspace_name)
    logger.debug("Connected to OneLake file system")
except Exception as e:
    logger.error(f"❌ Failed to connect to OneLake: {str(e)}")
    logger.error("Solution: Ensure you have proper permissions and the workspace is accessible")
    sys.exit(1)

# Create folder structure for CSV files
created_folders = set()
uploaded_files = 0

for local_file_path in csv_file_paths:
    # Get relative path from samples folder
    relative_file_path = os.path.relpath(local_file_path, samples_local_folder_path)
    bronze_datalake_file_path = os.path.join(bronze_lakehouse_onelake_root_path, relative_file_path)
    relative_folder_path = os.path.dirname(relative_file_path)
    
    # Create folders in lakehouse
    if relative_folder_path and relative_folder_path != '.' and relative_folder_path not in created_folders:
        try:
            logger.debug(f"Creating directory structure: {relative_folder_path}")
            create_lakehouse_directory_structure(udff_wfs_client, bronze_lakehouse_onelake_root_path, relative_folder_path)
            created_folders.add(relative_folder_path)
        except Exception as e:
            logger.error(f"❌ Failed to create folder structure '{relative_folder_path}': {str(e)}")
            sys.exit(1)

    # Upload file
    file_name = os.path.basename(local_file_path)
    try:
        file_start_time = time.time()
        bronze_datalake_file_client = udff_wfs_client.get_file_client(bronze_datalake_file_path)
        with open(local_file_path, "rb") as data:
            bronze_datalake_file_client.upload_data(data, overwrite=True)
        file_upload_time = time.time() - file_start_time
        logger.info(f"  ✅ Uploaded '{file_name}' to '{relative_file_path}' (took {file_upload_time:.2f}s)")
        uploaded_files += 1
    except Exception as e:
        logger.error(f"❌ Failed to upload file '{file_name}': {str(e)}")
        sys.exit(1)

total_upload_time = time.time() - start_time
logger.info(f"✅ Sample data upload complete: {uploaded_files} files uploaded (took {total_upload_time:.2f}s)")

#############
# Notebooks #
#############
# Docs: https://learn.microsoft.com/en-us/rest/api/fabric/notebook/items

logger.info("📓 Setting up notebooks...")
#Prepare variables
fabric_notebooks = {}
notebooks_directory = os.path.join(repo_root, 'src', 'fabric', 'notebooks')

#Item structure: {local notebook path: [source lakehouse name, destination lakehouse name, fabric folder path]}
udff_notebooks_path_lakehouse_folder = {
    # src\fabric\notebooks
    os.path.join(notebooks_directory, 'run_bronze_to_silver.ipynb'): [None, udff_lakehouse_silver_name, fabric_folder_path_notebooks],
    os.path.join(notebooks_directory, 'run_silver_to_gold.ipynb'): [None, udff_lakehouse_gold_name, fabric_folder_path_notebooks],

    # src\fabric\notebooks\bronze_to_silver notebooks
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_finance_account.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_finance_invoice.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_finance_payment.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_salesadb_order.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_salesadb_orderLine.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_salesadb_orderPayment.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_salesfabric_order.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_salesfabric_orderLine.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_salesfabric_orderPayment.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_shared_customer.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_shared_customeraccount.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_shared_customerRelationshipType.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_shared_customerTradeName.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_shared_location.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_shared_product.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    os.path.join(notebooks_directory, 'bronze_to_silver', 'bronze_to_silver_shared_productCategory.ipynb'): [udff_lakehouse_bronze_name, udff_lakehouse_silver_name, fabric_folder_path_notebooks_bronze_to_silver],
    
    # src\fabric\notebooks\data_management notebooks
    os.path.join(notebooks_directory, 'data_management', 'drop_all_tables_gold.ipynb'): [None, udff_lakehouse_gold_name, fabric_folder_path_notebooks_data_management],
    os.path.join(notebooks_directory, 'data_management', 'drop_all_tables_silver.ipynb'): [None, udff_lakehouse_silver_name, fabric_folder_path_notebooks_data_management],
    os.path.join(notebooks_directory, 'data_management', 'trouble_shooting.ipynb'): [None, None, fabric_folder_path_notebooks_data_management],
    os.path.join(notebooks_directory, 'data_management', 'truncate_all_tables_gold.ipynb'): [None, udff_lakehouse_gold_name, fabric_folder_path_notebooks_data_management],
    os.path.join(notebooks_directory, 'data_management', 'truncate_all_tables_silver.ipynb'): [None, udff_lakehouse_silver_name, fabric_folder_path_notebooks_data_management],

    # src\fabric\notebooks\schema notebooks
    os.path.join(notebooks_directory, 'schema', 'model_finance_gold.ipynb'): [None, udff_lakehouse_gold_name, fabric_folder_path_notebooks_schema],
    os.path.join(notebooks_directory, 'schema', 'model_salesadb_gold.ipynb'): [None, udff_lakehouse_gold_name, fabric_folder_path_notebooks_schema],
    os.path.join(notebooks_directory, 'schema', 'model_salesfabric_gold.ipynb'): [None, udff_lakehouse_gold_name, fabric_folder_path_notebooks_schema],
    os.path.join(notebooks_directory, 'schema', 'model_shared_gold.ipynb'): [None, udff_lakehouse_gold_name, fabric_folder_path_notebooks_schema],
    os.path.join(notebooks_directory, 'schema', 'model_finance_silver.ipynb'): [None, udff_lakehouse_silver_name, fabric_folder_path_notebooks_schema],
    os.path.join(notebooks_directory, 'schema', 'model_salesadb_silver.ipynb'): [None, udff_lakehouse_silver_name, fabric_folder_path_notebooks_schema],
    os.path.join(notebooks_directory, 'schema', 'model_salesfabric_silver.ipynb'): [None, udff_lakehouse_silver_name, fabric_folder_path_notebooks_schema],
    os.path.join(notebooks_directory, 'schema', 'model_shared_silver.ipynb'): [None, udff_lakehouse_silver_name, fabric_folder_path_notebooks_schema],
    
    # src\fabric\notebooks\silver_to_gold notebooks
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_finance_account.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_finance_invoice.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_finance_payment.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_sales_order_line.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_sales_order_payment.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_sales_order.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_salesadb_order.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_salesadb_orderLine.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_salesadb_orderPayment.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_salesfabric_order.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_salesfabric_orderLine.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_salesfabric_orderPayment.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_shared_customer.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_shared_customeraccount.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_shared_customerRelationshipType.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_shared_customerTradeName.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_shared_location.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_shared_product.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold],
    os.path.join(notebooks_directory, 'silver_to_gold', 'silver_to_gold_shared_productCategory.ipynb'): [udff_lakehouse_silver_name, udff_lakehouse_gold_name, fabric_folder_path_notebooks_silver_to_gold]
}

# Obtain existing notebooks
logger.info(f"📓 Deploying notebooks to workspace")

# Prepare notebook specifications for batch upload
notebook_specs = []
for notebook_path, (source_lakehouse_name, targeted_lakehouse_name, folder_path) in udff_notebooks_path_lakehouse_folder.items():
    notebook_specs.append({
        'path': notebook_path,
        'source_lakehouse': source_lakehouse_name,
        'target_lakehouse': targeted_lakehouse_name,
        'folder_path': folder_path
    })

# Deploy notebooks using optimized batch processing
try:
    logger.info(f"Found {len(notebook_specs)} notebooks to deploy")
    start_time = time.time()
    
    # Get existing notebooks
    try:
        existing_notebooks = fabric_client.get_notebooks(workspace_id)
        logger.debug(f"Found {len(existing_notebooks)} existing notebooks")
    except Exception as e:
        logger.error(f"❌ Failed to get existing notebooks: {str(e)}")
        logger.error("Solution: Check workspace permissions and connectivity")
        sys.exit(1)
    
    fabric_notebooks = {}
    upload_jobs = []
    
    for i, spec in enumerate(notebook_specs, 1):
        notebook_path = spec['path']
        source_lakehouse_name = spec.get('source_lakehouse')
        target_lakehouse_name = spec.get('target_lakehouse')
        folder_path = spec['folder_path']
        
        notebook_name = os.path.basename(notebook_path).replace('.ipynb', '')
        logger.info(f"  📓 Processing notebook {i}/{len(notebook_specs)}: '{notebook_name}'")
        
        folder_id = fabric_folders.get(folder_path)
        
        if not folder_id:
            logger.error(f"❌ Folder not found for path '{folder_path}', cannot deploy '{notebook_name}'")
            logger.error("Solution: Ensure folder structure was created successfully")
            sys.exit(1)
        
        # Get lakehouse objects
        target_lakehouse = fabric_lakehouses.get(target_lakehouse_name) if target_lakehouse_name else None
        source_lakehouse = fabric_lakehouses.get(source_lakehouse_name) if source_lakehouse_name else None
        existing_notebook_id = existing_notebooks.get(notebook_name)
        
        try:
            notebook_start_time = time.time()
            # Read and transform notebook content
            with open(notebook_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            logger.debug(f"Read notebook content: {len(content)} characters")
            
            # Transform notebook content by replacing UDFF-specific placeholders
            # Replace workspace placeholders
            pattern = r'WORKSPACE_NAME\s*=\s*\\"([^\\"]+)\\"'
            content = re.sub(pattern, f'WORKSPACE_ID = \\"{workspace_id}\\"', content)
            content = content.replace('{WORKSPACE_NAME}', '{WORKSPACE_ID}')
            
            # Replace lakehouse placeholders
            if source_lakehouse:
                pattern = r'SOURCE_LAKEHOUSE_NAME\s*=\s*\\"([^\\"]+)\\"'
                content = re.sub(pattern, f'SOURCE_LAKEHOUSE_ID = \\"{source_lakehouse["id"]}\\"', content)
                content = content.replace('{SOURCE_LAKEHOUSE_NAME}', '{SOURCE_LAKEHOUSE_ID}')
            
            # Fix ABFSS paths for UDFF project structure
            content = content.replace(
                'abfss://{WORKSPACE_ID}@onelake.dfs.fabric.microsoft.com/{SOURCE_LAKEHOUSE_ID}.Lakehouse/',
                'abfss://{WORKSPACE_ID}@onelake.dfs.fabric.microsoft.com/{SOURCE_LAKEHOUSE_ID}/'
            )
            
            notebook_json = json.loads(content)
            
            # Update notebook metadata with UDFF lakehouse configuration
            if target_lakehouse:
                # Ensure metadata structure exists
                if 'metadata' not in notebook_json:
                    notebook_json['metadata'] = {}
                
                if 'dependencies' not in notebook_json['metadata']:
                    notebook_json['metadata']['dependencies'] = {}
                
                # Set lakehouse configuration
                notebook_json['metadata']['dependencies']['lakehouse'] = {
                    'default_lakehouse': target_lakehouse['id'],
                    'default_lakehouse_name': target_lakehouse['displayName'],
                    'default_lakehouse_workspace_id': target_lakehouse['workspaceId']
                }
            
            # Prepare API data
            notebook_base64 = base64.b64encode(json.dumps(notebook_json).encode('utf-8'))
            notebook_data = {
                "displayName": os.path.basename(notebook_path).replace('.ipynb', ''),
                "definition": {
                    "format": "ipynb",
                    "parts": [{
                        "path": "notebook-content.ipynb",
                        "payload": notebook_base64.decode('utf-8'),
                        "payloadType": "InlineBase64"
                    }]
                },
                "folderId": folder_id
            }
            
            # Upload or update
            if existing_notebook_id:
                logger.info(f"    ✅ Updating notebook '{notebook_name}'")
                response = fabric_client.update_notebook(workspace_id, existing_notebook_id, notebook_data, wait_for_lro=False)
            else:
                logger.info(f"    ✅ Creating notebook '{notebook_name}'")
                response = fabric_client.create_notebook(workspace_id, notebook_data, wait_for_lro=False)
            
            notebook_process_time = time.time() - notebook_start_time
            logger.debug(f"Notebook processing took {notebook_process_time:.2f}s")
            
            if response.status_code == 202:
                # Track LRO for batch monitoring
                job_monitoring_url = response.headers.get('Location')
                if job_monitoring_url:
                    upload_jobs.append({
                        'notebook_name': notebook_name,
                        'job_url': job_monitoring_url,
                        'start_time': time.time()
                    })
            elif response.ok:
                fabric_notebooks[notebook_name] = response.json().get('id', 'unknown')
            else:
                logger.error(f"❌ ERROR: Failed to upload '{notebook_name}': {response.text}")
                sys.exit(1)
                
        except Exception as e:
            logger.error(f"❌ Error uploading '{notebook_name}': {str(e)}")
            logger.error("Solution: Check notebook file integrity and workspace permissions")
            sys.exit(1)
    
    # Check jobs completion
    if upload_jobs:
        logger.info(f"  ⏳ Waiting for {len(upload_jobs)} notebook upload jobs...")
        job_start_time = time.time()
        
        pending_jobs = upload_jobs.copy()
        start_time = time.time()
        max_wait_time = 600
        check_interval = 5
        
        while pending_jobs and (time.time() - start_time) < max_wait_time:
            
            jobs_to_remove = []
            for job in pending_jobs:
                try:
                    # Use the full job URL directly with proper headers
                    response = requests.get(job['job_url'], headers=fabric_client.get_headers())
                    
                    if response.ok:
                        job_result = response.json()
                        notebook_id = job_result.get('id', 'unknown')
                        fabric_notebooks[job['notebook_name']] = notebook_id
                        
                        logger.info(f"    ✅ '{job['notebook_name']}' completed")
                        jobs_to_remove.append(job)
                        
                except Exception as e:
                    # Critical errors during job monitoring should fail the deployment
                    if time.time() - job['start_time'] > max_wait_time:
                        logger.error(f"❌ ERROR: Upload job for '{job['notebook_name']}' failed: {str(e)}")
                        logger.error("Solution: Check workspace performance and retry deployment")
                        sys.exit(1)
                    else:
                        logger.warning(f"    ⚠️ Monitoring error for '{job['notebook_name']}': {str(e)}")
                        jobs_to_remove.append(job)
            
            for job in jobs_to_remove:
                pending_jobs.remove(job)

            if pending_jobs:
                time.sleep(check_interval)
                
    # Refresh notebooks list
    try:
        final_notebooks = fabric_client.get_notebooks(workspace_id)
        fabric_notebooks.update(final_notebooks)
    except Exception as e:
        logger.error(f"❌ ERROR: Failed to refresh notebooks list: {str(e)}")
        logger.error("Solution: Check workspace connectivity and permissions")
        sys.exit(1)
    
    uploaded_count = len([spec for spec in notebook_specs if os.path.basename(spec['path']).replace('.ipynb', '') in fabric_notebooks])
    total_notebook_time = time.time() - start_time
    logger.info(f"✅ Successfully deployed {uploaded_count}/{len(notebook_specs)} notebooks (took {total_notebook_time:.2f}s)")
    
except Exception as e:
    logger.error(f"❌ Failed to deploy notebooks: {str(e)}")
    sys.exit(1)

#################
# Notebook Jobs #
#################
# Docs: https://learn.microsoft.com/en-us/rest/api/fabric/core/job-scheduler

logger.info("🚀 Executing data transformation pipelines...")

# Prepare variables
notebooks_to_run = [
    'run_bronze_to_silver',
    'run_silver_to_gold'
]

execution_results = {}
successful_executions = []
failed_executions = []

pipeline_start_time = time.time()
logger.info(f"🚀 Executing data transformation pipelines sequentially")
logger.info(f"Pipelines to execute: {', '.join(notebooks_to_run)}")

# Execute notebooks one by one in sequence
for i, notebook_name in enumerate(notebooks_to_run, 1):
    logger.info(f"📓 Executing pipeline {i}/{len(notebooks_to_run)}: '{notebook_name}'")
    
    # Check if notebook exists
    if notebook_name not in fabric_notebooks:
        logger.error(f"  ❌ Notebook '{notebook_name}' not found")
        execution_results[notebook_name] = {'status': 'NotFound', 'error': 'Notebook not found'}
        failed_executions.append(notebook_name)
        continue
    
    notebook_id = fabric_notebooks[notebook_name]
    logger.debug(f"Notebook ID: {notebook_id}")
    
    try:
        execution_start_time = time.time()
        result = fabric_client.schedule_notebook_job(workspace_id, notebook_id)
        execution_time = time.time() - execution_start_time
        execution_results[notebook_name] = result
        
        # Track success/failure
        if result.get('status') == 'Completed':
            successful_executions.append(notebook_name)
            logger.info(f"  ✅ '{notebook_name}' completed successfully (took {execution_time:.2f}s)")
        else:
            failed_executions.append(notebook_name)
            logger.error(f"  ❌ '{notebook_name}' failed with status: {result.get('status')}")
            
    except Exception as e:
        execution_time = time.time() - execution_start_time
        error_msg = f"Exception: {str(e)}"
        execution_results[notebook_name] = {'status': 'Failed', 'error': error_msg}
        failed_executions.append(notebook_name)
        logger.error(f"  ❌ Error executing '{notebook_name}' (took {execution_time:.2f}s): {error_msg}")
    
    # Add delay between notebook executions (except for last one)
    if notebook_name != notebooks_to_run[-1]:
        logger.info(f"    📋 Completed '{notebook_name}', proceeding to next notebook...")

total_pipeline_time = time.time() - pipeline_start_time

# Final results summary
logger.info(f"\n📊 Execution Summary (took {total_pipeline_time:.2f}s total):")
for notebook_name, result in execution_results.items():
    if result.get('status') == 'Completed':
        duration = result.get('duration', 'unknown')
        logger.info(f"  ✅ '{notebook_name}' completed in {duration}")
    else:
        error = result.get('error', 'Unknown error')
        logger.error(f"  ❌ '{notebook_name}' failed: {result.get('status', 'Unknown')} - {error}")

# Exit with error if any notebooks failed
if failed_executions:
    logger.error(f"\n❌ {len(failed_executions)} notebook(s) failed to execute successfully")
    logger.error(f"Failed notebooks: {', '.join(failed_executions)}")
    sys.exit(1)
else:
    logger.info(f"✅ All {len(successful_executions)} pipelines executed successfully in sequence")

###################
# PowerBI Reports #
###################
# Docs: https://learn.microsoft.com/en-us/rest/api/power-bi/imports

logger.info("📊 Setting up Power BI reports...")
try:
    powerbi_start_time = time.time()
    powerbi_client = create_powerbi_client()
    powerbi_client.set_powerbi_auth_token()
    powerbi_auth_time = time.time() - powerbi_start_time
    logger.info(f"✅ Power BI client authenticated successfully (took {powerbi_auth_time:.2f}s)")
except Exception as e:
    logger.error(f"❌ Failed to authenticate Power BI client")
    logger.error(f"Details: {str(e)}")
    logger.error("Solution: Ensure you have proper Power BI permissions and are logged in")
    sys.exit(1)

reports_local_folder_path = os.path.join(repo_root, 'reports')
pbix_pattern = os.path.join(reports_local_folder_path, '**', '*.pbix')
pbix_file_paths = glob.glob(pbix_pattern, recursive=True)
deployed_reports = []  # Track deployed reports for final summary

if not pbix_file_paths:
    logger.info("  ℹ️ No Power BI report files (.pbix) found in reports directory")
else:
    logger.info(f"  📋 Found {len(pbix_file_paths)} Power BI report(s) to deploy")

for i, pbix_file_path in enumerate(pbix_file_paths, 1):
    report_file_name = os.path.basename(pbix_file_path)
    report_name = report_file_name.replace('.pbix','')
    logger.info(f"  📊 Deploying report {i}/{len(pbix_file_paths)}: '{report_name}'")
    
    try:
        report_start_time = time.time()
        new_report = powerbi_client.new_report(
            report_name=report_name,
            file_path=pbix_file_path,
            conflict_action=ImportConflictHandlerMode.CREATE_OR_OVERWRITE,
            workspace_id=workspace_id,
            subfolder_object_id=fabric_folders[fabric_folder_path_reports],
            timeout=300
        )
        report_deploy_time = time.time() - report_start_time
        
        report_name = new_report.get('name', 'Unknown')
        report_id = new_report.get('id', 'Unknown')
        deployed_reports.append({'name': report_name, 'id': report_id})
        logger.info(f"  ✅ Successfully deployed report '{report_name}' (ID: {report_id}, took {report_deploy_time:.2f}s)")
        
        # Get connection details from Gold lakehouse and configure dataset parameters
        logger.info(f"  🔧 Configuring dataset parameters for '{report_name}'...")
        config_start_time = time.time()
        dataset = powerbi_client.get_powerbi_dataset(workspace_id=workspace_id, dataset_name=report_name)
        
        try:
            gold_lakehouse = fabric_client.get_lakehouse(workspace_id=workspace_id, lakehouse_id=fabric_lakehouses[udff_lakehouse_gold_name]['id'])
            sql_endpoint_provisioning_status = gold_lakehouse['properties']['sqlEndpointProperties']['provisioningStatus']
            logger.info(f"    📋 SQL endpoint status: {sql_endpoint_provisioning_status}")
            
            if sql_endpoint_provisioning_status == 'Success':
                sql_endpoint = gold_lakehouse['properties']['sqlEndpointProperties']['connectionString']
                database_name = udff_lakehouse_gold_name
                
                logger.debug(f"SQL Endpoint: {sql_endpoint}")
                logger.debug(f"Database: {database_name}")
                
                powerbi_client.update_powerbi_dataset_parameters(dataset_id=dataset['id'], parameters=[
                    {"name": "sqlEndpoint", "newValue": sql_endpoint},
                    {"name": "database", "newValue": database_name}
                ])
                config_time = time.time() - config_start_time
                logger.info(f"  ✅ Dataset parameters updated successfully for '{report_name}' (took {config_time:.2f}s)")
            else:
                logger.error(f"  ❌ SQL endpoint not ready (status: {sql_endpoint_provisioning_status})")
                logger.error("Manual intervention required: Wait for SQL endpoint provisioning to complete and re-run script")
                sys.exit(1)
                
        except Exception as e:
            logger.error(f"❌ Failed to configure dataset parameters for '{report_name}': {str(e)}")
            logger.error("Solution: Check lakehouse availability and Power BI permissions")
            sys.exit(1)
    except Exception as e:
        logger.error(f"❌ Failed to deploy report '{report_name}': {str(e)}")
        logger.error("Solution: Verify the .pbix file is valid and you have upload permissions")
        sys.exit(1)


##################
# End of program #
##################

total_deployment_time = time.time() - datetime.now().timestamp()
logger.info("=" * 60)
logger.info(f"🎉 {solution_name} deployment completed successfully!")
logger.info(f"Deployment completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
logger.info(f"✅ Workspace: {workspace_name}")
logger.info(f"✅ Lakehouses: {len(udff_lakehouses)} created (Bronze, Silver, Gold)")
logger.info(f"✅ Notebooks: {uploaded_count}/{len(notebook_specs)} deployed with batch processing")
logger.info(f"✅ Sample data: {len(csv_file_paths)} files uploaded")
logger.info(f"✅ Pipelines: {len(successful_executions)} executed successfully with optimized monitoring")
logger.info(f"✅ Power BI Reports: {len(deployed_reports)} deployed")
if deployed_reports:
    for report in deployed_reports:
        logger.info(f"   📊 {report['name']} (ID: {report['id']})")
logger.info("=" * 60)
logger.info(f"📊 Deployment completed in {total_deployment_time:.2f} seconds")
