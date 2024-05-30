FROM gcr.io/google.com/cloudsdktool/google-cloud-cli:477.0.0-debian_component_based AS google-cloud-sdk


FROM python:3.11.9-slim-bookworm AS base

ENV DEBCONF_NONINTERACTIVE_SEEN true
ENV DEBIAN_FRONTEND noninteractive
ENV PULZE_HOME /pulze
ENV VIRTUAL_ENV ${PULZE_HOME}/lib/venv
ENV SOURCE_DIR ${PULZE_HOME}/src
ENV PYTHONPATH ${SOURCE_DIR}
ENV PATH ${VIRTUAL_ENV}/bin:${PULZE_HOME}/bin:${PATH}

# Copy configuration
COPY etc /etc

# Install core packages
RUN apt-get update && apt-get install ca-certificates tini

# Create nonroot account
RUN groupadd --gid 65532 nonroot \
    && useradd --no-log-init --create-home \
        --uid 65532 \
        --gid 65532 \
        --shell /sbin/nologin \
        nonroot

# Create Pulze directories
RUN mkdir -p ${PULZE_HOME}/bin ${PULZE_HOME}/lib ${PULZE_HOME}/share

# Set up virtual environment
RUN python -m venv ${VIRTUAL_ENV}

# Set working directory
WORKDIR ${SOURCE_DIR}

# Set entrypoint
ENTRYPOINT [ "/usr/bin/tini", "-g", "--" ]


FROM base AS aws-cli

ARG TARGETARCH

ENV AWS_CLI_VERSION "2.15.56"

# Install AWS CLI v2
RUN <<EOT bash
  set -e
  apt-get update && apt-get install curl unzip
  mkdir -p /tmp/aws-cli
  cd /tmp/aws-cli
  case "${TARGETARCH}" in
    amd64) curl -sSL -o awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWS_CLI_VERSION}.zip ;;
    arm64) curl -sSL -o awscliv2.zip https://awscli.amazonaws.com/awscli-exe-linux-aarch64-${AWS_CLI_VERSION}.zip ;;
    *) >&2 echo "Unsupported architecture" && exit 1 ;;
  esac
  unzip awscliv2.zip
  aws/install --install-dir ${PULZE_HOME}/lib/aws-cli --bin-dir ${PULZE_HOME}/bin
  rm -rf /tmp/aws-cli
EOT


FROM base AS devtools

ENV CLOUDSDK_HOME ${PULZE_HOME}/lib/google-cloud-sdk
ENV POETRY_HOME ${PULZE_HOME}/lib/poetry
ENV POETRY_VERSION "1.8.3"
ENV POETRY_VIRTUALENVS_CREATE false
ENV PATH ${CLOUDSDK_HOME}/bin:${POETRY_HOME}/bin:${PATH}

COPY --from=aws-cli ${PULZE_HOME}/ ${PULZE_HOME}/
COPY --from=google-cloud-sdk /google-cloud-sdk ${CLOUDSDK_HOME}

# Install development tools
RUN apt-get update && apt-get install build-essential curl git make ncat tmux vim
RUN curl -sSL https://install.python-poetry.org | /usr/local/bin/python -


FROM devtools AS devenv

ONBUILD ARG UID
ONBUILD ARG GID

# Create dev user account
ONBUILD RUN test -n "${UID-}" && test -n "${GID-}"
ONBUILD RUN getent group ${GID} || groupadd --gid ${GID} dev
ONBUILD RUN useradd --non-unique --no-log-init --create-home --uid ${UID} --gid ${GID} dev \
    && chown -R ${UID}:${GID} ${VIRTUAL_ENV}


FROM node:18.15.0-bullseye-slim AS node-devtools

ENV DEBCONF_NONINTERACTIVE_SEEN true
ENV DEBIAN_FRONTEND noninteractive
ENV PULZE_HOME /pulze
ENV CYPRESS_CACHE_FOLDER ${PULZE_HOME}/share/cypress
ENV PNPM_HOME ${PULZE_HOME}/share/pnpm
ENV SOURCE_DIR ${PULZE_HOME}/src
ENV PATH ${PNPM_HOME}:${PULZE_HOME}/bin:${PATH}

# Copy configuration
COPY etc /etc

# Install core system packages (required for Cypress)
RUN apt-get update && apt-get install \
    ca-certificates \
    libgtk2.0-0 \
    libgtk-3-0 \
    libnotify-dev \
    libgconf-2-4 \
    libgbm-dev \
    libnss3 \
    libxss1 \
    libasound2 \
    libxtst6 \
    procps \
    tini \
    xauth \
    xvfb

# Install core development packages
RUN npm install -g cypress@13.6.2 pnpm@8.14.1 prettier

# Create nonroot account
RUN groupadd --gid 65532 nonroot \
    && useradd --no-log-init --create-home \
        --uid 65532 \
        --gid 65532 \
        --shell /sbin/nologin \
        nonroot

# Create Pulze directories
RUN mkdir -p ${PULZE_HOME}/bin ${PULZE_HOME}/lib ${PULZE_HOME}/share

# Set working directory
WORKDIR ${SOURCE_DIR}

# Set entrypoint
ENTRYPOINT [ "/usr/bin/tini", "-g", "--" ]


FROM node-devtools AS node-devenv

ONBUILD ARG UID
ONBUILD ARG GID

# Create dev user account
ONBUILD RUN test -n "${UID-}" && test -n "${GID-}"
ONBUILD RUN getent group ${GID} || groupadd --gid ${GID} dev
ONBUILD RUN useradd --non-unique --no-log-init --create-home --uid ${UID} --gid ${GID} dev
