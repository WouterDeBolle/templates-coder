terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
    }
    docker = {
      source  = "kreuzwerker/docker"
    }
  }
}

locals {
  username = data.coder_workspace_owner.me.name
}

# Admin parameters
# variable "step2_arch" {
#   description = "arch: What architecture is your Docker host on?"
#   validation {
#     condition     = contains(["amd64", "arm64", "armv7"], var.step2_arch)
#     error_message = "Value must be amd64, arm64, or armv7."
#   }
#   sensitive = true
# }
# variable "step3_OS" {
#   description = <<-EOF
#   What operating system is your Coder host on?
#   EOF

#   validation {
#     condition     = contains(["MacOS", "Windows", "Linux"], var.step3_OS)
#     error_message = "Value must be MacOS, Windows, or Linux."
#   }
#   sensitive = true
# }

# https://ppswi.us/noVNC/app/images/icons/novnc-192x192.png

provider "docker" {
}

data "coder_provisioner" "me" {
}


data "coder_workspace" "me" {
}

data "coder_workspace_owner" "me" {
}

# Desktop
resource "coder_app" "novnc" {
  agent_id      = coder_agent.dev.id
  slug          = "novnc-desktop"
  display_name  = "novnc-desktop"
  icon          = "/icon/novnc.svg"
  url           = "http://localhost:6081"
  subdomain     = true
}

resource "coder_app" "code-server" {
  agent_id     = coder_agent.dev.id
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

resource "coder_agent" "dev" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<EOT
#!/bin/bash
set -euo pipefail

# install and start code-server
curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.19.1
/tmp/code-server/bin/code-server --auth none --port 13337 >/tmp/code-server.log 2>&1 &


# start VNC
echo "Creating desktop..."
mkdir -p "$XFCE_DEST_DIR"
cp -rT "$XFCE_BASE_DIR" "$XFCE_DEST_DIR"

# Skip default shell config prompt.
cp /etc/zsh/newuser.zshrc.recommended $HOME/.zshrc

echo "Initializing Supervisor..."
nohup supervisord

curl -L https://download.jetbrains.com/python/pycharm-community-2022.1.1.tar.gz  | tar -xz

echo "Unpacking pycharm done"

sudo mkdir -p /home/coder/.local/share/applications/
sudo touch /home/coder/.local/share/applications/pycharm.desktop
cd /home/coder/.local/share/applications
sudo chmod 777 pycharm.desktop
echo "[Desktop Entry]" >> pycharm.desktop
echo "Version=1.0" >> pycharm.desktop
echo "Type=Application" >> pycharm.desktop
echo "Name=PyCharm Community Edition" >> pycharm.desktop
echo "Icon=/home/coder/pycharm-community-2022.1.1/bin/pycharm.svg" >> pycharm.desktop
echo "Exec=\"/home/coder/pycharm-community-2022.1.1/bin/pycharm.sh\" %f" >> pycharm.desktop
echo "Comment=Python IDE for Professional Developers" >> pycharm.desktop
echo "Categories=Development;IDE;" >> pycharm.desktop
echo "Terminal=false" >> pycharm.desktop
echo "StartupWMClass=jetbrains-pycharm-ce" >> pycharm.desktop
echo "StartupNotify=true" >> pycharm.desktop
cd

cp -R /home/coder/.local/share/applications/pycharm.desktop /home/coder/Desktop/
cd /home/coder/Documents

sudo apt-get update
sudo apt-get install -y python3 python3-tk python3-venv

python3 -m venv venv
venv/bin/pip3 install pillow
venv/bin/pip3 install requests
venv/bin/pip3 install --upgrade pip setuptools wheel

git clone https://github.com/CodeFever-VZW/P2_Oplossing_L4.git

  EOT

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
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = lower(data.coder_workspace.me.name)
  dns      = ["1.1.1.1"]
  # Use the docker gateway if the access URL is 127.0.0.1 
  command = ["sh", "-c", replace(coder_agent.dev.init_script, "127.0.0.1", "host.docker.internal")]
  env     = ["CODER_AGENT_TOKEN=${coder_agent.dev.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/${local.username}"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
}