environment         = "dev"
location            = "australiaeast"
resource_group_name = "rg-networking-dev"
address_space       = ["10.10.0.0/16"]

subnets = {
  app = {
    address_prefix = "10.10.1.0/24"
    security_rules = [
      {
        name                       = "allow-https-inbound"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "443"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      },
      {
        name                       = "allow-http-inbound"
        priority                   = 110
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "80"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      },
    ]
  }
  data = {
    address_prefix = "10.10.2.0/24"
    security_rules = [
      {
        name                       = "allow-app-to-data"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "1433"
        source_address_prefix      = "10.10.1.0/24"
        destination_address_prefix = "*"
      },
      {
        name                       = "deny-all-inbound"
        priority                   = 4096
        direction                  = "Inbound"
        access                     = "Deny"
        protocol                   = "*"
        source_port_range          = "*"
        destination_port_range     = "*"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
      },
    ]
  }
}