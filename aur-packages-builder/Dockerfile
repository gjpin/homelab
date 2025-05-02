FROM archlinux:base-devel

# Install required packages and create user
RUN pacman -Syyu --noconfirm \
 && pacman -S --noconfirm --needed git gnupg sudo \
 && useradd -m -s /bin/bash builder \
 && echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Switch user
USER builder
WORKDIR /home/builder

# Install Paru
RUN git clone https://aur.archlinux.org/paru-bin.git \
 && cd paru-bin && makepkg -si --noconfirm