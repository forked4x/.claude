#!/usr/bin/env bash

BAR_WIDTH=8
SEP=" · "
FIVE_HOUR=$((5 * 3600))
SEVEN_DAY=$((7 * 86400))

ESC=$'\033'
C_GREEN="${ESC}[32m"
C_YELLOW="${ESC}[33m"
C_RED="${ESC}[31m"
C_RESET="${ESC}[0m"

input=$(cat)

if ! command -v jq >/dev/null 2>&1 || ! printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
    echo "?"
    exit 0
fi

j() { printf '%s' "$input" | jq -r "($1) // empty" 2>/dev/null; }
round() { awk "BEGIN{printf \"%d\", ($1) + 0.5}"; }

repeat() {
    local ch=$1 n=$2 i out=""
    (( n <= 0 )) && return
    for ((i = 0; i < n; i++)); do out+="$ch"; done
    printf '%s' "$out"
}

bar() {
    local filled
    filled=$(round "($1/100)*$BAR_WIDTH")
    (( filled > BAR_WIDTH )) && filled=$BAR_WIDTH
    (( filled < 0 )) && filled=0
    repeat '█' "$filled"
    repeat '░' $((BAR_WIDTH - filled))
}

humanize() {
    local s=$1
    (( s <= 0 )) && { printf '0m'; return; }
    if (( s < 3600 )); then
        printf '%dm' $(( s / 60 ))
    elif (( s < 86400 )); then
        printf '%dh%dm' $(( s / 3600 )) $(( (s % 3600) / 60 ))
    else
        printf '%dd%dh' $(( s / 86400 )) $(( (s % 86400) / 3600 ))
    fi
}

fmt_tok() {
    local n=$1
    if (( n >= 1000 )); then
        printf '%dk' $(( n / 1000 ))
    else
        printf '%d' "$n"
    fi
}

name=$(j '.model.display_name')
mid=$(j '.model.id')
name=$(printf '%s' "$name" | sed -E 's/[[:space:]]*\([^)]*\)[[:space:]]*$//')
ver=$(printf '%s' "$mid" | sed -nE 's/.*-([0-9]+)-([0-9]+)$/\1.\2/p')

model_label="?"
if [[ -n "$name" && -n "$ver" ]]; then
    if [[ "$name" == *"$ver"* ]]; then
        model_label="$name"
    else
        model_label="$name $ver"
    fi
elif [[ -n "$name" ]]; then
    model_label="$name"
elif [[ -n "$mid" ]]; then
    model_label="$mid"
fi

out="$model_label"

ctx_total=$(j '.context_window.context_window_size')
ctx_input=$(j '.context_window.current_usage | ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))')
if [[ -n "$ctx_total" && -n "$ctx_input" && "$ctx_input" != "0" ]]; then
    out+=" [$(fmt_tok "$ctx_input")/$(fmt_tok "$ctx_total")]"
fi

now=$(date +%s)

render_window() {
    local label=$1 path=$2 window=$3
    local pct reset slot remaining elapsed elapsed_pct pct_round color diff
    pct=$(j ".rate_limits.${path}.used_percentage")
    [[ -z "$pct" ]] && return

    reset=$(j ".rate_limits.${path}.resets_at")
    reset=${reset%%.*}
    elapsed_pct=""
    remaining=""
    if [[ -n "$reset" ]]; then
        remaining=$(( reset - now ))
        (( remaining < 0 )) && remaining=0
        elapsed=$(( window - remaining ))
        (( elapsed < 0 )) && elapsed=0
        (( elapsed > window )) && elapsed=$window
        elapsed_pct=$(round "100*$elapsed/$window")
    fi

    pct_round=$(round "$pct")
    color=""
    if [[ -n "$elapsed_pct" ]]; then
        diff=$(( pct_round - elapsed_pct ))
        if (( diff <= -10 )); then
            color=$C_GREEN
        elif (( diff >= 10 )); then
            color=$C_RED
        else
            color=$C_YELLOW
        fi
    fi

    slot="${label} $(bar "$pct") ${color}${pct_round}%${color:+$C_RESET}"
    if [[ -n "$reset" ]]; then
        slot+=" $(humanize "$remaining") [${elapsed_pct}%]"
    fi
    out+="${SEP}${slot}"
}

render_window "5h" "five_hour" "$FIVE_HOUR"
render_window "7d" "seven_day" "$SEVEN_DAY"

printf '%s\n' "$out"
