#!/bin/bash
set -euo pipefail
set +m   # ensure background jobs stay in same job-control context

# Determine the root directory based on the script location
ROOT=$(dirname "$(readlink -f "$0")")

# Optional first argument: FoXS command
FOXS_CMD="${1:-pyfoxs}"

# Directory to clear before running
CLEAR_DIR="$ROOT/carbonara_runs/humanSmarcal/fitdata"

# ========= NEW: bookkeeping for clean shutdown =========
PIDS=()
WATCHER_PID=""
cleanup() {
    echo
    echo ">>> Stopping Carbonara frontend..."
    # Stop watcher first
    if [[ -n "${WATCHER_PID}" ]]; then
        kill -INT "$WATCHER_PID" 2>/dev/null || true
        sleep 0.5
        kill -TERM "$WATCHER_PID" 2>/dev/null || true
        sleep 0.5
        kill -KILL "$WATCHER_PID" 2>/dev/null || true
    fi
    # Stop all predictor processes explicitly
    if ((${#PIDS[@]})); then
        echo ">>> Stopping predictor processes (${#PIDS[@]})"
        kill -INT  "${PIDS[@]}" 2>/dev/null || true
        sleep 1
        kill -TERM "${PIDS[@]}" 2>/dev/null || true
        sleep 1
        kill -KILL "${PIDS[@]}" 2>/dev/null || true
    fi
    echo ">>> Stopped."
    exit 0
}
trap cleanup SIGINT SIGTERM
# ======================================================

# Clear the directory
echo "Clearing directory: $CLEAR_DIR"
rm -rf "$CLEAR_DIR"/*
mkdir -p "$CLEAR_DIR"

### argv[ 1] scattering data file
ScatterFile="$ROOT/carbonara_runs/humanSmarcal/Saxs.dat"

### argv[ 2] sequence file location
fileLocs="$ROOT/carbonara_runs/humanSmarcal/"

### argv[ 3] restart tag (use to start from existing prediction)
initialCoordsFile="frompdb"

### argv[ 4] paired distances file (can be empty)
pairedPredictions="False"

### argv[ 5] fixed sections file (again can be empty)
fixedsections="$ROOT/carbonara_runs/humanSmarcal/varyingSectionSecondary1.dat"

### argv[ 6] number of structures
noStructures=1

### argv[ 7] request to apply hydrophobic covering WITHIN monomers will be a list of sections on which to apply it -- Currently not used
withinMonomerHydroCover="none"

### argv[ 8] kmin
kmin=0.01

### argv[ 9] kmax
kmax=0.2

### argv[ 10] kmax Start
kmaxStart=0.2

### argv[11] Max number of fitting steps
maxNoFitSteps=10000

### argv[12] prediction file - mol[i] in the fitting folder
predictionFile="$ROOT/carbonara_runs/humanSmarcal/fitdata"

### argv[13] scattering output file
scatterOut="$ROOT/carbonara_runs/humanSmarcal/fitdata"

### argv[14] mixture list file
mixtureFile="$ROOT/carbonara_runs/humanSmarcal/mixtureFile.dat"

### argv[15] previous fit string
prevFitStr="$ROOT/carbonara_runs/humanSmarcal/redundant"

### argv[16] log file location
logLoc="$ROOT/carbonara_runs/humanSmarcal/fitdata"

### argv[17] last line of the previous fit log
endLinePrevLog="null"

### argv[18] apply affine rotations
affineTrans="False"

### argv[19] use errors in scattering calculation
useErrors="True"

# ========= NEW: backmapping backend =========
BACKMAP_BACKEND="modeller"
CG2ALL_EXEC=""
DISULFIDE_CONSTRAINTS_FILE=""
# ===========================================

# ========= NEW: start watcher (background) =========
WATCHER_SCRIPT="$ROOT/watch_and_backmap.py"
BACKMAP_SCRIPT="$ROOT/backmap_cli.py"
WATCHER_LOG="$predictionFile/watcher.out"

if [[ ! -f "$WATCHER_SCRIPT" ]]; then
    echo "ERROR: watcher script not found: $WATCHER_SCRIPT"
    exit 1
fi
if [[ ! -f "$BACKMAP_SCRIPT" ]]; then
    echo "ERROR: backmap script not found: $BACKMAP_SCRIPT"
    exit 1
fi

WATCHER_ARGS=(
    --watch-dir "$predictionFile"
    --scenario-root "$ROOT/carbonara_runs/humanSmarcal"
    --backmap-script "$BACKMAP_SCRIPT"
    --max-backmap 3
    --no-structures "$noStructures"
    --defer-backmap-seconds 600
    --backend "$BACKMAP_BACKEND"
    --do-foxs
    --foxs-py "$FOXS_CMD"
    --saxs "$ScatterFile"
    --max-q "$kmax"
)

if [[ "$BACKMAP_BACKEND" == "cg2all" ]]; then
    WATCHER_ARGS+=(--cg2all-exec "$CG2ALL_EXEC")
fi

if [[ -n "$DISULFIDE_CONSTRAINTS_FILE" ]]; then
    WATCHER_ARGS+=(--disulfide-file "$DISULFIDE_CONSTRAINTS_FILE")
fi

python "$WATCHER_SCRIPT" "${WATCHER_ARGS[@]}" > "$WATCHER_LOG" 2>&1 &
WATCHER_PID=$!
echo "Watcher started (PID=$WATCHER_PID)"
# ==================================================

for i in {1..20}
do
    echo ""
    echo " >> Run number : $i "
    echo ""
    echo "Max number of fitting steps: " $maxNoFitSteps
    echo ""

    stdbuf -oL -eL \
    "$ROOT/build/bin/predictStructureQvary" \
        "$ScatterFile" \
        "$fileLocs" \
        "$initialCoordsFile" \
        "$pairedPredictions" \
        "$fixedsections" \
        "$noStructures" \
        "$withinMonomerHydroCover" \
        "$kmin" \
        "$kmax" \
        "$kmaxStart" \
        "$maxNoFitSteps" \
        "$predictionFile/mol$i" \
        "$scatterOut/scatter$i.dat" \
        "$mixtureFile" \
        "$prevFitStr" \
        "$logLoc/fitLog$i.dat" \
        "$endLinePrevLog" \
        "$affineTrans" \
        "$useErrors" \
        > "$predictionFile/run$i.out" 2> "$predictionFile/run$i.err" &

    PIDS+=($!)
done

echo
echo ">>> All runs launched"
echo ">>> Press Ctrl+C to stop everything"
echo

wait
