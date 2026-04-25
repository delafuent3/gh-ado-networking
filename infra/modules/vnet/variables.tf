variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "address_space" {
  type = list(string)
}

variable "subnets" {
  type = map(object({
    address_prefix = string
    nsg_id         = optional(string)
  }))
  default = {}
}

variable "tags" {
  type    = map(string)
  default = {}
}