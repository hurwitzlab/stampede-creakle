#!/bin/bash

set -u

QUERY_DIR=""
HOST_DIR=""
MODE_MIN="1"
MER_SIZE="20"
OUT_DIR="creakle-out"
PARTITION="normal" # or "development" AKA queue
TIME="24:00:00"
GROUP="iPlant-Collabs"
RUN_STEP=""

function HELP() {
  printf "Usage:\n  %s -q INPUT_DIR -s HOST_DIR -o OUT_DIR\n\n" $(basename $0)

  echo "Required arguments:"
  echo " -q QUERY_DIR"
  echo " -s HOST_DIR"
  echo ""
  echo "Options (default in parentheses):"
  echo " -k MER_SIZE ($MER_SIZE)"
  echo " -m MODE_MIN ($MODE_MIN)"
  echo " -o OUT_DIR ($OUT_DIR)"
  echo " -g GROUP ($GROUP)"
  echo " -p PARTITION ($PARTITION)"
  echo " -t TIME ($PARTITION)"
  echo " -r RUN_STEP"
  echo ""
  exit 0
}

if [[ $# -eq 0 ]]; then
  HELP
fi

function GET_ALT_ENV() {
  env | grep $1 | sed "s/.*=//"
}

while getopts :q:g:k:m:o:p:r:s:t:h OPT; do
  case $OPT in
    q)
      QUERY_DIR="$OPTARG"
      ;;
    g)
      GROUP="$OPTARG"
      ;;
    h)
      HELP
      ;;
    k)
      MER_SIZE="$OPTARG"
      ;;
    m)
      MODE_MIN="$OPTARG"
      ;;
    o)
      OUT_DIR="$OPTARG"
      ;;
    p)
      PARTITION="$OPTARG"
      ;;
    r)
      RUN_STEP="$OPTARG"
      ;;
    s)
      HOST_DIR="$OPTARG"
      ;;
    t)
      TIME="$OPTARG"
      ;;
    :)
      echo "Error: Option -$OPTARG requires an argument."
      exit 1
      ;;
    \?)
      echo "Error: Invalid option: -${OPTARG:-""}"
      exit 1
  esac
done

#
# Check user input
#
if [[ ${#QUERY_DIR} -lt 1 ]]; then
  echo "QUERY_DIR not defined."
  exit 1
fi

if [[ ! -d $QUERY_DIR ]]; then
  echo "QUERY_DIR \"$QUERY_DIR\" does not exist."
  exit 1
fi

if [[ ${#HOST_DIR} -lt 1 ]]; then
  echo "HOST_DIR not defined."
  exit 1
fi

if [[ ! -d $HOST_DIR ]]; then
  echo "HOST_DIR \"$HOST_DIR\" does not exist."
  exit 1
fi

if [[ ! -d $OUT_DIR ]]; then
  mkdir -p $OUT_DIR
fi

if [[ $MODE_MIN -lt 1 ]]; then
  echo MODE_MIN \"$MODE_MIN\" cannot be less than 1.
  exit 1
fi

CONFIG=$$.conf
echo "export QUERY_DIR=$QUERY_DIR" > $CONFIG
echo "export HOST_DIR=$HOST_DIR"  >> $CONFIG
echo "export OUT_DIR=$OUT_DIR"    >> $CONFIG
echo "export MODE_MIN=$MODE_MIN"  >> $CONFIG
echo "export MER_SIZE=$MER_SIZE"  >> $CONFIG

echo "Run parameters:"
echo "CONFIG          $CONFIG"
echo "QUERY_DIR       $QUERY_DIR"
echo "HOST_DIR        $HOST_DIR"
echo "OUT_DIR         $OUT_DIR"
echo "MER_SIZE        $MER_SIZE"
echo "MODE_MIN        $MODE_MIN"
echo "TIME            $TIME"
echo "PARTITION       $PARTITION"
echo "GROUP           $GROUP"
echo "RUN_STEP        $RUN_STEP"

PREV_JOB_ID=0
i=0

for STEP in $(ls 0[1-9]*.sh); do
  let i++

  if [[ ${#RUN_STEP} -gt 0 ]] && [[ $(basename $STEP) != $RUN_STEP ]]; then
    continue
  fi

  #
  # Allow overrides for each job in config
  #
  THIS_PARTITION=$PARTITION

  ALT_PARTITION=$(GET_ALT_ENV "OPT_PARTITION_${i}")
  if [[ ${#ALT_PARTITION} -gt 0 ]]; then
    THIS_PARTITION=$ALT_PARTITION
  fi

  THIS_TIME=$TIME

  ALT_TIME=$(GET_ALT_ENV "OPT_TIME${i}")
  if [[ ${#ALT_TIME} -gt 0 ]]; then
    THIS_TIME=$ALT_TIME
  fi

  ARGS="-p $THIS_PARTITION -t $THIS_TIME -A $GROUP -N 1 -n 1"

  if [[ $PREV_JOB_ID -gt 0 ]]; then
    ARGS="$ARGS --dependency=afterok:$PREV_JOB_ID"
  fi

  CMD="sbatch $ARGS ./$STEP $CONFIG"
  JOB_ID=$($CMD | egrep -e "^Submitted batch job [0-9]+$" | awk '{print $NF}')

  if [[ $JOB_ID -lt 1 ]]; then 
    echo Failed to get JOB_ID from \"$CMD\"
    exit 1
  fi
  
  printf "%3d: %s [%s]\n" $i $STEP $JOB_ID

  PREV_JOB_ID=$JOB_ID
done

echo Done.
