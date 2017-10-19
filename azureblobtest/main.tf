resource "azurerm_resource_group" "tf-blob-test-group" {
  name     = "tf-blob-test-group"
  location = "eastus"
}

resource "azurerm_storage_account" "tf-blob-test-account" {
  name                = "tfstorageaccount"
  resource_group_name = "${azurerm_resource_group.tf-blob-test-group.name}"
  location            = "eastus"
  account_type        = "Standard_RAGRS"
}

resource "azurerm_storage_container" "tf-blob-test-container" {
  name                  = "tf-blob-test-container"
  resource_group_name   = "${azurerm_resource_group.tf-blob-test-group.name}"
  storage_account_name  = "${azurerm_storage_account.tf-blob-test-account.name}"
  container_access_type = "blob"
}

resource "azurerm_storage_blob" "tf-blob-test-sb" {
  name = "tf-blob-test-sb"

  resource_group_name    = "${azurerm_resource_group.tf-blob-test-group.name}"
  storage_account_name   = "${azurerm_storage_account.tf-blob-test-account.name}"
  storage_container_name = "${azurerm_storage_container.tf-blob-test-container.name}"
}
