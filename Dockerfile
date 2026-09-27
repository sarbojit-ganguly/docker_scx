FROM debian:sid

# 1. Force Rust to install system-wide instead of inside /root
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

# 2. Install apt dependencies (removed cargo and rustc)
RUN apt-get update && apt-get install -y \
    build-essential bc kmod cpio flex bison rsync git \
    libelf-dev libssl-dev libncurses-dev pkg-config zlib1g-dev \
    clang llvm lld dwarves ccache \
    fakeroot dpkg-dev debhelper ca-certificates curl \
    meson ninja-build libcap-dev \
    && rm -rf /var/lib/apt/lists/*

# 3. Install Rust via rustup and grant read/write/execute access to all users
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    chmod -R 777 $RUSTUP_HOME $CARGO_HOME

# 4. Set up custom prompt and colors
RUN echo 'export PS1="kernel-builder@docker:\w\$ "' >> /etc/bash.bashrc && \
    echo "alias ls='ls --color=auto'" >> /etc/bash.bashrc && \
    echo "alias grep='grep --color=auto'" >> /etc/bash.bashrc

WORKDIR /workspace
