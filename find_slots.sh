#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

TOKEN="${ALTEGIO_TOKEN:?ALTEGIO_TOKEN is required}"
BASE="https://api.alteg.io/api/v1"
LOCATION_ID="${ALTEGIO_LOCATION_ID:?ALTEGIO_LOCATION_ID is required}"
ACCEPT="application/vnd.api.v2+json"

auth=(-H "Authorization: Bearer $TOKEN" -H "Accept: $ACCEPT")

usage() {
  cat <<'EOF'
Usage:
  ./find_slots.sh
  ./find_slots.sh list
  ./find_slots.sh list <staff_id>
  ./find_slots.sh list <staff_id> <service_id>
  ./find_slots.sh book <staff_id> <service_id> <date time> <fullname> <phone> <email> [comment]

Examples:
  ./find_slots.sh list
  ./find_slots.sh list 2120229
  ./find_slots.sh list 2120229 10897803
  ./find_slots.sh book 2120229 10897803 "2026-04-22 15:00" "Sergei Ivanov" "+380501234567"
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

fetch_times() {
  local staff_id="$1"
  local service_id="$2"
  local day="$3"

  curl -sS -G "${auth[@]}" \
    "$BASE/book_times/$LOCATION_ID/$staff_id/$day" \
    --data-urlencode "service_ids[]=$service_id"
}

create_booking() {
  local payload="$1"

  curl -sS -X POST "$BASE/book_record/$LOCATION_ID" \
    "${auth[@]}" \
    -H "Content-Type: application/json" \
    --data "$payload"
}

cmd_list_staff() {
  local staff_json
  staff_json="$(fetch_staff)"

  jq -r '.data[] | "\(.id)\t\t\(.name)"' <<< "$staff_json"
}

cmd_find_staff_name() {
  local staff_id="${1:?staff_id is required}"
  local staff_json
  staff_json="$(fetch_staff)"

  jq -r --arg id "$staff_id" '
    .data[]
    | select((.id|tostring) == $id)
    | .name
  ' <<< "$staff_json" | head -n1
}

cmd_list_services() {
  local staff_id="${1:?staff_id is required}"
  local service_json
  local staff_name

  staff_name="$(cmd_find_staff_name "$staff_id")"

  echo "Staff: ${staff_name:-UNKNOWN}"
  echo

  service_json="$(fetch_services "$staff_id")"

  jq -r '.data.services[] | "\(.id)\t\(.title)"' <<< "$service_json"
}

cmd_find_service_name() {
  local staff_id="${1:?staff_id is required}"
  local service_id="${2:?service_id is required}"
  local service_json

  service_json="$(fetch_services "$staff_id")"

  jq -r --arg id "$service_id" '
    .data.services[]
    | select((.id | tostring) == $id)
    | .title
  ' <<< "$service_json" | head -n1
}

date_plus_days() {
  local offset="$1"

  if date -d "+1 day" +%F >/dev/null 2>&1; then
    date -d "+$offset day" +%F
  else
    date -v+"$offset"d +%F
  fi
}

cmd_find_slots() {
  local staff_id="${1:?staff_id is required}"
  local service_id="${2:?service_id is required}"

  local found_any=false
  local staff_name service_name

  staff_name="$(cmd_find_staff_name "$staff_id")"
  service_name="$(cmd_find_service_name "$staff_id" "$service_id")"

  echo "Staff: ${staff_name:-UNKNOWN}"
  echo "Service: ${service_name:-UNKNOWN}"
  echo

  for offset in 0 1 2 3 4 5 6; do
    local day times_json times

    day="$(date_plus_days "$offset")"
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

cmd_book() {
  local staff_id="${1:?staff_id is required}"
  local service_id="${2:?service_id is required}"
  local datetime_input="${3:?datetime is required}"
  local fullname="${4:?fullname is required}"
  local phone="${5:?phone is required}"
  local email="${6:-}"
  local comment="${7:-}"

  local staff_name service_name payload response datetime

  staff_name="$(cmd_find_staff_name "$staff_id")"
  service_name="$(cmd_find_service_name "$staff_id" "$service_id")"

  if [[ -z "$staff_name" ]]; then
    echo "ERROR: staff not found for id=$staff_id" >&2
    exit 2
  fi

  if [[ -z "$service_name" ]]; then
    echo "ERROR: service not found for id=$service_id and staff_id=$staff_id" >&2
    exit 3
  fi

  datetime="$(resolve_booking_datetime "$staff_id" "$service_id" "$datetime_input")"

  if [[ -z "$datetime" ]]; then
    echo "ERROR: slot not found for '$datetime_input'" >&2
    exit 4
  fi

  payload="$(
    jq -n \
      --arg fullname "$fullname" \
      --arg phone "$phone" \
      --arg email "$email" \
      --arg comment "$comment" \
      --argjson staff_id "$staff_id" \
      --argjson service_id "$service_id" \
      --arg datetime "$datetime" '
      {
        fullname: $fullname,
        phone: $phone,
        email: $email,
        appointments: [
          {
            id: 1,
            services: [$service_id],
            staff_id: $staff_id,
            datetime: $datetime
          }
        ]
      }
      + (if $comment != "" then {comment: $comment} else {} end)
    '
  )"

  echo "Creating booking:"
  echo "Staff: $staff_name ($staff_id)"
  echo "Service: $service_name ($service_id)"
  echo "Requested: $datetime_input"
  echo "Resolved datetime: $datetime"
  echo "Client: $fullname, $phone"
  [[ -n "$email" ]] && echo "Email: $email"
  [[ -n "$comment" ]] && echo "Comment: $comment"
  echo

  echo $payload | jq

  response="$(create_booking "$payload")"

  echo "$response" | jq .
}

format_datetime() {
  local input="$1"

  if date -d "$input" +%FT%T%z >/dev/null 2>&1; then
    date -d "$input" +%FT%T%z | sed 's/\(..\)$/:\1/'
  else
    date -j -f "%Y-%m-%d %H:%M" "$input" +%FT%T%z | sed 's/\(..\)$/:\1/'
  fi
}

resolve_booking_datetime() {
  local staff_id="${1:?staff_id is required}"
  local service_id="${2:?service_id is required}"
  local input="${3:?datetime input is required}"

  local day time times_json

  day="${input%% *}"
  time="${input#* }"

  if [[ "$day" == "$time" ]]; then
    echo "ERROR: datetime must be in format 'YYYY-MM-DD HH:MM'" >&2
    exit 4
  fi

  times_json="$(fetch_times "$staff_id" "$service_id" "$day")"

  jq -r --arg time "$time" '
    .data
    | map(select(.time == $time))
    | .[0].datetime // empty
  ' <<< "$times_json"
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
    book)
      case $# in
        6|7|8)
          shift
          cmd_book "$@"
          ;;
        *)
          echo "ERROR: invalid number of arguments for 'book'" >&2
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