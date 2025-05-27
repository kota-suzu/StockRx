# syntax = docker/dockerfile:1

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t my-app .
# docker run -d -p 80:80 -p 443:443 --name my-app -e RAILS_MASTER_KEY=<value from config/master.key> my-app

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.3.8
FROM docker.io/library/ruby:$RUBY_VERSION-slim

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    curl \
    default-mysql-client \
    libjemalloc2 \
    libvips \
    libmariadb-dev \
    libyaml-dev \
<<<<<<< HEAD
    git && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

=======
    git \
    nodejs \
    npm \
    netcat-openbsd \
    telnet \
    dnsutils && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Create a non-root user for development
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p /usr/local/bundle && \
    chown -R rails:rails /usr/local/bundle

>>>>>>> origin/feat/claude-code-action
# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
<<<<<<< HEAD
    BUNDLE_WITHOUT="development"
=======
    BUNDLE_WITHOUT="nothing" \
    BUNDLE_FROZEN="0"
>>>>>>> origin/feat/claude-code-action

# Copy application code
COPY . .

<<<<<<< HEAD
# Install gems
RUN bundle install -j$(nproc)

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000
=======
# 権限設定
RUN chmod 666 Gemfile.lock

# Rails 7.2対応: キャッシュディレクトリの作成と権限設定
RUN mkdir -p tmp/cache tmp/cache/assets tmp/pids tmp/storage && \
    chmod -R 777 tmp/cache && \
    touch tmp/restart.txt

# Switch to the rails user for bundle install
USER rails

# Install gems
RUN bundle install -j$(nproc)

# Switch back to root for any remaining operations
USER root

# Run and own only the runtime files as a non-root user for security
RUN chown -R rails:rails db log storage tmp
USER rails
>>>>>>> origin/feat/claude-code-action

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/rails", "server"]
