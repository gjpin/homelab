#!/bin/sh
set -eu

while :; do
  busybox nc -l -p 8080 </dev/null >/dev/null 2>&1 || true
done
