#!/bin/bash

SWITCHOVER_COMMAND="repmgr standby switchover --siblings-follow -f /etc/repmgr/repmgr.conf --log-level DEBUG --verbose"

echo "Se va a ejecutar un switchover con el siguiente comando:"
echo $SWITCHOVER_COMMAND
echo "¿Está seguro? s/n"
read CONFIRM

if [ "$CONFIRM" != "s" ];then
	echo "Switchover cancelado"
	exit 0
fi
$SWITCHOVER_COMMAND
