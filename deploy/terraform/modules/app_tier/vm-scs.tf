# Create SCS NICs
resource "azurerm_network_interface" "scs" {
  count                         = local.enable_deployment ? (local.scs_high_availability ? 2 : 1) : 0
  name                          = "${upper(local.application_sid)}_scs${format("%02d", count.index)}-nic"
  location                      = var.resource-group[0].location
  resource_group_name           = var.resource-group[0].name
  enable_accelerated_networking = local.scs_sizing.compute.accelerated_networking

  ip_configuration {
    name                          = "IPConfig1"
    subnet_id                     = var.infrastructure.vnets.sap.subnet_app.is_existing ? data.azurerm_subnet.subnet-sap-app[0].id : azurerm_subnet.subnet-sap-app[0].id
    private_ip_address            = cidrhost(var.infrastructure.vnets.sap.subnet_app.prefix, tonumber(count.index) + local.ip_offsets.scs_vm)
    private_ip_address_allocation = "static"
  }
}

# Associate SCS VM NICs with the Load Balancer Backend Address Pool
resource "azurerm_network_interface_backend_address_pool_association" "scs" {
  count                   = local.enable_deployment ? length(azurerm_network_interface.scs) : 0
  network_interface_id    = azurerm_network_interface.scs[count.index].id
  ip_configuration_name   = azurerm_network_interface.scs[count.index].ip_configuration[0].name
  backend_address_pool_id = azurerm_lb_backend_address_pool.scs[0].id
}


# Create the SCS VM(s)
resource "azurerm_linux_virtual_machine" "scs" {
  count                        = local.enable_deployment ? (local.scs_high_availability ? 2 : 1) : 0
  name                         = "${upper(local.application_sid)}_scs${format("%02d", count.index)}"
  computer_name                = "${lower(local.application_sid)}scs${format("%02d", count.index)}"
  location                     = var.resource-group[0].location
  resource_group_name          = var.resource-group[0].name
  availability_set_id          = azurerm_availability_set.scs[0].id
  proximity_placement_group_id = lookup(var.infrastructure, "ppg", false) != false ? (var.ppg[0].id) : null
  network_interface_ids = [
    azurerm_network_interface.scs[count.index].id
  ]
  size                            = local.scs_sizing.compute.vm_size
  admin_username                  = local.authentication.username
  disable_password_authentication = true

  os_disk {
    name                 = "${upper(local.application_sid)}_scs${format("%02d", count.index)}-osDisk"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = local.os.publisher
    offer     = local.os.offer
    sku       = local.os.sku
    version   = local.os.version
  }

  admin_ssh_key {
    username   = local.authentication.username
    public_key = file(var.sshkey.path_to_public_key)
  }

  boot_diagnostics {
    storage_account_uri = var.storage-bootdiag.primary_blob_endpoint
  }
}

# Creates managed data disk
resource "azurerm_managed_disk" "scs" {
  count                = local.enable_deployment ? length(local.scs-data-disks) : 0
  name                 = local.scs-data-disks[count.index].name
  location             = var.resource-group[0].location
  resource_group_name  = var.resource-group[0].name
  create_option        = "Empty"
  storage_account_type = local.scs-data-disks[count.index].disk_type
  disk_size_gb         = local.scs-data-disks[count.index].size_gb
}

resource "azurerm_virtual_machine_data_disk_attachment" "scs" {
  count                     = local.enable_deployment ? length(azurerm_managed_disk.scs) : 0
  managed_disk_id           = azurerm_managed_disk.scs[count.index].id
  virtual_machine_id        = azurerm_linux_virtual_machine.scs[local.scs-data-disks[count.index].vm_index].id
  caching                   = local.scs-data-disks[count.index].caching
  write_accelerator_enabled = local.scs-data-disks[count.index].write_accelerator
  lun                       = count.index
}
