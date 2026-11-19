#!/usr/bin/env bash
# SPDX-License-Identifier: MIT-0
#
# Parallel Molecule test runner for the hifra01.utils Ansible Collection.
# Runs `molecule test` across roles and OS distributions in parallel while
# isolating container names, Molecule ephemeral directories, and Ansible
# collection caches so concurrent workers never collide.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
# Color & formatting helpers
# ---------------------------------------------------------------------------
if [[ -t 1 || "${FORCE_COLOR:-0}" == "1" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_CYAN=$'\033[36m'
else
  C_RESET=""
  C_BOLD=""
  C_DIM=""
  C_RED=""
  C_GREEN=""
  C_YELLOW=""
  C_BLUE=""
  C_CYAN=""
fi

# ---------------------------------------------------------------------------
# Matrix definitions (synced with .github/workflows/ci.yml & AGENTS.md)
# ---------------------------------------------------------------------------
ALL_DISTROS=(
  "ubuntu2204"
  "ubuntu2404"
  "ubuntu2604"
  "debian12"
  "debian13"
  "rockylinux10"
  "rockylinux9"
  "rockylinux8"
)

discover_all_roles() {
  local d role
  for d in "$REPO_ROOT"/roles/*/molecule/default/molecule.yml; do
    [[ -f "$d" ]] || continue
    role="${d#"$REPO_ROOT/roles/"}"
    role="${role%/molecule/default/molecule.yml}"
    printf '%s\n' "$role"
  done | sort
}

# Normalize OS alias -> canonical distro key
normalize_distro() {
  local input
  input="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$input" in
    ubuntu2204|ubuntu-22.04|ubuntu22|u22|jammy)
      printf 'ubuntu2204' ;;
    ubuntu2404|ubuntu-24.04|ubuntu24|u24|noble)
      printf 'ubuntu2404' ;;
    ubuntu2604|ubuntu-26.04|ubuntu26|u26|resolute)
      printf 'ubuntu2604' ;;
    debian12|debian-12|deb12|d12|bookworm)
      printf 'debian12' ;;
    debian13|debian-13|deb13|d13|trixie)
      printf 'debian13' ;;
    rockylinux10|rocky10|rocky-10|rhel10|el10|rl10)
      printf 'rockylinux10' ;;
    rockylinux9|rocky9|rocky-9|rhel9|el9|rl9)
      printf 'rockylinux9' ;;
    rockylinux8|rocky8|rocky-8|rhel8|el8|rl8)
      printf 'rockylinux8' ;;
    *)
      return 1 ;;
  esac
}

# Map canonical distro key -> container image
distro_image() {
  case "$1" in
    ubuntu2204)   printf 'geerlingguy/docker-ubuntu2204-ansible:latest' ;;
    ubuntu2404)   printf 'geerlingguy/docker-ubuntu2404-ansible:latest' ;;
    ubuntu2604)   printf 'geerlingguy/docker-ubuntu2604-ansible:latest' ;;
    debian12)     printf 'geerlingguy/docker-debian12-ansible:latest' ;;
    debian13)     printf 'geerlingguy/docker-debian13-ansible:latest' ;;
    rockylinux10) printf 'geerlingguy/docker-rockylinux10-ansible:latest' ;;
    rockylinux9)  printf 'geerlingguy/docker-rockylinux9-ansible:latest' ;;
    rockylinux8)  printf 'geerlingguy/docker-rockylinux8-ansible:latest' ;;
    *) return 1 ;;
  esac
}

# Check if a (role, distro) combination is excluded (matches ci.yml)
# Prints the skip reason and returns 0 if excluded; returns 1 if supported.
exclusion_reason() {
  local role="$1"
  local distro="$2"
  case "${role}:${distro}" in
    apt_mirror:rockylinux10|apt_mirror:rockylinux9|apt_mirror:rockylinux8)
      printf 'Debian/Ubuntu family only'
      return 0
      ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
${C_BOLD}Usage:${C_RESET} ./test-matrix.sh [OPTIONS]

Run Molecule tests across roles and OS distributions in parallel.
By default, tests all roles against all 8 CI distributions.

${C_BOLD}Selection Options:${C_RESET}
  -r, --role <roles>       Role(s) to test (comma-separated or repeated flag).
                           Default: all roles under roles/.
  -o, --os <distros>       OS distro(s) to test (comma-separated or repeated flag).
                           Supported: ubuntu2204, ubuntu2404, ubuntu2604, debian12, debian13,
                                      rockylinux10, rockylinux9, rockylinux8
                           Aliases:   u22, u24, u26, deb12, deb13, el10/rocky10, el9/rocky9, el8/rocky8
                           Default: all 8 distros.
  -c, --changed            Only test roles with files modified relative to git main/HEAD.

${C_BOLD}Execution Options:${C_RESET}
  -j, --jobs <N>           Max parallel Molecule jobs (default: 4; use 1 for sequential).
      --lint               Run yamllint and ansible-lint before running Molecule tests.
      --fail-fast          Stop scheduling new jobs as soon as any job fails.
      --no-pull            Skip pre-pulling Docker images before starting workers.
  -l, --list               Print the resolved (role x distro) test matrix and exit.
      --log-dir <path>     Directory for per-job logs (default: .molecule-logs/<timestamp>).
  -h, --help               Show this help message and exit.

${C_BOLD}Examples:${C_RESET}
  ./test-matrix.sh                                  # All roles x all OSes (4 parallel workers)
  ./test-matrix.sh -r nginx,php                     # nginx & php across all OSes
  ./test-matrix.sh -o ubuntu2404,rockylinux9        # All roles on Ubuntu 24.04 & Rocky 9
  ./test-matrix.sh -r datetime -o u24,deb12 -j 2    # datetime on Ubuntu 24.04 & Debian 12
  ./test-matrix.sh -c --lint                        # Lint + test only git-changed roles
  ./test-matrix.sh -r apt_mirror -l                 # Dry-run: preview matrix & exclusions
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
RAW_ROLES=()
RAW_DISTROS=()
CHANGED_ONLY=0
MAX_JOBS=4
RUN_LINT=0
FAIL_FAST=0
PRE_PULL=1
LIST_ONLY=0
LOG_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--role|--roles)
      [[ $# -ge 2 ]] || { echo "${C_RED}Error:${C_RESET} $1 requires an argument." >&2; exit 2; }
      RAW_ROLES+=("$2")
      shift 2
      ;;
    --role=*|--roles=*)
      RAW_ROLES+=("${1#*=}")
      shift
      ;;
    -o|--os|--distro|--distros)
      [[ $# -ge 2 ]] || { echo "${C_RED}Error:${C_RESET} $1 requires an argument." >&2; exit 2; }
      RAW_DISTROS+=("$2")
      shift 2
      ;;
    --os=*|--distro=*|--distros=*)
      RAW_DISTROS+=("${1#*=}")
      shift
      ;;
    -c|--changed)
      CHANGED_ONLY=1
      shift
      ;;
    -j|--jobs)
      [[ $# -ge 2 ]] || { echo "${C_RED}Error:${C_RESET} $1 requires a positive integer." >&2; exit 2; }
      MAX_JOBS="$2"
      shift 2
      ;;
    --jobs=*)
      MAX_JOBS="${1#*=}"
      shift
      ;;
    --lint)
      RUN_LINT=1
      shift
      ;;
    --fail-fast)
      FAIL_FAST=1
      shift
      ;;
    --no-pull)
      PRE_PULL=0
      shift
      ;;
    -l|--list|--dry-run)
      LIST_ONLY=1
      shift
      ;;
    --log-dir)
      [[ $# -ge 2 ]] || { echo "${C_RED}Error:${C_RESET} $1 requires a path." >&2; exit 2; }
      LOG_DIR="$2"
      shift 2
      ;;
    --log-dir=*)
      LOG_DIR="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "${C_RED}Error:${C_RESET} Unknown option '$1'. Run './test-matrix.sh --help' for usage." >&2
      exit 2
      ;;
  esac
done

if ! [[ "$MAX_JOBS" =~ ^[1-9][0-9]*$ ]]; then
  echo "${C_RED}Error:${C_RESET} --jobs must be a positive integer (got '$MAX_JOBS')." >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# Resolve roles and distros
# ---------------------------------------------------------------------------
AVAILABLE_ROLES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && AVAILABLE_ROLES+=("$line")
done < <(discover_all_roles)

role_exists() {
  local target="$1" r
  for r in "${AVAILABLE_ROLES[@]}"; do
    [[ "$r" == "$target" ]] && return 0
  done
  return 1
}

array_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

SELECTED_ROLES=()
if [[ ${#RAW_ROLES[@]} -gt 0 ]]; then
  for entry in "${RAW_ROLES[@]}"; do
    IFS=',' read -r -a parts <<< "$entry"
    for part in "${parts[@]}"; do
      part="$(printf '%s' "$part" | tr -d '[:space:]')"
      [[ -z "$part" ]] && continue
      if [[ "$part" == "all" ]]; then
        SELECTED_ROLES=("${AVAILABLE_ROLES[@]}")
        break 2
      fi
      if ! role_exists "$part"; then
        echo "${C_RED}Error:${C_RESET} Unknown role '$part'. Available roles: ${AVAILABLE_ROLES[*]}" >&2
        exit 2
      fi
      if [[ ${#SELECTED_ROLES[@]} -eq 0 ]] || ! array_contains "$part" "${SELECTED_ROLES[@]}"; then
        SELECTED_ROLES+=("$part")
      fi
    done
  done
elif [[ "$CHANGED_ONLY" -eq 1 ]]; then
  base_ref="HEAD"
  if git rev-parse --verify main >/dev/null 2>&1; then
    merge_base="$(git merge-base HEAD main 2>/dev/null || true)"
    [[ -n "$merge_base" ]] && base_ref="$merge_base"
  fi
  changed_files="$(
    {
      git diff --name-only "$base_ref" 2>/dev/null || true
      git diff --name-only --cached 2>/dev/null || true
      git ls-files --others --exclude-standard 2>/dev/null || true
    } | sort -u
  )"
  for r in "${AVAILABLE_ROLES[@]}"; do
    if printf '%s\n' "$changed_files" | grep -q "^roles/${r}/"; then
      SELECTED_ROLES+=("$r")
    fi
  done
  if [[ ${#SELECTED_ROLES[@]} -eq 0 ]]; then
    echo "${C_YELLOW}No changed roles detected relative to ${base_ref}.${C_RESET}"
    exit 0
  fi
else
  SELECTED_ROLES=("${AVAILABLE_ROLES[@]}")
fi

SELECTED_DISTROS=()
if [[ ${#RAW_DISTROS[@]} -gt 0 ]]; then
  for entry in "${RAW_DISTROS[@]}"; do
    IFS=',' read -r -a parts <<< "$entry"
    for part in "${parts[@]}"; do
      part="$(printf '%s' "$part" | tr -d '[:space:]')"
      [[ -z "$part" ]] && continue
      if [[ "$part" == "all" ]]; then
        SELECTED_DISTROS=("${ALL_DISTROS[@]}")
        break 2
      fi
      if ! canon="$(normalize_distro "$part")"; then
        echo "${C_RED}Error:${C_RESET} Unknown OS distro '$part'. Supported: ${ALL_DISTROS[*]}" >&2
        exit 2
      fi
      if [[ ${#SELECTED_DISTROS[@]} -eq 0 ]] || ! array_contains "$canon" "${SELECTED_DISTROS[@]}"; then
        SELECTED_DISTROS+=("$canon")
      fi
    done
  done
else
  SELECTED_DISTROS=("${ALL_DISTROS[@]}")
fi

# ---------------------------------------------------------------------------
# Build the execution matrix
# ---------------------------------------------------------------------------
JOB_ROLES=()
JOB_DISTROS=()
JOB_IMAGES=()
SKIPPED_ENTRIES=()

for role in "${SELECTED_ROLES[@]}"; do
  for distro in "${SELECTED_DISTROS[@]}"; do
    if reason="$(exclusion_reason "$role" "$distro")"; then
      SKIPPED_ENTRIES+=("${role}|${distro}|${reason}")
      continue
    fi
    img="$(distro_image "$distro")"
    JOB_ROLES+=("$role")
    JOB_DISTROS+=("$distro")
    JOB_IMAGES+=("$img")
  done
done

TOTAL_JOBS=${#JOB_ROLES[@]}
TOTAL_SKIPPED=${#SKIPPED_ENTRIES[@]}

# ---------------------------------------------------------------------------
# List / dry-run mode
# ---------------------------------------------------------------------------
if [[ "$LIST_ONLY" -eq 1 ]]; then
  echo "${C_BOLD}Resolved Molecule Matrix (${TOTAL_JOBS} runnable, ${TOTAL_SKIPPED} skipped):${C_RESET}"
  echo ""
  printf "  ${C_BOLD}%-4s %-18s %-14s %-48s${C_RESET}\n" "#" "ROLE" "DISTRO" "IMAGE / NOTE"
  printf "  %-4s %-18s %-14s %-48s\n" "---" "------------------" "--------------" "------------------------------------------------"
  idx=1
  for ((i = 0; i < TOTAL_JOBS; i++)); do
    printf "  %-4s %-18s %-14s ${C_CYAN}%-48s${C_RESET}\n" "$idx" "${JOB_ROLES[$i]}" "${JOB_DISTROS[$i]}" "${JOB_IMAGES[$i]}"
    idx=$((idx + 1))
  done
  if [[ "$TOTAL_SKIPPED" -gt 0 ]]; then
    for skip in "${SKIPPED_ENTRIES[@]}"; do
      IFS='|' read -r s_role s_distro s_reason <<< "$skip"
      printf "  ${C_YELLOW}%-4s %-18s %-14s SKIP (%s)${C_RESET}\n" "-" "$s_role" "$s_distro" "$s_reason"
    done
  fi
  exit 0
fi

if [[ "$TOTAL_JOBS" -eq 0 ]]; then
  echo "${C_YELLOW}Nothing to run (${TOTAL_SKIPPED} combination(s) skipped as unsupported).${C_RESET}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Activate virtualenv & verify prerequisites
# ---------------------------------------------------------------------------
if [[ -f "$REPO_ROOT/.venv/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.venv/bin/activate"
fi

for cmd in molecule ansible-playbook docker; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "${C_RED}Error:${C_RESET} Required command '$cmd' not found in PATH." >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "${C_RED}Error:${C_RESET} Docker daemon is not running or not accessible." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Optional pre-flight lint
# ---------------------------------------------------------------------------
if [[ "$RUN_LINT" -eq 1 ]]; then
  echo "${C_BOLD}==> Running yamllint & ansible-lint...${C_RESET}"
  yamllint .
  ansible-lint
  echo "${C_GREEN}==> Linting passed.${C_RESET}"
  echo ""
fi

# ---------------------------------------------------------------------------
# Setup run workspace, logs, and signal traps
# ---------------------------------------------------------------------------
RUN_TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
RUN_ID="${RUN_TIMESTAMP}-$$"
if [[ -z "$LOG_DIR" ]]; then
  LOG_DIR="$REPO_ROOT/.molecule-logs/$RUN_TIMESTAMP"
fi
mkdir -p "$LOG_DIR"

WORK_ROOT="${TMPDIR:-/tmp}/molecule-hifra01-utils-${RUN_ID}"
STATUS_DIR="$WORK_ROOT/status"
mkdir -p "$STATUS_DIR"

ACTIVE_PIDS=()
INTERRUPTED=0

cleanup_on_exit() {
  local exit_code=$?
  if [[ "$INTERRUPTED" -eq 1 ]]; then
    echo ""
    echo "${C_YELLOW}==> Interrupted! Stopping active Molecule workers and cleaning up containers...${C_RESET}"
    local pid
    for pid in "${ACTIVE_PIDS[@]:-}"; do
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null || true
      fi
    done
    wait 2>/dev/null || true

    # Remove any leftover containers created by this run
    local containers
    containers="$(docker ps -aq --filter "name=${RUN_ID}" 2>/dev/null || true)"
    if [[ -n "$containers" ]]; then
      # shellcheck disable=SC2086
      docker rm -f $containers >/dev/null 2>&1 || true
    fi
  fi
  rm -rf "$WORK_ROOT" 2>/dev/null || true
  return "$exit_code"
}

handle_interrupt() {
  INTERRUPTED=1
  exit 130
}

trap cleanup_on_exit EXIT
trap handle_interrupt INT TERM

# ---------------------------------------------------------------------------
# Pre-pull unique Docker images so workers don't race on `docker pull`
# ---------------------------------------------------------------------------
if [[ "$PRE_PULL" -eq 1 ]]; then
  UNIQUE_IMAGES=()
  for img in "${JOB_IMAGES[@]}"; do
    if [[ ${#UNIQUE_IMAGES[@]} -eq 0 ]] || ! array_contains "$img" "${UNIQUE_IMAGES[@]}"; then
      UNIQUE_IMAGES+=("$img")
    fi
  done

  echo "${C_BOLD}==> Checking/pulling ${#UNIQUE_IMAGES[@]} Docker image(s)...${C_RESET}"
  for img in "${UNIQUE_IMAGES[@]}"; do
    if docker image inspect "$img" >/dev/null 2>&1; then
      echo "  ${C_DIM}[cached]${C_RESET} $img"
    else
      echo "  ${C_CYAN}[pull]${C_RESET}   $img"
      docker pull -q "$img" >/dev/null
    fi
  done
  echo ""
fi

# ---------------------------------------------------------------------------
# Worker function
# ---------------------------------------------------------------------------
run_molecule_job() {
  local idx="$1"
  local role="$2"
  local distro="$3"
  local image="$4"

  local job_key="${role}-${distro}"
  local job_work="$WORK_ROOT/jobs/${job_key}"
  local ephem_dir="$job_work/ephemeral"
  local ansible_home="$job_work/ansible_home"
  local log_file="$LOG_DIR/${job_key}.log"
  local status_file="$STATUS_DIR/${idx}.status"

  # Sanitize names for Docker containers (alphanumeric, _, -)
  local safe_role="${role//[^a-zA-Z0-9_-]/-}"
  local suffix="-${safe_role}-${distro}-${RUN_ID}"
  local instance_name="instance${suffix}"

  mkdir -p "$ephem_dir" "$ansible_home/collections" "$ansible_home/roles"

  # Seed already-installed external collections (community.docker, ansible.posix, etc.)
  # so ansible-galaxy inside the isolated worker doesn't need to re-download them.
  local host_ansible_cols="${HOME}/.ansible/collections/ansible_collections"
  if [[ -d "$host_ansible_cols" ]]; then
    mkdir -p "$ansible_home/collections/ansible_collections"
    local ns_path ns_name
    for ns_path in "$host_ansible_cols"/*; do
      [[ -e "$ns_path" ]] || continue
      ns_name="$(basename "$ns_path")"
      [[ "$ns_name" == "hifra01" ]] && continue
      ln -s "$ns_path" "$ansible_home/collections/ansible_collections/$ns_name" 2>/dev/null || true
    done
  fi

  local start_ts end_ts duration rc
  start_ts="$(date +%s)"

  printf "  ${C_BLUE}[START]${C_RESET} (%d/%d) %-18s %-14s\n" \
    "$((idx + 1))" "$TOTAL_JOBS" "$role" "$distro"

  set +e
  (
    cd "$REPO_ROOT/roles/$role"
    export MOLECULE_DISTRO="$image"
    export MOLECULE_INSTANCE_NAME="$instance_name"
    export MOLECULE_INSTANCE_SUFFIX="$suffix"
    export MOLECULE_EPHEMERAL_DIRECTORY="$ephem_dir"
    export ANSIBLE_HOME="$ansible_home"
    export ANSIBLE_COLLECTIONS_PATH="$ansible_home/collections"
    export PY_COLORS="1"
    export ANSIBLE_FORCE_COLOR="1"
    molecule test
  ) >"$log_file" 2>&1
  rc=$?
  set -e

  # Best-effort container cleanup in case molecule crashed before destroy
  local leftover
  leftover="$(docker ps -aq --filter "name=${suffix}" 2>/dev/null || true)"
  if [[ -n "$leftover" ]]; then
    # shellcheck disable=SC2086
    docker rm -f $leftover >/dev/null 2>&1 || true
  fi

  end_ts="$(date +%s)"
  duration=$((end_ts - start_ts))

  if [[ "$rc" -eq 0 ]]; then
    printf 'PASS|%s|%s|%s|%s\n' "$role" "$distro" "$duration" "$log_file" >"$status_file"
    printf "  ${C_GREEN}[PASS]${C_RESET}  (%d/%d) %-18s %-14s ${C_DIM}(%ds)${C_RESET}\n" \
      "$((idx + 1))" "$TOTAL_JOBS" "$role" "$distro" "$duration"
  else
    printf 'FAIL|%s|%s|%s|%s\n' "$role" "$distro" "$duration" "$log_file" >"$status_file"
    printf "  ${C_RED}[FAIL]${C_RESET}  (%d/%d) %-18s %-14s ${C_DIM}(%ds)${C_RESET} -> %s\n" \
      "$((idx + 1))" "$TOTAL_JOBS" "$role" "$distro" "$duration" "${log_file#"$REPO_ROOT/"}"
  fi

  return "$rc"
}

# ---------------------------------------------------------------------------
# Parallel scheduler loop
# ---------------------------------------------------------------------------
echo "${C_BOLD}==> Running ${TOTAL_JOBS} Molecule test job(s) with max ${MAX_JOBS} parallel worker(s)${C_RESET}"
echo "    Roles:   ${SELECTED_ROLES[*]}"
echo "    Distros: ${SELECTED_DISTROS[*]}"
echo "    Logs:    ${LOG_DIR#"$REPO_ROOT/"}/"
if [[ "$TOTAL_SKIPPED" -gt 0 ]]; then
  for skip in "${SKIPPED_ENTRIES[@]}"; do
    IFS='|' read -r s_role s_distro s_reason <<< "$skip"
    printf "  ${C_YELLOW}[SKIP]${C_RESET}  %-18s %-14s (%s)\n" "$s_role" "$s_distro" "$s_reason"
  done
fi
echo ""

SUITE_START_TS="$(date +%s)"
ABORT_SCHEDULING=0

reap_finished_pids() {
  local still_running=()
  local pid
  for pid in "${ACTIVE_PIDS[@]:-}"; do
    [[ -z "$pid" ]] && continue
    if kill -0 "$pid" 2>/dev/null; then
      still_running+=("$pid")
    else
      if ! wait "$pid" 2>/dev/null; then
        if [[ "$FAIL_FAST" -eq 1 ]]; then
          ABORT_SCHEDULING=1
        fi
      fi
    fi
  done
  ACTIVE_PIDS=("${still_running[@]:-}")
}

for ((i = 0; i < TOTAL_JOBS; i++)); do
  # Wait until a worker slot is free
  while [[ ${#ACTIVE_PIDS[@]} -ge "$MAX_JOBS" ]]; do
    reap_finished_pids
    if [[ "$ABORT_SCHEDULING" -eq 1 ]]; then
      break 2
    fi
    if [[ ${#ACTIVE_PIDS[@]} -ge "$MAX_JOBS" ]]; then
      sleep 0.3
    fi
  done

  if [[ "$ABORT_SCHEDULING" -eq 1 ]]; then
    break
  fi

  run_molecule_job "$i" "${JOB_ROLES[$i]}" "${JOB_DISTROS[$i]}" "${JOB_IMAGES[$i]}" &
  ACTIVE_PIDS+=("$!")
done

# Wait for remaining active workers
for pid in "${ACTIVE_PIDS[@]:-}"; do
  [[ -n "$pid" ]] && { wait "$pid" 2>/dev/null || true; }
done
ACTIVE_PIDS=()

SUITE_END_TS="$(date +%s)"
SUITE_DURATION=$((SUITE_END_TS - SUITE_START_TS))

# ---------------------------------------------------------------------------
# Summary report
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0
FAILED_LOGS=()

echo ""
echo "${C_BOLD}================================================================================${C_RESET}"
printf "${C_BOLD}%-10s %-20s %-16s %-10s %s${C_RESET}\n" "STATUS" "ROLE" "DISTRO" "DURATION" "LOG / REASON"
echo "--------------------------------------------------------------------------------"

for ((i = 0; i < TOTAL_JOBS; i++)); do
  status_file="$STATUS_DIR/${i}.status"
  if [[ -f "$status_file" ]]; then
    IFS='|' read -r st r_role r_distro r_dur r_log < "$status_file"
    rel_log="${r_log#"$REPO_ROOT/"}"
    if [[ "$st" == "PASS" ]]; then
      PASS_COUNT=$((PASS_COUNT + 1))
      printf "${C_GREEN}%-10s${C_RESET} %-20s %-16s %-10s ${C_DIM}%s${C_RESET}\n" \
        "PASS" "$r_role" "$r_distro" "${r_dur}s" "$rel_log"
    else
      FAIL_COUNT=$((FAIL_COUNT + 1))
      FAILED_LOGS+=("${r_role}|${r_distro}|${r_log}")
      printf "${C_RED}%-10s${C_RESET} %-20s %-16s %-10s %s\n" \
        "FAIL" "$r_role" "$r_distro" "${r_dur}s" "$rel_log"
    fi
  else
    printf "${C_YELLOW}%-10s${C_RESET} %-20s %-16s %-10s %s\n" \
      "CANCELLED" "${JOB_ROLES[$i]}" "${JOB_DISTROS[$i]}" "-" "Skipped due to --fail-fast"
  fi
done

if [[ "$TOTAL_SKIPPED" -gt 0 ]]; then
  for skip in "${SKIPPED_ENTRIES[@]}"; do
    IFS='|' read -r s_role s_distro s_reason <<< "$skip"
    printf "${C_YELLOW}%-10s${C_RESET} %-20s %-16s %-10s %s\n" \
      "SKIP" "$s_role" "$s_distro" "-" "$s_reason"
  done
fi

echo "================================================================================"
printf "${C_BOLD}Summary:${C_RESET} ${C_GREEN}%d passed${C_RESET}, ${C_RED}%d failed${C_RESET}, ${C_YELLOW}%d skipped${C_RESET} in %ds\n" \
  "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL_SKIPPED" "$SUITE_DURATION"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo ""
  echo "${C_RED}${C_BOLD}Failed job output excerpts (last 35 lines):${C_RESET}"
  for entry in "${FAILED_LOGS[@]}"; do
    IFS='|' read -r f_role f_distro f_log <<< "$entry"
    echo ""
    echo "${C_RED}--- [FAIL] ${f_role} (${f_distro}) :: ${f_log#"$REPO_ROOT/"} ---${C_RESET}"
    tail -n 35 "$f_log" || true
  done
  exit 1
fi

exit 0
