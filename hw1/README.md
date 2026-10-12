# ДЗ № 1. Кластер HDFS на четырёх VM

В работе автоматизировано развёртывание **NameNode, SecondaryNameNode и трёх DataNode**.
Использую Apache Hadoop 3.4.1 и Java 11. Целевая среда — четыре VM Ubuntu 24.04,
как указано в общих правилах курса. Все команды Hadoop выполняются обычным
пользователем, установка находится в `~/mts-hdfs-hw1`, `sudo` скриптам не нужен.

## Схема

| VM | Процессы | Назначение |
|---|---|---|
| VM1 | NameNode | Пространство имён, метаданные и расположение блоков |
| VM2 | DataNode + SecondaryNameNode | Блоки данных и создание checkpoint метаданных |
| VM3 | DataNode | Блоки данных |
| VM4 | DataNode | Блоки данных |

```text
                     NameNode (VM1)
                      /     |     \
           DataNode       DataNode       DataNode
             (VM2)          (VM3)          (VM4)
               |
      SecondaryNameNode (VM2) <-- fsimage + edits --> NameNode
```

Клиент запрашивает у NameNode расположение блоков, а сами данные читает
и записывает через DataNode. `dfs.replication=3` означает три копии блока:
при трёх работающих DataNode каждая хранит по одной копии.
SecondaryNameNode объединяет `fsimage` и журнал `edits` в контрольную точку.
Он **не заменяет автоматически отказавший NameNode**: высокая доступность
NameNode в этой работе не настраивается. Размещение SNN на VM2 отделяет его
checkpoint от диска NameNode и укладывается в четыре предоставляемые VM.

## Подготовка

На каждой VM нужны Bash, Java **11 JDK** (включая `jps`), Python 3, `curl`, `tar`,
`sha512sum`, `timeout`, доступ к `downloads.apache.org` / `archive.apache.org` и свободный диск.
Для небольшого стенда рекомендую от 2 ГБ RAM на VM и 5 ГБ свободного места.
На компьютере запуска нужны Bash и SSH; Docker и Ansible не требуются.

SSH-пользователь должен входить на все четыре VM по ключу без интерактивного
пароля. Ключ остаётся на компьютере запуска: SSH между VM скриптам не нужен,
каждый демон запускается отдельной командой с компьютера управления.
При первом подключении проверьте отпечаток ключа сервера и добавьте его
обычным `ssh user@host` в `known_hosts`. Нестандартный порт, ключ или бастион
можно задать через алиасы в `~/.ssh/config`.

Для этого учебного стенда порты HDFS должны быть доступны **только в приватной
сети кластера**, SSH — с вашего адреса. Права HDFS включены по умолчанию,
но без Kerberos они не обеспечивают аутентификацию для недоверенной сети.

| Порт TCP | Где | Для чего |
|---|---|---|
| 9000 | VM1 | RPC NameNode |
| 9870 | VM1 | Web UI NameNode и передача checkpoint |
| 9866 | VM2–VM4 | Чтение, запись и репликация блоков |
| 9867 | VM2–VM4 | IPC DataNode |
| 9864 | VM2–VM4 | Web UI DataNode |
| 9868 | VM2 | Web UI и HTTP SecondaryNameNode |

Приватные IP должны маршрутизироваться между всеми четырьмя VM.
Скрипты не меняют облачные правила доступа и системный firewall.

## Запуск

```bash
git clone https://github.com/krmoty/mts-data-platforms.git
cd mts-data-platforms/hw1
cp cluster.conf.example cluster.conf
# Откройте cluster.conf и замените SSH_NODES и INTERNAL_IPS своими адресами.
./cluster.sh deploy
```

`cluster.conf` исключён из Git. Порядок узлов в обоих массивах одинаковый:
VM1, VM2, VM3, VM4. SSH-адрес может быть публичным или алиасом, а
`INTERNAL_IPS` содержит четыре разных приватных IPv4-адреса.

Скрипт последовательно:

1. Проверяет SSH, зависимости и Java 11 на всех узлах.
2. Останавливает ранее запущенные процессы именно этого стенда.
3. Скачивает Hadoop с Apache Downloads (резервный источник — Apache Archive),
   проверяет SHA-512 и распаковывает его.
   При повторном запуске установленный дистрибутив используется снова.
4. Создаёт `core-site.xml`, `hdfs-site.xml`, `hadoop-env.sh` и отдельные
   каталоги для метаданных, блоков, checkpoint, PID и логов.
5. Форматирует NameNode **только при первом запуске с пустым каталогом**.
6. Запускает NameNode, три DataNode и SecondaryNameNode.
7. Выполняет проверку работоспособности.

Все параметры адресов формируются из конфига. Демоны слушают приватные IP.
Проверка обратного DNS для регистрации DataNode отключена, поскольку в
учебном стенде используются IP без обязательных PTR-записей.
Период checkpoint — 60 секунд, чтобы результат можно было быстро увидеть.

## Проверка результата

```bash
./cluster.sh check
```

Проверка завершится с ненулевым кодом при ошибке. Она проверяет:

- Запущенные процессы на всех четырёх VM.
- Через JMX NameNode: `live=3`, `dead=0`, `stale=0`, `failed volumes=0`.
- Выход из safe mode и отчёт `hdfs dfsadmin -report`.
- Загрузку небольшого файла в `/hw1`, ожидание трёх реплик и совпадение
  прочитанного файла с исходным.
- `hdfs fsck`: `Status: HEALTHY` и `Live_repl=3`.
- Наличие созданного SecondaryNameNode файла checkpoint.

Текстовый результат сохраняется локально в `results/`. Тестовый файл остаётся
в HDFS, чтобы его можно было посмотреть в интерфейсе и после перезапуска.
Повторная проверка создаёт новый файл с уникальным именем.

Для Web UI откройте SSH-туннель (подставьте IP VM1 и SSH-адрес):

```bash
ssh -N -L 9870:10.0.0.11:9870 ubuntu@vm1
```

Откройте [http://localhost:9870](http://localhost:9870). На странице **Datanodes**
должны быть три живых узла без деградации, на **Overview** — отсутствие
missing/corrupt blocks. В **Utilities → Browse the file system** виден `/hw1`.

Для ручных команд на VM1:

```bash
export HADOOP_HOME="$HOME/mts-hdfs-hw1/hadoop-3.4.1"
export HADOOP_CONF_DIR="$HOME/mts-hdfs-hw1/conf"
export PATH="$HADOOP_HOME/bin:$PATH"
hdfs dfsadmin -report
hdfs dfs -ls /hw1
hdfs fsck /hw1 -files -blocks -locations
```

Логи каждого узла: `~/mts-hdfs-hw1/logs/`.
При проблеме с запуском сначала посмотрите `.log` и `.out` соответствующего
демона; типичные причины — закрытые порты, неверный приватный IP, Java другой
версии, занятый порт или недостаток места. После исправления повторите `deploy`.

## Остановка и повторный запуск

```bash
./cluster.sh stop
./cluster.sh deploy
```

Остановка сохраняет данные. `deploy` перезапускает процессы, не форматируя
существующий NameNode. Самостоятельно удалять его метаданные при сохранённых
DataNode нельзя: это создаст другой cluster ID и нарушит целостность кластера.
После перезагрузки VM запустите `deploy` снова: автозапуск ОС здесь не настроен.
Каталог стенда и роль каждой VM при повторном запуске должны оставаться прежними.

## Воспроизводимость

В [GitHub Actions](https://github.com/krmoty/mts-data-platforms/actions)
предусмотрен запуск этих же скриптов по SSH на четырёх изолированных контейнерах
Ubuntu 24.04 с Java 11, включая повторное развёртывание и проверку сохранности
файла. Это проверка автоматизации; контейнерный стенд не является проверкой
доступности конкретных VM и правил сети MWS.

## Источники

- Материалы первого модуля курса: архитектура Hadoop, HDFS и развёртывание;
  [условие ДЗ № 1](https://go.teachbase.ru/education/listener/course_player/sessions/1415858/tasks/412727).
- [Apache Hadoop: Cluster Setup](https://hadoop.apache.org/docs/r3.4.1/hadoop-project-dist/hadoop-common/ClusterSetup.html).
- [HDFS Users Guide: Secondary NameNode](https://hadoop.apache.org/docs/r3.4.1/hadoop-project-dist/hadoop-hdfs/HdfsUserGuide.html#Secondary_NameNode).
- [HDFS Commands Guide](https://hadoop.apache.org/docs/r3.4.1/hadoop-project-dist/hadoop-hdfs/HDFSCommands.html).
