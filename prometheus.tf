resource "random_uuid" "prometheus_machine_id" {
}

data "template_cloudinit_config" "prometheus_config" {
  gzip          = false # does not work with NoCloud ds?!?
  base64_encode = false # does not work with NoCloud ds?!?

  part {
    content_type = "text/cloud-config"
    content      = <<EOT
#cloud-config

preserve_hostname: false
hostname: ${local.prometheus_server.name}
fqdn: ${local.prometheus_server.fqdn}
prefer_fqdn_over_hostname: true

ssh_pwauth: True
chpasswd:
  expire: false
  users:
    - name: ubuntu
      password: ubuntu
      type: text  

ssh_authorized_keys:
  - "${local.prometheus_server.ssh_key}"  

ca_certs:
  trusted:
    - |
      ${indent(6, tls_self_signed_cert.ca_cert.cert_pem)}
EOT
  }
}

resource "libvirt_cloudinit_disk" "prometheus_cloudinit" {

  name           = local.prometheus_server.cloudinit
  meta_data      = templatefile("${path.module}/cloud-init/meta_data.cfg.tpl", { machine_id = random_uuid.prometheus_machine_id.result, hostname = local.prometheus_server.name })
  user_data      = data.template_cloudinit_config.prometheus_config.rendered
  network_config = templatefile("${path.module}/cloud-init/network_config.cfg.tpl", {})
  pool           = libvirt_pool.monitoring.name
}

resource "libvirt_domain" "prometheus_instance" {

  autostart = false
  name      = local.prometheus_server.name
  memory    = "2048"
  vcpu      = 1
  machine   = "q35"
  xml { # para a q35 o cdrom necessita de ser sata
    xslt = file("lib-virt/q35-cdrom-model.xslt")
  }
  qemu_agent = true

  cpu {
    mode = "host-passthrough"
  }

  firmware  = "${local.uefi_location_files}/OVMF_CODE.fd"
  cloudinit = libvirt_cloudinit_disk.prometheus_cloudinit.id

  network_interface {
    network_id     = libvirt_network.observability_network.id
    hostname       = local.prometheus_server.name
    addresses      = [local.prometheus_server.ip]
    wait_for_lease = true
  }


  disk {
    volume_id = libvirt_volume.prometheus.id
  }

  graphics {
    type = "spice"
  }

  depends_on = [
    libvirt_cloudinit_disk.prometheus_cloudinit
  ]

  # lifecycle {
  #   create_before_destroy = true
  # }
}


