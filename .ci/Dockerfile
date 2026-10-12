FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    openjdk-11-jdk-headless openssh-server curl ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash student \
    && mkdir -p /run/sshd /home/student/.ssh /home/student/mts-hdfs-hw1
COPY runtime/hadoop-3.4.1.tar.gz /tmp/hadoop.tar.gz
RUN tar -xzf /tmp/hadoop.tar.gz -C /home/student/mts-hdfs-hw1 \
    && rm /tmp/hadoop.tar.gz \
    && chown -R student:student /home/student
COPY --chown=student:student runtime/id_ed25519.pub /home/student/.ssh/authorized_keys
RUN chmod 700 /home/student/.ssh && chmod 600 /home/student/.ssh/authorized_keys
CMD ["/usr/sbin/sshd", "-D", "-e"]
