{
  authorizedKeys,
  inputs,
  pkgs,
  qemuPackage,
  sharedDirectory,
  stateDirectory,
  user,
}:
let
  name = "ubuntu-tools";
  uuid = "ffc88199-9902-4d22-bc40-ae80b7be7e04";
  diskPath = "${stateDirectory}/disk.qcow2";
  yaml = pkgs.formats.yaml { };
  shellUser = pkgs.lib.escapeShellArg user;
  shellWorkLink = pkgs.lib.escapeShellArg "/home/${user}/Work";

  # NoCloud runs provisioning once per disk/instance-id, not once per rebuild.
  # A fresh state disk replays this seed; existing guests retain their own changes.
  userData = yaml.generate "ubuntu-tools-user-data.yaml" {
    bootcmd = [
      [
        "modprobe"
        "virtiofs"
      ]
      [
        "mkdir"
        "-p"
        "/mnt/work"
      ]
    ];
    disable_root = true;
    hostname = name;
    manage_etc_hosts = true;
    mounts = [
      [
        "work"
        "/mnt/work"
        "virtiofs"
        "defaults"
        "0"
        "0"
      ]
    ];
    package_update = true;
    packages = [
      "ubuntu-desktop-minimal"
      "dconf-cli"
      "spice-vdagent"
      "qemu-guest-agent"
      "openssh-server"
    ];
    runcmd = [
      [
        "sh"
        "-ec"
        ''
          ln -s /mnt/work ${shellWorkLink}
          chown -h ${shellUser}:${shellUser} ${shellWorkLink}
          systemctl enable --now ssh.service
          systemctl restart ssh.service
          systemctl start qemu-guest-agent.service
          dconf update
          systemctl set-default graphical.target
          # Do not hold cloud-final's start job while graphical boot completes.
          systemctl --no-block start graphical.target
        ''
      ]
    ];
    ssh_pwauth = false;
    users = [
      {
        groups = [
          "adm"
          "sudo"
        ];
        lock_passwd = true;
        name = user;
        shell = "/bin/bash";
        ssh_authorized_keys = authorizedKeys;
        sudo = "ALL=(ALL) NOPASSWD:ALL";
        uid = 1000;
      }
    ];
    write_files = [
      {
        content = ''
          user-db:user
          system-db:local
        '';
        path = "/etc/dconf/profile/user";
      }
      {
        content = ''
          [org/gnome/desktop/lockdown]
          disable-lock-screen=true

          [org/gnome/desktop/screensaver]
          lock-enabled=false
        '';
        path = "/etc/dconf/db/local.d/00-workspace";
      }
      {
        content = ''
          /org/gnome/desktop/lockdown/disable-lock-screen
          /org/gnome/desktop/screensaver/lock-enabled
        '';
        path = "/etc/dconf/db/local.d/locks/workspace";
      }
      {
        content = ''
          [daemon]
          WaylandEnable=false
          AutomaticLoginEnable=true
          AutomaticLogin=${user}
        '';
        defer = true;
        owner = "root:root";
        path = "/etc/gdm3/custom.conf";
        permissions = "0644";
      }
      {
        content = ''
          PasswordAuthentication no
          KbdInteractiveAuthentication no
          PermitRootLogin no
        '';
        owner = "root:root";
        path = "/etc/ssh/sshd_config.d/00-workspace-public-keys.conf";
        permissions = "0644";
      }
    ];
  };
  metadata = yaml.generate "ubuntu-tools-meta-data.yaml" {
    instance-id = uuid;
    local-hostname = name;
  };
  seed = pkgs.runCommand "ubuntu-tools-nocloud.iso" { nativeBuildInputs = [ pkgs.cdrkit ]; } ''
    mkdir seed
    printf '#cloud-config\n' > seed/user-data
    cat ${userData} >> seed/user-data
    cp ${metadata} seed/meta-data
    genisoimage -quiet -output "$out" -volid cidata -joliet -rock seed
  '';
  base = inputs.NixVirt.lib.domain.templates.linux {
    inherit name uuid;
    install_vol = "${seed}";
    memory = {
      count = 6;
      unit = "GiB";
    };
    net_iface_mac = "52:54:00:24:04:01";
    storage_vol = diskPath;
    vcpu = {
      count = 4;
    };
    # Standard Linux virgl acceleration keeps the local desktop off software rendering.
    virtio_video = true;
  };
  domain = base // {
    devices = base.devices // {
      console = {
        target = {
          port = 0;
          type = "serial";
        };
        type = "pty";
      };
      emulator = "${qemuPackage}/bin/qemu-system-x86_64";
      filesystem = {
        accessmode = "passthrough";
        driver = {
          type = "virtiofs";
        };
        source = {
          dir = sharedDirectory;
        };
        target = {
          dir = "work";
        };
        type = "mount";
      };
      graphics = base.devices.graphics // {
        listen = {
          type = "none";
        };
      };
      interface = {
        mac = {
          address = "52:54:00:24:04:01";
        };
        model = {
          type = "virtio";
        };
        source = {
          network = "default";
        };
        type = "network";
      };
      serial = {
        target = {
          port = 0;
        };
        type = "pty";
      };
    };
    memoryBacking = {
      access = {
        mode = "shared";
      };
      source = {
        type = "memfd";
      };
    };
    # The cloud image supports BIOS boot, so there is no mutable firmware state.
    os = base.os // {
      boot = [ { dev = "hd"; } ];
    };
  };
in
{
  inherit name uuid diskPath;
  definition = inputs.NixVirt.lib.domain.writeXML domain;
  diskSize = "64G";
  initialImage = pkgs.fetchurl {
    sha256 = "04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94";
    url = "https://cloud-images.ubuntu.com/noble/20261017/noble-server-cloudimg-amd64.img";
  };
}
