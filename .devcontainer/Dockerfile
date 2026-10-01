# WI-081 (ASSESS-001 FND-21): pinned to the image index digest the registry gave for this tag on 2026-10-01
FROM hexpm/elixir:1.20.4-erlang-29.1.1-debian-trixie-20260918-slim@sha256:27dc95204c20b774f5c73f050d13ce7735d251a2e349c3ddcd2c3acf6ea873c1
# FROM hexpm/elixir:1.20.4-erlang-28.5.0.7-debian-bookworm-20260918-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    chromium \
    curl \
    fonts-dejavu-core \
    fonts-liberation \
    git \
    inotify-tools \
    openssh-client \
    postgresql-client \
    python3 \
    sudo \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Non-root development user.
RUN useradd -m -s /bin/bash vscode \
    && echo "vscode ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode

ENV MIX_HOME=/home/vscode/.mix
ENV HEX_HOME=/home/vscode/.hex

RUN mkdir -p \
      /home/vscode/.mix \
      /home/vscode/.hex \
      /workspace \
    && chown -R vscode:vscode \
      /home/vscode \
      /workspace

USER vscode
WORKDIR /workspace

RUN mix local.hex --force \
    && mix local.rebar --force