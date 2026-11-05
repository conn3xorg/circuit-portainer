output "services" {
  description = "The systemd services that run Portainer on each host."
  value       = concat(var.server ? ["portainer.service"] : [], var.agent ? ["portainer-agent.service"] : [])
}

output "url" {
  description = "Where the server answers on each host, such as \"https://127.0.0.1:9443\", or null without server. Point a reverse proxy here."
  value       = var.server ? "https://${local.listen_host}:${var.port}" : null
}

output "agent_address" {
  description = "The address to give Portainer when you add this host as an Agent environment, such as \"10.0.0.5:9001\", or null without agent."
  value       = var.agent ? "${local.agent_host}:${var.agent_port}" : null
}

output "images" {
  description = "The images the hosts run, with their tags and digests."
  value       = concat(var.server ? [local.server_image] : [], var.agent ? [local.agent_image] : [])
}
