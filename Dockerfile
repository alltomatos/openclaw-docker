# Use Ubuntu 24.04 LTS as the base image
FROM ubuntu:24.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

# Define build argument for extra packages (Official compatibility)
ARG OPENCLAW_DOCKER_APT_PACKAGES=""

# Install dependencies
# - dumb-init: handles PID 1 signals correctly
# - libvips-dev: for sharp (image processing) optimization
# - ffmpeg: for media processing capabilities
# - jq: useful for JSON manipulation in scripts
# - cron: for scheduling periodic tasks
# - gosu: for easy step-down from root
RUN apt-get update && apt-get install -y \
    curl \
    git \
    ca-certificates \
    gnupg \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    iproute2 \
    dumb-init \
    libvips-dev \
    ffmpeg \
    jq \
    cron \
    gosu \
    procps \
    file \
    $OPENCLAW_DOCKER_APT_PACKAGES \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Create openclaw user and group
# We use a fixed GID for docker group to match host if possible, but for now we rely on socket permissions
RUN groupadd -r openclaw && useradd -r -g openclaw -m -s /bin/bash -G audio,video openclaw \
    && mkdir -p /home/openclaw/.openclaw \
    && chown -R openclaw:openclaw /home/openclaw \
    && mkdir -p /home/linuxbrew/.linuxbrew \
    && chown -R openclaw:openclaw /home/linuxbrew/.linuxbrew

# Allow openclaw user to access docker socket (dynamically adjust group if needed in entrypoint)
# This is crucial for Sandboxing to work
RUN if ! getent group docker > /dev/null; then \
    groupadd -g 999 docker || groupadd docker; \
    fi && \
    usermod -aG docker openclaw

# Install OpenClaw and PM2 globally
# PM2 is used for process management and reloading
RUN npm install -g openclaw@latest pm2@latest

# Install Playwright globally to access the CLI for dependency installation
RUN npm install -g playwright

# Install Playwright system dependencies (requires root)
RUN npx playwright install-deps

# Copy scripts and config
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY scan_skills.sh /usr/local/bin/scan_skills.sh
COPY ecosystem.config.js /home/openclaw/ecosystem.config.js

# Set permissions
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/scan_skills.sh && \
    chown openclaw:openclaw /home/openclaw/ecosystem.config.js

# Create configuration directory
RUN mkdir -p /home/openclaw/.openclaw && \
    chown -R openclaw:openclaw /home/openclaw

# Define Python User Base for persistence
ENV PYTHONUSERBASE=/home/openclaw/.openclaw/python_deps
ENV PATH=$PYTHONUSERBASE/bin:$PATH

# Switch to non-root user for Playwright installation
# We temporarily switch to install browsers in user space
USER openclaw
WORKDIR /home/openclaw

# Install Homebrew (Linuxbrew)
ENV NONINTERACTIVE=1
RUN /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Add Homebrew to PATH
ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH"

# Install uv and other common tools via Homebrew
# We also install gcc as it is often required for building Python packages
RUN brew install uv gcc

# Install Playwright browsers (as the user)
RUN npx playwright install

# Switch back to root because entrypoint needs to start cron
USER root

# Expose the default gateway port and canvas host port
EXPOSE 18789 18793

# Use dumb-init as the entrypoint handler
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/entrypoint.sh"]

# Default command to start the gateway via PM2
CMD ["pm2-runtime", "start", "ecosystem.config.js"]
