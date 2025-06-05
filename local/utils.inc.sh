#!/bin/echo This script should be sourced in a shell, not executed directly

# Filter valgrind logs and remove all records/stacktraces where X > 16 in:
# ==[0-9]+== .*in loss record X of Y
function filter_valgrind_log() {
  local input_file="${1:-valgrind-test.log}"
  local output_file="${2:-valgrind-test-filter.log}"

  awk '
  function strip_commas(s) {
      gsub(",", "", s)
      return s + 0  # force numeric
  }

  /==[0-9]+== .*in loss record [0-9,]+ of [0-9,]+/ {
      match($0, /==([0-9]+)== .*in loss record ([0-9,]+) of [0-9,]+/, m)
      record_num = strip_commas(m[2])  # cleans and converts
      if (record_num > 16) {
          skipping = 1
      } else {
          skipping = 0
          print
      }
      next
  }

  /^==[0-9]+== $/ {
      if (!skipping) print
      skipping = 0  # end of current record
      next
  }

  {
      if (!skipping) print
  }
  ' "$input_file" > "$output_file"
}


# Filter valgrind logs and remove all records/stacktraces where X > 16 in:
# ==[0-9]+== .*in loss record X of Y
# Write stacktraces with different PIDs to separate files.
function filter_valgrind_log_to_files() {
  local input_file="${1:-valgrind-test.log}"
  local output_file="${2:-valgrind-test-filter.log}"
  local max_records="${3:-16}"

  awk -v max="$max_records" -v base_out="$output_file" '
  function strip_commas(s) {
      gsub(",", "", s)
      return s + 0
  }

  function write_record(pid, lines, count, skip,    fname, i) {
      if (skip) {
          fname = "valgrind-extra-" pid ".log"
      } else {
          fname = base_out
      }
      for (i = 1; i <= count; i++) {
          print lines[i] >> fname
      }
      close(fname)
  }

  /==[0-9]+== .*in loss record [0-9,]+ of [0-9,]+/ {
      # Flush previous buffered record
      if (in_record) {
          write_record(current_pid, record_lines, lines_count, skip_record)
      }

      match($0, /==([0-9]+)== .*in loss record ([0-9,]+) of [0-9,]+/, m)
      current_pid = m[1]
      current_record_num = strip_commas(m[2])
      in_record = 1
      skip_record = (current_record_num > max)
      delete record_lines
      lines_count = 0
      record_lines[++lines_count] = $0
      next
  }

  /^==[0-9]+==\s*$/ {
      if (in_record) {
          record_lines[++lines_count] = $0
          write_record(current_pid, record_lines, lines_count, skip_record)
          in_record = 0
          lines_count = 0
          next
      }
  }

  {
      if (in_record) {
          record_lines[++lines_count] = $0
      } else {
          # Always output non-record lines (like LEAK SUMMARY)
          print >> base_out
      }
  }

  END {
      # Final flush
      if (in_record) {
          write_record(current_pid, record_lines, lines_count, skip_record)
      }
  }
  ' "$input_file"
}


# Clone git repository if REPO_DIR doesn't exist.
# Then checkout to a commit_id, a tag, or a branch.
function setup_git_repo() {
    if [ $# -ne 3 ]; then
        echo "Usage: setup_git_repo <GIT_REPO> <GIT_BRANCH/COMMIT> <REPO_DIR>"
        return 1
    fi

    local GIT_REPO=$1
    local GIT_BRANCH=$2
    local REPO_DIR=$3

    if [ ! -d "$REPO_DIR" ]; then
        echo "Cloning repository..."
        git clone "$GIT_REPO" "$REPO_DIR" || { echo "Error: git clone failed"; return 1; }
    fi

    pushd "$REPO_DIR" || { echo "Error: Cannot enter directory $REPO_DIR"; return 1; }

    git remote set-url origin "$GIT_REPO"
    git fetch --all --tags

    git reset --hard
    git clean -xdf

    # Try different checkout approaches
    if ! git checkout -B "$GIT_BRANCH" --track "origin/$GIT_BRANCH" 2>/dev/null &&
    ! git checkout "tags/$GIT_BRANCH" 2>/dev/null &&
    ! git checkout "$GIT_BRANCH" 2>/dev/null; then
        echo "Error: git checkout $GIT_BRANCH failed"
        popd
        return 1
    fi

    git submodule update --init --recursive
    popd
}


# Parses mysql-test-run.pl file and extracts the contents of the @DEFAULT_SUITES
# array (defined using 'qw(...)'). The extracted suite names are returned as
# a single comma-separated string.
function extract_default_suites() {
  local input_file=${1:-mysql-test/mysql-test-run.pl}
  local all_suites=""
  local capturing=0

  while IFS= read -r line; do
    if [[ "$capturing" == "1" ]]; then
      # Stop capturing if end of array is found
      if [[ "$line" == *");"* ]]; then
        capturing=0
        break
      fi

      # Remove leading/trailing whitespace and append
      line=$(echo "$line" | xargs)
      if [[ -n "$line" ]]; then
        all_suites+="${line} "
      fi
    fi

    # Start capturing after the DEFAULT_SUITES assignment
    if [[ "$line" == *"DEFAULT_SUITES = qw("* ]]; then
      capturing=1
    fi
  done < "$input_file"

  # Convert whitespace-separated words to comma-separated
  all_suites=$(echo "$all_suites" | xargs | tr ' ' ',')

  echo "$all_suites"
}
