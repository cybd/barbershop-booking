---
name: barberok
description: Find free appointment slots and book visits at the BarberOK barbershop (Kyiv) through the Altegio API. Use when the user wants to get a haircut, beard trim, shave or other barbershop service, asks which barbers/services/prices are available, asks for free time slots, or wants to book an appointment ("запиши мене на стрижку", "book a haircut tomorrow", "коли вільна Катерина").
---

# BarberOK: find slots and book

All API work goes through `./find_slots.sh` in the project root. Always run it from the project root: it loads `ALTEGIO_TOKEN` and `ALTEGIO_LOCATION_ID` from `./.env`. It needs `bash`, `curl` and `jq`.

## Commands

| Goal | Command | Output |
|---|---|---|
| List barbers | `./find_slots.sh list` | `<staff_id>\t\t<name>` per line |
| List a barber's services | `./find_slots.sh list <staff_id>` | `Staff: <name>`, then `<service_id>\t<price UAH>\t<title>` |
| Free slots, next 7 days (today included) | `./find_slots.sh list <staff_id> <service_id>` | `YYYY-MM-DD:` followed by `  - HH:MM` lines, or `No available slots found for the next 7 days.` |
| Book | `./find_slots.sh book <staff_id> <service_id> "YYYY-MM-DD HH:MM" "<fullname>" "<phone>" "<email>" ["<comment>"]` | Summary, request payload, then the API JSON response |

Notes:
- Barber names and service titles are in Ukrainian (e.g. `Катерина`, `Чоловіча стрижка`). Match the user's words loosely: "haircut" means `Чоловіча стрижка`, "beard" means `Стрижка бороди`, "Kateryna"/"Катя" means `Катерина`, and so on. If more than one match is plausible, ask the user.
- Services and prices differ between barbers, so always look up `service_id` for the chosen barber.
- The `email` argument is positional. Pass `""` if there is no email but there is a comment.
- `book` re-checks the slot itself. It exits with code 4 and `ERROR: slot not found` if the time is no longer free.

## Workflow

1. **Work out the request.** Find the barber, service, and preferred day or time. Resolve relative dates ("tomorrow", "у п'ятницю") against today's date. Slots only cover the next 7 days; for a later date, tell the user it can't be booked yet.
2. **Barber.** If the user named one, find their `staff_id` with `list`. If they said "any barber", check slots for every barber who offers that service and show the options grouped by barber.
3. **Service.** Run `list <staff_id>` and pick the matching `service_id`. If the request is vague ("щось з бородою"), show the relevant services with prices and ask the user to choose.
4. **Slots.** Run `list <staff_id> <service_id>`. Show the slots compactly, one line per day (e.g. `Вт 06.10: 10:00, 11:00, 12:00 …`). If the user asked for a time, check that it is free; if not, offer the nearest free times.
5. **Client details.** Read the defaults with `grep '^CLIENT_' .env` (do not print or read the rest of `.env`, which holds the API token). Variables: `CLIENT_NAME`, `CLIENT_PHONE`, `CLIENT_EMAIL`. Use whatever details the user gives in the request instead. If the name or phone is missing, ask for it. Phone format: `+380XXXXXXXXX`.
6. **Confirm. This step is mandatory.** Before booking, show a summary and wait for an explicit "yes":
   ```
   Барбер:  Катерина
   Послуга: Чоловіча стрижка (900 ₴)
   Час:     вівторок, 06.10.2026, 16:00
   Клієнт:  <name>, <phone>, <email>
   ```
   Never run `book` without confirmation, even if the request sounded final.
7. **Book.** Run the `book` command. Check the JSON response:
   - `"success": true`: report success with `data[0].record_id`, date and time, barber, service, cost, and the address `data[0].record.company.address`.
   - Otherwise, or on a non-zero exit code: show the error message and offer other free slots. Do not retry the same booking without asking.

## Reply style

Reply in the user's language (usually Ukrainian). Keep slot lists short. Don't dump raw JSON; summarise it.
