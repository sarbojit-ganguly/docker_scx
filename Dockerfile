FROM debian:sid

# 1. Environment configuration for Rust and ccache
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:/usr/lib/ccache:$PATH

# 2. Install kernel build dependencies, scx tools, and QEMU/KVM for running the kernel
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential bc kmod cpio flex bison rsync git \
    libelf-dev libssl-dev libncurses-dev pkg-config zlib1g-dev \
    lld dwarves ccache fakeroot dpkg-dev debhelper ca-certificates \
    curl meson ninja-build libcap-dev zstd xz-utils \
    cmake protobuf-compiler libseccomp-dev libbpf-dev \
    lsb-release wget software-properties-common gnupg \
    qemu-system-x86 qemu-kvm debootstrap \
    && rm -rf /var/lib/apt/lists/*

# 3. Fetch and install Clang 22 directly from apt.llvm.org for correct BPF lowering
RUN wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    ./llvm.sh 22 && \
    rm llvm.sh

# 4. Set Clang 22 as the default compiler for eBPF/scx
ENV CC=clang-22 \
    CXX=clang++-22

# 5. Install Rust via rustup and grant access
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    chmod -R 777 $RUSTUP_HOME $CARGO_HOME

# 6. Set up ccache directory to persist cache across container runs
RUN mkdir -p /workspace/.ccache && chmod -R 777 /workspace/.ccache
ENV CCACHE_DIR=/workspace/.ccache

# 7. Set up custom prompt
RUN echo 'export PS1="kernel-builder@docker:\w\$ "' >> /etc/bash.bashrc && \
    echo "alias ls='ls --color=auto'" >> /etc/bash.bashrc && \
    echo "alias grep='grep --color=auto'" >> /etc/bash.bashrc

WORKDIR /workspace
