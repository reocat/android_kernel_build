#!/bin/sh

set -e

DEST=$1
GCDA=/d/gcov

if [ -z "$DEST" ] ; then
  echo "Usage: $0 <output.tar.gz>" >&2
  exit 1
fi

export TEMPDIR=$(mktemp -d -p /data/local/tmp/)
echo "Collecting data..."
echo "-- Creating directories..."
find $GCDA -type d -exec sh -c 'mkdir -p $TEMPDIR/$0' {} \;
echo "-- Fetching .gcda files..."
find $GCDA -name '*.gcda' -exec sh -c 'cat < $0 > '$TEMPDIR'/$0' {} \;
echo "-- Fetching .gcno files.."
find $GCDA -name '*.gcno' -exec sh -c 'cp -d $0 '$TEMPDIR'/$0' {} \;
echo "-- Creating archive..."
tar -czf $DEST -C $TEMPDIR ${GCDA#/}
echo "-- Cleaning up temporary directory..."
rm -rf $TEMPDIR

echo "$DEST successfully created, copy to build system and unpack with:"
echo "  tar -xfz $DEST"
