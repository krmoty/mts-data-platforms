# ДЗ 1. Развертывание HDFS

Поднимем Hadoop 3.4.1 на четырех VM с Ubuntu 24.04:
VM1 — NameNode, VM2 — DataNode и SecondaryNameNode, VM3–VM4 — DataNode.
У каждого блока будет три копии. SecondaryNameNode делает checkpoint, а не заменяет NameNode при сбое.

## Подготовка

Для начала на каждой VM нужны:

- Java **11 JDK** (с `jps`), Python 3, Bash, `curl`, `tar`, `sha512sum`, `timeout`.
- Доступ к `downloads.apache.org` и `archive.apache.org`, от 2 ГБ RAM и 5 ГБ места.
- Вход по SSH-ключу с компьютера запуска. Заранее подключимся к каждой VM, сверим отпечатки ключей серверов и сохраним их в `known_hosts`.

Машины должны видеть друг друга по приватным IP. Внутри сети откроем TCP-порты:
на VM1 — `9000, 9870`, на VM2–VM4 — `9866, 9867, 9864`, дополнительно на VM2 — `9868`.
В интернет их не выставляем, т.к. Kerberos здесь не настроен. Firewall настраиваем отдельно.

## Запуск

На компьютере с Bash и SSH:

```bash
git clone https://github.com/krmoty/mts-data-platforms.git
cd mts-data-platforms/hw1
cp cluster.conf.example cluster.conf
```

В `cluster.conf` укажем свои `SSH_NODES` (адреса вида `user@host` или SSH-алиасы)
и `INTERNAL_IPS` (четыре разных приватных IPv4). Порядок в обоих массивах: VM1, VM2, VM3, VM4.

Ну и запускаем:

```bash
./cluster.sh deploy
```

Скрипт проверит зависимости, скачает Hadoop с проверкой SHA-512, создаст конфиги
и запустит сервисы. Все хранится в `~/mts-hdfs-hw1`, `sudo` не нужен.
NameNode форматируется только при первом запуске с пустым каталогом, потому что при повторном нужно сохранить данные.

## Проверка

В конце `deploy` проверка запускается сама. Отдельно ее можно повторить:

```bash
./cluster.sh check
```

Ожидаем три живых DataNode без сбоев, успешную запись и чтение файла,
`Status: HEALTHY`, `Live_repl=3` и checkpoint от SecondaryNameNode.
Результаты — в локальной `results/`, логи сервисов — в `~/mts-hdfs-hw1/logs/` на VM.

Для веб-интерфейса откроем туннель, подставив адреса VM1:

```bash
ssh -N -L 9870:10.0.0.11:9870 ubuntu@vm1
```

Вот [интерфейс NameNode](http://localhost:9870): в **Datanodes** должно быть три живых узла,
в **Overview** — ноль missing/corrupt blocks.

## Остановка и повторный запуск

```bash
./cluster.sh stop
./cluster.sh deploy
```

Данные сохраняются. Каталоги и роли VM оставляем прежними.
После перезагрузки VM тоже нужен `deploy`, т.к. автозапуска нет. На этом все :)

## Где проверялось

В [GitHub Actions](https://github.com/krmoty/mts-data-platforms/actions/runs/38273291235)
на четырех контейнерах Ubuntu внутри одной VM: запись, чтение, три реплики,
checkpoint и повторный запуск с сохранением файла прошли. На учебных VM в MWS запуск не проводился.
