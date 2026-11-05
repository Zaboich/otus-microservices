# Демонстрация: хранение данных в Kubernetes

Полный показ выполняется после теоретической части. Последовательность: общий том контейнеров → данные узла → статический PV/PVC → динамическое выделение → StatefulSet → квота → очистка.

## Подготовка стенда и файлов

### Рабочая директория и инструменты

Все локальные команды выполняются из корня проекта в PowerShell. Исключение — явно выделенные блоки внутри контейнера или SSH-сеанса Linux. Команды ниже — инструкция для запуска демонстрации, при подготовке материалов они не выполнялись.

Нужны Minikube, kubectl, работающий драйвер для Linux-узла и возможность скачать `busybox:1.37.0`. Используйте выделенный одноузловой профиль `k8s4-storage`, Kubernetes 1.32+ и namespace `k8s4-storage`. Не добавляйте узлы: учебный hostPath-provisioner здесь рассчитан на один узел.

```console
cd D:\repo\other-repo\otus-ms-k8s-4
minikube version
kubectl version --client
minikube start -p k8s4-storage --nodes=1 --cpus=2 --memory=4096
minikube addons enable storage-provisioner -p k8s4-storage
minikube addons enable default-storageclass -p k8s4-storage
kubectl --context=k8s4-storage version
kubectl --context=k8s4-storage wait --for=condition=Ready nodes --all --timeout=180s
kubectl --context=k8s4-storage get nodes
kubectl --context=k8s4-storage get storageclass
kubectl --context=k8s4-storage get storageclass standard -o yaml
kubectl --context=k8s4-storage -n kube-system get pods
kubectl --context=k8s4-storage create namespace k8s4-storage
```

Ожидается один Ready-узел, работающий `storage-provisioner`, единственный default-класс `standard` с provisioner `k8s.io/minikube-hostpath`, `reclaimPolicy: Delete`, `volumeBindingMode: Immediate`. Если эти условия не выполнены, сначала восстановите учебный профиль; не подменяйте ими настройки другого кластера. Если namespace уже существует, проверьте остатки предыдущего показа и выполните очистку в конце этого файла перед повтором.

### Исходные значения для повторного показа

Откройте три файла. Если они редактировались ранее, вручную верните значения таблицы. Начинайте в очищенном namespace, без PV `k8s4-static`, `k8s4-manual-0` и сохранённых динамических PV от предыдущего показа.

| Файл | Начальная конфигурация |
| --- | --- |
| [volumes.yaml](demo-manifests/volumes.yaml) | Deployment `volume-demo`, `replicas: 2`; активен только `emptyDir: {}`; hostPath/PVC/tmpfs закомментированы |
| [storage.yaml](demo-manifests/storage.yaml) | Только PV активен: `k8s4-static`, 3Gi, класс `""`, Retain, `/data/k8s4-storage/shared`; PVC выключен, но содержит `demo-claim`, 5Gi, класс `""`; Quota выключена, лимиты 2Gi и два PVC |
| [stateful.yaml](demo-manifests/stateful.yaml) | Обе секции активны: Service и StatefulSet; две реплики, шаблон `data`, 1Gi, класс `""`; обе retention policy — Retain |

В `storage.yaml` включайте/выключайте **весь документ вместе с `---`**, убирая/добавляя один префикс `# ` у строк секции. Строки-заголовки `# === ... ===` остаются комментариями. Комментирование секции не удаляет уже созданный объект. Не выполняйте `apply -f results/demo-manifests` на весь каталог: документы предназначены для разных этапов.

`POD_1`, `POD_2`, `POD_NEW`, `PV_DYNAMIC` и `PV_QUOTA` — обозначения для ручной подстановки. Реальные имена берите из указанных команд `get`, перед запуском заменяйте обозначения целиком. После пересоздания снова смотрите список Pod. При `--watch` дождитесь нужного состояния и нажмите Ctrl+C — это прекращает наблюдение, но не удаляет ресурсы. Не переходите дальше после неожиданного тайм-аута: используйте раздел диагностики.

## Временное хранение: emptyDir

### Запустить два Pod с двумя контейнерами

Откройте `volumes.yaml`. Покажите `volumes[].name: data` и оба `volumeMounts`: `/cache1` у `writer`, `/cache2` у `reader`. Ручных изменений пока нет. Активен один документ Deployment, источник только `emptyDir: {}`.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/volumes.yaml
kubectl --context=k8s4-storage -n k8s4-storage rollout status deployment/volume-demo --timeout=180s
kubectl --context=k8s4-storage -n k8s4-storage get pods -l app=volume-demo -o wide
```

Назовите два готовых Pod `POD_1` и `POD_2`. Оба имеют `READY 2/2`.

### Передать файл между контейнерами

```console
kubectl --context=k8s4-storage -n k8s4-storage exec POD_1 -c writer -- sh -c 'echo from-writer > /cache1/shared.txt'
kubectl --context=k8s4-storage -n k8s4-storage exec POD_1 -c reader -- cat /cache2/shared.txt
kubectl --context=k8s4-storage -n k8s4-storage exec POD_2 -c reader -- ls -la /cache2
```

В первом Pod читается `from-writer`; во втором каталоге нет `shared.txt`. Общий том существует в пределах одного Pod. `-c` явно выбирает контейнер.

### Заменить Pod

```console
kubectl --context=k8s4-storage -n k8s4-storage delete pod POD_1 --wait=true
kubectl --context=k8s4-storage -n k8s4-storage rollout status deployment/volume-demo --timeout=180s
kubectl --context=k8s4-storage -n k8s4-storage get pods -l app=volume-demo -o wide
kubectl --context=k8s4-storage -n k8s4-storage wait --for=condition=Ready pod/POD_NEW --timeout=180s
kubectl --context=k8s4-storage -n k8s4-storage exec POD_NEW -c reader -- ls -la /cache2
```

`POD_NEW` — новая реплика вместо удалённой, а не прежний `POD_2`. В ней файл отсутствует: создан новый emptyDir. Этот опыт показывает замену Pod; перезапуск отдельного контейнера в том же Pod сохраняет emptyDir.

### Проверить вариант в памяти

Удалите Deployment и дождитесь его Pod:

```console
kubectl --context=k8s4-storage -n k8s4-storage delete deployment volume-demo --wait=true
kubectl --context=k8s4-storage -n k8s4-storage wait --for=delete pod -l app=volume-demo --timeout=120s
```

В `volumes.yaml` замените `emptyDir: {}` на предусмотренные в комментариях `emptyDir.medium: Memory` и `emptyDir.sizeLimit: 32Mi`. HostPath и PVC остаются выключенными. Активен только Deployment с tmpfs-источником.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/volumes.yaml
kubectl --context=k8s4-storage -n k8s4-storage rollout status deployment/volume-demo --timeout=180s
kubectl --context=k8s4-storage -n k8s4-storage get pods -l app=volume-demo
kubectl --context=k8s4-storage -n k8s4-storage exec POD_1 -c writer -- df -h /cache1
kubectl --context=k8s4-storage -n k8s4-storage exec POD_1 -c writer -- sh -c 'echo in-memory > /cache1/shared.txt'
kubectl --context=k8s4-storage -n k8s4-storage exec POD_1 -c reader -- cat /cache2/shared.txt
```

Подставьте свежее имя `POD_1`. `df` показывает tmpfs размером около 32 MiB; файл снова общий. Лимит памяти контейнера 128 MiB включает расход на записанные им файлы tmpfs. Нагрузочный опыт с OOM здесь не нужен.

```console
kubectl --context=k8s4-storage -n k8s4-storage delete deployment volume-demo --wait=true
kubectl --context=k8s4-storage -n k8s4-storage wait --for=delete pod -l app=volume-demo --timeout=120s
```

## Данные узла: hostPath

### Подготовить каталог на Linux-узле

```console
minikube ssh -p k8s4-storage
```

Следующий блок выполняется **в SSH-сеансе узла**:

```console
sudo mkdir -p /data/k8s4-storage/shared
sudo sh -c 'echo from-node > /data/k8s4-storage/shared/node.txt'
ls -la /data/k8s4-storage/shared
exit
```

В каталоге находится `node.txt`. Если там уже есть `shared.txt` от прошлого показа, сначала завершите очистку: иначе нельзя достоверно сравнить результаты.

### Подключить один каталог к двум Pod

В `volumes.yaml` выключите весь источник `emptyDir`, включая `medium` и `sizeLimit`. Включите `hostPath` с путём `/data/k8s4-storage/shared` и `type: DirectoryOrCreate`. PVC выключен. Активен один Deployment с hostPath.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/volumes.yaml
kubectl --context=k8s4-storage -n k8s4-storage rollout status deployment/volume-demo --timeout=180s
kubectl --context=k8s4-storage -n k8s4-storage get pods -l app=volume-demo -o wide
kubectl --context=k8s4-storage -n k8s4-storage exec POD_1 -c writer -- cat /cache1/node.txt
kubectl --context=k8s4-storage -n k8s4-storage exec POD_1 -c writer -- sh -c 'echo from-pod > /cache1/shared.txt'
kubectl --context=k8s4-storage -n k8s4-storage exec POD_2 -c reader -- cat /cache2/shared.txt
```

Оба Pod находятся на одном узле, оба видят `node.txt` и `shared.txt`. Здесь общий каталог между Pod объясняется одинаковыми узлом и путём, а не принадлежностью к Deployment.

### Проверить сохранность после удаления приложения

```console
kubectl --context=k8s4-storage -n k8s4-storage delete deployment volume-demo --wait=true
kubectl --context=k8s4-storage -n k8s4-storage wait --for=delete pod -l app=volume-demo --timeout=120s
minikube ssh -p k8s4-storage -- cat /data/k8s4-storage/shared/shared.txt
```

Ожидается `from-pod`. Файлы пока оставьте: следующий этап подключит тот же каталог через PV/PVC.

## Статический PV/PVC и Retain

### Создать доступный PV

Откройте `storage.yaml`. Активна только секция PV; PVC и Quota выключены. Проверьте `k8s4-static`, ёмкость 3Gi, пустой класс и Retain.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/storage.yaml
kubectl --context=k8s4-storage wait '--for=jsonpath={.status.phase}=Available' pv/k8s4-static --timeout=60s
kubectl --context=k8s4-storage get pv k8s4-static
```

PV имеет статус `Available` и не имеет namespace.

### Показать неудовлетворённую заявку

Включите секцию PVC вместе с её `---`. В PVC оставьте `demo-claim`, `storageClassName: ""` и запрос 5Gi. Активны PV и PVC, Quota выключена.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/storage.yaml
kubectl --context=k8s4-storage -n k8s4-storage get pvc demo-claim
kubectl --context=k8s4-storage -n k8s4-storage describe pvc demo-claim
kubectl --context=k8s4-storage get pv k8s4-static
```

Ожидаемый результат — PVC `Pending`, PV `Available`: 3Gi не покрывает запрос 5Gi. Автоматического выделения нет, так как класс явно пустой.

### Пересоздать заявку подходящего размера

```console
kubectl --context=k8s4-storage -n k8s4-storage delete pvc demo-claim --wait=true
```

Измените только `PVC.spec.resources.requests.storage` с 5Gi на 1Gi. Ёмкость PV остаётся 3Gi. Активны PV и PVC, Quota выключена.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/storage.yaml
kubectl --context=k8s4-storage -n k8s4-storage wait '--for=jsonpath={.status.phase}=Bound' pvc/demo-claim --timeout=120s
kubectl --context=k8s4-storage -n k8s4-storage get pvc demo-claim
kubectl --context=k8s4-storage get pv k8s4-static
```

Оба объекта `Bound`; PVC получает весь PV на 3Gi. Это не физическая квота каталога. Уменьшение заявки показывается через удаление и создание PVC, а не попытку уменьшить существующий том.

### Подключить PVC к приложению

В `volumes.yaml` выключите hostPath и включите `persistentVolumeClaim.claimName: demo-claim`. Активен только Deployment с источником PVC; emptyDir и hostPath выключены.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/volumes.yaml
kubectl --context=k8s4-storage -n k8s4-storage rollout status deployment/volume-demo --timeout=180s
kubectl --context=k8s4-storage -n k8s4-storage get pods -l app=volume-demo -o wide
kubectl --context=k8s4-storage -n k8s4-storage exec POD_1 -c writer -- cat /cache1/shared.txt
kubectl --context=k8s4-storage -n k8s4-storage exec POD_2 -c reader -- cat /cache2/node.txt
```

Файлы прежние: backend не изменился, изменился способ его предоставления. Две реплики на одном узле используют RWO-PVC; RWO не означает один Pod.

### Освободить Retain-том

```console
kubectl --context=k8s4-storage -n k8s4-storage delete deployment volume-demo --wait=true
kubectl --context=k8s4-storage -n k8s4-storage wait --for=delete pod -l app=volume-demo --timeout=120s
kubectl --context=k8s4-storage -n k8s4-storage delete pvc demo-claim --wait=true
kubectl --context=k8s4-storage wait '--for=jsonpath={.status.phase}=Released' pv/k8s4-static --timeout=120s
kubectl --context=k8s4-storage get pv k8s4-static
minikube ssh -p k8s4-storage -- cat /data/k8s4-storage/shared/shared.txt
kubectl --context=k8s4-storage delete pv k8s4-static --wait=true
minikube ssh -p k8s4-storage -- cat /data/k8s4-storage/shared/shared.txt
```

После удаления PVC PV — `Released`; после удаления PV его API-объекта нет, но `from-pod` читается с узла. Данные статического Retain-тома будут удалены отдельно в финале.

## Динамическое выделение и Delete

### Использовать default-класс

В `storage.yaml` выключите **всю секцию PV**. Активна только PVC, Quota выключена. У PVC оставьте `demo-claim` и 1Gi, а строку `storageClassName: ""` удалите или закомментируйте. Отсутствие поля позволит назначить проверенный в подготовке default `standard`.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/storage.yaml
kubectl --context=k8s4-storage -n k8s4-storage wait '--for=jsonpath={.status.phase}=Bound' pvc/demo-claim --timeout=180s
kubectl --context=k8s4-storage -n k8s4-storage get pvc demo-claim -o wide
kubectl --context=k8s4-storage get pv
```

В колонке VOLUME у PVC возьмите имя `PV_DYNAMIC`. PV создан автоматически на 1Gi с классом `standard` и политикой Delete. Deployment для этого опыта не нужен: используется Immediate.

```console
kubectl --context=k8s4-storage get pv PV_DYNAMIC -o yaml
kubectl --context=k8s4-storage -n k8s4-storage delete pvc demo-claim --wait=true
kubectl --context=k8s4-storage wait --for=delete pv/PV_DYNAMIC --timeout=180s
```

PV исчезает, provisioner удаляет созданный им каталог. Имя PV нужно сохранить до удаления PVC. Исчезновение API-объекта — наблюдение этого опыта; поведение удаления данных объясняется реализацией данного provisioner.

## StatefulSet: индивидуальные PVC

### Сначала без автоматического выделения

Убедитесь, что `demo-claim` и предыдущие PV удалены. Откройте `stateful.yaml`: активны Service и StatefulSet; две реплики, `volumeClaimTemplates` с именем `data`, объём 1Gi и `storageClassName: ""`. Политики сохранения PVC — Retain.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/stateful.yaml
kubectl --context=k8s4-storage -n k8s4-storage get pods,pvc --watch
```

Дождитесь появления `storage-set-0` и `data-storage-set-0` в Pending и выйдите Ctrl+C. Второй Pod ещё не запускается из-за OrderedReady.

В `storage.yaml` включите только PV, выключите PVC и Quota. В PV вручную задайте имя `k8s4-manual-0`, ёмкость 1Gi и путь `/data/k8s4-storage/manual-0`; класс `""`, политика Retain. Это новый PV в отдельном каталоге.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/storage.yaml
kubectl --context=k8s4-storage -n k8s4-storage wait '--for=jsonpath={.status.phase}=Bound' pvc/data-storage-set-0 --timeout=120s
kubectl --context=k8s4-storage -n k8s4-storage wait --for=condition=Ready pod/storage-set-0 --timeout=180s
kubectl --context=k8s4-storage -n k8s4-storage get pods,pvc --watch
```

Дождитесь появления `storage-set-1` и `data-storage-set-1` в Pending, выйдите Ctrl+C. Единственный PV уже занят первой репликой. Создавать второй PV вручную не требуется: следующий шаг сравнит этот процесс с автоматикой.

### Пересоздать StatefulSet с динамическим классом

Смена класса в `volumeClaimTemplates` требует пересоздания StatefulSet и учебных PVC. Сначала удалите потребителей:

```console
kubectl --context=k8s4-storage -n k8s4-storage delete statefulset storage-set --wait=true
kubectl --context=k8s4-storage -n k8s4-storage wait --for=delete pod -l app=storage-set --timeout=120s
kubectl --context=k8s4-storage -n k8s4-storage get pvc
kubectl --context=k8s4-storage -n k8s4-storage delete pvc data-storage-set-0 data-storage-set-1 --wait=true
kubectl --context=k8s4-storage wait '--for=jsonpath={.status.phase}=Released' pv/k8s4-manual-0 --timeout=120s
kubectl --context=k8s4-storage delete pv k8s4-manual-0 --wait=true
```

PVC пережили удаление контроллера и были удалены явно. Service остаётся и будет повторно применён без смены имени.

В `stateful.yaml` замените только `volumeClaimTemplates[0].spec.storageClassName` с `""` на `standard`. Обе секции активны: Service и StatefulSet, `replicas: 2`. В `storage.yaml` выключите все секции до следующего блока; этот файл сейчас не применяется.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/stateful.yaml
kubectl --context=k8s4-storage -n k8s4-storage rollout status statefulset/storage-set --timeout=300s
kubectl --context=k8s4-storage -n k8s4-storage get pods,pvc
kubectl --context=k8s4-storage get pv
kubectl --context=k8s4-storage -n k8s4-storage exec storage-set-0 -- sh -c 'echo replica-zero > /data/owner.txt'
kubectl --context=k8s4-storage -n k8s4-storage exec storage-set-1 -- ls -la /data
```

Два готовых Pod, два PVC, два PV. Во втором Pod нет `owner.txt` первого: тома разные.

### Очистить StatefulSet перед квотой

```console
kubectl --context=k8s4-storage -n k8s4-storage delete statefulset storage-set --wait=true
kubectl --context=k8s4-storage -n k8s4-storage wait --for=delete pod -l app=storage-set --timeout=180s
kubectl --context=k8s4-storage -n k8s4-storage get pvc
kubectl --context=k8s4-storage -n k8s4-storage delete pvc data-storage-set-0 data-storage-set-1 --wait=true
kubectl --context=k8s4-storage -n k8s4-storage delete service storage-headless
kubectl --context=k8s4-storage get pv --watch
```

Дождитесь удаления двух динамических PV этого namespace и выйдите Ctrl+C. Данные этих томов удаляются по Delete. Retain в StatefulSet сохранял сами PVC до явного удаления и не менял reclaim policy PV.

## Дополнительный опыт: квота на заявки

### Создать ограничение в пустом namespace

Проверьте отсутствие PVC:

```console
kubectl --context=k8s4-storage -n k8s4-storage get pvc
```

В `storage.yaml` активна **только Quota**, PV и PVC выключены. Значения Quota: `requests.storage: 2Gi`, `persistentvolumeclaims: "2"`.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/storage.yaml
kubectl --context=k8s4-storage -n k8s4-storage describe resourcequota storage-quota
```

Убедитесь, что Used равен нулю, а Hard содержит 2Gi и два PVC. Если значения ещё не появились, повторите `describe` перед опытом.

### Получить ожидаемый отказ и исправить запрос

Включите секцию PVC вместе с `---`; PV остаётся выключенным, активны PVC и Quota. В PVC задайте **новое имя** `quota-probe`, класс `standard`, запрос 3Gi.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/storage.yaml
kubectl --context=k8s4-storage -n k8s4-storage get pvc
```

**Ожидаемая ошибка:** `Forbidden`, `exceeded quota`. Новый PVC не создан; Quota при многообъектном `apply` остаётся на месте. Это не атомарная транзакция всего файла.

Исправьте запрос PVC с 3Gi на 1Gi. По-прежнему активны PVC и Quota, PV выключен.

```console
kubectl --context=k8s4-storage apply -f results/demo-manifests/storage.yaml
kubectl --context=k8s4-storage -n k8s4-storage wait '--for=jsonpath={.status.phase}=Bound' pvc/quota-probe --timeout=180s
kubectl --context=k8s4-storage -n k8s4-storage get pvc quota-probe -o wide
kubectl --context=k8s4-storage -n k8s4-storage describe resourcequota storage-quota
```

Теперь Used — одна заявка и 1Gi. Запишите VOLUME как `PV_QUOTA`. Это учёт запрошенных ресурсов, не измерение файлов на диске.


