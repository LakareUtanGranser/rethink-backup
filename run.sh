#!/bin/bash

set -e

RETHINK__HOST=${RETHINK__HOST:-"localhost:28015"}
DUMP__NAME=${DUMP__NAME:-"dump"}
DUMP__LOCATION=${DUMP__LOCATION:-"/tmp/backup"}
DUMP__LIMIT=${DUMP__LIMIT:-"10"}
RUN_ON_STARTUP=${RUN_ON_STARTUP:-"false"}

_main() {
  if [[ ! -z $(ps aux|grep [c]ron) ]]; then
    echo "service already started"
    tail -f /var/log/backup.log
    return 0
  fi

  mkdir -p /opt/bin

  cat <<EOF > /opt/bin/helper.sh
#!/bin/bash
function pdate {
  echo \$(date +%Y-%m-%dT%H:%M:%S)/opt/bin/
  return 0
}
function einf {
  echo " > \$1 @ \$(pdate)"
  return 0
}
function eerr {
  echo "!!> \$1 @ \$(pdate)" 1>&2
  return 1
}
function estd {
  echo "  > \$1"
  return 0
}
EOF

  chmod +x /opt/bin/helper.sh
  source /opt/bin/helper.sh

  if [[ ! -d "$DUMP__LOCATION" ]]; then
    estd "creating dump location ($DUMP__LOCATION)"
    mkdir -p $DUMP__LOCATION
  fi

  estd "generate backup script"
  cat <<EOF > /opt/bin/backup.sh
#!/bin/bash

source /opt/bin/helper.sh

dump_file=$DUMP__LOCATION/$DUMP__NAME.\$(date +%Y%m%d%H%M).tar.gz

_main() {
  _run() {
    local n=0
    local retries=2
    local status=1

    until [[ \$n -ge \$retries ]]; do
      if rethinkdb-dump --connect=$RETHINK__HOST --file=\$dump_file ; then
        status=0
        break
      fi
      ((n++))
      estd "retry \$n"
      sleep 5
    done

    return \$status
  }

  einf "backup \$dump_file"

  if ! _run ; then
    eerr "backup failed"
    rm -f \$dump_file
    return 1
  fi

  einf "backup succeeded"

  /opt/bin/cleanup.sh
  
  return 0
}

_main
EOF

  chmod +x /opt/bin/backup.sh

  estd "generate restore script"
  cat <<EOF > /opt/bin/restore.sh
#!/bin/bash

source /opt/bin/helper.sh

restore_path=""
force=""

while getopts ":f:p:" opt; do
  case "\$opt" in
    f) force="\$OPTARG" ;;
    p) restore_path="\$OPTARG" ;;
  esac
done; shift \$((OPTIND-1)); [ "\$1" = "--" ] && shift

if [[ ! -z "\$force" ]]; then
  force="--force"
fi

_main() {
  if [ -z "\$restore_path" ]; then
    eerr "path not set, use --p"
    return 1
  fi

  einf "restore from \$restore_path"

  if rethinkdb-restore --connect=$RETHINK__HOST \$restore_path \$force ;then
    einf "restore done"
    return 0
  else
    eerr "restore failed"
    return 1
  fi
}

_main
EOF

  chmod +x /opt/bin/restore.sh

  estd "generate cleanup script"
  cat <<EOF > /opt/bin/cleanup.sh
#!/bin/bash

source /opt/bin/helper.sh

einf "running cleanup"

while [ \$(ls $DUMP__LOCATION/ -N1 | wc -l) -gt $DUMP_LIMIT ]; do
  TO_DELETE=\$(ls $DUMP__LOCATION/ -N1 | sort -t . -k 2 | head -n 1)
  estd "removing \$TO_DELETE ..."
  rm -f $DUMP__LOCATION/\$TO_DELETE
  estd "\$TO_DELETE is removed"
done
EOF

  chmod +x /opt/bin/cleanup.sh

  estd "starting logger"
  touch /var/log/backup.log
  tail -f /var/log/backup.log &

  if [ "$RUN_ON_STARTUP" == "true" ]; then
    /opt/bin/backup.sh
  fi

  echo -e "$CRON_TIME /opt/bin/backup.sh >> /var/log/backup.log 2>&1" | crontab -

  estd "running postgres backups at $CRON_TIME"

  exec cron -f
  exit 0
}

_main
