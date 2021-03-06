#!/bin/bash

# example:
# curl -s https://raw.githubusercontent.com/conbu/scripts/master/cc-syslog-01-setup.sh | /bin/bash -s 10.200.0.50 test_aws_key test_aws_sec_key test_bucket   

HOST_ELASTICSEARCH=$1
AWS_KEY_ID=$2
AWS_SEC_KEY=$3
AWS_BUCKET=$4

PATH_TDAGENTCONF=/etc/td-agent/td-agent.conf
PATH_INITD_SFLOWTOOL=/etc/init.d/sflowtool

echo "START PROCESSING cc-syslog-01-setup"

echo "STEP: package update"
apt update
#apt -y upgrade
apt install -y gcc make tmux g++

echo "STEP: install td-agent and packages"
apt install -y curl ruby
curl -L https://toolbelt.treasuredata.com/sh/install-ubuntu-xenial-td-agent2.sh | sh
/usr/sbin/td-agent-gem install fluent-plugin-elasticsearch
/usr/sbin/td-agent-gem install fluent-plugin-s3
#/usr/sbin/td-agent-gem install fluent-plugin-netflow
/usr/sbin/td-agent-gem uninstall bindata
/usr/sbin/td-agent-gem install fluent-plugin-sflow

echo "STEP: setup td-agent.conf"
cat << EOS > ${PATH_TDAGENTCONF}
<source>
  @type syslog
  port 514
  bind 0.0.0.0
  tag syslog
</source>

<source>
  @type sflow
  tag sflow.event
  port 6343
</source>

<match syslog.**>
  type copy
  <store>
    type s3
    aws_key_id ${AWS_KEY_ID}
    aws_sec_key ${AWS_SEC_KEY}
    s3_bucket ${AWS_BUCKET}
    s3_endpoint https://b.sakurastorage.jp
    s3_object_key_format %{path}%{time_slice}_%{index}.%{file_extension}
    signature_version s3

    path log_
    buffer_path /var/log/td-agent/buffer/s3
    time_slice_format %Y%m%d%H
    time_slice_wait 30m
    buffer_chunk_limit 256m
    check_apikey_on_start false
  </store>

  <store>
    type elasticsearch

    host ${HOST_ELASTICSEARCH}
    port 9200

    logstash_format true
    logstash_prefix syslog

    flush_interval 10s
  </store>
</match>

<match sflow.**>
  type copy
  <store>
    type elasticsearch
    host ${HOST_ELASTICSEARCH}
    port 9200
    type_name sflow

    logstash_format true
    logstash_prefix sflow
    logstash_dateformat %Y%m%d
  </store>
  <store>
    type file
    path /var/log/td-agent/buffer/sflow
    time_slice_format %Y%m%d
    time_slice_wait 10m
    time_format %Y%m%dT%H%M%S%z
  </store>
</match>
EOS
ls ${PATH_TDAGENTCONF}

echo "STEP: add cap_net_bind_service to ruby"
setcap 'cap_net_bind_service=ep' /opt/td-agent/embedded/bin/ruby

echo "STEP: restart td-agetn"
service td-agent restart

echo "STEP: install sflowtool"
cd /tmp/
git clone https://github.com/kplimack/sflowtool.git
cd sflowtool
./configure
make
make install

echo "STEP-obsoleted: setup /etc/init.d/sflowtool"
cat << 'EOS' > ${PATH_INITD_SFLOWTOOL}
#!/bin/sh

### BEGIN INIT INFO
# Provides:          sflowtool
# Required-Start:    $remote_fs $syslog
# Required-Stop:     $remote_fs $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Put a short description of the service here
# Description:       Put a long description of the service here
### END INIT INFO

# Change the next 3 lines to suit where you install your script and what you want to call it
DIR=/usr/local/bin/
DAEMON=$DIR/sflowtool
DAEMON_NAME=sflowtool

# Add any command line options for your daemon here
DAEMON_OPTS="-p 6343 -d 5141 -c localhost"

# This next line determines what user the script runs as.
# Root generally not recommended but necessary if you are using the Raspberry Pi GPIO from Python.
DAEMON_USER=root

# The process ID of the script when it runs is stored here:
PIDFILE=/var/run/$DAEMON_NAME.pid

. /lib/lsb/init-functions

do_start () {
    log_daemon_msg "Starting system $DAEMON_NAME daemon"
    start-stop-daemon --start --background --pidfile $PIDFILE --user $DAEMON_USER --chuid $DAEMON_USER --startas $DAEMON -- $DAEMON_OPTS
    log_end_msg $?
}
do_stop () {
    log_daemon_msg "Stopping system $DAEMON_NAME daemon"
    start-stop-daemon --stop --pidfile $PIDFILE --retry 10
    log_end_msg $?
}

case "$1" in

    start|stop)
        do_${1}
        ;;

    restart|reload|force-reload)
        do_stop
        do_start
        ;;

    status)
        status_of_proc "$DAEMON_NAME" "$DAEMON" && exit 0 || exit $?
        ;;

    *)
        echo "Usage: /etc/init.d/$DAEMON_NAME {start|stop|restart|status}"
        exit 1
        ;;

esac
exit 0
EOS
ls ${PATH_INITD_SFLOWTOOL}

echo "STEP-obsoleted: make sflowtool launch at boot"
chmod +x /etc/init.d/sflowtool
#update-rc.d sflowtool defaults

echo "STEP-obsoleted: launch sflowtool"
#/etc/init.d/sflowtool start

echo "COMPLETED"

exit 0
