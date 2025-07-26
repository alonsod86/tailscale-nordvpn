#!/bin/sh

set -x

tailscaled &

sleep 10s
ps auxwwf

ip route del default
ip route add default via $IP_NORDVPN dev eth0

INSTANCE_NAME_=$(echo $INSTANCE_NAME | sed 's/_/-/g')

#tailscale up --advertise-exit-node --login-server https://headscale.limau.net
if [ -n "$TAILSCALE_UP_LOGIN_SERVER" ]; then
  LOGIN_SERVER="--login-server $TAILSCALE_UP_LOGIN_SERVER"
  tailscale up --advertise-exit-node --hostname $INSTANCE_NAME_ --login-server $TAILSCALE_UP_LOGIN_SERVER
else
  tailscale up --advertise-exit-node --hostname $INSTANCE_NAME_ $LOGIN_SERVER 
fi

apk add mtr curl prometheus-node-exporter tinyproxy jq mosquitto-clients

cat <<EOF > /etc/tinyproxy.conf
Port 80
Listen 0.0.0.0
Timeout 600
ReversePath "/" "http://${IP_NORDVPN}:80/"
EOF

tinyproxy -c /etc/tinyproxy.conf

nohup /usr/bin/node_exporter > /tmp/node_exporter.log 2>&1 &

while [ 1 ]; do
  sleep 60
  if tailscale status --json | jq -e '.BackendState=="Running" and (.TailscaleIPs|length>0) and (.HealthWarnings|length==0)' > /dev/null; then
    STATUS=healthy
  else
    STATUS=unhealthy
  fi
  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  mosquitto_pub \
    -h "$MQTT_BROKER" -u "$MQTT_USER" -P "$MQTT_PASS" \
    -t "${TOPIC_PREFIX}/tailscale" \
    -m "{\"status\":\"$STATUS\",\"ts\":\"$TIMESTAMP\"}"
done
