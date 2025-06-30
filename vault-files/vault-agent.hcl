vault {
  address = "http://vault:8200"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path   = "/run/secrets/vault/role-id"
      secret_id_file_path = "/run/secrets/vault/secret-id"
    }
  }
}

env_template "VAULT_TOKEN" {
  contents = <<EOH
{{ with secret "auth/token/lookup-self" }}{{ .Data.id }}{{ end }}
EOH
}

exec {
  command = ["/app/mechasqueak"]
  restart_on_secret_changes = "always"
  restart_stop_signal = "SIGTERM"
}

