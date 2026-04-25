output "vnet_id" {
  description = "Resource ID of the virtual network"
  value       = module.vnet.id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = module.vnet.name
}

output "subnet_ids" {
  description = "Map of subnet name → resource ID"
  value       = module.vnet.subnet_ids
}

output "nsg_ids" {
  description = "Map of subnet name → NSG resource ID"
  value       = { for k, v in module.nsg : k => v.id }
}