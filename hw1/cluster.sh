#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f cluster.conf ]]; then
  echo 'Скопируйте cluster.conf.example в cluster.conf и укажите адреса четырёх VM.' >&2
  exit 1
fi
# shellcheck source=cluster.conf.example
source cluster.conf
[[ ${#SSH_NODES[@]} -eq 4 && ${#INTERNAL_IPS[@]} -eq 4 ]] || {
  echo 'Нужны ровно четыре SSH-адреса и четыре внутренних IP.' >&2; exit 1;
}
for ip in "${INTERNAL_IPS[@]}"; do
  [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "Ожидался IPv4-адрес: $ip" >&2; exit 1;
  }
done
[[ $(printf '%s\n' "${INTERNAL_IPS[@]}" | sort -u | wc -l) -eq 4 ]] || {
  echo 'Внутренние адреса VM должны различаться.' >&2; exit 1;
}
for host in "${SSH_NODES[@]}"; do
  [[ $host =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.@-]*$ ]] || {
    echo "Некорректный SSH-адрес: $host" >&2; exit 1;
  }
done

remote() {
  local index=$1 action=$2
  echo "--- ${SSH_NODES[$index]}: $action ---"
  ssh -o BatchMode=yes -o ConnectTimeout=10 "${SSH_NODES[$index]}" \
    bash -s -- "$action" "$index" "${INTERNAL_IPS[@]}" < node.sh
}

case "${1:-}" in
  deploy)
    # Проверяем доступ ко всем VM прежде, чем менять кластер.
    for i in 0 1 2 3; do remote "$i" preflight; done
    for i in 1 2 3 0; do remote "$i" stop; done
    for i in 0 1 2 3; do remote "$i" install; done
    remote 0 start
    for i in 1 2 3; do remote "$i" start; done
    remote 1 checkpoint-start
    "$0" check
    ;;
  check)
    mkdir -p results
    for i in 0 1 2 3; do remote "$i" status; done
    remote 0 check | tee results/hdfs-check.txt
    remote 1 checkpoint-check | tee results/checkpoint-check.txt
    ;;
  stop)
    for i in 1 2 3 0; do remote "$i" stop; done
    ;;
  *) echo "Использование: $0 {deploy|check|stop}" >&2; exit 1 ;;
esac
