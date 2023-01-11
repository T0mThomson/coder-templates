terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "0.6.0"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 2.22"
    }
  }
}

locals {
  username = data.coder_workspace.me.owner
}

data "coder_provisioner" "me" {
}

provider "docker" {
}

data "coder_workspace" "me" {
}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<EOF
echo #!/bin/bash
      # Start mongodb
      mongod &

      # Start mongo-express
      export ME_CONFIG_BASICAUTH_USERNAME= && export ME_CONFIG_BASICAUTH_PASSWORD= && mongo-express --url mongodb://127.0.0.1:27017 --port 1010 --admin &

      # Wait for any process to exit
      wait -n

      # Exit with status of process that exited first
      exit $?
    EOF
}

resource "coder_app" "mongo-express" {
  agent_id     = coder_agent.main.id
  slug         = "mongo-express"
  display_name = "Mongo Express"
  url          = "http://localhost:1010/"
  icon         = "https://cdn.iconscout.com/icon/free/png-256/mongodb-3629020-3030245.png"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:1010"
    interval  = 5
    threshold = 6
  }
}


resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace.me.owner
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace.me.owner_id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}


resource "docker_image" "main" {
  name = "coder-${data.coder_workspace.me.id}"
  build {
    path = "./build"
    build_arg = {
      USER = local.username
    }
  }
  triggers = {
    dir_sha1 = sha1(join("", [for f in fileset(path.module, "build/*") : filesha1(f)]))
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.name
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace.me.owner}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/${local.username}"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace.me.owner
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace.me.owner_id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
