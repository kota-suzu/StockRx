# syntax = docker/dockerfile:1

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t my-app .
# docker run -d -p 80:80 -p 443:443 --name my-app -e RAILS_MASTER_KEY=<value from config/master.key> my-app

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.3.8
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl default-mysql-client libjemalloc2 libvips && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development"

# == Builder stage ==
FROM ruby:3.3-slim AS builder
WORKDIR /app
RUN apt-get update -qq && apt-get install -y --no-install-recommends build-essential libmariadb-dev libyaml-dev git
COPY Gemfile Gemfile.lock ./
RUN bundle install -j$(nproc)

# == Runtime stage ==
FROM ruby:3.3-slim AS runtime
WORKDIR /app
ENV RAILS_ENV=production
RUN apt-get update -qq && apt-get install -y --no-install-recommends libmariadb-dev libyaml-dev git
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . .
CMD ["bash", "-c", "bin/rails db:migrate && exec puma -C config/puma.rb"]

# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=builder /usr/local/bundle "${BUNDLE_PATH}"
COPY --from=builder /rails /rails

# Run and own only the runtime files as a non-root user for security
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start the server by default, this can be overwritten at runtime
EXPOSE 3000
CMD ["./bin/rails", "server"]
