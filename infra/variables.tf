variable "environment" {
  description = "Deployment environment: dev, test, or prod"
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "Must be dev, test, or prod."
  }
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "australiaeast"
}

variable "resource_group_name" {
  description = "Target resource group (must already exist)"
  type        = string
}

variable "address_space" {
  description = "VNet address space CIDR(s)"
  type        = list(string)
}

variable "subnets" {
  description = "Map of subnets to create. Each entry includes CIDR and NSG rules."
  type = map(object({
    address_prefix = string
    security_rules = list(object({
      name                       = string
      priority                   = number
      direction                  = string # Inbound | Outbound
      access                     = string # Allow | Deny
      protocol                   = string # Tcp | Udp | Icmp | *
      source_port_range          = string
      destination_port_range     = string
      source_address_prefix      = string
      destination_address_prefix = string
    }))
  }))
}