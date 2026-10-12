#!/usr/bin/env bash
# Выполняется cluster.sh по SSH. Все файлы принадлежат обычному SSH-пользователю.
set -euo pipefail
umask 077
action=$1
index=$2
shift 2
ips=("$@")
version=3.4.1
lab="$HOME/mts-hdfs-hw1"
export HADOOP_HOME="$lab/hadoop-$version"
export HADOOP_CONF_DIR="$lab/conf"
export HADOOP_LOG_DIR="$lab/logs"
export HADOOP_PID_DIR="$lab/pids"
export HADOOP_IDENT_STRING=mts-hw1
export HADOOP_HEAPSIZE_MAX=512
export JAVA_HOME
JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")
hdfs="$HADOOP_HOME/bin/hdfs"
role=datanode
[[ $index != 0 ]] || role=namenode

case "$action" in
  preflight)
    for tool in java curl tar sha512sum python3 timeout; do command -v "$tool" >/dev/null; done
    "$JAVA_HOME/bin/java" -version 2>&1 | grep -E 'version "11\.' >/dev/null || {
      echo 'Для этого решения требуется Java 11, как в среде курса.' >&2; exit 1;
    }
    python3 - "${ips[@]}" <<'PY'
import ipaddress, sys
for address in sys.argv[1:]:
    ipaddress.IPv4Address(address)
PY
    ;;
  install)
    mkdir -p "$lab" "$HADOOP_LOG_DIR" "$HADOOP_PID_DIR"
    if [[ ! -x $hdfs ]]; then
      archive="hadoop-$version.tar.gz"
      base="https://downloads.apache.org/hadoop/common/hadoop-$version"
      cd "$lab"
      if ! curl -fL --retry 2 --connect-timeout 20 "$base/$archive" -o "$archive"; then
        base="https://archive.apache.org/dist/hadoop/common/hadoop-$version"
        curl -fL --retry 2 --connect-timeout 20 "$base/$archive" -o "$archive"
      fi
      curl -fL --retry 3 "$base/$archive.sha512" -o "$archive.sha512"
      sha512sum -c "$archive.sha512"
      tar -xzf "$archive"
      rm "$archive" "$archive.sha512"
    fi
    mkdir -p "$HADOOP_CONF_DIR" "$lab/data/name" "$lab/data/blocks" "$lab/data/checkpoint"
    cp "$HADOOP_HOME/etc/hadoop/log4j.properties" "$HADOOP_CONF_DIR/"
    cat > "$HADOOP_CONF_DIR/hadoop-env.sh" <<EOF
export JAVA_HOME="$JAVA_HOME"
export HADOOP_LOG_DIR="$HADOOP_LOG_DIR"
export HADOOP_PID_DIR="$HADOOP_PID_DIR"
export HADOOP_IDENT_STRING=mts-hw1
export HADOOP_HEAPSIZE_MAX=512
EOF
    cat > "$HADOOP_CONF_DIR/core-site.xml" <<EOF
<?xml version="1.0"?>
<configuration>
  <property><name>fs.defaultFS</name><value>hdfs://${ips[0]}:9000</value></property>
</configuration>
EOF
    cat > "$HADOOP_CONF_DIR/hdfs-site.xml" <<EOF
<?xml version="1.0"?>
<configuration>
  <property><name>dfs.replication</name><value>3</value></property>
  <property><name>dfs.namenode.name.dir</name><value>file://$lab/data/name</value></property>
  <property><name>dfs.datanode.data.dir</name><value>file://$lab/data/blocks</value></property>
  <property><name>dfs.namenode.checkpoint.dir</name><value>file://$lab/data/checkpoint</value></property>
  <property><name>dfs.namenode.rpc-address</name><value>${ips[0]}:9000</value></property>
  <property><name>dfs.namenode.http-address</name><value>${ips[0]}:9870</value></property>
  <property><name>dfs.namenode.secondary.http-address</name><value>${ips[1]}:9868</value></property>
  <property><name>dfs.datanode.address</name><value>${ips[$index]}:9866</value></property>
  <property><name>dfs.datanode.http.address</name><value>${ips[$index]}:9864</value></property>
  <property><name>dfs.datanode.ipc.address</name><value>${ips[$index]}:9867</value></property>
  <property><name>dfs.datanode.hostname</name><value>${ips[$index]}</value></property>
  <property><name>dfs.namenode.datanode.registration.ip-hostname-check</name><value>false</value></property>
  <property><name>dfs.namenode.checkpoint.period</name><value>60</value></property>
</configuration>
EOF
    "$hdfs" version | head -n 1
    ;;
  start)
    if [[ $index == 0 && ! -f $lab/data/name/current/VERSION ]]; then
      # Никогда не форматируем непустой каталог без VERSION: он может содержать данные.
      [[ -z $(find "$lab/data/name" -mindepth 1 -print -quit) ]] || {
        echo 'Каталог NameNode непустой, но VERSION отсутствует. Автоформатирование отменено.' >&2
        exit 1
      }
      "$hdfs" namenode -format -nonInteractive
    fi
    "$hdfs" --daemon start "$role"
    ;;
  checkpoint-start) "$hdfs" --daemon start secondarynamenode ;;
  stop)
    if [[ -x $hdfs && -d $HADOOP_CONF_DIR ]]; then
      if [[ $index == 1 ]]; then "$hdfs" --daemon stop secondarynamenode; fi
      "$hdfs" --daemon stop "$role"
    fi
    ;;
  status)
    "$hdfs" --daemon status "$role"
    if [[ $index == 1 ]]; then "$hdfs" --daemon status secondarynamenode; fi
    "$JAVA_HOME/bin/jps" -l
    ;;
  check)
    # Ждём реальную регистрацию трёх DataNode и отсутствие деградировавших узлов.
    python3 - "${ips[0]}" <<'PY'
import json, sys, time, urllib.request
url = f'http://{sys.argv[1]}:9870/jmx?qry=Hadoop:service=NameNode,name=FSNamesystemState'
for attempt in range(60):
    try:
        with urllib.request.urlopen(url, timeout=3) as response:
            state = json.load(response)['beans'][0]
        if (state['NumLiveDataNodes'] == 3 and state['NumDeadDataNodes'] == 0
                and state['NumStaleDataNodes'] == 0 and state['VolumeFailuresTotal'] == 0):
            print('DataNode: live=3, dead=0, stale=0, failed volumes=0')
            break
    except (OSError, ValueError, KeyError, IndexError):
        pass
    time.sleep(2)
else:
    raise SystemExit('Кластер не стал здоровым за 120 секунд. Проверьте logs на VM.')
PY
    timeout 120 "$hdfs" dfsadmin -safemode wait
    "$hdfs" dfsadmin -report
    sample=$(mktemp)
    trap 'rm -f "$sample"' EXIT
    printf 'HDFS homework 1: three replicas, %s\n' "$(date -u +%FT%TZ)" > "$sample"
    target="/hw1/check-$(date +%s)-$$.txt"
    "$hdfs" dfs -mkdir -p /hw1
    "$hdfs" dfs -put "$sample" "$target"
    timeout 120 "$hdfs" dfs -setrep -w 3 "$target"
    "$hdfs" dfs -cat "$target" | cmp "$sample" -
    report=$("$hdfs" fsck "$target" -files -blocks -locations)
    printf '%s\n' "$report"
    grep -q 'Status: HEALTHY' <<< "$report"
    grep -q 'Live_repl=3' <<< "$report"
    echo "PASS: запись, чтение и три реплики проверены. Файл: $target"
    ;;
  checkpoint-check)
    "$hdfs" --daemon status secondarynamenode
    # Форматирование создаёт fsimage_...0 только на NN; здесь ждём образ от SNN.
    for ((attempt=0; attempt<60; attempt++)); do
      if find "$lab/data/checkpoint" -type f -name 'fsimage_[0-9]*' ! -name '*.md5' | grep -q .; then
        find "$lab/data/checkpoint" -type f -name 'fsimage_[0-9]*' ! -name '*.md5'
        echo 'PASS: SecondaryNameNode создал checkpoint.'
        exit 0
      fi
      sleep 2
    done
    echo 'Checkpoint не появился за 120 секунд. Проверьте лог SecondaryNameNode.' >&2
    exit 1
    ;;
  *) echo "Неизвестное действие: $action" >&2; exit 1 ;;
esac
