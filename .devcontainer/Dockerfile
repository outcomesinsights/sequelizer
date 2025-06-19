# Start with Ruby 3.2 slim for a smaller image
FROM ruby:3.2-slim

# Set timezone argument (can be overridden in devcontainer.json)
ARG TZ=America/Los_Angeles
ENV TZ=$TZ

# Set host home directory for copying credentials
ARG HOST_HOME

# Set DEVCONTAINER environment variable to help with orientation
ENV DEVCONTAINER=true

# Create a non-root user (following Claude Code pattern)
ARG USERNAME=rubydev
ARG USER_UID=1001
ARG USER_GID=$USER_UID

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Essential build tools for Ruby gems
    build-essential \
    libpq-dev \
    libvips \
    pkg-config \
    # Network and system tools
    curl \
    wget \
    git \
    openssh-client \
    # Firewall tools (for init-firewall.sh script)
    iptables \
    ipset \
    # Additional utilities from Claude Code setup
    sudo \
    zsh \
    fzf \
    jq \
    ca-certificates \
    locales \
    locales-all \
    # Node.js for potential frontend needs
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/*

# Create the non-root user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Install git-delta (from Claude Code setup)
RUN ARCH=$(dpkg --print-architecture) && \
    wget "https://github.com/dandavison/delta/releases/download/0.18.2/git-delta_0.18.2_${ARCH}.deb" && \
    dpkg -i "git-delta_0.18.2_${ARCH}.deb" && \
    rm "git-delta_0.18.2_${ARCH}.deb"

# Install Claude Code CLI (as root first, then fix permissions)
RUN npm install -g @anthropic-ai/claude-code

# Set up command history persistence (from Claude Code setup)
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
    && mkdir /commandhistory \
    && touch /commandhistory/.bash_history \
    && chown -R $USERNAME /commandhistory

# Create workspace and config directories
RUN mkdir -p /workspace /home/$USERNAME/.claude /home/$USERNAME/.bundle \
    && chown -R $USERNAME:$USERNAME /workspace /home/$USERNAME/.claude /home/$USERNAME/.bundle

# Set working directory
WORKDIR /workspace

# Copy Gemfile and Gemfile.lock for better Docker layer caching
COPY Gemfile Gemfile.lock *.gemspec ./
COPY lib/sequelizer/version.rb ./lib/sequelizer/version.rb

# Switch to non-root user before gem installation
USER $USERNAME

# Set up ZSH with powerline10k theme (from Claude Code setup)
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v1.1.5/zsh-in-docker.sh)" -- \
    -t https://github.com/romkatv/powerlevel10k \
    -a 'ZSH_THEME="powerlevel10k/powerlevel10k"' \
    -p git \
    -p ssh-agent \
    -p 'history-substring-search' \
    -a 'bindkey "\$terminfo[kcuu1]" history-substring-search-up' \
    -a 'bindkey "\$terminfo[kcud1]" history-substring-search-down'

# Configure bundler and install gems
RUN bundle config set --local path "/home/${USERNAME}/.bundle" \
    && bundle config set --local bin "/home/${USERNAME}/.bundle/bin" \
    && bundle install

# Set the default shell to zsh
ENV SHELL=/bin/zsh

COPY .devcontainer/.zshrc /home/$USERNAME/.zshrc
COPY .devcontainer/.p10k.zsh /home/$USERNAME/.p10k.zsh

# Add bundle bin to PATH
ENV PATH="/home/$USERNAME/.bundle/bin:$PATH"

# Set Ruby environment variables
ENV BUNDLE_PATH="/home/$USERNAME/.bundle"
ENV BUNDLE_BIN="/home/$USERNAME/.bundle/bin"

USER root

# Copy the credential setup scripts
COPY .devcontainer/copy-claude-credentials.sh /usr/local/bin/
COPY .devcontainer/setup-credentials.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/copy-claude-credentials.sh \
    && chmod +x /usr/local/bin/setup-credentials.sh

# Copy the firewall initialization script
COPY .devcontainer/init-firewall.sh /usr/local/bin/init-firewall.sh
RUN chmod +x /usr/local/bin/init-firewall.sh

USER $USERNAME

# Default command
CMD ["/bin/zsh"]