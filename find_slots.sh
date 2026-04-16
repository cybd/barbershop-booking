#!/usr/bin/env bash
set -euo pipefail

TOKEN="${ALTEGIO_TOKEN:?ALTEGIO_TOKEN is required}"
BASE="https://api.alteg.io/api/v1"
LOCATION_ID="${LOCATION_ID:?LOCATION_ID is required}"
ACCEPT="application/vnd.api.v2+json"

auth=(-H "Authorization: Bearer $TOKEN" -H "Accept: $ACCEPT")

usage() {
  cat <<'EOF'
Usage:
  ./find_slots.sh
  ./find_slots.sh list
  ./find_slots.sh list <staff_id>
  ./find_slots.sh list <staff_id> <service_id>

Examples:
  ./find_slots.sh list
  ./find_slots.sh list 2120229
  ./find_slots.sh list 2120229 10897803
EOF
}

fetch_staff() {
  curl -sS "${auth[@]}" "$BASE/book_staff/$LOCATION_ID"
}

fetch_services() {
  local staff_id="$1"

  curl -sS -G "${auth[@]}" \
    "$BASE/book_services/$LOCATION_ID" \
    --data-urlencode "staff_id=$staff_id"
}

fetch_service_name() {
  local staff_id="$1"

  curl -sS -G "${auth[@]}" \
    "$BASE/book_services/$LOCATION_ID" \
    --data-urlencode "staff_id=$staff_id"
}

fetch_times() {
  local staff_id="$1"
  local service_id="$2"
  local day="$3"

  curl -sS -G "${auth[@]}" \
    "$BASE/book_times/$LOCATION_ID/$staff_id/$day" \
    --data-urlencode "service_ids[]=$service_id"
}

cmd_list_staff() {
  local staff_json
  staff_json="$(fetch_staff)"

  jq -r '.data[] | "\(.id)\t\t\(.name)"' <<< "$staff_json"
}

cmd_find_staff_name() {
  local staff_json
  staff_json="$(fetch_staff)"

  jq -r --arg id $staff_id '
    .data[]
    | select((.id|tostring) == $id)
    | .name
  ' <<< $staff_json
}

cmd_list_services() {
  local staff_id="${1:?staff_id is required}"
  local service_json

  staff_name="$(cmd_find_staff_name "$staff_id")"

  echo "Staff: $staff_name"
  echo

  service_json="$(fetch_services "$staff_id")"

  jq -r '.data.services[] | "\(.id)\t\(.title)"' <<< "$service_json"
}

cmd_find_service_name() {
  local staff_id="${1:?staff_id is required}"
  local service_id="${2:?service_id is required}"

  service_json="$(fetch_services "$staff_id")"

  jq -r --arg id "$service_id" '
    .data.services[]
    | select((.id | tostring) == $id)
    | .title
  ' <<< "$service_json"

}

cmd_find_slots() {
  local staff_id="${1:?staff_id is required}"
  local service_id="${2:?service_id is required}"

  local found_any=false

  staff_name="$(cmd_find_staff_name "$staff_id")"

  service_name="$(cmd_find_service_name "$staff_id" "$service_id")"

  echo "Staff: $staff_name"
  echo "Service: $service_name"
  echo

  for offset in 0 1 2 3 4 5 6; do
    local day times_json times

    day="$(date -I -d "+$offset day")"

    times_json="$(fetch_times "$staff_id" "$service_id" "$day")"

    times="$(
      jq -r '
        if (.data | length) == 0 then
          empty
        else
          .data[].time
        end
      ' <<< "$times_json"
    )"

    if [[ -n "$times" ]]; then
      found_any=true
      echo "$day:"
      sed 's/^/  - /' <<< "$times"
    fi
  done

  if [[ "$found_any" == false ]]; then
    echo "No available slots found for the next 7 days."
  fi
}

main() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  case "$1" in
    list)
      case $# in
        1)
          cmd_list_staff
          ;;
        2)
          cmd_list_services "$2"
          ;;
        3)
          cmd_find_slots "$2" "$3"
          ;;
        *)
          echo "ERROR: invalid number of arguments for 'list'" >&2
          usage >&2
          exit 1
          ;;
      esac
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "ERROR: unknown command: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"