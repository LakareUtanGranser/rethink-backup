#!/bin/bash

RETHINK_HOST=$([[ ! -z $RETHINK_HOST ]] && echo "$RETHINK_HOST" || echo "localhost:28015")
DUMP_NAME=$([[ ! -z $DUMP_NAME ]] && echo "$DUMP_NAME" || echo "dump")
DUMP_LOCATION=$([[ ! -z $DUMP_LOCATION ]] && echo "$DUMP_LOCATION" || echo "/tmp/backup")

_main() {
  if [[ ! -z $(ps aux|grep [c]ron) ]]; then
    echo "service already started"
    tail -f /var/log/backup.log
    return 0
  fi

  cat <<EOF > out
#!/bin/bash
function pdate {
  echo \$(date +%Y-%m-%dT%H:%M:%S)
  return 0
}
function einf {
  echo " > \$1 @ \$(pdate)"
  return 0
}
function eerr {
  echo "!!> \$1 @ \$(pdate)" 1>&2
  return 0
}
function estd {
  echo "  > \$1"
  return 0
}
EOF
  chmod u+x out

  source ./out

  estd "creating dump location ($DUMP_LOCATION)"
  mkdir -p $DUMP_LOCATION

  estd "generate backup script"
  cat <<EOF > backup.sh
#!/bin/bash

source ./out

FILE=$DUMP_LOCATION/$DUMP_NAME\_\$(pdate).tar.gz
ACTION="rethinkdb-dump --connect=$RETHINK_HOST --file=\$FILE"

_main() {
  einf "backup \$FILE"
  if ! \${ACTION}; then
    eerr "backup failed"
    rm -f \$FILE
    return 1
  fi

  einf "backup succeeded"

  ./cleanup.sh
  return 0
}

_main
EOF
  chmod u+x backup.sh

  estd "generate restore script"
  cat <<EOF > restore.sh
#!/bin/bash

source ./out

restore_path=\$(echo "$DUMP_LOCATION/\$(ls $DUMP_LOCATION/ -N1 | sort | tail -n 1)")
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

  ACTION="rethinkdb-restore --connect=$RETHINK_HOST \$restore_path \$force"
  einf "restore from \$restore_path"

  if \${ACTION} ;then
    einf "restore done"
    return 0
  else
    eerr "restore failed"
    return 1
  fi
}

_main
EOF
  chmod u+x restore.sh

  estd "generate cleanup script"
  cat <<EOF > cleanup.sh
#!/bin/bash

source ./out

einf "running cleanup"

while [ \$(ls $DUMP_LOCATION/ -N1 | wc -l) -gt $DUMP_LIMIT ]; do
  TO_DELETE=\$(ls $DUMP_LOCATION/ -N1 | sort | head -n 1)
  estd "removing \$TO_DELETE ..."
  rm -f $DUMP_LOCATION/\$TO_DELETE
  estd "\$TO_DELETE is removed"
done
EOF
  chmod u+x cleanup.sh

  estd "starting logger"
  touch /var/log/backup.log
  tail -f /var/log/backup.log &

  echo "$CRON_TIME /app/backup.sh >> /var/log/backup.log 2>&1" > crontab.conf

  crontab crontab.conf
  estd "running rethinkdb backups at $CRON_TIME"

  exec cron -f
  exit 0
}

_main
