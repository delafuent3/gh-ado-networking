environment         = "test"
location            = "australiaeast"
resource_group_name = "rg-networking-test"
address_space       = ["10.20.0.0/16"]

subnets = {
  app = {
    address_prefix = "10.20.1.0/24"
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
    ]
  }
  data = {
    address_prefix = "10.20.2.0/24"
    security_rules = [
      {
        name                       = "allow-app-to-data"
        priority                   = 100
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "1433"
        source_address_prefix      = "10.20.1.0/24"
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