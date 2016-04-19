#!/bin/bash
# --------------------------------------------------
# pairwise-cmp.sh
# Use Jellyfish to run a pairwise comparison of all samples
# --------------------------------------------------

set -u

BIN="$( readlink -f -- "${0%/*}" )"
if [ -f $BIN ]; then
  BIN=$(dirname $BIN)
fi

HOST_DIR=""
QUERY_DIR=""
OUT_DIR=""
BAR="# ----------------------"

function lc() {
  wc -l $1 | cut -d ' ' -f 1
}

function HELP() {
  printf "Usage:\n  %s -s HOST_DIR -q QUERY_DIR -o OUT_DIR\n\n" \ $(basename $0)

  echo "Required Arguments:"
  echo " -s HOST_DIR (Jellyfish indexes)"
  echo " -q QUERY_DIR (k-mer files)"
  echo " -o OUT_DIR"
  echo
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
echo "PARAMS_FILE \"$PARAMS_FILE\"" >> $LOG

while getopts :m:o:q:s:h OPT; do
  case $OPT in
    h)
      HELP
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
  echo "Error: HOST_DIR \"$HOST_DIR\" is not a directory" >> $LOG
  exit 1
fi

if [[ ! -d $QUERY_DIR ]]; then
  echo "Error: QUERY_DIR \"$QUERY_DIR\" is not a directory" >> $LOG
  exit 1
fi

if [[ ! -d $OUT_DIR ]]; then
  mkdir -p $OUT_DIR
fi

JF_FILES=$(mktemp)
find $HOST_DIR -mindepth 1 -maxdepth 1 -type f -size +0c > $JF_FILES

NUM_JF_FILES=$(lc $JF_FILES)
if [ $NUM_JF_FILES -lt 1 ]; then
  echo "Error: Found no files in HOST_DIR \"$HOST_DIR\"" >> $LOG
  exit 1
fi

KMER_FILES=$(mktemp)
find $QUERY_DIR -type f -size +0c -name \*.kmer > $KMER_FILES
NUM_KMER_FILES=$(lc $KMER_FILES)

if [[ $NUM_KMER_FILES -lt 1 ]]; then
  echo "Error: Found no kmer files in QUERY_DIR \"$QUERY_DIR\"" >> $LOG
  exit 1
fi

echo $BAR                       >> $LOG
echo Settings for run:          >> $LOG
echo "HOST_DIR      $HOST_DIR"  >> $LOG
echo "QUERY_DIR     $QUERY_DIR" >> $LOG
echo "OUT_DIR       $OUT_DIR"   >> $LOG
echo $BAR                       >> $LOG
echo                            >> $LOG

# --------------------------------------------------
# Ready to go
# --------------------------------------------------
PROG=$(basename $0 ".sh")

MODE_DIR=$OUT_DIR/mode
READ_MODE_DIR=$OUT_DIR/read_mode

if [[ ! -d "$MODE_DIR" ]]; then
  echo "Making MODE_DIR \"$MODE_DIR\"" >> $LOG
  mkdir "$MODE_DIR"
fi

if [[ ! -d "$READ_MODE_DIR" ]]; then
  echo "Making READ_MODE_DIR \"$READ_MODE_DIR\"" >> $LOG
  mkdir "$READ_MODE_DIR"
fi

while read KMER_FILE; do
  KMER_BASENAME=$(basename $KMER_FILE '.kmer')
  LOC_FILE="$QUERY_DIR/${KMER_BASENAME}.loc"
  THIS_MODE_DIR=$MODE_DIR/$KMER_BASENAME
  THIS_READ_MODE_DIR=$READ_MODE_DIR/$KMER_BASENAME

  if [[ ! -d $THIS_MODE_DIR ]]; then
    mkdir $THIS_MODE_DIR
  fi

  if [[ ! -d $THIS_READ_MODE_DIR ]]; then
    mkdir $THIS_READ_MODE_DIR
  fi

  while read JF_FILE; do
    JF_BASENAME=$(basename $JF_FILE)
    MODE_FILE=$THIS_MODE_DIR/$JF_BASENAME
    READ_MODE_FILE=$THIS_READ_MODE_DIR/$JF_BASENAME

    if [[ ! -s $READ_MODE_FILE ]]; then
      echo jellyfish query -i $JF_FILE \< $KMER_FILE \| \
         $BIN/jellyfish-reduce.pl -l $LOC_FILE -o $MODE_FILE \
         -r $READ_MODE_FILE --mode-min 0 >> $PARAMS_FILE
    fi
  done < $JF_FILES
done < $KMER_FILES

# while read JF_FILE; do
#   JF_BASENAME=$(basename $JF_FILE)
#   THIS_MODE_DIR=$MODE_DIR/$JF_BASENAME
#   THIS_READ_MODE_DIR=$READ_MODE_DIR/$JF_BASENAME
# 
#   if [[ ! -d $THIS_MODE_DIR ]]; then
#     mkdir $THIS_MODE_DIR
#   fi
# 
#   if [[ ! -d $THIS_READ_MODE_DIR ]]; then
#     mkdir $THIS_READ_MODE_DIR
#   fi
# 
#   while read KMER_FILE; do
#     KMER_BASENAME=$(basename $KMER_FILE '.kmer')
#     LOC_FILE="$QUERY_DIR/${KMER_BASENAME}.loc"
#     MODE_FILE=$THIS_MODE_DIR/$KMER_BASENAME
#     READ_MODE_FILE=$THIS_READ_MODE_DIR/$KMER_BASENAME
# 
#     echo jellyfish query -i $JF_FILE \< $KMER_FILE \| \
#          $BIN/jellyfish-reduce.pl -l $LOC_FILE -o $MODE_FILE \
#          -r $READ_MODE_FILE --mode-min 0 >> $PARAMS_FILE
#   done < $KMER_FILES
# done < $JF_FILES

NUM_JOBS=$(lc $PARAMS_FILE)

if [ $NUM_JOBS -lt 1 ]; then
  echo "Error: Failed to generate Jellyfish query file." >> $LOG
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

echo "Cleaning up temp files" >> $LOG
rm $JF_FILES
rm $KMER_FILES
echo "Done" >> $LOG
