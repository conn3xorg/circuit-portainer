variable "hosts" {
  type        = any
  description = "Hosts to configure: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file or jump_hosts."
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}

variable "server" {
  type        = bool
  default     = true
  description = "Run the Portainer server, with its web UI, on each host."
}

variable "agent" {
  type        = bool
  default     = false
  description = "Run the Portainer agent on each host, so a Portainer server elsewhere can manage its Podman."

  validation {
    condition     = var.server || var.agent
    error_message = "Set server, agent or both: with neither, there's nothing to run."
  }
}

variable "portainer_version" {
  type        = string
  default     = "2.45.3"
  nullable    = false
  description = "Tag of the portainer/portainer-ce and portainer/agent images, such as \"2.45.3\". Change image_digest and agent_image_digest with it."

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]*$", var.portainer_version))
    error_message = "portainer_version must be an image tag, such as \"2.45.3\"."
  }
}

variable "image_digest" {
  type        = string
  default     = "sha256:3609c307943bca8e5c492f69ddd6965df177208b50678a4cff28391c8dd4e96e"
  nullable    = false
  description = "Digest of docker.io/portainer/portainer-ce for portainer_version. Podman pulls by the digest, so a tag that moves upstream can't change what runs."

  validation {
    condition     = can(regex("^sha256:[a-f0-9]{64}$", var.image_digest))
    error_message = "image_digest must be a sha256 digest, such as \"sha256:\" followed by 64 hex digits."
  }
}

variable "agent_image_digest" {
  type        = string
  default     = "sha256:6e6d2d5d8967da5b4d45eab32b7268af170395395d753d3f34ecb4d6ca5bd388"
  nullable    = false
  description = "Digest of docker.io/portainer/agent for portainer_version."

  validation {
    condition     = can(regex("^sha256:[a-f0-9]{64}$", var.agent_image_digest))
    error_message = "agent_image_digest must be a sha256 digest, such as \"sha256:\" followed by 64 hex digits."
  }
}

variable "admin_password" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "Password Portainer gives the admin user on its first start. Needed with server. At least 12 characters, Portainer's own minimum. It reaches the host in a root-only file and never the plan or state."

  validation {
    condition     = !var.server || (length(coalesce(var.admin_password, "-")) >= 12 && !strcontains(coalesce(var.admin_password, "-"), "\n"))
    error_message = "server needs an admin_password of at least 12 characters, on one line."
  }
}

variable "agent_secret" {
  type        = string
  default     = null
  ephemeral   = true
  sensitive   = true
  description = "Shared secret for the server and agent, set as AGENT_SECRET on both. With it, an agent answers any server that has the same secret. Without it, an agent belongs to the first server that connects. It reaches the host in root-only files and never the plan or state."

  validation {
    condition     = var.agent_secret == null || (length(coalesce(var.agent_secret, "-")) >= 16 && !strcontains(coalesce(var.agent_secret, "-"), "\n"))
    error_message = "agent_secret must be at least 16 characters on one line."
  }
}

variable "listen_address" {
  type        = string
  default     = "127.0.0.1"
  description = "Address the server's HTTPS UI and its Edge tunnel listen on. The default keeps both on the host, for a reverse proxy or an SSH tunnel."

  validation {
    condition     = can(cidrhost("${var.listen_address}/${strcontains(var.listen_address, ":") ? 128 : 32}", 0))
    error_message = "listen_address must be an IPv4 or IPv6 address, such as \"127.0.0.1\"."
  }
}

variable "port" {
  type        = number
  default     = 9443
  description = "Port the server's HTTPS UI and API listen on."

  validation {
    condition     = var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port must be a whole number from 1 to 65535."
  }
}

variable "tunnel_port" {
  type        = number
  default     = 8000
  description = "Port of the server's tunnel for Edge agents. Portainer listens on it even when no Edge agent uses it."

  validation {
    condition     = var.tunnel_port >= 1 && var.tunnel_port <= 65535 && floor(var.tunnel_port) == var.tunnel_port && var.tunnel_port != var.port
    error_message = "tunnel_port must be a whole number from 1 to 65535, and not the same as port."
  }
}

variable "agent_listen_address" {
  type        = string
  default     = "127.0.0.1"
  description = "Address the agent listens on. A server on another host can't reach the default: set the address it reaches this host at, such as a private network address."

  validation {
    condition     = can(cidrhost("${var.agent_listen_address}/${strcontains(var.agent_listen_address, ":") ? 128 : 32}", 0))
    error_message = "agent_listen_address must be an IPv4 or IPv6 address, such as \"10.0.0.5\"."
  }
}

variable "agent_port" {
  type        = number
  default     = 9001
  description = "Port the agent listens on."

  validation {
    condition     = var.agent_port >= 1 && var.agent_port <= 65535 && floor(var.agent_port) == var.agent_port && !contains([var.port, var.tunnel_port], var.agent_port)
    error_message = "agent_port must be a whole number from 1 to 65535, and not the same as port or tunnel_port."
  }
}
