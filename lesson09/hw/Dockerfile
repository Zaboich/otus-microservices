FROM alpine:3.24.2

WORKDIR /app
COPY handler.sh /app/
RUN chmod +x /app/handler.sh

EXPOSE 8000
ENTRYPOINT ["sh", "-c", "while true; do nc -lp 8000 -e /app/handler.sh; done"]