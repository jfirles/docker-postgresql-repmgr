#!/bin/bash

## Valores por defecto
DEFAULT_PG_DATA=/var/lib/postgresql/data

## Validamos que esten todas la variables
## verificamos que estan seteadas las variables de la base de datos
VARS_MUST_SETTED="CLUSTER_NODE_NUMBER CLUSTER_NODE_NAME CLUSTER_HOST REPMGR_PASSWORD CHECK_USER_USERNAME CHECK_USER_PASSWORD"

for i in $VARS_MUST_SETTED;do
        VALUE=${!i}
        if [ -z $VALUE ];then
                echo "ERROR: $i env var is not setted"
                exit 1
        fi
done

## añadimos las variables para la notificación por email
NOTIFY_CONFIG_FILE=/etc/default/docker-postgresql
echo "NOTIFY_EMAIL=$NOTIFY_EMAIL" > $NOTIFY_CONFIG_FILE
echo "SMTP_SERVER=$SMTP_SERVER" >> $NOTIFY_CONFIG_FILE
echo "FROM=$FROM" >> $NOTIFY_CONFIG_FILE

## verificamos que esta la clave ssh en su sitio
SSH_KEY=/opt/ssh_postgres/id_rsa
if [ ! -f $SSH_KEY ];then
	echo "ERROR: ssh key not found at $SSH_KEY, remember mount dir with -v /local/path_ssh_postgres:/opt/ssh_postgres"
	exit 1
fi
SSH_KEY_PUB=/opt/ssh_postgres/id_rsa.pub
if [ ! -f $SSH_KEY_PUB ];then
        echo "ERROR: ssh pub key not found at $SSH_KEY_PUB, remember mount dir with -v /local/path_ssh_postgres:/opt/ssh_postgres"
        exit 1
fi
## añadimos las keys al usuario ssh
SSH_PG_DIR=/var/lib/postgresql/.ssh
mkdir -p $SSH_PG_DIR
cp $SSH_KEY $SSH_PG_DIR
cp $SSH_KEY_PUB $SSH_PG_DIR
cp $SSH_KEY_PUB $SSH_PG_DIR/authorized_keys
## añadimos la config para que no sea estrico al verificar las keys
echo "Host *" > $SSH_PG_DIR/config
echo "    StrictHostKeyChecking no" >> $SSH_PG_DIR/config
## ponemos los permisos
chown postgres:postgres -R $SSH_PG_DIR
## permiso de solo lectura a la key
chmod 0600 $SSH_PG_DIR/id_rsa


## borramos el fichero del pid de apache por si se ha quedado de antes
APACHE_PID_FILE=/var/run/apache2/apache2.pid
if [ -f $APACHE_PID_FILE ];then
        rm $APACHE_PID_FILE
fi

## creamos el fichero de config para el check en php
echo "<?php" > /var/www/html/postgresql/config.php
echo "\$dbconn = pg_connect(\"host=127.0.0.1 port=6432 dbname=$CHECK_USER_USERNAME user=$CHECK_USER_USERNAME password=$CHECK_USER_PASSWORD\");" >> /var/www/html/postgresql/config.php
echo "?>" >> /var/www/html/postgresql/config.php

## variables que luego se reemplazaran
REPLACE_VARS="$VARS_MUST_SETTED REPMGR_PASSWORD PG_DATA CLUSTER_HOST"


if [ -z "$PG_DATA" ];then
	PG_DATA=$DEFAULT_PG_DATA
fi

## verificamos si el PG_DATA es un fichero
if [ -f $PG_DATA ];then
	echo "ERROR: Specified PG_DATA=$PG_DATA is not a directory, is a file!!"
	exit 1
fi

## REPMGR
# procesamos los templates de repmgr
REPMGR_FILES="repmgr.conf repmgrd.conf"
for i in $REPMGR_FILES;do
	SRC_FILE=/opt/app/$i
	DST_FILE=/etc/repmgr/$i
	cp $SRC_FILE $DST_FILE
	## sustituimos las variables
	for j in $REPLACE_VARS;do
		VALUE=${!j}
		sed -i "s|$j|$VALUE|g" $DST_FILE
	done
done
## copiamos la configuracion del supervisord
if [ "$WITNESS" = "true" ];then
	cp /opt/app/supervisord-witness.conf /etc/supervisor/conf.d/supervisord.conf
else
	cp /opt/app/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
fi

## aliases para el usuario postgres
cp /opt/app/postgres_bash_profile /var/lib/postgresql/.bash_profile && chown postgres:postgres /var/lib/postgresql/.bash_profile

## directorio run ssh
SSH_RUN_DIR=/var/run/sshd
#if [ -f $SSH_RUN_DIR ];then
#	rm -rf $SSH_RUN_DIR
#fi
mkdir $SSH_RUN_DIR

## creamos el pg data si no existe
if [ ! -d $PG_DATA ];then
	# miramos si somos el inicial
	if [ -z "$MASTER_SERVER" ];then
		echo
		echo "========================================================================"
		echo "Server con rol MASTER, inicializamos"
		echo "========================================================================"
		echo
		# consideramos que es master
		## no existe el directorio, creamos el pg_data
	        su - postgres -c "/usr/lib/postgresql/11/bin/pg_ctl -D $PG_DATA initdb"
		## añadimos el template de pg_hba.conf
	        cp /opt/app/pg_hba-template.conf $PG_DATA/pg_hba.conf
		## añadimos la config local
		cp /opt/app/local_pg.conf $PG_DATA/local_pg.conf
        	chown postgres:postgres $PG_DATA/pg_hba.conf $PG_DATA/local_pg.conf
		## añadimos al postgresl.conf la config local
		echo "include = 'local_pg.conf'" >> $PG_DATA/postgresql.conf
	        ## arrancamos el postgres
        	su - postgres -c "/usr/lib/postgresql/11/bin/pg_ctl -D $PG_DATA -l logfile start"
	        echo "Creando el usuario de replicación \"repmgr\" con el pass \"$REPMGR_PASSWORD\""
        	## creamos el usuario de replicación
	        su - postgres -c "psql -c \"CREATE USER repmgr SUPERUSER LOGIN ENCRYPTED PASSWORD '$REPMGR_PASSWORD';\""
        	su - postgres -c "createdb -O repmgr repmgr"
		## creamos el fichero .pgpass
		echo "*:5432:repmgr:repmgr:$REPMGR_PASSWORD" > /var/lib/postgresql/.pgpass
		chown postgres:postgres /var/lib/postgresql/.pgpass
		chmod 600 /var/lib/postgresql/.pgpass
	        ## creamos el usuario checkuser
        	echo "Creando el usuario de check \"$CHECK_USER_USERNAME\" con el pass \"$CHECK_USER_PASSWORD\" y la db $CHECK_USER_USERNAME"
	        su - postgres -c "psql -c \"CREATE USER $CHECK_USER_USERNAME LOGIN ENCRYPTED PASSWORD '$CHECK_USER_PASSWORD';\""
        	## creamos una base de datos para el usuario checkuser
	        su - postgres -c "createdb -O $CHECK_USER_USERNAME $CHECK_USER_USERNAME"
		# registramos como master
		su - postgres -c "repmgr -f /etc/repmgr/repmgr.conf master register"
		# paramos el postgres
		su - postgres -c "/usr/lib/postgresql/11/bin/pg_ctl -D $PG_DATA stop"
		echo
		echo "========================================================================"
		echo "Server con rol MASTER, inicialización finalizada"
		echo "========================================================================"
		echo
	else
		## comprobamos si es un witness
		if [ "$WITNESS" = "true" ];then
			echo
			echo "========================================================================"
			echo "Server con rol WITNESS, siguiendo al master $MASTER_SERVER, inicializamos"
			echo "========================================================================"
			echo
			su - postgres -c "/usr/lib/postgresql/11/bin/pg_ctl -D $PG_DATA initdb"
			## añadimos el template de pg_hba.conf
	                cp /opt/app/pg_hba-template.conf $PG_DATA/pg_hba.conf
			## añadimos la config local
	                cp /opt/app/local_pg_witness.conf $PG_DATA/local_pg_witness.conf
        	        chown postgres:postgres $PG_DATA/pg_hba.conf $PG_DATA/local_pg_witness.conf
                	## añadimos al postgresl.conf la config local
	                echo "include = 'local_pg_witness.conf'" >> $PG_DATA/postgresql.conf
        	        ## arrancamos el postgres
                	su - postgres -c "/usr/lib/postgresql/11/bin/pg_ctl -D $PG_DATA -l logfile start"
	                echo "Creando el usuario de replicación \"repmgr\" con el pass \"$REPMGR_PASSWORD\""
        	        ## creamos el usuario de replicación
                	su - postgres -c "psql -c \"CREATE USER repmgr SUPERUSER LOGIN ENCRYPTED PASSWORD '$REPMGR_PASSWORD';\""
	                su - postgres -c "createdb -O repmgr repmgr"
			## creamos el fichero .pgpass
			echo "*:5432:repmgr:repmgr:$REPMGR_PASSWORD" > /var/lib/postgresql/.pgpass
			chown postgres:postgres /var/lib/postgresql/.pgpass
			chmod 600 /var/lib/postgresql/.pgpass
        	        ## creamos el usuario checkuser
                	echo "Creando el usuario de check \"$CHECK_USER_USERNAME\" con el pass \"$CHECK_USER_PASSWORD\" y la db $CHECK_USER_USERNAME"
	                su - postgres -c "psql -c \"CREATE USER $CHECK_USER_USERNAME LOGIN ENCRYPTED PASSWORD '$CHECK_USER_PASSWORD';\""
        	        ## creamos una base de datos para el usuario checkuser
                	su - postgres -c "createdb -O $CHECK_USER_USERNAME $CHECK_USER_USERNAME"
	                # paramos el postgres
			su - postgres -c "PGPASSWORD=$REPMGR_PASSWORD repmgr -f /etc/repmgr/repmgr.conf -U repmgr -h $MASTER_SERVER witness register"
        	        su - postgres -c "/usr/lib/postgresql/11/bin/pg_ctl -D $PG_DATA stop"
		else
			# consideramos que es slave y hay que seguir el master que se indica en esta variable
			echo
			echo "========================================================================"
			echo "Server con rol SLAVE, siguiendo al master $MASTER_SERVER, inicializamos"
			echo "========================================================================"
			echo
			## creamos el fichero .pgpass
			echo "*:5432:repmgr:repmgr:$REPMGR_PASSWORD" > /var/lib/postgresql/.pgpass
			chown postgres:postgres /var/lib/postgresql/.pgpass
			chmod 600 /var/lib/postgresql/.pgpass
			su - postgres -c "PGPASSWORD=$REPMGR_PASSWORD repmgr -f /etc/repmgr/repmgr.conf -h $MASTER_SERVER -U repmgr -d repmgr -D $PG_DATA standby clone"
			# arrancamos el postgres
			su - postgres -c "/usr/lib/postgresql/11/bin/pg_ctl -D $PG_DATA -l logfile start"
			# registramos como standby
			su - postgres -c "PGPASSWORD=$REPMGR_PASSWORD repmgr -f /etc/repmgr/repmgr.conf standby register"
			# paramos el postgres
			su - postgres -c "/usr/lib/postgresql/11/bin/pg_ctl -D $PG_DATA stop"
			echo
			echo "========================================================================"
			echo "Server con rol SLAVE, siguiendo al master $MASTER_SERVER, inicialización finalizada"
			echo "========================================================================"
			echo
		fi
	fi
else
	echo
	echo "========================================================================"
	echo "Server previamente inicializado"
	echo "========================================================================"
	echo
fi


exec "$@"
