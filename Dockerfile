FROM --platform=${BUILDPLATFORM} ruby:3.1.3-alpine3.16 AS pre-builder

LABEL maintainer="adrianoamalfi"
LABEL org.opencontainers.image.authors "Adriano Amalfi"
LABEL org.opencontainers.image.description "An opensource alternative to Intercom, Zendesk, Drift, Crisp etc. "
LABEL org.opencontainers.image.url "https://github.com/adrianoamalfi/chatwoot-multiarch-docker"
LABEL org.opencontainers.image.documentation "https://raw.githubusercontent.com/adrianoamalfi/chatwoot-multiarch-docker/main/README.md"
LABEL org.opencontainers.image.source "https://raw.githubusercontent.com/adrianoamalfi/chatwoot-multiarch-docker/main/Dockerfile"
LABEL org.opencontainers.image.version "v2.15.0"
LABEL org.opencontainers.image.base.name "ruby:3.1.3-alpine3.16"
LABEL org.opencontainers.image.licenses "MIT"


# ARG default to production settings
# For development docker-compose file overrides ARGS
ARG BUNDLE_WITHOUT="development:test"
ENV BUNDLE_WITHOUT ${BUNDLE_WITHOUT}
ENV BUNDLER_VERSION=2.1.2

ARG RAILS_SERVE_STATIC_FILES=true
ENV RAILS_SERVE_STATIC_FILES ${RAILS_SERVE_STATIC_FILES}

ARG RAILS_ENV=production
ENV RAILS_ENV ${RAILS_ENV}

ENV BUNDLE_PATH="/gems"

RUN apk add --no-cache \
    openssl \
    tar \
    build-base \
    tzdata \
    postgresql-dev \
    postgresql-client \
    nodejs \
    yarn \
    git \
  && mkdir -p /var/app \
  && gem install bundler

WORKDIR /app

RUN apk add --no-cache git
RUN git clone https://github.com/chatwoot/chatwoot.git .

# COPY --from=chatwoot/chatwoot:latest /app/Gemfile /app/Gemfile.lock ./

# natively compile grpc and protobuf to support alpine musl (dialogflow-docker workflow)
# https://github.com/googleapis/google-cloud-ruby/issues/13306
# adding xz as nokogiri was failing to build libxml
# https://github.com/chatwoot/chatwoot/issues/4045
RUN apk add --no-cache musl ruby-full ruby-dev gcc make musl-dev openssl openssl-dev g++ linux-headers xz
RUN bundle config set --local force_ruby_platform true

# Do not install development or test gems in production
RUN if [ "$RAILS_ENV" = "production" ]; then \
  bundle config set without 'development test'; bundle install -j 4 -r 3; \
  else bundle install -j 4 -r 3; \
  fi

# COPY --from=chatwoot/chatwoot:latest /app/package.json /app/yarn.lock ./
RUN yarn install

# COPY --from=chatwoot/chatwoot:latest /app /app

# creating a log directory so that image wont fail when RAILS_LOG_TO_STDOUT is false
# https://github.com/chatwoot/chatwoot/issues/701
RUN mkdir -p /app/log

# generate production assets if production environment
RUN if [ "$RAILS_ENV" = "production" ]; then \
  SECRET_KEY_BASE=precompile_placeholder RAILS_LOG_TO_STDOUT=enabled bundle exec rake assets:precompile \
  && rm -rf spec node_modules tmp/cache; \
  fi

# Remove unnecessary files
RUN rm -rf /gems/ruby/3.1.0/cache/*.gem \
  && find /gems/ruby/3.1.0/gems/ \( -name "*.c" -o -name "*.o" \) -delete

# final build stage
FROM --platform=${BUILDPLATFORM} ruby:3.1.3-alpine3.16 


ARG BUNDLE_WITHOUT="development:test"
ENV BUNDLE_WITHOUT ${BUNDLE_WITHOUT}
ENV BUNDLER_VERSION=2.1.2

ARG EXECJS_RUNTIME="Disabled"
ENV EXECJS_RUNTIME ${EXECJS_RUNTIME}

ARG RAILS_SERVE_STATIC_FILES=true
ENV RAILS_SERVE_STATIC_FILES ${RAILS_SERVE_STATIC_FILES}

ARG BUNDLE_FORCE_RUBY_PLATFORM=1
ENV BUNDLE_FORCE_RUBY_PLATFORM ${BUNDLE_FORCE_RUBY_PLATFORM}

ARG RAILS_ENV=production
ENV RAILS_ENV ${RAILS_ENV}
ENV BUNDLE_PATH="/gems"

RUN apk add --no-cache \
    openssl \
    tzdata \
    postgresql-client \
    imagemagick \
    git \
  && gem install bundler

RUN if [ "$RAILS_ENV" != "production" ]; then \
  apk add --no-cache nodejs yarn; \
  fi

COPY --from=pre-builder /gems/ /gems/
COPY --from=pre-builder /app /app

WORKDIR /app

EXPOSE 3000