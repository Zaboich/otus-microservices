FROM alpine:3.24.2

RUN apk add --no-cache bash socat

WORKDIR /app
COPY handler.sh /app/
RUN chmod +x /app/handler.sh

EXPOSE 8000
ENTRYPOINT ["socat", "TCP-LISTEN:8000,reuseaddr,fork", "EXEC:/app/handler.sh"]