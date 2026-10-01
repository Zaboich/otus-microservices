#!/usr/bin/env sh
set -euo pipefail

# Читаем request line: METHOD PATH PROTO
read -r METHOD PATH PROTO || exit 0
# Отрезаем query string, если есть
PATH="${PATH%%\?*}"
# убрать концевой \r
PROTO="${PROTO%$'\r'}"

echo "$METHOD $PATH $PROTO" >&2

# Пропускаем заголовки до пустой строки
while IFS= read -r line; do
  echo $line >&2
  line="${line%$'\r'}"
  [ -z "$line" ] && break
done

if [ "$METHOD" = "GET" ] && { [ "$PATH" = "/health" ] || [ "$PATH" = "/health/" ]; }; then
  code="200 OK"
  body=' {"status": "OK"}'
else
  code="404 Not Found"
  body=' {"status": "Not Found"}'
fi

printf 'HTTP/1.1 %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
  "$code" "${#body}" "$body"