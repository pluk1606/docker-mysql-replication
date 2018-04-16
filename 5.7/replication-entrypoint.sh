#!/bin/bash
set -eo pipefail

cat > /etc/mysql/mysql.conf.d/repl.cnf << EOF
[mysqld]
log-bin=mysql-bin
relay-log=mysql-relay
#bind-address=0.0.0.0
#skip-name-resolve
EOF

if [[ -z $MASTER_ROOT_PASSWORD ]];then

    echo MASTER_ROOT_PASSWORD is mandatory.

else
    #Getting server-id not used
    #TODO: maybe server id can be setted from command and check if it's free
    #SERVER_ID=$(mysql -u root -p$MASTER_ROOT_PASSWORD -h$MASTER_HOST -P$MASTER_PORT -e "SHOW SLAVE HOSTS;" | sed 's/^.* \(".*"$\)/\1/' | awk 'NR>1 {print $1}' | awk 'BEGIN{a=   0}{if ($1>0+a) a=$1} END{print a+1}')

    echo  Server id = "$SERVER_ID" and master root password = "$MASTER_ROOT_PASSWORD"

    # If there is a linked master use linked container information
    if [ -n "$MASTER_PORT_3306_TCP_ADDR" ]; then
      export MASTER_HOST=$MASTER_PORT_3306_TCP_ADDR
      export MASTER_PORT=$MASTER_PORT_3306_TCP_PORT
    fi

    if [ -z "$MASTER_HOST" ]; then
      export SERVER_ID=1
      cat >/docker-entrypoint-initdb.d/init-master.sh  <<'EOF'
#!/bin/bash

echo Creating replication user ...
mysql -u root -e "\
  GRANT \
    FILE, \
    SELECT, \
    SHOW VIEW, \
    LOCK TABLES, \
    RELOAD, \
    REPLICATION SLAVE, \
    REPLICATION CLIENT \
  ON *.* \
  TO '$REPLICATION_USER'@'%' \
  IDENTIFIED BY '$REPLICATION_PASSWORD'; \
  FLUSH PRIVILEGES; \
"
EOF

    else
        # TODO: make server-id discoverable
        export SERVER_ID=$SERVER_ID
        cp -v /init-slave.sh /docker-entrypoint-initdb.d/
        cat > /etc/mysql/mysql.conf.d/repl-slave.cnf << EOF
[mysqld]
log-slave-updates
master-info-repository=TABLE
relay-log-info-repository=TABLE
relay-log-recovery=1
EOF
    fi

    cat > /etc/mysql/mysql.conf.d/server-id.cnf << EOF
[mysqld]
server-id=$SERVER_ID
read_only=on
sql_mode="NO_ENGINE_SUBSTITUTION"
character-set-server = utf8
collation-server = utf8_general_ci
EOF

    exec docker-entrypoint.sh "$@"

fi
