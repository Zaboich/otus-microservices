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

if [ "$METHOD" = "GET" ] && { [ "$PATH" = "/test" ] || [ "$PATH" = "/test/" ]; }; then
  code="200 OK"
  body='OK'
else
  code="404 Not Found"
  body='Not Found'
fi

printf 'HTTP/1.1 %s\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
  "$code" "${#body}" "$body"