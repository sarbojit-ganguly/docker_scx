# Containerized `sched_ext` & eBPF Development Environment Guide

This document outlines a standardized, reproducible workflow for compiling Linux kernels with `sched_ext` and eBPF support. It uses a hybrid approach: isolating volatile build toolchains (like LLVM and `pahole`) inside a Debian Sid Docker container, while executing the compiled artifacts natively via QEMU/KVM on a stable Ubuntu host.

## 1. Preparing the Host System 
The host operating system requires no cross-compilers or bleeding-edge eBPF tools. The only requirements are a working Docker engine and the virtualization stack for running the QEMU test-bed.

Ensure your Ubuntu 26.04 LTS host is updated:
```bash
sudo apt update && sudo apt upgrade -y
```

## 2. Installing Required Packages (Host)
Install Docker and the native KVM virtualization tools. This ensures hardware acceleration is available for booting the compiled kernels.

```bash
sudo apt install -y docker.io docker-buildx qemu-system-x86 qemu-kvm libvirt-daemon-system virt-manager
```

Configure user permissions to run Docker and KVM without `sudo`:
```bash
sudo usermod -aG docker $USER
sudo usermod -aG kvm $USER
sudo usermod -aG libvirt $USER
```
*Note: A complete system logout or reboot is required for these group changes to take effect.*

## 3. Preparing the Docker Environment
Create a dedicated directory for the build environment (e.g., `mkdir ~/docker-kernel-build`) and create a file named `Dockerfile` with the following configuration. 

This configuration isolates the eBPF toolchain, configures system-wide Rust access (avoiding `/root` permission traps), and bakes in shell aliases.

```dockerfile
FROM debian:sid

# 1. Force Rust to install system-wide
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# 2. Install Kernel, Debian Packaging, and eBPF dependencies
RUN apt-get update && apt-get install -y \
    build-essential bc kmod cpio flex bison rsync git \
    libelf-dev libssl-dev libncurses-dev pkg-config zlib1g-dev \
    clang llvm lld dwarves ccache \
    fakeroot dpkg-dev debhelper ca-certificates curl \
    meson ninja-build libcap-dev \
    && rm -rf /var/lib/apt/lists/*

# 3. Install Rust via rustup (for scx schedulers) & grant permissions
RUN curl --proto '=https' --tlsv1.2 -sSf [https://sh.rustup.rs](https://sh.rustup.rs) | sh -s -- -y && \
    chmod -R 777 $RUSTUP_HOME $CARGO_HOME

# 4. Set custom prompt and colored aliases for container shell
RUN echo 'export PS1="kernel-builder@docker:\w\$ "' >> /etc/bash.bashrc && \
    echo "alias ls='ls --color=auto'" >> /etc/bash.bashrc && \
    echo "alias grep='grep --color=auto'" >> /etc/bash.bashrc

WORKDIR /workspace
```

## 4. Building the Docker Image
Execute the build command from the directory containing the `Dockerfile`. This bakes the toolchain into a reusable local image named `sched-ext-builder`.

```bash
docker build -t sched-ext-builder .
```

## 5. Running the Docker Container
Organize your host filesystem so the Linux kernel source and the `scx` repository share a common parent directory (e.g., `~/Projects`). 

```bash
cd ~/Projects
git clone [https://github.com/sched-ext/scx.git](https://github.com/sched-ext/scx.git)
# Ensure your linux source is also located here, e.g., ~/Projects/linux
```

Launch the interactive build container from this parent directory. The `--user` flag ensures all compiled files belong to your host user.

```bash
docker run -it --rm \
  -v $(pwd):/workspace \
  --user $(id -u):$(id -g) \
  sched-ext-builder \
  bash
```

## 6. Configuring and Building for QEMU (Debian Trixie)
Once inside the container shell, navigate to your kernel source directory (`cd linux`) and configure the build. 

**Kernel Configuration:**
Generate a default configuration and merge the KVM guest optimizations to ensure the kernel can boot rapidly in QEMU without a complex `initramfs`.
```bash
make defconfig
make kvm_guest.config
make menuconfig # Enable CONFIG_SCHED_CLASS_EXT=y and BPF options
```

**Compilation (Direct Boot Method):**
Utilize all available CPU threads to compile the `bzImage` and export the modules to a staging directory. This is optimal for rapid iteration. Leveraging `$(nproc)` will automatically utilize all cores of the Intel Core Ultra 9 to minimize compilation time.
```bash
make -j$(nproc) bzImage modules
make INSTALL_MOD_PATH=../vm-shared modules_install
make INSTALL_HDR_PATH=../vm-shared/usr headers_install
```

**Compilation (Debian Package Method):**
If deploying a standardized OS image to hardware controllers, package the kernel and headers directly into `.deb` files.
```bash
make -j$(nproc) bindeb-pkg
```

## 7. Important Things to Consider
* **Standard Linux Target Over AOSP:** The compiled schedulers (like `scx_lavd` and `scx_cosmos`) and the generated `.deb` packages are entirely decoupled from Android Open Source Project constraints. They are ready for native deployment on standard distributions like Debian, Ubuntu, or Yocto targeting hardware like the Qualcomm IQ-9075.
* **Building Userspace Schedulers:** To compile the `scx` schedulers alongside the kernel, navigate to the `/workspace/scx` directory inside the container and run `meson setup build && ninja -C build`. This provides the reference C and Rust binaries to synthesize custom scheduling logic like the DCJL algorithm.
* **Volume Mapping Strategy:** Running `docker run` from the parent directory is mandatory if using `make bindeb-pkg`, as the Debian packaging scripts write the output files one level above the kernel source tree. 

## 8. Caveats
* **Rust Crate Caching:** Because the container uses the `--rm` flag, it vanishes upon exit. While the kernel source and compiled `bzImage` remain safe on your host via the `-v` mount, the `~/.cargo/registry` inside the container does not persist. Rust will re-download crates every time you run a fresh container shell and build the `scx` repository. 
* **CCache Persistance:** Similarly, `ccache` stores its cache in `~/.ccache` by default. To make recompilations truly instantaneous across different container sessions, you must map a dedicated cache folder from the host into the container by adding `-v ~/.ccache:/.cache/ccache` and setting `ENV CCACHE_DIR=/.cache/ccache` in the Dockerfile.
* **Direct Boot vs Initramfs:** When using direct kernel boot with QEMU (`-kernel bzImage`), you must ensure the filesystem drivers (like `virtio-blk` and `ext4`) are built into the kernel (`=y`), not as modules (`=m`). If they are modules, the kernel will panic attempting to mount `/dev/vda1`.

## 9. Closing Notes
This architecture strictly isolates fragile eBPF dependencies from the host system while preserving native I/O performance. You can comfortably edit source files on the host using your preferred IDE, use the container purely as a heavy-duty compilation engine, and execute the results directly via host-native QEMU.
