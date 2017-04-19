FROM python:2.7-slim

RUN apt-get update && \
  apt-get install -y --no-install-recommends cron && \
  rm -rf /var/lib/apt/lists/*

ARG RETHINK__VERSION
ARG LOCATION

# https://pypi.python.org/pypi/rethinkdb
ENV RETHINK__HOST localhost:28015
ENV DUMP__NAME dump
ENV DUMP__LIMIT 14
ENV DUMP__LOCATION /opt/backup

# set to "true" to run backup on start
ENV RUN_ON_STARTUP false

# https://en.wikipedia.org/wiki/Cron#Overview
ENV CRON_TIME "0 4 */2 * *"

RUN pip install rethinkdb==$RETHINK__VERSION

RUN echo "$LOCATION" > /etc/timezone && \
  cp /usr/share/zoneinfo/$LOCATION /etc/localtime

ADD run.sh /opt/run.sh
RUN chmod +x /opt/run.sh

WORKDIR "/opt"

VOLUME "/opt/backup"

ENTRYPOINT "/opt/run.sh"

CMD "opt/run.sh"
