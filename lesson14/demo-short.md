# Сокращённая демонстрация: Job, CronJob, размещение и конфигурация

Показ выполняется после теоретической части [пособия](k8s_5_method.md). Ориентир — **25–35 минут на подготовленном стенде**, включая объяснения и ручное редактирование YAML. Подготовка кластера и загрузка образа выполняются заранее. Это оценка, а не результат хронометража.

| Блок | Время |
|---|---|
| Job: успех, параллелизм, Never и OnFailure | 9–12 минут |
| CronJob: расписание и Forbid | 5–7 минут |
| nodeSelector: успешный запуск и Pending | 4–5 минут |
| ConfigMap и Secret | 7–11 минут |

Используются существующие файлы из [manifests](manifests). Не применяйте весь каталог сразу. Дополнительные опыты перечислены в конце; [полный план](demo.md) остаётся отдельным вариантом занятия.

## Подготовка до занятия

Нужны Docker с Linux-контейнерами, minikube и kubectl. Используйте выделенный учебный профиль `k8s-5` и namespace `lab-k8s-5`. Версия Kubernetes должна поддерживать поле `CronJob.spec.timeZone`. Все команды выполняются из корня репозитория:

```console
cd D:\repo\other-repo\otus-ms-k8s-5
minikube profile list
minikube start -p k8s-5 --driver=docker --nodes=2 --cpus=2 --memory=2200
kubectl --context k8s-5 wait --for=condition=Ready nodes --all --timeout=180s
kubectl --context k8s-5 get nodes -o wide
minikube image pull busybox:1.36.1 -p k8s-5
kubectl --context k8s-5 create namespace lab-k8s-5
```

Если профиль уже существует, сначала убедитесь, что это именно учебный стенд. Перед повторным показом выполните очистку в конце этого документа, затем создайте namespace заново. После полного показа также снимите оставшиеся учебные taints по его разделу очистки. Ожидаемые имена узлов — `k8s-5` и `k8s-5-m02`; если они отличаются, подставьте фактические имена в команды меток.

Восстановите исходные значения файлов перед показом:

| Файл | Исходное состояние |
|---|---|
| [job.yaml](manifests/job.yaml) | completions/parallelism `1/1`, backoffLimit `2`, activeDeadlineSeconds `300`, restartPolicy `Never`, args `['echo start; sleep 10; echo done; exit 0']`; TTL закомментирован |
| [cronjob.yaml](manifests/cronjob.yaml) | schedule `* * * * *`, timeZone `Europe/Moscow`, concurrencyPolicy `Allow`, startingDeadlineSeconds `30`, suspend `false`, история `2/1`; Job: completions/parallelism `1/1`, deadline `240`, backoffLimit `1`, args `['date; sleep 10; echo done']` |
| [pod.yaml](manifests/pod.yaml) | Для первого использования в этом плане заранее поставьте `restartPolicy: Always`, args `['exec sleep 3600']`; включите SELECTOR со значением `ssd`; REQUIRED, PREFERRED, TOLERATION оставьте закомментированными |
| [config-data.yaml](manifests/config-data.yaml) | Оба документа активны; все четыре адреса содержат `v1`, пароль `demo-only-v1` |
| [config-app.yaml](manifests/config-app.yaml) | Один активный Deployment, replicas `2`, обычные directory mounts без `subPath` |

Для включения SELECTOR удалите только `# ` перед YAML-строками `nodeSelector` и его метки, сохранив отступы. Заголовок блока оставьте комментарием. Имена ресурсов и namespace не меняйте.

При `--watch` завершайте просмотр через **Ctrl+C**: это не останавливает ресурс. Таймауты `wait` — предел ожидания, а не обязательная пауза. Удаление потомков асинхронное: не переходите к повторному `apply`, пока они не исчезли. Если `wait --for=delete` сообщает, что ресурсы не найдены, удаление уже завершено; другие ошибки требуют проверки.

## Job: результат, параллелизм и ошибки

### Выполнить одну задачу

Откройте `job.yaml`: один активный Job, TTL выключен. Покажите `spec` Job и вложенный шаблон Pod. Кратко объясните, что `Never` позволяет контейнеру завершиться без перезапуска kubelet.

```console
kubectl --context k8s-5 apply -f results/manifests/job.yaml
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Complete job/batch-demo --timeout=180s
kubectl --context k8s-5 -n lab-k8s-5 get jobs,pods -l app=batch-demo
kubectl --context k8s-5 -n lab-k8s-5 get job batch-demo
kubectl --context k8s-5 -n lab-k8s-5 logs job/batch-demo
```

Ожидаются Job `1/1`, Pod `Completed`, логи `start` и `done`. Метка `app=batch-demo` есть у Pod, сам Job проверяется отдельной командой. Работа закончена, но объекты и логи ещё доступны.

### Получить семь успехов с параллелизмом два

В том же файле измените только `completions: 7` и `parallelism: 2`. Один Job остаётся активным, TTL выключен.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete job batch-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=batch-demo --timeout=120s
kubectl --context k8s-5 apply -f results/manifests/job.yaml
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=batch-demo --watch
```

Покажите две работающие задачи и накопление завершённых Pod, затем Ctrl+C.

```console
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Complete job/batch-demo --timeout=180s
kubectl --context k8s-5 -n lab-k8s-5 get job batch-demo
```

Ожидается `7/7`: completions задаёт число успехов, parallelism — параллельность работы.

### Сравнить Never и OnFailure при ошибке

Верните `completions: 1`, `parallelism: 1`; замените args на `['echo failing; sleep 3; exit 1']`. Сохраните `Never`, backoffLimit `2`, deadline `300`, выключенный TTL. Применяется один Job.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete job batch-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=batch-demo --timeout=120s
kubectl --context k8s-5 apply -f results/manifests/job.yaml
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=batch-demo --watch
```

Дождитесь нескольких отдельных ошибочных Pod, затем Ctrl+C. **Ошибки ожидаемы:** при `Never` Job создаёт новые Pod для повторных попыток.

```console
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Failed job/batch-demo --timeout=240s
kubectl --context k8s-5 -n lab-k8s-5 describe job batch-demo
```

Найдите `BackoffLimitExceeded`. Теперь измените только `spec.template.spec.restartPolicy` на `OnFailure`, остальные значения сохраните. Активен тот же единственный Job.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete job batch-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=batch-demo --timeout=120s
kubectl --context k8s-5 apply -f results/manifests/job.yaml
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=batch-demo --watch
```

Достаточно увидеть рост `RESTARTS` у одного Pod, затем Ctrl+C. Теперь kubelet перезапускает контейнер внутри Pod; лимит повторов по-прежнему контролирует Job. Повторно ждать конечного отказа не нужно.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete job batch-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=batch-demo --timeout=120s
```

## CronJob: расписание и запрет пересечения

### Увидеть цепочку CronJob → Job → Pod

Откройте исходный `cronjob.yaml`: один активный CronJob, `Allow`, задача 10 секунд, `suspend: false`. Покажите schedule и jobTemplate.

```console
kubectl --context k8s-5 apply -f results/manifests/cronjob.yaml
kubectl --context k8s-5 -n lab-k8s-5 get jobs -l app=clock-demo --watch
```

Дождитесь первого запуска на минутной границе и завершения Job, затем Ctrl+C. Одного запуска достаточно; очистку истории здесь не наблюдаем.

```console
kubectl --context k8s-5 -n lab-k8s-5 get cronjob clock-demo
kubectl --context k8s-5 -n lab-k8s-5 get jobs,pods -l app=clock-demo
```

CronJob создаёт Job по расписанию, Job запускает Pod.

### Показать Forbid на длинной задаче

Измените только `concurrencyPolicy: Forbid` и args на `['date; sleep 90; echo done']`. Остальные параметры сохраните, активен один CronJob. Пересоздайте цепочку, чтобы предыдущие запуски не мешали наблюдению:

```console
kubectl --context k8s-5 -n lab-k8s-5 delete cronjob clock-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete job -l app=clock-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=clock-demo --timeout=120s
kubectl --context k8s-5 apply -f results/manifests/cronjob.yaml
kubectl --context k8s-5 -n lab-k8s-5 get jobs -l app=clock-demo --watch
```

Наблюдайте две последовательные минутные границы: на первой появляется Job, на второй она ещё работает, поэтому новая не создаётся. Это ожидаемый результат `Forbid`. После наблюдения Ctrl+C. Поздний запуск после завершения первой Job может зависеть от окна `startingDeadlineSeconds`; ждать его в этом опыте не нужно.

Пока идёт ожидание, объясните устно: `Allow` разрешает пересечение, `Replace` заменяет незавершённую Job. Отдельные опыты для них не выполняются.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete cronjob clock-demo --cascade=true --wait=true
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete job -l app=clock-demo --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 wait --for=delete pod -l app=clock-demo --timeout=120s
```

## nodeSelector: подходящий узел и Pending

### Запустить Pod на узле с нужной меткой

```console
kubectl --context k8s-5 label node k8s-5 lab.example/disk=hdd --overwrite
kubectl --context k8s-5 label node k8s-5-m02 lab.example/disk=ssd --overwrite
kubectl --context k8s-5 get nodes -L lab.example/disk
```

Откройте подготовленный `pod.yaml`: один Pod, `Always`, args `['exec sleep 3600']`, SELECTOR включён со значением `ssd`; REQUIRED, PREFERRED, TOLERATION отключены.

```console
kubectl --context k8s-5 apply -f results/manifests/pod.yaml
kubectl --context k8s-5 -n lab-k8s-5 wait --for=condition=Ready pod/probe --timeout=120s
kubectl --context k8s-5 -n lab-k8s-5 get pod probe -o wide
```

Ожидается `k8s-5-m02`. Selector выбирает по метке, наличие физического SSD не проверяется.

### Получить ожидаемый отказ планирования

В SELECTOR замените только `ssd` на `nvme`. Остальные секции остаются в прежнем состоянии.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true
kubectl --context k8s-5 apply -f results/manifests/pod.yaml
kubectl --context k8s-5 -n lab-k8s-5 get pod probe --watch
```

При `Pending` нажмите Ctrl+C и проверьте события:

```console
kubectl --context k8s-5 -n lab-k8s-5 describe pod probe
```

Ожидается `FailedScheduling`: подходящей метки нет ни у одного узла. Если события ещё не появились, повторите `describe` через несколько секунд. Здесь не нужно ждать `Ready`.

```console
kubectl --context k8s-5 -n lab-k8s-5 delete pod probe --wait=true
```

## ConfigMap и Secret: env против файла

### Передать конфигурацию приложению

Откройте `config-data.yaml`: оба документа активны, значения исходные (`v1`). Покажите отдельные ключи ConfigMap, многострочный `app.conf` и Secret с `stringData`. В `config-app.yaml` активен один Deployment: покажите `configMapKeyRef`, `secretKeyRef` и тома. Файлы не меняйте.

```console
kubectl --context k8s-5 apply -f results/manifests/config-data.yaml
kubectl --context k8s-5 apply -f results/manifests/config-app.yaml
kubectl --context k8s-5 -n lab-k8s-5 rollout status deployment/config-demo --timeout=180s
kubectl --context k8s-5 -n lab-k8s-5 get pods -l app=config-demo
```

Вместо `CONFIG_POD` подставьте имя одного Pod из списка. Во всех дальнейших проверках используйте **тот же Pod**.

```console
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- printenv SERVER_URL DB_URL
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- cat /etc/demo/app.conf
```

Оба способа передают значения `v1`.

### Обновить ConfigMap без перезапуска Pod

В `config-data.yaml` замените `v1` на `v2` только в четырёх адресах: `server.url`, `db.url` и двух строках `app.conf`. Secret оставьте без изменений. Оба документа по-прежнему активны; `config-app.yaml` не меняйте.

```console
kubectl --context k8s-5 apply -f results/manifests/config-data.yaml
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- printenv SERVER_URL DB_URL
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- cat /etc/demo/app.conf
```

Env остаётся с `v1`; файл асинхронно обновится до `v2`. Повторяйте только `cat` с паузами. Обновление может занять несколько минут; не обещайте аудитории фиксированные 10 секунд. Пока ожидаете, выполните короткий показ Secret ниже, затем вернитесь к `cat`.

Объясните результат: новые env попадут в новый Pod, а смонтированный файл может обновиться в существующем. Само приложение должно уметь перечитывать файл. Rollout в этом сокращённом показе не выполняется.

### Кратко показать Secret

```console
kubectl --context k8s-5 -n lab-k8s-5 get secret app-credentials -o yaml
kubectl --context k8s-5 -n lab-k8s-5 exec CONFIG_POD -- printenv DB_USER DB_PASSWORD
```

В API Secret значения представлены в `data` как base64; контейнер получает обычные строки `demo-user` и `demo-only-v1`. Base64 — кодирование, не шифрование. Здесь используются исключительно вымышленные данные. Покажите ссылки на Secret в манифесте; повторять для него опыт с обновлением env и файлов не нужно.

## Если результат отличается

```console
kubectl --context k8s-5 get nodes -o wide
kubectl --context k8s-5 -n lab-k8s-5 get pods,jobs,cronjobs,deployments
kubectl --context k8s-5 -n lab-k8s-5 get events --sort-by=.metadata.creationTimestamp
```

Для проблемного Pod возьмите фактическое имя из списка:

```console
kubectl --context k8s-5 -n lab-k8s-5 describe pod POD_NAME
```

Проверьте загрузку образа, метки узлов, taints и события планирования. Если файл ConfigMap не обновляется, проверьте, что применён `config-data.yaml`, проверяется прежний Pod, том смонтирован без `subPath`, а оба адреса внутри `app.conf` тоже изменены. Таймаут или ошибка команды — повод проверить состояние, а не продолжать вслепую.

## Очистка после показа

Namespace выделен только для демонстрации. Его удаление удалит все учебные объекты внутри, включая Deployment, ConfigMap и Secret. Стенд и файлы манифестов останутся.

```console
kubectl --context k8s-5 delete namespace lab-k8s-5 --wait=true --timeout=180s
kubectl --context k8s-5 label node k8s-5 lab.example/disk-
kubectl --context k8s-5 label node k8s-5-m02 lab.example/disk-
kubectl --context k8s-5 get nodes -L lab.example/disk
```

Если больше не нужен работающий кластер, остановите профиль:

```console
minikube stop -p k8s-5
```

Перед следующим показом восстановите значения файлов по таблице подготовки. В ходе показа изменились `job.yaml`, `cronjob.yaml`, `pod.yaml` и ConfigMap в `config-data.yaml`.

## Дополнительные опыты при наличии времени

В [полном плане](demo.md) есть самостоятельные серии для restartPolicy у Pod, Job deadline и TTL, CronJob Allow/Replace/suspend, node affinity, taints/tolerations, pod affinity/anti-affinity и rollout конфигурации. Выбирайте отдельный блок под вопросы аудитории; в оценку 25–35 минут эти опыты не входят.
