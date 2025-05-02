#!/bin/bash
set -euxo pipefail

# Ensure packages are up-to-date
sudo pacman -Syyu --noconfirm

# Clone Arch Linux repo and make it PWD
git clone https://github.com/gjpin/arch-linux-repo \
cd arch-linux-repo

# Ensure SSH config is safe
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*

# Disable debug symbols for smaller packages
echo "OPTIONS=(!debug)" > ~/.makepkg.conf

# Prepare directories
mkdir -p ~/packages ~/new_packages
export PKGDEST=~/new_packages

# List of AUR packages
packages=(
  xr-hardware-git
  monado-git
  opencomposite-git
  wlx-overlay-s-git
  wivrn-server
  wivrn-dashboard
  alvr-git
  envision-xr-git
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
