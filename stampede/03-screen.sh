#!/bin/bash

set -u

CONFIG="config.sh"

if [[ $# -eq 1 ]]; then
  CONFIG=$1
fi

if [[ ! -s $CONFIG ]]; then
  echo CONFIG \"$CONFIG\" does not exist.
  exit 1
fi

source $CONFIG

module load launcher/2.0

./scripts/screen-host.sh -q $QUERY_DIR -m $OUT_DIR/read_mode -r $OUT_DIR/rejected -a $OUT_DIR/accepted -n $MODE_MIN
