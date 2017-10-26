# Create a resource group
resource "azurerm_resource_group" "tf-test-group" {
  name     = "tf-test-group"
  location = "East US"

  tags {
    environment = "tf-test"
  }
}

# Create a virtual network in the web_servers resource group
resource "azurerm_virtual_network" "tf-test-vnet" {
  name                = "tf-test-vnet"
  address_space       = ["10.0.0.0/20"]
  location            = "East US"
  resource_group_name = "${azurerm_resource_group.tf-test-group.name}"

  tags {
    environment = "tf-test"
  }
}

# Create a subnet for public use
resource "azurerm_subnet" "tf-test-public-sn" {
  name                 = "tf-test-public-sn"
  resource_group_name  = "${azurerm_resource_group.tf-test-group.name}"
  virtual_network_name = "${azurerm_virtual_network.tf-test-vnet.name}"
  address_prefix       = "10.0.1.0/25"
}

# Create a subnet for private user
resource "azurerm_subnet" "tf-test-private-sn" {
  name                 = "tf-test-private-sn"
  resource_group_name  = "${azurerm_resource_group.tf-test-group.name}"
  virtual_network_name = "${azurerm_virtual_network.tf-test-vnet.name}"
  address_prefix       = "10.0.1.128/25"
}

#create storage account and container for VM
resource "azurerm_storage_account" "tfteststorageaccount" {
  name                     = "tfteststorageaccount"
  resource_group_name      = "${azurerm_resource_group.tf-test-group.name}"
  location                 = "East US"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags {
    environment = "tf-test"
  }

}


resource "azurerm_storage_container" "tf-test-storage-container" {
  name                  = "tf-test-storage-container"
  resource_group_name   = "${azurerm_resource_group.tf-test-group.name}"
  storage_account_name  = "${azurerm_storage_account.tfteststorageaccount.name}"
  container_access_type = "private"
}

# ================ Public IP Addresses ===========================
resource "azurerm_public_ip" "tf-test-bh-pub-ip" {
  name                         = "tf-test-bh-pub-ip"
  location                     = "${azurerm_resource_group.tf-test-group.location}"
  resource_group_name          = "${azurerm_resource_group.tf-test-group.name}"
  public_ip_address_allocation = "static"
}

resource "azurerm_public_ip" "tf-test-lb-pub-ip" {
  name                         = "tf-test-lb-pub-ip"
  location                     = "${azurerm_resource_group.tf-test-group.location}"
  resource_group_name          = "${azurerm_resource_group.tf-test-group.name}"
  public_ip_address_allocation = "static"
}
# =============End Public IP Addresses ===========================



# ================ Network Interfaces ============================
resource "azurerm_network_interface" "tf-test-ni" {
  name                = "tf-test-ni"
  location            = "East US"
  resource_group_name = "${azurerm_resource_group.tf-test-group.name}"
  network_security_group_id = "${azurerm_network_security_group.tf-test-nsg.id}"

  ip_configuration {
    name                          = "tf-test-config1"
    subnet_id                     = "${azurerm_subnet.tf-test-public-sn.id}"
    private_ip_address_allocation = "dynamic"
    public_ip_address_id          = "${azurerm_public_ip.tf-test-bh-pub-ip.id}"
  }

  tags {
    environment = "tf-test"
  }
}
# ============ End Network Interfaces ============================


# ============ Bastion Host VM ===================================
resource "azurerm_virtual_machine" "tf-test-bastion-host" {
  name                  = "tf-test-bastion-host"
  location              = "East US"
  resource_group_name   = "${azurerm_resource_group.tf-test-group.name}"
  network_interface_ids = ["${azurerm_network_interface.tf-test-ni.id}"]
  vm_size               = "Standard_A0"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  delete_data_disks_on_termination = true

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name          = "tf-test-os-disk"
    vhd_uri       = "${azurerm_storage_account.tfteststorageaccount.primary_blob_endpoint}${azurerm_storage_container.tf-test-storage-container.name}/myosdisk1.vhd"
    caching       = "ReadWrite"
    create_option = "FromImage"
  }

  # Optional data disks
  storage_data_disk {
    name          = "tf-test-data-disk"
    vhd_uri       = "${azurerm_storage_account.tfteststorageaccount.primary_blob_endpoint}${azurerm_storage_container.tf-test-storage-container.name}/datadisk0.vhd"
    disk_size_gb  = "1023"
    create_option = "Empty"
    lun           = 0
  }

  os_profile {
    computer_name  = "hostname"
    admin_username = "azure-user"
    admin_password = "Password1234!"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path = "/home/azure-user/.ssh/authorized_keys"
      key_data = "${file("/Users/mil9186/.ssh/azure.pub")}"
    }
  }

  tags {
    environment = "tf-test"
  }
}
# ========= End Bastion Host VM ==================================


# ========= Bastion Host Network Security Group ==================
resource "azurerm_network_security_group" "tf-test-nsg" {
  name                = "tf-test-nsg"
  location            = "${azurerm_resource_group.tf-test-group.location}"
  resource_group_name = "${azurerm_resource_group.tf-test-group.name}"

  security_rule {
    name                       = "OnlyNYPSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "143.104.3.47/32"
    destination_address_prefix = "*"
  }

  tags {
    environment = "tf-test"
    }
}
# ======End Bastion Host Network Security Group ==================

# ========= Public Load Balancer =================================
resource "azurerm_lb" "tf-test-pub-lb" {
  name                = "tf-test-pub-lb"
  location            = "${azurerm_resource_group.tf-test-group.location}"
  resource_group_name = "${azurerm_resource_group.tf-test-group.name}"

  frontend_ip_configuration {
    name                 = "PublicIPAddress"
    public_ip_address_id = "${azurerm_public_ip.tf-test-lb-pub-ip.id}"
  }
  tags {
    environment = "tf-test"
  }
}

resource "azurerm_lb_backend_address_pool" "tf-test-bpepool" {
  resource_group_name = "${azurerm_resource_group.tf-test-group.name}"
  loadbalancer_id     = "${azurerm_lb.tf-test-pub-lb.id}"
  name                = "tf-test-bpepool"
}

resource "azurerm_lb_nat_pool" "tf-test-lbnatpool" {
  count                          = 2
  resource_group_name            = "${azurerm_resource_group.tf-test-group.name}"
  name                           = "ssh"
  loadbalancer_id                = "${azurerm_lb.tf-test-pub-lb.id}"
  protocol                       = "Tcp"
  frontend_port_start            = 80
  frontend_port_end              = 81
  backend_port                   = 80
  frontend_ip_configuration_name = "PublicIPAddress"
}

# resource "azurerm_lb_nat_rule" "tf-test-nat-rule" {
#   resource_group_name            = "${azurerm_resource_group.tf-test-group.name}"
#   loadbalancer_id                = "${azurerm_lb.tf-test-pub-lb.id}"
#   name                           = "HTTP Access"
#   protocol                       = "Tcp"
#   frontend_port                  = 80
#   backend_port                   = 80
#   frontend_ip_configuration_name = "PublicIPAddress"
# }

# ======End Public Load Balancer =================================


# ========= VM Scale Set =========================================
resource "azurerm_virtual_machine_scale_set" "tf-test-vmscaleset" {
  name                = "tf-test-vmscaleset"
  location            = "${azurerm_resource_group.tf-test-group.location}"
  resource_group_name = "${azurerm_resource_group.tf-test-group.name}"
  upgrade_policy_mode = "Manual"

  sku {
    name     = "Standard_A0"
    tier     = "Standard"
    capacity = 2
  }

  os_profile {
    computer_name_prefix = "nginx-"
    admin_username       = "azure-user"
    admin_password       = "Passwword1234"
    custom_data          = "${file("/Users/mil9186/code/terraform/azurereference/cloud-init.txt")}"
  }

  os_profile_linux_config {
    disable_password_authentication = true

    ssh_keys {
      path = "/home/azure-user/.ssh/authorized_keys"
      key_data = "${file("/Users/mil9186/.ssh/azure-vm.pub")}"
    }
  }

  network_profile {
    name    = "tf-test-networkprofile"
    primary = true

    ip_configuration {
      name      = "tf-test-ipconfiguration"
      subnet_id = "${azurerm_subnet.tf-test-private-sn.id}"
      load_balancer_backend_address_pool_ids = ["${azurerm_lb_backend_address_pool.tf-test-bpepool.id}"]
      load_balancer_inbound_nat_rules_ids    = ["${element(azurerm_lb_nat_pool.tf-test-lbnatpool.*.id, count.index)}"]
    }
  }

  storage_profile_os_disk {
    name           = "osDiskProfile"
    caching        = "ReadWrite"
    create_option  = "FromImage"
    vhd_containers = ["${azurerm_storage_account.tfteststorageaccount.primary_blob_endpoint}${azurerm_storage_container.tf-test-storage-container.name}"]
  }

  storage_profile_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }
}
# ========= VM Scale Set =========================================
