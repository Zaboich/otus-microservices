# Задание
* Шаг 1. Создать минимальный сервис, который:
  * отвечает на порту 8000
  * имеет HTTP-метод:
     GET /health/
     RESPONSE: {"status": "OK"}
* Шаг 2. Собрать локально образ приложения в Docker-контейнер под архитектуру AMD64.
* Запушить образ в Dockerhub
* На выходе необходимо предоставить:
  * имя репозитория и тег на Dockerhub
  * ссылку на GitHub c Dockerfile, либо приложить Dockerfile в ДЗ

# Решение
Используется образ alpine:3.24.2 (последний доступный) и штатные средства shell без установки дополнительных пакетов

Для прослушивания порта используется команда `nc -lp 8000`. Команда слушает порт 8000 и передаёт вызов обработчику - скрипту [handler.sh](./handler.sh), который проверяет содержимое запроса и если METHOD и PATH запроса совпадают с требуемыми возвращает ответ 200. В иных случаях - ответ 404.  
Важное замечание: вывод `handler.sh` передаётся как ответ команды `nc` на запрос. Поэтому логи и отладочная информация записываются в stderr ( `>&2` )
## Порядок выполнения
1. Сборка образа в контексте директории c [Dockerfile](./Dockerfile)
```shell
docker buildx build --platform linux/amd64 -t minimal-http:amd64 --load .
```
или на Linux машине 
```shell
docker build -t minimal-http:amd64 --load .
```

2. Запуск сервиса и просмотр логов
```shell
docker run --rm -d -p 8000:8000 --name testsr minimal-http:amd64 && docker logs -f testsr
```

3. Проверка работы в другом терминале
```shell
$ curl -X GET -v http://127.0.0.1:8000/health/
Note: Unnecessary use of -X or --request, GET is already inferred.
*   Trying 127.0.0.1:8000...
* Connected to 127.0.0.1 (127.0.0.1) port 8000
> GET /health/ HTTP/1.1
> Host: 127.0.0.1:8000
> User-Agent: curl/8.5.0
> Accept: */*
> 
< HTTP/1.1 200 OK
< Content-Type: application/json
< Content-Length: 17
< Connection: close
< 
* Closing connection
 {"status": "OK"}
```
4. лог запущеного контейнера testsr
```
GET /health/ HTTP/1.1
Host: 127.0.0.1:8000
User-Agent: curl/8.5.0
Accept: */*
```

### Установка тега для собранного образа и push в docker hub
```shell
docker tag minimal-http:amd64 zaboich/minimal-http:amd64
docker push zaboich/minimal-http:amd64
```
