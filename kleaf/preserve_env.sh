#!/bin/bash

sed=/bin/sed

( export -p; export -f ) | \
  # Remove the reference to PWD itself
  $sed '/PWD=/d' | \
  # Now ensure, new new PWD gets expanded
  $sed "s|$PWD|\$PWD|g"
