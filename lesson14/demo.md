# Полная демонстрация: Job, CronJob, размещение и конфигурация

Показ выполняется целиком после теоретической части [пособия](k8s_5_method.md). Все команды ниже предназначены для отдельного учебного профиля `k8s-5`, namespace `lab-k8s-5`. Время показа — ориентировочно 45–60 минут с ожиданием расписаний и ручным редактированием. Не применяйте весь каталог сразу: файлы вводятся последовательно.

## Подготовка стенда и файлов

### Проверить инструменты и рабочую директорию

Нужны Docker с Linux-контейнерами, minikube и kubectl. Для двух узлов предусмотрено по 2 CPU и 2200 MiB памяти; Docker должен иметь достаточно доступных ресурсов. Версия Kubernetes должна поддерживать `CronJob.spec.timeZone` (стабильно с 1.27); используйте поддерживаемую версию, которую поддерживает ваш minikube. Понадобится доступ узлов к registry для образа `busybox:1.36.1`.

Все команды `apply -f` рассчитаны на рабочую директорию **корня этого репозитория**. На текущем компьютере:

```console
cd D:\repo\other-repo\otus-ms-k8s-5
docker version
minikube version
kubectl version --client
minikube profile list
```

Профиль `k8s-5` должен быть выделен только под этот показ. Если он уже существует, убедитесь, что это прежний учебный стенд; не используйте профиль с чужими ресурсами. Перед повторным показом выполните раздел очистки старого учебного namespace и меток, затем восстановите файлы по таблице ниже.

### Восстановить исходные значения

Имена ресурсов и namespace во всех опытах остаются неизменными. Изменяйте только перечисленные параметры.

| Файл | Исходное состояние перед полным показом |
|---|---|
| [pod.yaml](demo-manifests/pod.yaml) | `restartPolicy: Never`; `args: ['echo start; sleep 3; echo done; exit 0']`; блоки SELECTOR, REQUIRED, PREFERRED, TOLERATION закомментированы |
| [job.yaml](demo-manifests/job.yaml) | completions/parallelism `1/1`, backoffLimit `2`, activeDeadlineSeconds `300`, restartPolicy `Never`, `args: ['echo start; sleep 10; echo done; exit 0']`, TTL закомментирован |
| [cronjob.yaml](demo-manifests/cronjob.yaml) | schedule `* * * * *`, timeZone `Europe/Moscow`, policy `Allow`, startingDeadlineSeconds `30`, suspend `false`, история `2/1`, Job completions/parallelism `1/1`, deadline `240`, backoffLimit `1`, `args: ['date; sleep 10; echo done']` |
| [affinity.yaml](demo-manifests/affinity.yaml) | replicas `3`, `podAntiAffinity`, обязательное правило по `kubernetes.io/hostname` |
| [config-data.yaml](demo-manifests/config-data.yaml) | оба документа активны; адреса содержат `v1` и в отдельных ключах, и внутри `app.conf`; пароль `demo-only-v1` |
| [config-app.yaml](demo-manifests/config-app.yaml) | replicas `2`, обычные directory mounts; `subPath` отсутствует |

В `pod.yaml` заголовки SELECTOR/REQUIRED/PREFERRED/TOLERATION всегда остаются комментариями. Чтобы включить блок, удалите только `# ` после исходных двух пробелов перед каждой YAML-строкой блока. Вложенные отступы сохраняйте. SELECTOR, REQUIRED и PREFERRED в этом показе используются по одному. TOLERATION включается дополнительно к SELECTOR. Закомментированное поле исчезает из файла, но комментирование целого ресурса не удалило бы уже существующий объект из кластера.

### Создать два узла

```console
minikube start -p k8s-5 --driver=docker --nodes=2 --cpus=2 --memory=2200
kubectl --context k8s-5 version
kubectl --context k8s-5 wait --for=condition=Ready nodes --all --timeout=180s
kubectl --context k8s-5 get nodes -o wide
kubectl --context k8s-5 create namespace lab-k8s-5
kubectl --context k8s-5 get namespace lab-k8s-5
```

Ожидаются два узла `Ready`, обычно `k8s-5` и `k8s-5-m02`. Далее используются именно эти имена. Если вывод отличается, замените их в командах меток и taints фактическими именами. Оба узла должны быть доступны для обычных Pod. Если позже anti-affinity даст только одну работающую реплику, проверьте taints и доступные ресурсы второго узла.

Во всех командах kubectl контекст указан явно. Обозначения `POD_NAME`, `POD_PENDING`, `CONFIG_POD`, `JOB_NAME` — это не готовые имена: копируйте актуальное имя из ближайшего `get` и подставляйте перед запуском команды. После пересоздания имена дочерних Pod меняются.

В командах удаления используется `--cascade=true`, совместимый с kubectl, где этот флаг принимает только `true/false`. Удаление зависимых ресурсов асинхронное: после удаления контроллера отдельно ждём исчезновения его потомков (для CronJob — сначала Job, затем Pod; для Deployment — сначала ReplicaSet, затем Pod). Если `wait --for=delete` сообщает, что ресурсы не найдены, очистка уже завершена. При timeout или другой ошибке проверьте оставшиеся ресурсы и не переходите к повторному `apply` до завершения очистки.

Команды с `--watch` показывают изменения до **Ctrl+C**; остановка просмотра не останавливает ресурс. Если объект ещё не появился, сначала повторите `get` или дождитесь его в watch, затем запускайте `wait` или `logs`. Для коротких Job ждите `Complete`, а не `Ready` Pod: кратковременное состояние готовности можно пропустить.

## Завершение процесса и restartPolicy

### Успешно закончить самостоятельный Pod

Откройте `pod.yaml`, покажите `spec.restartPolicy` и команду контейнера. Все четыре блока размещения отключены. Файл содержит один активный Pod.

```console
kubectl --context k8s-5 apply -f results/demo-manifests/pod.yaml
kubectl --context k8s-5 -n lab-k8s-5 wait --for=jsonpath='{.status.phase}'=Succeeded pod/probe --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get pod probe
kubectl --context k8s-5 -n lab-k8s-5 logs probe
```

Ожидаются `Completed` в таблице, фаза `Succeeded`, строки `start` и `done`. API-объект остаётся доступен, хотя процесс закончен.

### Сравнить ошибку без перезапуска и с перезапуском

В `pod.yaml` замените только `exit 0` на `exit 1`, оставьте `Never`. Перед каждым новым вариантом удаляйте Pod: изменение команды или restart policy существующего Pod требует пересоздания.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true
kubectl --context k8s-5 apply -f results/demo-manifests/pod.yaml
kubectl --context k8s-5 -n lab-k8s-5 wait --for=jsonpath='{.status.phase}'=Failed pod/probe --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get pod probe
```

Ожидается неуспешное завершение без перезапуска. Теперь измените `restartPolicy` на `OnFailure`, команда остаётся с `exit 1`. Блоки размещения всё ещё отключены.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true
kubectl --context k8s-5 apply -f results/demo-manifests/pod.yaml
kubectl --context k8s-5 -n lab-k8s-5 get pod probe --watch
```

Дождитесь `RESTARTS` больше нуля и остановите просмотр. Имя Pod осталось `probe`, перезапускается контейнер. Возможен `CrashLoopBackOff` между попытками.

```console
kubectl --context k8s-5 -n lab-k8s-5 logs probe --previous
kubectl --context k8s-5 -n lab-k8s-5 describe pod probe
```

- `logs --previous` показывает вывод предыдущего завершившегося экземпляра контейнера. Сам по себе `exit 1` не добавляет сообщение об ошибке в логи.
- `describe pod` показывает причину завершения и перезапуски: найдите в `Last State` значения `Reason: Error` и `Exit Code: 1`, проверьте `Restart Count`. В `Events` возможен `BackOff` — пауза перед очередной попыткой запуска.

### Показать Always после успешного выхода

Измените `restartPolicy` на `Always` и верните `exit 0`. Остальные блоки отключены.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true
kubectl --context k8s-5 apply -f results/demo-manifests/pod.yaml
kubectl --context k8s-5 -n lab-k8s-5 get pod probe --watch
```

Дождитесь роста `RESTARTS`, нажмите Ctrl+C. Даже успешный выход приводит к новому запуску контейнера. Завершите опыт:

```console
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true
```

## Job: успехи, параллелизм, ошибки и очистка

### Выполнить одну задачу

Откройте исходный `job.yaml`: один активный Job, TTL выключен. Покажите различие между `spec` Job и `spec.template.spec` Pod.

```console
kubectl --context k8s-5 apply -f results/demo-manifests/job.yaml
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Complete job/batch-demo --timeout=180s
kubectl --context k8s-5 -n lab-k8s-5 get job batch-demo
kubectl --context k8s-5 -n lab-k8s-5 get pods -l batch.kubernetes.io/job-name=batch-demo --show-labels
kubectl --context k8s-5 -n lab-k8s-5 logs job/batch-demo
```

Ожидается `1/1` успешных завершений. У Pod автоматически есть метки Job; связь владения видна в `ownerReferences`. Ресурсы не исчезают сразу после завершения.

### Получить семь успехов с параллелизмом два

Измените только `spec.completions: 7` и `spec.parallelism: 2`. TTL остаётся выключенным. Чтобы начать новый опыт, удалите старую Job и дождитесь удаления её Pod:

```console
kubectl --context k8s-5 -n lab-k8s-5 delete job batch-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=batch-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=batch-demo
kubectl --context k8s-5 apply -f results/demo-manifests/job.yaml
kubectl --context k8s-5 -n lab-k8s-5 get pods -l batch.kubernetes.io/job-name=batch-demo --watch
```

В нормальном выполнении видны до двух одновременно работающих Pod и накопление завершённых. После наблюдения нажмите Ctrl+C:

```console
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Complete job/batch-demo --timeout=180s
kubectl --context k8s-5 -n lab-k8s-5 get job batch-demo
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=batch-demo
```

Ожидается `7/7`. Возьмите имя одного завершённого Pod из списка вместо `POD_NAME`:

```console
kubectl --context k8s-5 -n lab-k8s-5 logs POD_NAME
```

### Ограничить ошибки при Never

Верните `completions: 1`, `parallelism: 1`; оставьте `backoffLimit: 2`, deadline `300`, `Never`, TTL выключен. Замените args на `['echo failing; sleep 3; exit 1']`.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete job batch-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=batch-demo --timeout=120s
kubectl --context k8s-5 apply -f results/demo-manifests/job.yaml
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=batch-demo --watch
```

Видны отдельные неуспешные Pod, а не перезапуски контейнера в одном Pod. Между попытками есть задержки. Остановите просмотр после нескольких попыток:

```console
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Failed job/batch-demo --timeout=240s
kubectl --context k8s-5 -n lab-k8s-5 describe job batch-demo
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=batch-demo
```

**Ожидаемый отказ:** условие `Failed`, причина `BackoffLimitExceeded`. Команда `wait` здесь успешно дожидается именно неуспеха задачи. Не используйте число строк Pod как универсальную формулу `backoffLimit`.

### Сравнить OnFailure в той же Job

Измените только `spec.template.spec.restartPolicy` на `OnFailure`. Все остальные значения предыдущего опыта сохранены, TTL выключен.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete job batch-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=batch-demo --timeout=120s
kubectl --context k8s-5 apply -f results/demo-manifests/job.yaml
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=batch-demo --watch
```

Дождитесь роста `RESTARTS` у одного Pod и нажмите Ctrl+C. Пока этот Pod существует, подставьте его имя вместо `POD_NAME`:

```console
kubectl --context k8s-5 -n lab-k8s-5 logs POD_NAME --previous
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Failed job/batch-demo --timeout=240s
kubectl --context k8s-5 -n lab-k8s-5 describe job batch-demo
```

Если Pod уже удалён контроллером по достижении лимита, логи через API могут быть недоступны. Это и объясняет удобство `Never` при отладке. Лимит повторов по-прежнему контролирует Job.

### Ограничить длительность зависшей задачи

Верните `Never`, задайте `activeDeadlineSeconds: 20` и args `['echo waiting; sleep 120; echo done']`. completions/parallelism `1/1`, backoffLimit `2`, TTL выключен. Образ уже использовался, поэтому опыт обычно измеряет ожидание программы, а не загрузку образа.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete job batch-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=batch-demo --timeout=120s
kubectl --context k8s-5 apply -f results/demo-manifests/job.yaml
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Failed job/batch-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 describe job batch-demo
```

**Ожидаемый отказ:** `DeadlineExceeded`. Job прекращается по общему времени, хотя программа не успела вернуть ошибку. Точный момент отражения конечного состояния зависит от завершения Pod и работы контроллеров.

### Удалить завершённую Job по TTL

Верните deadline `300` и args `['echo start; sleep 10; echo done; exit 0']`. Оставьте `Never`, `1/1`, backoffLimit `2`; раскомментируйте `ttlSecondsAfterFinished: 30`.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete job batch-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=batch-demo --timeout=120s
kubectl --context k8s-5 apply -f results/demo-manifests/job.yaml
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Complete job/batch-demo --timeout=180s
kubectl --context k8s-5 -n lab-k8s-5 logs job/batch-demo
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete job/batch-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=batch-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=batch-demo
```

Job становится доступной для удаления через 30 секунд после завершения; затем исчезают её Pod. Если при проверке удаления Pod уже отсутствуют, результат «ресурсы не найдены» также соответствует ожидаемой очистке. Перед следующим полным показом снова закомментируйте TTL в файле.

## CronJob: расписание и пересечение запусков

### Наблюдать создание Job по минутам

Откройте исходный `cronjob.yaml`: один активный CronJob, `Allow`, `suspend: false`, задача 10 секунд, история `2/1`. TTL в шаблоне Job отсутствует.

```console
kubectl --context k8s-5 apply -f results/demo-manifests/cronjob.yaml
kubectl --context k8s-5 -n lab-k8s-5 get cronjob clock-demo
kubectl --context k8s-5 -n lab-k8s-5 get jobs -l app=clock-demo --watch
```

Ждите следующей минутной границы и небольшого времени на обработку. Для истории можно наблюдать 3–4 завершения: останется не больше двух успешных Job после работы очистки. Нажмите Ctrl+C, скопируйте имя одной существующей Job вместо `JOB_NAME`:

```console
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Complete job/JOB_NAME --timeout=180s
kubectl --context k8s-5 -n lab-k8s-5 get job JOB_NAME -o yaml
kubectl --context k8s-5 -n lab-k8s-5 logs job/JOB_NAME
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=clock-demo
```

Покажите `ownerReferences` Job на CronJob и у Pod на Job. CronJob сама Pod не создаёт. Команда `date` печатает время в часовом поясе контейнера; `spec.timeZone` определяет расписание контроллера и не меняет часовой пояс контейнера. При слишком долгой паузе старая Job может быть удалена лимитом истории: выберите актуальную из нового `get`.

### Разрешить перекрытие запусков

Удалите CronJob вместе с созданными задачами. В файле замените args на `['date; sleep 90; echo done']`. Политика `Allow`, дедлайн Job `240`, suspend `false`; остальные значения исходные.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete cronjob clock-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete job -l app=clock-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=clock-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get jobs,pods -l app=clock-demo
kubectl --context k8s-5 apply -f results/demo-manifests/cronjob.yaml
kubectl --context k8s-5 -n lab-k8s-5 get jobs -l app=clock-demo --watch
```

Наблюдайте две последовательные минутные границы: вторая Job появляется, пока первая ещё работает. Нажмите Ctrl+C, посмотрите `ACTIVE` CronJob и Pod:

```console
kubectl --context k8s-5 -n lab-k8s-5 get cronjob clock-demo
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=clock-demo
```

### Запретить перекрытие запусков

Измените только `concurrencyPolicy: Forbid`; длительность остаётся 90 секунд. Для чистого опыта снова удалите всю предыдущую цепочку:

```console
kubectl --context k8s-5 -n lab-k8s-5 delete cronjob clock-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete job -l app=clock-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=clock-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get jobs,pods -l app=clock-demo
kubectl --context k8s-5 apply -f results/demo-manifests/cronjob.yaml
kubectl --context k8s-5 -n lab-k8s-5 get jobs -l app=clock-demo --watch
```

На следующей минутной границе при ещё активной первой Job вторая не создаётся. Это ожидаемый пропуск, а не ошибка. После завершения предыдущей Job возможен запоздалый запуск, если он ещё укладывается в окно 30 секунд. `Forbid` запрещает пересечение работающих Job; более поздний догоняющий старт может быть допустим. Нажмите Ctrl+C.

### Заменять незавершённую работу

Измените только `concurrencyPolicy: Replace`, сохранив 90 секунд, suspend `false` и остальные значения.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete cronjob clock-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete job -l app=clock-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=clock-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get jobs,pods -l app=clock-demo
kubectl --context k8s-5 apply -f results/demo-manifests/cronjob.yaml
kubectl --context k8s-5 -n lab-k8s-5 get jobs -l app=clock-demo --watch
```

На новой минуте старая незавершённая Job заменяется новой. При задаче 90 секунд и минутном расписании успех может вообще не наступать: каждый запуск прерывается следующим. Удаление Pod асинхронно; это не механизм транзакционного отката. Нажмите Ctrl+C.

### Приостановить расписание, сохранив текущую Job

Дождитесь появления очередной активной Job и запомните её имя. В `cronjob.yaml` измените только `suspend: true`; `Replace` и 90 секунд остаются. Применяется один активный CronJob:

```console
kubectl --context k8s-5 apply -f results/demo-manifests/cronjob.yaml
kubectl --context k8s-5 -n lab-k8s-5 get cronjob clock-demo
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Complete job/JOB_NAME --timeout=180s
kubectl --context k8s-5 -n lab-k8s-5 get jobs -l app=clock-demo --watch
```

Подставьте сохранённое имя вместо `JOB_NAME`. Приостановленная CronJob не создаёт замену на следующей минуте, и текущая Job получает возможность закончить 90-секундную работу. Наблюдайте ещё одну минутную границу без появления новой Job, затем Ctrl+C.

Покажите `startingDeadlineSeconds: 30`: это окно запоздалого создания Job. Для возобновления верните в файле `suspend: false` и примените один CronJob:

```console
kubectl --context k8s-5 apply -f results/demo-manifests/cronjob.yaml
kubectl --context k8s-5 -n lab-k8s-5 get jobs -l app=clock-demo --watch
```

В зависимости от момента возобновления возможен запуск недавнего пропущенного расписания либо ожидание новой минуты. Здесь не моделируется отказ control plane, и не следует ожидать строго определённого догоняющего запуска. После наблюдения Ctrl+C и очистка:

```console
kubectl --context k8s-5 -n lab-k8s-5 delete cronjob clock-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete job -l app=clock-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=clock-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get jobs,pods -l app=clock-demo
```

## Выбор узла и tolerations

### Пометить узлы и включить nodeSelector

```console
kubectl --context k8s-5 label node k8s-5 lab.example/disk=hdd --overwrite
kubectl --context k8s-5 label node k8s-5-m02 lab.example/disk=ssd --overwrite
kubectl --context k8s-5 get nodes -L lab.example/disk
```

В `pod.yaml` поставьте `restartPolicy: Always`, args `['exec sleep 3600']`. Включите SELECTOR со значением `ssd`. REQUIRED, PREFERRED и TOLERATION отключены. Применяется один Pod:

```console
kubectl --context k8s-5 apply -f results/demo-manifests/pod.yaml
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Ready pod/probe --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get pod probe -o wide
```

Ожидается узел `k8s-5-m02`. Метка демонстрационная, физический SSD не проверяется.

### Получить ожидаемый Pending

В активном SELECTOR замените `ssd` на `nvme`, которого нет у узлов. Остальные блоки отключены.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true
kubectl --context k8s-5 apply -f results/demo-manifests/pod.yaml
kubectl --context k8s-5 -n lab-k8s-5 get pod probe --watch
```

После появления `Pending` нажмите Ctrl+C; если события ещё не появились, повторите `describe` через несколько секунд.

```console
kubectl --context k8s-5 -n lab-k8s-5 describe pod probe
```

**Ожидаемый отказ планирования:** нет узла с подходящей меткой; в Events появляется `FailedScheduling`. Здесь не ждём `Ready` как успешного результата.

### Заменить selector обязательной Node affinity

Полностью закомментируйте SELECTOR. Включите REQUIRED, оставив `operator: In`, `values: [ssd]`. PREFERRED и TOLERATION отключены; долгоживущая команда и `Always` сохраняются.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true
kubectl --context k8s-5 apply -f results/demo-manifests/pod.yaml
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Ready pod/probe --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get pod probe -o wide
```

Pod снова назначен на `k8s-5-m02`. Теперь измените метку работающего узла, не меняя Pod:

```console
kubectl --context k8s-5 label node k8s-5-m02 lab.example/disk=hdd --overwrite
kubectl --context k8s-5 get nodes -L lab.example/disk
kubectl --context k8s-5 -n lab-k8s-5 get pod probe -o wide
```

Pod остаётся на узле и продолжает работать: правило `IgnoredDuringExecution` не выселяет его после изменения метки.

### Разрешить запасной узел через мягкое предпочтение

Сейчас оба узла имеют `hdd`. Выключите REQUIRED и включите PREFERRED с `values: [ssd]`, `weight: 100`. SELECTOR и TOLERATION отключены.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true
kubectl --context k8s-5 apply -f results/demo-manifests/pod.yaml
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Ready pod/probe --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get pod probe -o wide
```

Pod запускается на одном из узлов несмотря на отсутствие SSD-метки. Мягкое предпочтение допускает такой выбор. Завершите опыт и восстановите метку второго узла:

```console
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true
kubectl --context k8s-5 label node k8s-5-m02 lab.example/disk=ssd --overwrite
```

### Совместить выбор и допуск к узлу

```console
kubectl --context k8s-5 taint node k8s-5-m02 lab.example/dedicated=lesson:NoSchedule --overwrite
kubectl --context k8s-5 describe node k8s-5-m02
```

В `pod.yaml` выключите PREFERRED, включите SELECTOR со значением `ssd`. REQUIRED и TOLERATION отключены.

```console
kubectl --context k8s-5 apply -f results/demo-manifests/pod.yaml
kubectl --context k8s-5 -n lab-k8s-5 get pod probe --watch
```

Дождитесь `Pending`, Ctrl+C, затем `describe`. **Ожидаемый отказ:** совпавший по метке узел имеет непереносимый taint, а другой не подходит по selector.

```console
kubectl --context k8s-5 -n lab-k8s-5 describe pod probe
```

Теперь дополнительно включите TOLERATION: key `lab.example/dedicated`, value `lesson`, operator `Equal`, effect `NoSchedule`. SELECTOR остаётся включённым; REQUIRED и PREFERRED отключены.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true
kubectl --context k8s-5 apply -f results/demo-manifests/pod.yaml
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Ready pod/probe --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get pod probe -o wide
```

Ожидается `k8s-5-m02`. Selector выбрал узел, toleration позволила терпеть его ограничение. Удалите Pod и учебный taint до следующего блока:

```console
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true
kubectl --context k8s-5 taint node k8s-5-m02 lab.example/dedicated:NoSchedule-
kubectl --context k8s-5 describe node k8s-5-m02
```

## Размещение относительно других Pod

### Разнести реплики по узлам

Откройте `affinity.yaml`: один активный Deployment, `replicas: 3`, обязательная `podAntiAffinity`, селектор `app: spread-demo`, topology key `kubernetes.io/hostname`. Taints учебного опыта уже сняты.

```console
kubectl --context k8s-5 apply -f results/demo-manifests/affinity.yaml
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=spread-demo -o wide --watch
```

Дождитесь двух `Running`/`1/1` и одного `Pending`, затем Ctrl+C. Если картина иная, проверьте события и доступность обоих узлов. Подставьте имя ожидающего Pod вместо `POD_PENDING`:

```console
kubectl --context k8s-5 -n lab-k8s-5 describe pod POD_PENDING
kubectl --context k8s-5 -n lab-k8s-5 get deployment spread-demo
```

**Ожидаемое ограничение:** двум узлам не хватает третьей области hostname для трёх реплик. Полного успешного rollout здесь не ожидаем.

### Разместить реплики рядом

В том же файле замените только `podAntiAffinity` на `podAffinity`. Остальные значения сохраняются. Удалите Deployment с потомками, чтобы прежние реплики не влияли на новый опыт:

```console
kubectl --context k8s-5 -n lab-k8s-5 delete deployment spread-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete replicaset -l app=spread-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=spread-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=spread-demo
kubectl --context k8s-5 apply -f results/demo-manifests/affinity.yaml
kubectl --context k8s-5 -n lab-k8s-5 rollout status deployment/spread-demo --timeout=180s
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=spread-demo -o wide
```

Ожидаются три готовые реплики на одном узле при достаточных ресурсах. Первый Pod может начать self-affinity-группу; следующие выбирают ту же область hostname. Очистите опыт:

```console
kubectl --context k8s-5 -n lab-k8s-5 delete deployment spread-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete replicaset -l app=spread-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=spread-demo --timeout=120s
```

## ConfigMap и Secret: env и файлы

### Создать данные, затем потребителя

Откройте `config-data.yaml`: **оба документа активны**, ConfigMap `app-settings` и Secret `app-credentials`; отключённых секций нет. Покажите `data`, многострочную `app.conf`, `stringData`. Все значения учебные, адреса `.invalid` никуда не подключаются. Затем откройте `config-app.yaml`: один активный Deployment с двумя репликами, ссылки на отдельные ключи и два volume.

```console
kubectl --context k8s-5 apply -f results/demo-manifests/config-data.yaml
kubectl --context k8s-5 -n lab-k8s-5 get configmap app-settings
kubectl --context k8s-5 -n lab-k8s-5 get secret app-credentials
kubectl --context k8s-5 apply -f results/demo-manifests/config-app.yaml
kubectl --context k8s-5 -n lab-k8s-5 rollout status deployment/config-demo --timeout=180s
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=config-demo
```

Выберите один Pod и замените `CONFIG_POD` его именем во всех командах до rollout. Важно читать один и тот же Pod при сравнении старого и нового значения.

```console
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- printenv SERVER_URL DB_URL DB_USER DB_PASSWORD
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- cat /etc/demo/app.conf
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- cat /etc/credentials/password
kubectl --context k8s-5 -n lab-k8s-5 get secret app-credentials -o yaml
```

В env и файлах видны значения `v1`; в API Secret — base64 в поле `data`, хотя исходный манифест использует `stringData`. Программа получает декодированное значение. Вывод пароля допустим здесь только потому, что он вымышленный.

### Обновить данные без изменения Deployment

В `config-data.yaml` замените `v1` на `v2` в четырёх адресах: `server.url`, `db.url` и двух строках `app.conf`. Замените пароль на `demo-only-v2`. `username` остаётся `demo-user`. **Оба документа активны**, отключённых секций нет. В `config-app.yaml` ничего не меняйте.

```console
kubectl --context k8s-5 apply -f results/demo-manifests/config-data.yaml
kubectl --context k8s-5 -n lab-k8s-5 get configmap app-settings -o yaml
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- printenv SERVER_URL DB_URL DB_PASSWORD
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- cat /etc/demo/app.conf
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- cat /etc/credentials/password
```

Env остаётся с `v1`. Повторяйте две команды `cat` с паузами, пока файлы не покажут `v2`: обновление асинхронное и не обязано укладываться в 10 секунд. На обычном стенде дайте ему несколько минут; если обновления нет, используйте диагностику ниже. Имя и UID Pod при этом не меняются. Само приложение должно уметь перечитывать изменённые файлы.

### Обновить окружение через rollout

```console
kubectl --context k8s-5 -n lab-k8s-5 rollout restart deployment/config-demo
kubectl --context k8s-5 -n lab-k8s-5 rollout status deployment/config-demo --timeout=180s
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=config-demo
```

Выберите **новое** имя `CONFIG_POD` из последнего списка:

```console
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- printenv SERVER_URL DB_URL DB_PASSWORD
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- cat /etc/demo/app.conf
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- cat /etc/credentials/password
```

Теперь и env, и файлы содержат `v2`. Тома не используют `subPath`; его влияние в этом показе объясняется теоретически, без дополнительного варианта файла.

## Диагностика отклонений

### Посмотреть состояние и события

```console
kubectl --context k8s-5 get nodes -o wide
kubectl --context k8s-5 -n lab-k8s-5 get pods,jobs,cronjobs,deployments
kubectl --context k8s-5 -n lab-k8s-5 get events --sort-by=.metadata.creationTimestamp
```

Для конкретного Pod подставьте текущее имя из списка:

```console
kubectl --context k8s-5 -n lab-k8s-5 describe pod POD_NAME
kubectl --context k8s-5 -n lab-k8s-5 logs POD_NAME
```

| Симптом | Действие |
|---|---|
| `ImagePullBackOff` | проверить registry и сетевой доступ узла, исправить причину до продолжения |
| Неожиданный `Pending` | проверить selector/affinity, метки, все taints и requests; учебные Pending описаны явно выше |
| Job упала не по ожидаемой причине | прочитать `describe job batch-demo` и код выхода Pod; не считать timeout команды доказательством нужного поведения |
| `CreateContainerConfigError`/`FailedMount` | проверить namespace, имена объектов и ключей в обоих конфигурационных файлах |
| Env не обновилась | это ожидаемо до rollout; после него проверить, что выбрано новое имя Pod |
| Файлы не обновились | проверить данные API, mounts без subPath, состояние kubelet и ожидание синхронизации |
| `field is immutable` | не пытаться менять готовую Job/Pod на месте; выполнить предусмотренное удаление с ожиданием |
| CronJob не создаёт Job | проверить `suspend`, ближайшую минуту, active Job, policy и starting deadline; затем события |
| `NotFound` у динамического имени | заново выполнить get: объект мог быть удалён TTL, историей или заменой |

## Последовательная очистка

### Удалить только учебные ресурсы

Сначала остановите источник новых Job, затем остальные контроллеры и Pod. `--ignore-not-found` позволяет выполнить очистку и после частичного показа. Если Kubernetes сообщает, что ресурс уже отсутствует, продолжайте.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete cronjob clock-demo --cascade=true --wait=true --ignore-not-found
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete job -l app=clock-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=clock-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 delete job batch-demo --cascade=true --wait=true --ignore-not-found
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=batch-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 delete deployment spread-demo config-demo --cascade=true --wait=true --ignore-not-found
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete replicaset -l "app in (spread-demo,config-demo)" --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l "app in (spread-demo,config-demo)" --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true --ignore-not-found
kubectl --context k8s-5 -n lab-k8s-5 delete configmap app-settings --ignore-not-found
kubectl --context k8s-5 -n lab-k8s-5 delete secret app-credentials --ignore-not-found
kubectl --context k8s-5 -n lab-k8s-5 get pods,jobs,cronjobs,deployments
kubectl --context k8s-5 delete namespace lab-k8s-5 --wait=true --ignore-not-found
```

Namespace выделен только для занятия; его удаление убирает оставшиеся учебные объекты, если показ был прерван. Это удаление API-ресурсов, а не команда удаления внешних данных. В данном комплекте PVC и внешних хранилищ нет.

### Снять учебные изменения узлов

Сначала посмотрите метки и taints:

```console
kubectl --context k8s-5 get nodes -L lab.example/disk
kubectl --context k8s-5 describe node k8s-5-m02
```

Если `lab.example/dedicated=lesson:NoSchedule` ещё есть, снимите его; если он уже снят, пропустите первую команду. Удаляйте учебную метку только на узлах, где она присутствует:

```console
kubectl --context k8s-5 taint node k8s-5-m02 lab.example/dedicated:NoSchedule-
kubectl --context k8s-5 label node k8s-5 lab.example/disk-
kubectl --context k8s-5 label node k8s-5-m02 lab.example/disk-
kubectl --context k8s-5 get nodes -L lab.example/disk
kubectl --context k8s-5 describe node k8s-5-m02
```

Верните локальные файлы к исходным значениям из первой таблицы, чтобы следующий показ начинался в том же состоянии.

### Освободить ресурсы стенда

Для сохранения стенда с остановкой:

```console
minikube stop -p k8s-5
minikube status -p k8s-5
```

Если выделенный стенд больше не нужен, вместо остановки можно удалить профиль:

```console
minikube delete -p k8s-5
minikube profile list
```

Последняя операция необратимо уничтожает выделенный учебный кластер `k8s-5` и его локальные данные. Не заменяйте её удалением всех профилей.
