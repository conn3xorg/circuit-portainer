variable "port" {
  type    = number
  default = 2222
}

# An example password only. Pass your own with -var or TF_VAR_ on a real host.
variable "admin_password" {
  type      = string
  default   = "example-password-not-secret"
  ephemeral = true
  sensitive = true
}

variable "agent_secret" {
  type      = string
  default   = "example-agent-secret-not-secret"
  ephemeral = true
  sensitive = true
}

# Null keeps the circuit's pins. CI sets an older release here first, to
# test an upgrade.
variable "portainer_version" {
  type    = string
  default = null
}

variable "image_digest" {
  type    = string
  default = null
}

variable "agent_image_digest" {
  type    = string
  default = null
}

# The server and an agent on one host, so the check can add the agent as a
# second environment.
module "portainer" {
  source = "../.."

  hosts                = { box = "127.0.0.1" }
  ssh_port             = var.port
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"

  agent              = true
  admin_password     = var.admin_password
  agent_secret       = var.agent_secret
  portainer_version  = var.portainer_version
  image_digest       = var.image_digest
  agent_image_digest = var.agent_image_digest
}

output "url" {
  value = module.portainer.url
}
