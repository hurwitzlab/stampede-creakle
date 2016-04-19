#!/bin/bash

#SBATCH -p development
#SBATCH -t 02:00:00
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -A iPlant-Collabs
#SBATCH -J count
#SBATCH -o count-%j.out

set -u

CONFIG="config.sh"

if [[ $# -eq 1 ]]; then
  CONFIG=$1
fi

source $CONFIG

module load launcher/2.0

export PATH=$PATH:./bin

./scripts/count.sh -q $QUERY_DIR -s $HOST_DIR -o $OUT_DIR -m $MER_SIZE
