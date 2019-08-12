FROM debian:buster
MAINTAINER Jose Fco. Irles <jfirles@siptize.com>
LABEL maintainer="jfirles@siptize.com"
LABEL "com.siptize.vendor"="Siptize S.L."
LABEL "com.siptize.project"="common"
LABEL "com.siptize.app"="postgres-repmgr"
LABEL "com.siptize.version"="11.0.0"
LABEL version="11.0.0"

ENV PG_DATA /var/lib/postgresql/data

## zona horaria
RUN echo "Europe/Madrid" > /etc/timezone
RUN rm /etc/localtime && ln -s /usr/share/zoneinfo/Europe/Madrid /etc/localtime

## actualizamos e instalamos lo basico
RUN apt-get update && apt-get dist-upgrade -y && apt-get install curl ca-certificates gnupg openssh-server rsync -y

## añadimos el repository key
RUN curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -

## Añadimos el repositorio
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ buster-pgdg main" > /etc/apt/sources.list.d/pgdg.list

## Actualizamos el listado de paquetes
RUN apt-get update && apt-get install -y postgresql-11 postgresql-11-partman \
 postgresql-11-repmgr repmgr supervisor pgbouncer libapache2-mod-php apache2 \
 php-pgsql openssh-server && apt-get clean

## Añadimos el entrypoint
ADD files/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

## Añadimos el script para hacer switchover
ADD files/repmgr_switchover.sh /usr/local/bin/repmgr_switchover.sh

## Borramos el cluster que crea debian por defecto
RUN pg_dropcluster 11 main

RUN mkdir /opt/app

## Añadimos el pg_hba.conf
ADD files/pg_hba-template.conf /opt/app/pg_hba-template.conf

## Añadimos la config de pgbouncer
ADD files/pgbouncer.ini /etc/pgbouncer/pgbouncer.ini

## añadimos los templates de rpmgrd
RUN mkdir /etc/repmgr
ADD files/repmgr.conf /opt/app/repmgr.conf
ADD files/repmgrd.conf /opt/app/repmgrd.conf
ADD files/local_pg.conf /opt/app/local_pg.conf
ADD files/local_pg_witness.conf /opt/app/local_pg_witness.conf

## añadimos el script de promote
ADD files/repmgrd_promote /usr/local/bin/repmgrd_promote
RUN chmod a+x /usr/local/bin/repmgrd_promote

## supervisord
ADD files/supervisord-main.conf /etc/supervisor/supervisord.conf
ADD files/supervisord.conf /opt/app/supervisord.conf
ADD files/supervisord-witness.conf /opt/app/supervisord-witness.conf

## añadimos el bash_profile para el usuario postgres
ADD files/postgres_bash_profile /opt/app/postgres_bash_profile

## añadimos el directorio para monitorizar el estado
RUN mkdir /var/www/html/postgresql
ADD files/index_check_postgres.php /var/www/html/postgresql/index.php

EXPOSE 80 5432 6432

ENTRYPOINT ["docker-entrypoint.sh"]
#CMD ["/bin/bash"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
