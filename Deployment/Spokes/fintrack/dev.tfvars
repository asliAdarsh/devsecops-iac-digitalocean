# Target region and tenancy tracking environment flags
region      = "sgp1"
environment = "Development"
app_name    = "fintrack"

# State data backend target lookup config
state_bucket_name = "fintrack-tfstate-bucket"

# Compute Tier Parameters (Passed straight to Modules/droplet)
droplet_size   = "s-1vcpu-1gb"
instance_count = 1

# Data Tier Parameters (Passed straight to Modules/mongo_db)
db_size_slug     = "db-s-1vcpu-1gb"
db_node_count    = 1
initial_database = "fintrack_dev_store"