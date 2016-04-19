#!/bin/bash
# --------------------------------------------------
# jellyfish-count.sh
# --------------------------------------------------

set -u

BIN="$( readlink -f -- "${0%/*}" )"
if [ -f $BIN ]; then
  BIN=$(dirname $BIN)
fi

HOST_DIR=""
QUERY_DIR=""
OUT_DIR=""
MER_SIZE=20
THREADS=16
HASH_SIZE="100M"
BAR="# ----------------------"

function lc() {
  wc -l $1 | cut -d ' ' -f 1
}

function HELP() {
  printf "Usage:\n  %s -s HOST_DIR -q QUERY_DIR -o OUT_DIR\n\n" \
    $(basename $0)

  echo "Required Arguments:"
  echo " -s HOST_DIR (host files)"
  echo " -q QUERY_DIR (files to screen)"
  echo " -o OUT_DIR (where to put accepted/rejected)"
  echo
  echo "Options (default in parentheses):"
  echo " -a HASH_SIZE ($HASH_SIZE)"
  echo " -m MER_SIZE ($MER_SIZE)"
  echo " -t NUM_THREADS ($THREADS)"
  exit 0
}

if [[ $# == 0 ]]; then
  HELP
fi

PROG=$(basename "$0" ".sh")
LOG=launcher-$PROG.log
PARAMS_FILE="${PROG}.params"

if [[ -e $LOG ]]; then
  rm $LOG
fi

if [[ -e $PARAMS_FILE ]]; then
  echo Removing previous PARAMS_FILE \"$PARAMS_FILE\" >> $LOG
  rm $PARAMS_FILE
fi


echo $BAR >> $LOG
echo "Invocation: $0 $@" >> $LOG

while getopts :a:m:o:q:s:t:h OPT; do
  case $OPT in
    a)
      HASH_SIZE="$OPTARG"
      ;;
    h)
      HELP
      ;;
    m)
      MER_SIZE="$OPTARG"
      ;;
    o)
      OUT_DIR="$OPTARG"
      ;;
    q)
      QUERY_DIR="$OPTARG"
      ;;
    s)
      HOST_DIR="$OPTARG"
      ;;
    t)
      THREADS="$OPTARG"
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

if [[ ${#HOST_DIR} -lt 1 ]]; then
  echo "Error: No HOST_DIR specified." >> $LOG
  exit 1
fi

if [[ ${#QUERY_DIR} -lt 1 ]]; then
  echo "Error: No QUERY_DIR specified." >> $LOG
  exit 1
fi

if [[ ${#OUT_DIR} -lt 1 ]]; then
  echo "Error: No OUT_DIR specified." >> $LOG
  exit 1
fi

if [[ ! -d $HOST_DIR ]]; then
  echo "Error: HOST_DIR \"$HOST_DIR\" does not exist." >> $LOG
  exit 1
fi

if [[ ! -d $QUERY_DIR ]]; then
  echo "Error: QUERY_DIR \"$QUERY_DIR\" does not exist." >> $LOG
  exit 1
fi

HOST_FILES=$(mktemp)
find $HOST_DIR -mindepth 1 -maxdepth 1 -type f -size +0c | sort > $HOST_FILES

QUERY_FILES=$(mktemp)
find $QUERY_DIR -mindepth 1 -maxdepth 1 -type f -size +0c | sort > $QUERY_FILES

NUM_HOST_FILES=$(lc $HOST_FILES)
NUM_QUERY_FILES=$(lc $QUERY_FILES)

if [ $NUM_HOST_FILES -lt 1 ]; then
  echo "Error: Found no files in HOST_DIR \"$HOST_DIR\"" >> $LOG
  exit 1
fi

if [ $NUM_QUERY_FILES -lt 1 ]; then
  echo "Error: Found no files in QUERY_DIR \"$QUERY_DIR\"" >> $LOG
  exit 1
fi

echo $BAR                                     >> $LOG
echo Settings for run:                        >> $LOG
echo "HOST_DIR       $HOST_DIR"               >> $LOG
echo "QUERY_DIR      $QUERY_DIR"              >> $LOG
echo "OUT_DIR        $OUT_DIR"                >> $LOG
echo "MER_SIZE       $MER_SIZE"               >> $LOG
echo "THREADS        $THREADS"                >> $LOG
echo "HASH_SIZE      $HASH_SIZE"              >> $LOG
echo $BAR                                     >> $LOG
echo                                          >> $LOG
echo Will process \"$NUM_HOST_FILES\" files:  >> $LOG
cat -n $HOST_FILES                            >> $LOG
echo Will process \"$NUM_QUERY_FILES\" files: >> $LOG
cat -n $QUERY_FILES                           >> $LOG

# --------------------------------------------------
# Good to go, without a word to say.
# --------------------------------------------------
if [[  ! -d $OUT_DIR ]]; then
  echo Making OUT_DIR \"$OUT_DIR\" >> $LOG
  mkdir -p $OUT_DIR
fi

HOST_DIR="$OUT_DIR/host"
QUERY_DIR="$OUT_DIR/query"

HOST_JF_DIR="$HOST_DIR/jellyfish"
if [[ ! -d $HOST_JF_DIR ]]; then
  echo Making HOST_JF_DIR \"$HOST_JF_DIR\" >> $LOG
  mkdir -p $HOST_JF_DIR
fi

QUERY_KMER_DIR="$QUERY_DIR/kmer"
if [[ ! -d $QUERY_KMER_DIR ]]; then
  echo Making QUERY_KMER_DIR \"$QUERY_KMER_DIR\" >> $LOG
  mkdir -p $QUERY_KMER_DIR
fi

# --------------------------------------------------
# Index HOST with Jellyfish
# --------------------------------------------------
while read FILE; do
  BASENAME=$(basename $FILE)
  JF_FILE="$HOST_JF_DIR/$BASENAME"

  if [[ -e $JF_FILE ]]; then
    echo Host JF_FILE \"$JF_FILE\" already exists. >> $LOG
  else
    echo "jellyfish count -m $MER_SIZE -s $HASH_SIZE -t $THREADS -o $JF_FILE $FILE" >> $PARAMS_FILE
  fi
done < $HOST_FILES

# --------------------------------------------------
# Kmerize QUERY files
# --------------------------------------------------
while read FILE; do
  BASENAME=$(basename $FILE)
  KMER_FILE="$QUERY_KMER_DIR/${BASENAME}.kmer"
  LOC_FILE="$QUERY_KMER_DIR/${BASENAME}.loc"

  if [[ -e $KMER_FILE ]]; then
    echo Query KMER_FILE \"$KMER_FILE\" already exists. >> $LOG
  else
    echo "$BIN/kmerizer.pl -q -i $FILE -o $KMER_FILE -l $LOC_FILE -k $MER_SIZE" >> $PARAMS_FILE
  fi
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

rm $HOST_FILES  
rm $QUERY_FILES  
