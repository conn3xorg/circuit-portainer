locals {
  server_image = "docker.io/portainer/portainer-ce:${var.portainer_version}@${var.image_digest}"
  agent_image  = "docker.io/portainer/agent:${var.portainer_version}@${var.agent_image_digest}"

  etc           = "/etc/portainer"
  data          = "/var/lib/portainer/data"
  password_file = "${local.etc}/admin_password"

  # Podman's Docker-compatible API. Portainer and its agent only speak to
  # /var/run/docker.sock inside the container, so the socket goes there.
  socket = "/run/podman/podman.sock:/var/run/docker.sock"

  listen_host = strcontains(var.listen_address, ":") ? "[${var.listen_address}]" : var.listen_address
  agent_host  = strcontains(var.agent_listen_address, ":") ? "[${var.agent_listen_address}]" : var.agent_listen_address

  # HTTP stays off, so the only listener with a login page has TLS, even if
  # that's Portainer's own self-signed certificate. -H gives Portainer this
  # host's Podman as its first environment.
  server_args = join(" ", [
    "--http-disabled",
    "--bind-https ${local.listen_host}:${var.port}",
    "--tunnel-addr ${var.listen_address}",
    "--tunnel-port ${var.tunnel_port}",
    "--admin-password-file /run/portainer/admin_password",
    "-H unix:///var/run/docker.sock",
  ])

  containers = merge(
    var.server ? {
      portainer = {
        image   = local.server_image
        volumes = [local.socket, "${local.data}:/data:Z", "${local.password_file}:/run/portainer/admin_password:ro,Z"]
        # Host network, so listen_address is a real address on the host and
        # the server reaches agents listening on its loopback. The socket is
        # labelled for Podman, not for containers, so SELinux separation is
        # off for this container. It holds the engine's socket, which is as
        # good as root on the host anyway.
        extra = ["Network=host", "SecurityLabelDisable=true", "Exec=${local.server_args}"]
      }
    } : {},
    var.agent ? {
      portainer-agent = {
        image = local.agent_image
        # The agent reads volumes where Docker keeps them. Podman keeps them
        # here.
        volumes = [local.socket, "/var/lib/containers/storage/volumes:/var/lib/docker/volumes"]
        # On the host's network too, listening where AGENT_HOST and
        # AGENT_PORT say. A published port would be a firewall rule on some
        # Podman versions, with no listener for the apply to wait for.
        environment = {
          AGENT_HOST = var.agent_listen_address
          AGENT_PORT = tostring(var.agent_port)
        }
        extra = ["Network=host", "SecurityLabelDisable=true"]
      }
    } : {},
  )

  secrets = var.agent_secret == null ? {} : { for name in keys(local.containers) : name => { AGENT_SECRET = var.agent_secret } }
}

circuit "portainer" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Installed here as well as by circuit-podman, so the socket is listening
  # before either container starts. Mounting a socket that isn't there yet
  # would leave an empty directory in its place.
  step "podman" {
    package {
      name = "podman"
    }
  }

  step "socket" {
    service {
      name    = "podman.socket"
      state   = "started"
      enabled = true
    }
  }

  # Podman makes its volume directory with the first volume, and the agent's
  # mount needs it before then.
  step "volumes" {
    for_each = toset(var.agent ? ["agent"] : [])
    command {
      command = "install -d -m 0700 /var/lib/containers/storage/volumes"
      creates = "/var/lib/containers/storage/volumes"
    }
  }

  step "etc" {
    for_each = toset(var.server ? ["server"] : [])
    directory {
      path  = local.etc
      owner = "root"
      group = "root"
      mode  = "0700"
    }
  }

  # Portainer reads it on its first start only, to create the admin user.
  # Write-only: the plan and state record an HMAC of it, never the password.
  step "password" {
    for_each = toset(var.server ? ["server"] : [])
    file {
      path       = local.password_file
      content_wo = var.admin_password
      owner      = "root"
      group      = "root"
      mode       = "0600"
    }
  }

  # Portainer's database, its TLS certificate and its key pair for agents,
  # in a parent only root can enter.
  step "data" {
    for_each = toset(var.server ? ["server"] : [])
    command {
      command = "install -d -m 0700 /var/lib/portainer ${local.data}"
      unless  = "[ \"$(stat -c '%u %a' /var/lib/portainer)\" = '0 700' ] && [ -d ${local.data} ]"
    }
  }
}

module "podman" {
  source = "github.com/conn3xorg/circuit-podman?ref=v0.1.0"

  depends_on = [conn3x_service.portainer__socket, conn3x_command.portainer__volumes, conn3x_file.portainer__password, conn3x_command.portainer__data]

  hosts                = var.hosts
  ssh_user             = var.ssh_user
  ssh_port             = var.ssh_port
  ssh_private_key_file = var.ssh_private_key_file
  ssh_known_hosts_file = var.ssh_known_hosts_file
  ssh_become           = var.ssh_become

  containers = local.containers
  secrets    = local.secrets
}

circuit "ready" {
  hosts = var.hosts

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # A changed unit restarts the containers after the port checks below
  # have already passed at plan time, so this waits for the ports again
  # whenever the units change. bash's /dev/tcp, since the host may have no
  # nc or curl.
  step "restarted" {
    depends_on = [module.podman]
    command {
      command  = "bash -c 'for _ in $(seq 300); do ${join(" && ", concat(var.server ? ["(exec 3<>/dev/tcp/${var.listen_address}/${var.port})"] : [], var.agent ? ["(exec 3<>/dev/tcp/${var.agent_listen_address}/${var.agent_port})"] : []))} 2>/dev/null && exit 0; sleep 2; done; echo \"Portainer did not open its ports in 10 minutes. See journalctl -u portainer -u portainer-agent.\" >&2; exit 1'"
      triggers = sha256(jsonencode(local.containers))
    }
  }

  step "server" {
    for_each   = toset(var.server ? ["server"] : [])
    depends_on = [conn3x_command.ready__restarted]
    wait_for {
      port    = var.port
      timeout = "10m"
    }
  }

  step "agent" {
    for_each   = toset(var.agent ? ["agent"] : [])
    depends_on = [conn3x_command.ready__restarted]
    wait_for {
      port    = var.agent_port
      timeout = "10m"
    }
  }
}
