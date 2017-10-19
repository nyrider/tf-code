# Create a resource group
resource "azurerm_resource_group" "tf-test-group" {
  name     = "tf-test-group"
  location = "East US"
}

# Create a virtual network in the web_servers resource group
resource "azurerm_virtual_network" "tf-test-vnet" {
  name                = "tf-test-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = "East US"
  resource_group_name = "${azurerm_resource_group.tf-test-group.name}"

}


resource "azurerm_subnet" "tf-public-sn" {
  name                 = "tf-public-sn"
  resource_group_name  = "${azurerm_resource_group.tf-test-group.name}"
  virtual_network_name = "${azurerm_virtual_network.tf-test-vnet.name}"
  address_prefix       = "10.0.1.0/24"
}

resource "azurerm_subnet" "tf-private-sn" {
  name                 = "tf-private-sn"
  resource_group_name  = "${azurerm_resource_group.tf-test-group.name}"
  virtual_network_name = "${azurerm_virtual_network.tf-test-vnet.name}"
  address_prefix       = "10.0.1.0/24"
}


resource "azurerm_network_interface" "tf-test-ni" {
  name                = "tf-test-ni"
  location            = "East US"
  resource_group_name = "${azurerm_resource_group.tf-test-group.name}"

  ip_configuration {
    name                          = "tf-test-configuration"
    subnet_id                     = "${azurerm_subnet.tf-public-sn.id}"
    private_ip_address_allocation = "dynamic"
  }
}
