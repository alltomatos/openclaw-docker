# Use Ubuntu 24.04 LTS as the base image
FROM ubuntu:24.04

# Avoid prompts from apt
ENV DEBIAN_FRONTEND=noninteractive

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
    iproute2 \
    dumb-init \
    libvips-dev \
    ffmpeg \
    jq \
    cron \
    gosu \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js 22
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Create a non-root user 'openclaw'
RUN groupadd -r openclaw && useradd -r -g openclaw -m -s /bin/bash openclaw

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

# Switch to non-root user for Playwright installation
# We temporarily switch to install browsers in user space
USER openclaw
WORKDIR /home/openclaw

# Install Playwright browsers (as the user)
RUN npx playwright install

# Switch back to root because entrypoint needs to start cron
USER root

# Expose the default gateway port
EXPOSE 18789

# Use dumb-init as the entrypoint handler
ENTRYPOINT ["/usr/bin/dumb-init", "--", "/usr/local/bin/entrypoint.sh"]

# Default command to start the gateway via PM2
CMD ["pm2-runtime", "start", "ecosystem.config.js"]
