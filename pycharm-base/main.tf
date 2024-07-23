terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  username = data.coder_workspace_owner.me.name
}

data "coder_provisioner" "me" {
}

provider "docker" {
}

data "coder_workspace" "me" {
}
data "coder_workspace_owner" "me" {}

variable "jetbrains-ide" {
  description = "JetBrains PyCharm IDE"
  default     = "PyCharm Community Edition 2021.3"
  validation {
    condition = contains([
      "PyCharm Community Edition 2021.3",
      "PyCharm Community Edition 2020.3",
      "PyCharm Professional Edition 2021.3",
      "PyCharm Professional Edition 2020.3"
    ], var.jetbrains-ide)
    # Find all compatible IDEs with the `projector IDE find` command
    error_message = "Invalid JetBrains IDE!"
}
}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    #!/bin/bash

    # Prepare user home with default files on first start.
      if [ ! -f ~/.init_done ]; then
        cp -rT /etc/skel ~
        touch ~/.init_done
      fi

    xhost +local:docker

    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.19.1
    /tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &


    # Create virtual environment and install the correct packages
    python3 -m venv venv
    venv/bin/pip3 install pillow
    venv/bin/pip3 install requests
    venv/bin/pip3 install --upgrade pip setuptools wheel


    # install projector
    PROJECTOR_BINARY=/home/${local.username}/.local/bin/projector
    if [ -f $PROJECTOR_BINARY ]; then
        echo 'projector has already been installed - check for update'
        /home/${local.username}/.local/bin/projector self-update 2>&1 | tee projector.log
    else
        echo 'installing projector'
        git clone https://github.com/WouterDeBolle/projector-installer.git
        cd projector-installer
        pip3 install -r requirements.txt --user --break-system-packages
        python3 setup.py bundle
        pip3 install . --user --break-system-packages 2>&1 | tee projector.log
        cd ..
        mv projector-installer/settings.zip settings.zip
        rm -rf projector-installer
    fi

    echo 'access projector license terms'
    /home/${local.username}/.local/bin/projector --accept-license 2>&1 | tee -a projector.log

    PROJECTOR_CONFIG_PATH=/home/${local.username}/.projector/configs/pycharm

    if [ -d "$PROJECTOR_CONFIG_PATH" ]; then
        echo 'projector has already been configured and the JetBrains IDE downloaded - skip step' 2>&1 | tee -a projector.log
    else
        echo 'autoinstalling IDE and creating projector config folder'
        /home/${local.username}/.local/bin/projector ide autoinstall --config-name "pycharm" --ide-name "${var.jetbrains-ide}" --hostname=localhost --port 8997 --use-separate-config --password coder 2>&1 | tee -a projector.log

        # delete the configuration's run.sh input parameters that check password tokens since tokens do not work with coder_app yet passed in the querystring
        grep -iv "HANDSHAKE_TOKEN" $PROJECTOR_CONFIG_PATH/run.sh > temp && mv temp $PROJECTOR_CONFIG_PATH/run.sh 2>&1 | tee -a projector.log
        chmod +x $PROJECTOR_CONFIG_PATH/run.sh 2>&1 | tee -a projector.log

        echo "creation of pycharm configuration complete" 2>&1 | tee -a projector.log
    fi
    # start JetBrains projector-based IDE
    /home/${local.username}/.local/bin/projector run pycharm >/tmp/pycharm-server.log 2>&1 &

    git clone https://github.com/CodeFever-VZW/P2_Oplossing_L4.git

    unzip -o settings.zip -d /home/${local.username}/.projector/configs/pycharm/config/
    rm settings.zip

    
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }

}

resource "coder_app" "pycharm" {
  agent_id      = coder_agent.main.id
  slug          = "pycharm"
  display_name  = "${var.jetbrains-ide}"
  icon          = "/icon/pycharm.svg"
  url           = "http://localhost:8997/"
  subdomain     = false
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  url          = "http://localhost:13337/?folder=/home/${local.username}"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
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
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
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
    context = "./build"
    build_args = {
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
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
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
    host_path      = "/tmp/.X11-unix"
    container_path = "/tmp/.X11-unix"
    # volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
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
