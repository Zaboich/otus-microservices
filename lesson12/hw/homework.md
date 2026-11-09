# Решение ДЗ к lesson 12

## Образ docker 
Используется образ, подготовленный по ДЗ lesson 09 - `zaboich/minimal-http:amd64`
Образ содержим мини сервер, отвечающий на `GET /health` - `RESPONSE: {"status": "OK"}`
Образ загружен на https://hub.docker.com/r/zaboich/minimal-http

## Подготовка стенда
Для запуска кластера используется minikube на Linux машине
```shell
minikube start --driver=docker
```

Для контроллера ingress используеся helm chart ingress-nginx
### Установка ingress-nginx
```shell
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx/
helm repo update 
```
Устанавливается helm chart igress-nginx с созданием контроллера для работы в minikube --driver=docker
```shell
helm install nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace --set controller.hostPort.enabled=true --set controller.service.type=NodePort 
```

## Подготовлены манифесты
* [deployment.yaml](deployment.yaml) В манифесте объявляется Namespace - otus-microservices-12 и Deployment.
  Используется собранный образ zaboich/minimal-http:amd64.
  В спецификации указано replicas: 3, указаны readinessProbe, livenessProbe, resources requests и limits

* [service.yaml](service.yaml)
  type: ClusterIP 
  публикуется порт http = 80
* [ingress.yaml](ingress.yaml)
Особенность: добавлены два правила.  
  1. правило обрабатывает все запросы и передаёт их service minimal-http-svc, описанному в манифесте sefvice.yaml
  2. ingress-nginx должен обрабатывать регулярные выражения `/otusapp/([^/]+)/(.*)` и редиректить запросы со статусом 301. Для этого создано правило 2 и для его поддержки helm install добавлен параметр `--set controller.allowSnippetAnnotations=true`

## Создание namespace, deployment, service, ingress
kubectl apply -f deployment.yaml -f service.yaml -f ingress.yaml
kubectl config set-context --current --namespace=otus-microservices-12

## Тестирование
Коллекция Postman: [otus-lesson12.postman_collection.json](otus-lesson12.postman_collection.json)
Запуск тестов
```shell
docker run --rm --network host -v "$PWD":/etc/newman:Z docker.io/postman/newman:6-alpine run otus-lesson12.postman_collection.json  
```
Запуск напрямую
```shell
newman run otus-lesson12.postman_collection.json
```

Проверяются:
* `GET /health` -> 200, `{"status": "OK"}`
* `GET /otusapp/test/health` -> `Content-Type: application/json`, `{"status": "OK"}`
* `GET /test` -> 404, `{"status": "Not Found"}`
* `GET /otusapp/test/test` -> 404, `Content-Type: application/json`, `{"status": "Not Found"}`


## просмотр логов ingress
kubectl logs  $(kubectl get pods -n ingress-nginx | grep nginx | awk '{print $1}') -n ingress-nginx
