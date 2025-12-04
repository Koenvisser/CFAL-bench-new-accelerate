#!/bin/bash

# Check if already sourced
[[ -n "${CFAL_COMMON_SOURCED:-}" ]] && return 0
CFAL_COMMON_SOURCED=1

# Names of folders containing accelerate-llvm and accelerate-llvm-native
PACKAGES=(accelerate-llvm-folds-0.5 accelerate-llvm-folds accelerate-llvm-folds-2 accelerate-llvm-folds-shards-128-0.5 accelerate-llvm-folds-shards-128 accelerate-llvm-folds-shards-128-2)
# PACKAGES=(accelerate-llvm accelerate-llvm-shard accelerate-llvm-folds accelerate-llvm-folds-shards-128 accelerate-llvm-TSS)
# PACKAGES=(accelerate-llvm-fix accelerate-llvm-folds)

BASELINE="accelerate-llvm-folds"

# Name of the accelerate-llvm variant that will be displayed in results
declare -A PKG_NAMES=(
  [accelerate-llvm]="Self Scheduling (Current)"
  [accelerate-llvm-fix]="Self Scheduling (Current)"
  [accelerate-llvm-shard]="Sharded Self Scheduling"
  [accelerate-llvm-folds]="1x Shard 1x TileSize"
  [accelerate-llvm-folds-0.5]="1x Shard 0.5x TileSize"
  [accelerate-llvm-folds-2]="1x Shard 2x TileSize"
  [accelerate-llvm-folds-shards-128]="2x Shard 1x TileSize"
  [accelerate-llvm-folds-shards-128-0.5]="2x Shard 0.5x TileSize"
  [accelerate-llvm-folds-shards-128-2]="2x Shard 2x TileSize"
  [accelerate-llvm-TSS]="Trapezoid Self Scheduling"
  [accelerate-llvm-numa]="Assist NUMA First"
)

declare -A PKG_COLORS=(
  [accelerate-llvm]="#e41a1c"
  [accelerate-llvm-fix]="#e41a1c"
  [accelerate-llvm-shard]="#377eb8"
  [accelerate-llvm-folds]="#4daf4a"
  [accelerate-llvm-folds-0.5]="#f8fc00"
  [accelerate-llvm-folds-2]="#00fcf0"
  [accelerate-llvm-folds-shards-128]="#ff7f00"
  [accelerate-llvm-folds-shards-128-0.5]="#fc00c6"
  [accelerate-llvm-folds-shards-128-2]="#fc000d"
  [accelerate-llvm-TSS]="#984ea3"
  [accelerate-llvm-numa]="#ffff33"
)

declare -A PKG_POINTTYPE=(
  [accelerate-llvm]="7"
  [accelerate-llvm-fix]="7"
  [accelerate-llvm-shard]="2"
  [accelerate-llvm-folds]="3"
  [accelerate-llvm-folds-0.5]="2"
  [accelerate-llvm-folds-2]="6"
  [accelerate-llvm-folds-shards-128]="1"
  [accelerate-llvm-folds-shards-128-0.5]="4"
  [accelerate-llvm-folds-shards-128-2]="5"
  [accelerate-llvm-TSS]="4"
  [accelerate-llvm-numa]="5"
)

CRITERION_FLAGS=""

# Thread counts to benchmark
THREAD_COUNTS=(1 4 8 12 16 20 24 28 32)
# THREAD_COUNTS=(1 3 6)

parse_flags() {
    TIMER_FALLBACK=""
    DEBUG=""
    RESUME=false
    REPLOT=false
    
    for arg in "$@"; do
        if [[ "$arg" == "--timer-fallback" ]]; then
            TIMER_FALLBACK="ghc-options:
  accelerate: -DTRACY_TIMER_FALLBACK"
        fi
        if [[ "$arg" == "--debug" && -z "$DEBUG" ]]; then
            DEBUG="flags:
  accelerate:
    debug: true"
        fi
        if [[ "$arg" == "--tracy" ]]; then
            DEBUG="flags:
  accelerate:
    debug: true
    tracy: true"
        fi
        if [[ "$arg" == "--resume" ]]; then
            RESUME=true
        fi
        if [[ "$arg" == "--replot" ]]; then
            REPLOT=true
        fi
    done
}

create_temp_stack_yaml() {
    local pkg="$1"
    local path="$2"
    local extra_packages="$3"
    local extra_deps="$4"
    local extra_flags="$5"
    
    parse_flags "$@"

    cat > temp-stack.yaml <<EOF
snapshot:
  url: https://raw.githubusercontent.com/commercialhaskell/stackage-snapshots/master/lts/21/25.yaml

$extra_flags

packages:
- .
- ../${path}accelerate
- ../$path$pkg/accelerate-llvm
- ../$path$pkg/accelerate-llvm-native
$extra_packages

extra-deps:
- monadLib-3.10.3@sha256:026ba169762e63f0fe5f5c78829808f522a28730043bc3ad9b7c146baedf709f,637
- github: tomsmeding/llvm-pretty
  commit: a253a7fc1c62f4825ffce6b2507eebc5dadff32c
- MIP-0.2.0.0
- OptDir-0.0.4
- bytestring-encoding-0.1.2.0
- acme-missiles-0.3
- git: https://github.com/commercialhaskell/stack.git
  commit: e7b331f14bcffb8367cd58fbfc8b40ec7642100a
$extra_deps

$TIMER_FALLBACK

$DEBUG
EOF
}

bench() {
    local path="$1"
    local bench_name="$2"
    local extra_packages="$3"
    local extra_deps="$4"
    local extra_flags="$5"
    local criterion_flags="$6"

    parse_flags "$@"

    mkdir -p results

    if [ "$REPLOT" = true ]; then
      # Remove old plots
      rm -f results/benchmark_*.svg
      plot_all
      return 0
    fi

    if [ "$RESUME" = false ]; then
      # Remove old results files
      rm -f results/results-*.csv
      rm -f results/benchmark_*.csv
      rm -f results/benchmark_*.svg
    fi

    if [ "$RESUME" = true ]; then
      # Check if results/results-*.csv files exist
      results_files=$(ls results/results-*.csv 2>/dev/null)
      # Check if results/benchmark_*.csv files exist
      benchmark_files=$(ls results/benchmark_*.csv 2>/dev/null)
      if [ -z "$results_files" ] && [ -n "$benchmark_files" ]; then
        echo "Skipping benchmark $bench_name, results already exist."
        return 0
      fi
    fi


    for pkg in "${PACKAGES[@]}"; do
      name="${PKG_NAMES[$pkg]}"
      
      echo "Benching $name"

      # Create temp stack.yaml
      create_temp_stack_yaml "$pkg" "$path" "$extra_packages" "$extra_deps" "$extra_flags" "$@" > temp-stack.yaml

      for threads in "${THREAD_COUNTS[@]}"; do
        if [ "$RESUME" = true ] && [ -f "results/results-$name-$threads.csv" ]; then
          echo "Skipping $name with $threads threads, already exists"
          continue
        fi

        echo "Benching with $threads threads"
        
        # Create temp file for results
        temp_result_file=$(mktemp "/tmp/results-$name-$threads.XXXXXX.csv")
        result_file="results/results-$name-$threads.csv"

        # Set thread count and run benchmark
        export ACCELERATE_LLVM_NATIVE_THREADS=$threads
        if STACK_YAML=temp-stack.yaml stack run "$bench_name" -- --csv "$temp_result_file" $criterion_flags $CRITERION_FLAGS; then
          mv "$temp_result_file" "$result_file"
        else
          rm -f "$temp_result_file"
          echo "Benchmark failed for $name with $threads threads"
          continue
        fi

        # Add thread count column to CSV
        if [ -f "$result_file" ]; then

          while IFS= read -r line; do
            line=$(echo "$line" | tr -d '\n\r')
            # Skip header line
            if [[ $line == "Name,Mean,MeanLB,MeanUB,Stddev,StddevLB,StddevUB"* ]]; then
                continue
            fi
            
            # Skip empty lines
            [[ -z "$line" ]] && continue
            
            # Extract benchmark name (first field)
            if [[ $line =~ ^\"([^\"]*)\", ]]; then
                # In case the name is in quotes
                benchmark_name="${BASH_REMATCH[1]}"
            elif [[ $line =~ ^([^,]*), ]]; then
                # In case the name is without quotes, stop at ','
                benchmark_name="${BASH_REMATCH[1]}"
            else
                echo "Error: Unable to parse benchmark name from line: $line" >&2
                exit 1
            fi
            
            file_name=$(echo "$benchmark_name" | sed 's/\//_/g' | sed 's/ /_/g')
            output_file="results/benchmark_${file_name}.csv"
            
            # Create header if this is the first time writing to this file
            if [ ! -f "$output_file" ]; then
                echo "Name,Mean,MeanLB,MeanUB,Stddev,StddevLB,StddevUB,scheduler,threads" > "$output_file"
            fi
            
            # Add the data line with package name and thread count
            printf "%s,%s,%s\n" "$line" "$name" "$threads" >> "$output_file"
        done < "$result_file"
      fi
      done

      rm temp-stack.yaml
    done

    # Clean up results files
    rm -f results/results-*-*.csv

    echo "Benchmarks results saved in results folder"

    unset ACCELERATE_LLVM_NATIVE_THREADS

    # Make pretty plots for all results
    plot_all
}

plot_all() {
  echo "Generating plots..."
  for csv_file in results/benchmark_*.csv; do
    if [ -f "$csv_file" ]; then
      plot "$csv_file"
    fi
  done
  echo "Plots saved in results folder"
}

plot() {
  local csv_file="$1"

  # Check if file exists
  if [ ! -f "$csv_file" ]; then
      echo "Error: File '$csv_file' not found!"
      exit 1
  fi

  basename=$(basename "$csv_file" .csv)
  path=$(dirname "$csv_file")
  output_file="${path}/${basename}.svg"

  # Extract title information from filename
  title=$(echo "$basename" | sed 's/_/ /g' | sed 's/benchmark //')

  # Get baseline time for 1 thread
  baseline_name="${PKG_NAMES[$BASELINE]}"
  baseline_time=$(awk -v FPAT='[^,]*|("([^"]|"")*")' -v OFS=',' -v sched="$baseline_name" \
      'NR>1 && NF>=9 && $8==sched && $9==1 { print $2; exit }' "$csv_file")

  if [ -z "$baseline_time" ] || [ "$baseline_time" == "0" ]; then
      echo "Error: Could not find baseline time for $baseline_name with 1 thread"
      exit 1
  fi

  # Create temporary data files for each scheduler
  declare -a data_files
  declare -a plot_commands

  for pkg in "${PACKAGES[@]}"; do
    name="${PKG_NAMES[$pkg]}"
    color="${PKG_COLORS[$pkg]}"
    pointtype="${PKG_POINTTYPE[$pkg]}"

    data_file=$(mktemp)
    data_files+=("$data_file")

    awk -v FPAT='[^,]*|("([^"]|"")*")' -v OFS=',' -v sched="$name" -v baseline="$baseline_time" \
        'NR>1 && NF>=9 && $8==sched { 
            speedup = baseline / $2
            speedup_lb = baseline / $3
            speedup_ub = baseline / $4
            error = (speedup_lb - speedup_ub) / 2
            print $9, speedup, error
        }' "$csv_file" > "$data_file"

    plot_commands+=("'$data_file' using 1:2:3 with errorbars linecolor rgb '$color' linewidth 2 pointtype $pointtype pointsize 1.2 title \"$name\"")
    plot_commands+=("'$data_file' using 1:2 with linespoints linecolor rgb '$color' linewidth 2 pointtype $pointtype pointsize 1.2 notitle")
  done

  gnuplot_script=$(mktemp)

  cat > "$gnuplot_script" << EOF
  set terminal svg size 600,400 enhanced font 'Arial,12'
  set output '$output_file'

  set title "$title" font 'Arial,14'
  set xlabel "Number of Threads"
  set ylabel "Speedup"

  set grid
  set key top left Left reverse  
  
  set lmargin 10
  set rmargin 3
  set tmargin 3
  set bmargin 5

  set xrange [${THREAD_COUNTS[0]}:${THREAD_COUNTS[-1]}]
  set yrange [0:*]
  set xtics ($(IFS=', '; echo "${THREAD_COUNTS[*]}"))

  set datafile sep ','
  # Plot using temporary data files
  plot $(IFS=', \\'; echo "${plot_commands[*]}")


EOF

  # Run gnuplot
  if command -v gnuplot >/dev/null 2>&1; then
      gnuplot "$gnuplot_script"
  else
      echo "Error: gnuplot not found. Please install gnuplot first."
      echo "On Ubuntu/Debian: sudo apt install gnuplot"
      exit 1
  fi

    rm "$gnuplot_script" "${data_files[@]}"
}
