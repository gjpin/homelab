#!/bin/bash
set -euxo pipefail

# Ensure packages are up-to-date
sudo pacman -Syyu --noconfirm

# Disable debug symbols for smaller packages
echo "OPTIONS=(!debug)" > ~/.makepkg.conf

# Prepare directories
mkdir -p ~/packages ~/new_packages
export PKGDEST=~/new_packages

# Clone Arch Linux repo and make it PWD
git clone --depth=1 https://github.com/gjpin/arch-linux-repo
cd arch-linux-repo

# List of AUR packages to be built
packages=(
  xr-hardware-git
  monado-git
  opencomposite-git
  wlx-overlay-s-git
  wivrn-server
  wivrn-dashboard
  wivrn-full-git
  alvr-git
  envision-xr-git
  xrizer-git
)

# Clone and build each package
for pkg in "${packages[@]}"; do
  git clone "https://aur.archlinux.org/$pkg.git" "packages/$pkg"
  paru -B --noconfirm "packages/$pkg"
done

# Move built packages to the mounted repo dir
mkdir -p /repo
mv ~/new_packages/* /repo

# Create/update the package database
repo-add repo/gjpin.db.tar.zst repo/*.pkg.tar.zst

# Commit and push updates
git config --global user.name "gjpin"
git config --global user.email "3874515+gjpin@users.noreply.github.com"
git add repo
git commit -m "Update AUR packages"
git push origin main
