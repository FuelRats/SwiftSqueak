########################
#  VARIABLES
########################
variable "env"        { type = string }
variable "image_tag"  { type = string }
variable "dc_list"    { type = list(string) }
variable "replicas"   { type = number }
variable "vault_role_id"   { type = string }
variable "vault_secret_id" { type = string }

########################
#  JOB
########################
job "swiftsqueak-${var.env}" {
  # ——— scope ———
  datacenters = var.dc_list
  namespace   = var.env        # prod vs staging isolation

  type = "service"

  group "app" {
    count = var.replicas

    network {
      port "web" { to = 8080 }
    }

    task "web" {
      driver = "docker"
      config {
        image = "ghcr.io/you/swiftsqueak:${var.image_tag}"
        ports = ["web"]
      }

      ########################
      #  VAULT INTEGRATION
      ########################
      vault { policies = ["swiftsqueak"] }

      # AppRole login → child token → env file
      template {
        destination = "secrets/token.env"
        env         = true          # load as ENV
        change_mode = "signal"
        data = <<-EOT
          {{ with secret "auth/approle/login" "role_id=${var.vault_role_id}" "secret_id=${var.vault_secret_id}" }}
          VAULT_TOKEN="{{ .Data.token }}"
          {{ end }}
        EOT
      }

      env {
        # Nomad auto-injects VAULT_ADDR; we only need the port our app listens on.
        WEB_PORT = "8080"
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }

  ########################
  #  UPDATE STRATEGY
  ########################
  update {
    max_parallel     = 1
    health_check     = "checks"
    min_healthy_time = "10s"
    progress_deadline= "3m"
  }
}
