#!/bin/bash

set -u

HOST_DIR=""
SEQ_DIR=""
OUT_DIR="$PWD/$(basename $0 '.sh')"
MER_SIZE=20
THREADS=16
MODE_MIN=2
HASH_SIZE="100M"
BAR="----------------------"
CHECK="\xE2\x9C\x93"
BIN="$( readlink -f -- "${0%/*}" )"
PATH=$BIN/../local/bin:$PATH
export LD_LIBRARY_PATH=$BIN/../local/lib:/usr/local/lib

function HELP() {
  printf "Usage:\n  %s -r REFERENCE_DIR -s SEQUENCE_DIR\n\n" \
    $(basename $0)

  echo "Required Arguments:"
  echo " -r REFERENCE_DIR (host files)"
  echo " -s SEQUENCE_DIR (files to be screened)"
  echo
  echo "Options (default in parentheses):"
  echo " -a HASH_SIZE ($HASH_SIZE)"
  echo " -m MER_SIZE ($MER_SIZE)"
  echo " -n MODE_MIN ($MODE_MIN)"
  echo " -t NUM_THREADS ($THREADS)"
  echo " -o OUT_DIR ($OUT_DIR)"
  exit 0
}

function lc() {
  wc -l $1 | cut -d ' ' -f 1
}

if [[ $# == 0 ]]; then
  HELP
fi

while getopts :a:m:n:o:r:s:t:h OPT; do
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
    n)
      MODE_MIN="$OPTARG"
      ;;
    o)
      OUT_DIR="$OPTARG"
      ;;
    r)
      HOST_DIR="$OPTARG"
      ;;
    s)
      SEQ_DIR="$OPTARG"
      ;;
    t)
      THREADS="$OPTARG"
      ;;
    :)
      echo "Option -$OPTARG requires an argument."
      exit 1
      ;;
    \?)
      echo "Invalid option: -${OPTARG:-""}"
      exit 1
  esac
done

if [[ ! -d $HOST_DIR ]]; then
  echo REFERENCE_DIR \"$HOST_DIR\" is not a directory
  exit 1
fi

if [[ ! -d $SEQ_DIR ]]; then
  echo SEQUENCE_DIR \"$SEQ_DIR\" is not a directory
  exit 1
fi

SCREENED_DIR="$OUT_DIR/screened"
REJECTED_DIR="$OUT_DIR/rejected"
HOST_JF_DIR="$OUT_DIR/jf"
KMER_DIR="$OUT_DIR/kmer"
FOUND_HOST_DIR="$OUT_DIR/host"

for DIR in "$OUT_DIR $SCREENED_DIR $REJECTED_DIR $HOST_DIR $HOST_JF_DIR $KMER_DIR $FOUND_HOST_DIR"
do
  if [[ ! -d $DIR ]]; then
    mkdir -p $DIR
  fi
done

echo Settings for run:
echo "REFERENCE_DIR $HOST_DIR"
echo "SEQUENCE_DIR  $SEQ_DIR"
echo "OUT_DIR       $OUT_DIR"
echo "SCREENED_DIR  $SCREENED_DIR"
echo "REJECTED_DIR  $REJECTED_DIR"
echo "MER_SIZE      $MER_SIZE"
echo "THREADS       $THREADS"
echo "MODE_MIN      $MODE_MIN"
echo "HASH_SIZE     $HASH_SIZE"

#
# Find host/reference files to index
#
HOST_LIST=$(mktemp)
find $HOST_DIR -type f > $HOST_LIST
NUM_HOST_FILES=$(lc $HOST_LIST)
echo Found \"$NUM_HOST_FILES\" host files

if [[ $NUM_HOST_FILES -lt 1 ]]; then
  exit 1
fi

#
# Find query files to screen
#
SEQ_LIST=$(mktemp)
find $SEQ_DIR -type f > $SEQ_LIST
NUM_SEQ_FILES=$(lc $SEQ_LIST)

echo Found \"$NUM_SEQ_FILES\" sequence files

if [[ $NUM_SEQ_FILES -lt 1 ]]; then
  exit 1
fi

#
# Create Jellyfish indexes of host
#
echo
echo Indexing host

i=0
while read FILE; do
  let i++
  BASENAME=$(basename $FILE)
  JF_FILE="$HOST_JF_DIR/$BASENAME"

  printf "%5d: %s" $i $BASENAME 

  if [[ -e $JF_FILE ]]; then
    echo " (index file exists, skipping)"
  else 
    jellyfish count -m $MER_SIZE -s $HASH_SIZE -t $THREADS -o $JF_FILE $FILE
    echo " (finished)"
  fi
done < $HOST_LIST

while read FILE; do
  BASENAME=$(basename $FILE)
  KMER_FILE="$KMER_DIR/${BASENAME}.kmer"
  LOC_FILE="$KMER_DIR/${BASENAME}.loc"
  HOST="$FOUND_HOST_DIR/$BASENAME"

  echo $BAR
  echo Processing $BASENAME 
  echo $BAR

  if [[ -e $KMER_FILE ]]; then
    echo -e $CHECK k-mer file exists
  else 
    echo -e $CHECK kmerizing
    $BIN/kmerizer.pl -q -i "$FILE" -o "$KMER_FILE" \
      -l "$LOC_FILE" -k "$MER_SIZE"
  fi

  #
  # The "host" file is what will be created in the querying
  # and will be passed to the "screen-host.pl" script
  # Null it out if it exists
  #
  cat /dev/null > $HOST

  JF_LIST=$(find $HOST_JF_DIR -type f)
  for JF in $JF_LIST; do
    echo -e $CHECK query $(basename $JF)

    #
    # Note: no "-o" output file as we only care about the $HOST file
    #
    jellyfish query -i "$JF" < "$KMER_FILE" | \
      $BIN/jellyfish-reduce.pl -l "$LOC_FILE" -u $HOST --mode-min $MODE_MIN
  done 

  NUM_HOST_HITS=$(lc $HOST)

  if [[ $NUM_HOST_HITS -lt 1 ]]; then
    echo Found no hits to host
    continue
  fi

  echo -e $CHECK found \"$NUM_HOST_HITS\" hits to host

  $BIN/screen-host.pl -h "$HOST" -o "$SCREENED_DIR" \
    -r "$REJECTED_DIR/$BASENAME" $FILE
done < $SEQ_LIST

echo Done, see SCREENED_DIR \"$SCREENED_DIR\"
