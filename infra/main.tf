terraform {
  required_version = ">= 1.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}

# ---------------------------------------------------------------------------
# NSG per subnet — one NSG module call per subnet entry
# ---------------------------------------------------------------------------
module "nsg" {
  for_each = var.subnets

  source              = "./modules/nsg"
  name                = "nsg-${var.environment}-${each.key}"
  resource_group_name = var.resource_group_name
  location            = var.location
  security_rules      = each.value.security_rules

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Virtual Network
# ---------------------------------------------------------------------------
module "vnet" {
  source              = "./modules/vnet"
  name                = "vnet-${var.environment}-networking"
  resource_group_name = var.resource_group_name
  location            = var.location
  address_space       = var.address_space

  subnets = {
    for name, config in var.subnets : name => {
      address_prefix = config.address_prefix
      nsg_id         = module.nsg[name].id
    }
  }

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------
locals {
  tags = {
    environment  = var.environment
    managed-by   = "azure-devops"
    repo         = "gh-ado-networking"
  }
}