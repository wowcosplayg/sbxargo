FROM debian:stable-slim

# Install runtime dependencies
# procps is needed for 'nohup' and process management logic checks
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    ca-certificates \
    procps \
    tzdata \
    uuid-runtime \
    tar \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Set timezone
ENV TZ=Asia/Shanghai

# Setup App Directory
WORKDIR /app

# Copy Scripts
COPY main.sh /app/
COPY modules /app/modules
COPY docker-entrypoint.sh /app/

# Permissions
RUN chmod +x /app/docker-entrypoint.sh /app/main.sh /app/modules/*.sh

# Persist Data
VOLUME ["/root/agsbx"]

# Default Env Vars (User can override)
ENV vlpt=yes
# Add more defaults if needed, e.g.
# ENV hypt=yes

# Entrypoint
ENTRYPOINT ["/app/docker-entrypoint.sh"]
