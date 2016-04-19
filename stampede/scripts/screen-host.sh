#!/bin/bash
# --------------------------------------------------
# screen-host.sh
# --------------------------------------------------

set -u

BIN="$( readlink -f -- "${0%/*}" )"
if [ -f $BIN ]; then
  BIN=$(dirname $BIN)
fi

SOURCE_DIR=""
OUT_DIR=""
MODE_MIN=1
BAR="# ----------------------"

function lc() {
  wc -l $1 | cut -d ' ' -f 1
}

function HELP() {
  printf "Usage:\n  %s ARGS\n\n" \
    $(basename $0)

  echo "Required Arguments:"
  echo " -q QUERY_DIR (FASTA files to screen)"
  echo " -m MODE_DIR (read mode files for FASTA files)"
  echo " -a ACCEPTED_DIR"
  echo " -r REJECTED_DIR"
  echo
  echo "Optional arguments (defaults in parentheses)";
  echo " -n MODE_MIN ($MODE_MIN)"
  exit 0
}

if [[ $# == 0 ]]; then
  HELP
fi

PROG=$(basename "$0" ".sh")
LOG="$BIN/launcher-$PROG.log"
PARAMS_FILE="$BIN/${PROG}.params"

if [[ -e $LOG ]]; then
  rm $LOG
fi

if [[ -e $PARAMS_FILE ]]; then
  rm $PARAMS_FILE
fi

echo $BAR >> $LOG
echo "Invocation: $0 $@" >> $LOG

while getopts :a:m:n:q:r:h OPT; do
  case $OPT in
    h)
      HELP
      ;;
    a)
      ACCEPTED_DIR="$OPTARG"
      ;;
    m)
      MODE_DIR="$OPTARG"
      ;;
    n)
      MODE_MIN="$OPTARG"
      ;;
    q)
      QUERY_DIR="$OPTARG"
      ;;
    r)
      REJECTED_DIR="$OPTARG"
      ;;
    :)
      echo "Error: Option -$OPTARG requires an argument." >> $LOG
      exit 1
      ;;
    \?)
      echo "Error: Invalid option: -${OPTARG:-""}" >> $LOG
      exit 1
  esac
done

# --------------------------------------------------
# Check user input
# --------------------------------------------------

if [[ ${#QUERY_DIR} -lt 1 ]]; then
  echo "Error: No QUERY_DIR specified." >> $LOG
  exit 1
fi

if [[ ${#MODE_DIR} -lt 1 ]]; then
  echo "Error: No MODE_DIR specified." >> $LOG
  exit 1
fi

if [[ ${#ACCEPTED_DIR} -lt 1 ]]; then
  echo "Error: No ACCEPTED_DIR specified." >> $LOG
  exit 1
fi

if [[ ${#REJECTED_DIR} -lt 1 ]]; then
  echo "Error: No REJECTED_DIR specified." >> $LOG
  exit 1
fi

if [[ ! -d $QUERY_DIR ]]; then
  echo "Error: QUERY_DIR \"$QUERY_DIR\" does not exist." >> $LOG
  exit 1
fi

if [[ ! -d $MODE_DIR ]]; then
  echo "Error: MODE_DIR \"$MODE_DIR\" does not exist." >> $LOG
  exit 1
fi

QUERY_FILES=$(mktemp)
find $QUERY_DIR -type f -size +0c | sort > $QUERY_FILES

NUM_FILES=$(lc $QUERY_FILES)

if [ $NUM_FILES -lt 1 ]; then
  echo "Error: Found no files in QUERY_DIR \"$QUERY_DIR\"" >> $LOG
  exit 1
fi

echo $BAR                              >> $LOG
echo Settings for run:                 >> $LOG
echo "QUERY_DIR         $QUERY_DIR"    >> $LOG
echo "MODE_DIR          $MODE_DIR"     >> $LOG
echo "ACCEPTED_DIR      $ACCEPTED_DIR" >> $LOG
echo "REJECTED_DIR      $REJECTED_DIR" >> $LOG
echo "MODE_MIN          $MODE_MIN"     >> $LOG
echo $BAR                              >> $LOG
echo                                   >> $LOG

# --------------------------------------------------
if [[ ! -d $ACCEPTED_DIR ]]; then
  echo Making ACCEPTED_DIR \"$ACCEPTED_DIR\" >> $LOG
  mkdir -p $ACCEPTED_DIR
fi

if [[ ! -d $REJECTED_DIR ]]; then
  echo Making REJECTED_DIR \"$REJECTED_DIR\" >> $LOG
  mkdir -p $REJECTED_DIR
fi

# --------------------------------------------------
# For each query file, find all the read mode files 
# to the host indexes
# --------------------------------------------------
while read QUERY_FILE; do
  BASENAME=$(basename $QUERY_FILE)
  READ_MODE_DIR=$MODE_DIR/$BASENAME

  if [[ ! -d $READ_MODE_DIR ]]; then
    echo "Cannot find expected READ_MODE_DIR \"$READ_MODE_DIR\"" >> $LOG
    continue
  fi

  READ_MODE_FILES=$(mktemp)
  find $READ_MODE_DIR -type f -size +0c > $READ_MODE_FILES
  NUM=$(lc $READ_MODE_FILES)

  if [[ $NUM -gt 0 ]]; then 
    echo "$BIN/screen-host.pl -f $QUERY_FILE -m $READ_MODE_DIR -a $ACCEPTED_DIR -r $REJECTED_DIR -n $MODE_MIN" >> $PARAMS_FILE
  else
    echo "QUERY_FILE \"$QUERY_FILE\" has no read modes in READ_MODE_DIR \"$READ_MODE_DIR\", skipping." >> $LOG
    continue
  fi

  rm $READ_MODE_FILES
done < $QUERY_FILES

NUM_JOBS=$(lc $PARAMS_FILE)

if [[ $NUM_JOBS -lt 1 ]]; then
  echo "Error: No jobs to submit." >> $LOG
  exit 1
fi

echo "Submitting \"$NUM_JOBS\" jobs" >> $LOG

export TACC_LAUNCHER_NPHI=0
export TACC_LAUNCHER_PPN=2
export EXECUTABLE=$TACC_LAUNCHER_DIR/init_launcher
export WORKDIR=$BIN
export TACC_LAUNCHER_SCHED=interleaved

echo "Starting parallel job..." >> $LOG
echo $(date) >> $LOG
$TACC_LAUNCHER_DIR/paramrun SLURM $EXECUTABLE $WORKDIR $PARAMS_FILE
echo $(date) >> $LOG
echo "Done" >> $LOG

rm $QUERY_FILE    
