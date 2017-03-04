FROM python:2.7-slim

RUN apt-get update && \
  apt-get install -y --no-install-recommends cron && \
  rm -rf /var/lib/apt/lists/*

# https://pypi.python.org/pypi/rethinkdb
ENV RETHINK_VERSION 2.3.0
ENV RETHINK_HOST localhost:28015

# https://en.wikipedia.org/wiki/Cron#Overview
ENV CRON_TIME "0 4 */2 * *"

ENV DUMP_NAME dump
ENV DUMP_LIMIT 14
ENV DUMP_LOCATION /tmp/backup

RUN pip install rethinkdb==$RETHINK_VERSION

WORKDIR /app

COPY ./run.sh /app/run.sh

CMD ./run.sh
