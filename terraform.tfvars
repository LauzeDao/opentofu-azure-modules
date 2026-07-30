subscription_id       = "00000000-0000-0000-0000-000000000000"
tenant_id             = "00000000-0000-0000-0000-000000000000"
deployer_principal_id = "00000000-0000-0000-0000-000000000000"

project     = "demo"
environment = "dev"
location    = "germanywestcentral"

vnet_address_space = "10.42.0.0/16"

kubernetes_version  = null
sku_tier            = "Free"
system_node_vm_size = "Standard_B2s"
user_node_vm_size   = "Standard_B2s"

enable_user_node_pool = true
user_node_count       = 1

admin_group_object_ids          = []
api_server_authorized_ip_ranges = []

acr_sku = "Basic"

key_vault_purge_protection_enabled = false
grant_kubelet_key_vault_access     = true

tags = {}
