# syntax=docker/dockerfile:1.4
FROM node:lts-alpine AS node_builder

WORKDIR /app
COPY ui ./
RUN if [ ! -f "/app/exported/index.html" ]; then npm install --production --prefer-offline --frozen-lockfile && npm run generate; else echo "Skipping UI build, already built."; fi

FROM python:3.13-alpine AS python_builder

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONFAULTHANDLER=1
ENV PIP_NO_CACHE_DIR=off
ENV PIP_CACHE_DIR=/root/.cache/pip
ENV UV_CACHE_DIR=/root/.cache/pip

# Install dependencies
RUN apk add --update coreutils curl gcc g++ musl-dev libffi-dev openssl-dev curl make && pip install uv

WORKDIR /opt/

COPY ./pyproject.toml ./uv.lock ./
RUN --mount=type=cache,target=/root/.cache/pip uv venv --system-site-packages --relocatable ./python && \
  VIRTUAL_ENV=/opt/python uv sync --link-mode=copy --active

FROM python:3.13-alpine

ARG TZ=UTC
ARG USER_ID=1000
ENV IN_CONTAINER=1
ENV UMASK=0002
ENV YTP_CONFIG_PATH=/config
ENV YTP_TEMP_PATH=/tmp
ENV YTP_DOWNLOAD_PATH=/downloads
ENV YTP_PORT=8081
ENV XDG_CONFIG_HOME=/config
ENV XDG_CACHE_HOME=/tmp
ENV PYDEVD_DISABLE_FILE_VALIDATION=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONFAULTHANDLER=1

RUN mkdir /config /downloads && ln -snf /usr/share/zoneinfo/${TZ} /etc/localtime && echo ${TZ} > /etc/timezone && \
  apk add --update --no-cache bash mkvtoolnix patch aria2 coreutils curl shadow sqlite tzdata libmagic ffmpeg rtmpdump fribidi && \
  groupadd -g 10000 app && \
  useradd -u 1000 -g 10000 -d /app -s /bin/bash app && \
  rm -rf /var/cache/apk/*

COPY entrypoint.sh /

RUN sed -i 's/\r$//g' /entrypoint.sh && chmod +x /entrypoint.sh

COPY --chown=app:app ./app /app/app
COPY --chown=app:app --from=node_builder /app/exported /app/ui/exported
COPY --chown=app:app --from=python_builder /opt/python /opt/python
COPY --chown=app:app --from=ghcr.io/arabcoders/alpine-mp4box /usr/bin/mp4box /usr/bin/mp4box
COPY --chown=app:app ./healthcheck.sh /usr/local/bin/healthcheck

ENV PATH="/opt/python/bin:$PATH"

RUN chown -R app:app /config /downloads && chmod +x /usr/local/bin/healthcheck /usr/bin/mp4box

VOLUME /config
VOLUME /downloads

EXPOSE 8081

USER app

WORKDIR /tmp

HEALTHCHECK --interval=10s --timeout=20s --start-period=10s --retries=3 CMD [ "/usr/local/bin/healthcheck" ]

ENTRYPOINT ["/entrypoint.sh"]

CMD ["/opt/python/bin/python", "/app/app/main.py", "--ytp-process"]
