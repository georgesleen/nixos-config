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
  name = "windows-workstation";
  uuid = "5c29be1c-5d6a-486e-9189-01855f78eada";
  diskPath = "${stateDirectory}/disk.qcow2";
  mediaDirectory = "/home/${user}/Media/Disk Images";
  publicKeys = pkgs.writeText "windows-workstation-authorized-keys" (
    builtins.concatStringsSep "\n" authorizedKeys + "\n"
  );
  provisioningIso =
    pkgs.runCommand "windows-workstation-provision.iso"
      {
        nativeBuildInputs = [ pkgs.xorriso ];
      }
      ''
        mkdir provision
        cp ${./Setup-Workstation.ps1} provision/Setup-Workstation.ps1
        cp ${./INSTALL.txt} provision/INSTALL.txt
        cp ${publicKeys} provision/authorized_keys
        xorriso -as mkisofs -J -r -V WORKSTATION -o "$out" provision
      '';
  domainLibrary = inputs.NixVirt.lib.domain;
  base = domainLibrary.templates.windows {
    inherit name uuid;
    install_virtio = false;
    install_vol = "${mediaDirectory}/Win11_24H2_English_x64.iso";
    memory = {
      count = 12;
      unit = "GiB";
    };
    nvram_path = "${stateDirectory}/nvram.fd";
    storage_vol = diskPath;
    vcpu = {
      count = 8;
    };
    virtio_drive = false;
    virtio_net = false;
    virtio_video = false;
  };
  cdrom = device: source: {
    device = "cdrom";
    driver = {
      name = "qemu";
      type = "raw";
    };
    readonly = true;
    source = {
      file = source;
      startupPolicy = "mandatory";
    };
    target = {
      bus = "sata";
      dev = device;
    };
    type = "file";
  };
  domain = base // {
    cpu = base.cpu // {
      topology = {
        cores = 8;
        sockets = 1;
        threads = 1;
      };
    };
    devices = base.devices // {
      channel = [
        {
          target = {
            name = "com.redhat.spice.0";
            type = "virtio";
          };
          type = "spicevmc";
        }
        {
          target = {
            name = "org.qemu.guest_agent.0";
            type = "virtio";
          };
          type = "unix";
        }
      ];
      disk = [
        {
          device = "disk";
          driver = {
            discard = "unmap";
            name = "qemu";
            type = "qcow2";
          };
          source = {
            file = diskPath;
          };
          target = {
            bus = "sata";
            dev = "sda";
          };
          type = "file";
        }
        (cdrom "sdb" "${mediaDirectory}/Win11_24H2_English_x64.iso")
        (cdrom "sdc" "${mediaDirectory}/virtio-win-0.1.271.iso")
        (cdrom "sdd" "${provisioningIso}")
      ];
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
      graphics = {
        autoport = true;
        gl = {
          enable = false;
        };
        listen = {
          type = "none";
        };
        type = "spice";
      };
      interface = {
        mac = {
          address = "52:54:00:11:00:01";
        };
        model = {
          type = "e1000e";
        };
        source = {
          network = "default";
        };
        type = "network";
      };
    };
    features = base.features // {
      smm = {
        state = true;
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
    os = base.os // {
      bootmenu = {
        enable = true;
      };
      loader = base.os.loader // {
        secure = true;
      };
    };
  };
  # The pinned NixVirt schema cannot serialize a TPM backend source directory.
  tpmBackend = "<backend type='emulator' version='2.0'/>";
  tpmBackendWithSource = inputs.NixVirt.lib.xml.toText (
    inputs.NixVirt.lib.xml.elem "backend"
      [
        (inputs.NixVirt.lib.xml.attr "type" "emulator")
        (inputs.NixVirt.lib.xml.attr "version" "2.0")
      ]
      [
        (inputs.NixVirt.lib.xml.elem "source" [
          (inputs.NixVirt.lib.xml.attr "type" "dir")
          (inputs.NixVirt.lib.xml.attr "path" "${stateDirectory}/tpm")
        ] null)
      ]
  );
  sourceXml = domainLibrary.getXML domain;
  definition =
    assert pkgs.lib.hasInfix tpmBackend sourceXml;
    pkgs.writeText "NixVirt-domain-${name}" (
      builtins.replaceStrings [ tpmBackend ] [ tpmBackendWithSource ] sourceXml
    );
in
{
  inherit
    name
    uuid
    definition
    diskPath
    ;
  diskSize = "128G";
  initialImage = null;
}
