# Builds one GARM runner image into the Azure Compute Gallery. runner-base (small and medium runners) starts from
# Ubuntu 24.04; runner-large starts from the runner-base version built in the same run and adds pre-pulled images.
# New versions are published hidden from "latest"; promote.sh boot-tests them and makes them the latest.

packer {
  required_plugins {
    azure = {
      source  = "github.com/hashicorp/azure"
      version = "= 2.6.5"
    }
  }
}

variable "flavor" {
  type        = string
  description = "base or large"
  validation {
    condition     = contains(["base", "large"], var.flavor)
    error_message = "The flavor must be base or large."
  }
}

variable "image_version" {
  type        = string
  description = "Gallery version to publish, such as 1.20261030.1712"
}

variable "base_version" {
  type        = string
  default     = ""
  description = "runner-base version the large image starts from"
}

variable "subscription_id" {
  type = string
}

variable "resource_group" {
  type    = string
  default = "rg-runner-images"
}

variable "gallery" {
  type    = string
  default = "vizmo_runners"
}

variable "vm_size" {
  type    = string
  default = "Standard_F8ams_v6"
}

variable "ghcr_token" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Reads the private ghcr.io/vizmo-vms images the large image pre-pulls"
}

variable "allow_missing_private_images" {
  type        = bool
  default     = false
  description = "Skip private images when ghcr_token is empty (local test builds)"
}

locals {
  is_base = var.flavor == "base"
}

source "azure-arm" "runner" {
  use_azure_cli_auth        = true
  subscription_id           = var.subscription_id
  build_resource_group_name = var.resource_group
  vm_size                   = var.vm_size
  os_type                   = "Linux"
  # The VM disks are bigger (32 and 64 GB); the image only needs room for what it holds.
  os_disk_size_gb = local.is_base ? 30 : 60

  spot {
    eviction_policy = "Delete"
  }

  image_publisher = local.is_base ? "Canonical" : null
  image_offer     = local.is_base ? "ubuntu-24_04-lts" : null
  image_sku       = local.is_base ? "server" : null

  dynamic "shared_image_gallery" {
    for_each = local.is_base ? [] : [var.base_version]
    content {
      subscription   = var.subscription_id
      resource_group = var.resource_group
      gallery_name   = var.gallery
      image_name     = "runner-base"
      image_version  = shared_image_gallery.value
    }
  }

  shared_image_gallery_destination {
    subscription         = var.subscription_id
    resource_group       = var.resource_group
    gallery_name         = var.gallery
    image_name           = "runner-${var.flavor}"
    image_version        = var.image_version
    storage_account_type = "Standard_LRS"
    target_region {
      name = "newzealandnorth"
      # About one replica per 20 VMs created at once; small and medium together peak near 40.
      replicas = local.is_base ? 2 : 1
    }
  }
  shared_gallery_image_version_exclude_from_latest = true

  azure_tags = {
    purpose = "github-runner-image-build"
  }
}

build {
  sources = ["source.azure-arm.runner"]

  provisioner "shell" {
    inline = ["mkdir -p /tmp/runner-image"]
  }

  provisioner "file" {
    sources     = ["${path.root}/scripts", "${path.root}/files", "${path.root}/images-base.txt", "${path.root}/images-large.txt"]
    destination = "/tmp/runner-image/"
  }

  provisioner "shell" {
    environment_vars = [
      "GHCR_TOKEN=${var.ghcr_token}",
      "ALLOW_MISSING_PRIVATE_IMAGES=${var.allow_missing_private_images}",
    ]
    execute_command = "chmod +x {{ .Path }}; sudo -E bash '{{ .Path }}'"
    inline          = ["bash /tmp/runner-image/scripts/build.sh ${var.flavor}"]
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo -E bash '{{ .Path }}'"
    inline = [
      "rm -rf /tmp/runner-image",
      "cloud-init clean --logs --machine-id",
      "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync",
    ]
    skip_clean = true
  }
}
