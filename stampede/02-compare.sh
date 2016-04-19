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

./scripts/compare.sh -q $OUT_DIR/query/kmer -s $OUT_DIR/host/jellyfish -o $OUT_DIR 
