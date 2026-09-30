#!/usr/bin/env bash
set -euo pipefail

# Читаем request line: METHOD PATH PROTO
IFS= read -r METHOD PATH PROTO || exit 0

# Пропускаем заголовки до пустой строки
while IFS= read -r line; do
  line="${line%$'\r'}"
  [ -z "$line" ] && break
done

# Отрезаем query string, если есть
path="${path%%\?*}"

if [ "$METHOD" = "GET" ] && [ "$PATH" = "/test" ]; then
  code="200 OK"
  body='OK'
else
  code="404 Not Found"
  body='Not Found'
fi

printf 'HTTP/1.1 %s\r\nContent-Type: text/plain\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s' \
  "$code" "${#body}" "$body"