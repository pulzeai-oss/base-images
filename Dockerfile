FROM python:3.11.6-slim-bullseye AS base

ENV DEBCONF_NONINTERACTIVE_SEEN true
ENV DEBIAN_FRONTEND noninteractive
ENV PULZE_HOME /pulze
ENV VIRTUAL_ENV ${PULZE_HOME}/lib/venv
ENV PATH ${VIRTUAL_ENV}/bin:${POETRY_HOME}/bin:${PATH}

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

# Set entrypoint
ENTRYPOINT [ "/usr/bin/tini", "-g", "--" ]


FROM base AS devtools

ENV POETRY_HOME ${PULZE_HOME}/lib/poetry
ENV POETRY_VERSION "1.6.1"
ENV POETRY_VIRTUALENVS_CREATE false
ENV PATH ${POETRY_HOME}/bin:${PATH}

# Install development tools
RUN apt-get update && apt-get install build-essential curl git make tmux vim
RUN curl -sSL https://install.python-poetry.org | python3 -


FROM devtools AS devenv

ONBUILD ARG UID
ONBUILD ARG GID

# Create dev user account
ONBUILD RUN test -n "${UID-}" && test -n "${GID-}"
ONBUILD RUN getent group ${GID} || groupadd --gid ${GID} dev
ONBUILD RUN useradd --no-log-init --create-home --uid ${UID} --gid ${GID} dev \
    && chown -R ${UID}:${GID} ${VIRTUAL_ENV}

# Set working directory
ONBUILD ENV SOURCE_DIR ${PULZE_HOME}/src
ONBUILD WORKDIR ${SOURCE_DIR}
