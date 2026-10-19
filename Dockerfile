# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.4.1
FROM ruby:${RUBY_VERSION}-slim AS base
WORKDIR /rails
ENV BUNDLE_DEPLOYMENT=1 BUNDLE_PATH=/usr/local/bundle BUNDLE_WITHOUT=development:test RAILS_LOG_TO_STDOUT=1
RUN apt-get update -qq && apt-get install --no-install-recommends -y curl libjemalloc2 libpq5 && rm -rf /var/lib/apt/lists/*

FROM base AS build
RUN apt-get update -qq && apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN bundle install && rm -rf /root/.bundle /usr/local/bundle/ruby/*/cache
COPY . .
RUN RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 APP_HOST=example.invalid REDIS_URL=redis://redis:6379/0 SMTP_HOST=localhost bin/rails assets:precompile

FROM base
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /rails /rails
RUN groupadd --system --gid 1000 rails && useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown rails:rails log storage tmp
USER rails
ENTRYPOINT ["/rails/bin/docker-entrypoint"]
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
