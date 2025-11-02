#!/bin/bash

# Source shared configuration
source "../../accelerate_config.sh" || { echo "Failed to source accelerate_config.sh"; exit 1; }

bench "../../" "mandelbrot" "" "- colour-accelerate-0.4.0.0" "" "" "$@"
