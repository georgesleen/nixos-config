# MATLAB on NixOS (local package)

This folder contains a local MATLAB wrapper setup for NixOS.

## What this does

- Defines an FHS runtime (`matlab-fhs`) for running the proprietary MATLAB installer/binaries.
- Defines `matlab-install` to launch the installer inside that runtime.
- Defines `matlab` to launch an installed MATLAB from your home directory.

Definitions live in `pkgs/matlab/default.nix`.

## Where it is enabled

It is only enabled in `modules/laptop.nix` via:

- `matlabPkgs.matlab-fhs`
- `matlabPkgs.matlab-install`
- `matlabPkgs.matlab`

Other hosts/modules are unaffected unless they import and add this package set.

## Install flow

1. Rebuild your system:

```bash
sudo nixos-rebuild switch --flake /etc/nixos#gs-thinkpad-t480s
```

2. Unzip MATLAB installer (example):

```bash
unzip matlab_R2025b_Linux.zip -d ~/Downloads/matlab_R2025b_Linux
```

3. Run installer in FHS env:

```bash
matlab-install ~/Downloads/matlab_R2025b_Linux
```

4. In the installer, choose install location:

```text
/home/<your-user>/opt/MATLAB/R2025b
```

`sudo` is not needed when installing to your home directory.

## Run MATLAB

```bash
matlab
```

The wrapper currently expects MATLAB at:

```text
$HOME/opt/MATLAB/R2025b
```

If you install a different version/path, update `matlabRoot` in `pkgs/matlab/default.nix`.
