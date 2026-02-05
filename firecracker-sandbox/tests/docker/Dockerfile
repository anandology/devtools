FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install base dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    tar \
    gzip \
    e2fsprogs \
    util-linux \
    iproute2 \
    iptables \
    iputils-ping \
    netcat \
    openssh-client \
    sudo \
    kmod \
    debootstrap \
    && rm -rf /var/lib/apt/lists/*

# Install firecracker
RUN ARCH="$(uname -m)" && \
    FIRECRACKER_VERSION="v1.7.0" && \
    curl -fsSL https://github.com/firecracker-microvm/firecracker/releases/download/${FIRECRACKER_VERSION}/firecracker-${FIRECRACKER_VERSION}-${ARCH}.tgz \
    -o /tmp/firecracker.tgz && \
    tar -xzf /tmp/firecracker.tgz -C /tmp && \
    mv /tmp/release-${FIRECRACKER_VERSION}-${ARCH}/firecracker-${FIRECRACKER_VERSION}-${ARCH} /usr/local/bin/firecracker && \
    chmod +x /usr/local/bin/firecracker && \
    rm -rf /tmp/firecracker.tgz /tmp/release-${FIRECRACKER_VERSION}-${ARCH}

# Download kernel for testing
RUN mkdir -p /root/.firecracker-vms/.images && \
    curl -fsSL https://s3.amazonaws.com/spec.ccfc.min/firecracker-ci/v1.7/x86_64/vmlinux-6.1.77 \
    -o /root/.firecracker-vms/.images/vmlinux && \
    chmod +r /root/.firecracker-vms/.images/vmlinux

# Create test user (for non-root tests)
RUN useradd -m -s /bin/bash -G sudo testuser && \
    echo "testuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/testuser && \
    chmod 0440 /etc/sudoers.d/testuser

# Set up working directory
WORKDIR /workspace

# Default command runs the quick-check tests
CMD ["tests/quick-check.sh"]
