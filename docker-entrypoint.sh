#!/bin/bash
set -e

function info() {
    >&2 echo "[$(date "+%Y-%m-%d %H:%M:%S")][Info]" "$@"
}

function warning() {
    >&2 echo "[$(date "+%Y-%m-%d %H:%M:%S")][Warning]" "$@"
}

function error() {
    >&2 echo "[$(date "+%Y-%m-%d %H:%M:%S")][Error]" "$@"
}

CURRENT_NODE_ADDRESS=$(ip addr show eth0 | grep "inet" | awk '{print $2}' | cut -d/ -f1)

GALERA_CLUSTER_PORT=4567
GALERA_IST_PORT=4568
GALERA_SST_PORT=4569

GALERA_CLUSTER_ADDRESS="gcomm://"

SECRETS_FILE="/run/secrets/${SECRETS}"

if [ -f ${SECRETS_FILE} ]; then
    info "Found a secret file: ${SECRETS_FILE}"
    
    GALERA_DONER_SERVICE=$(crudini --get ${SECRETS_FILE} database cluster_doner)
    GALERA_CLUSTER_NAME=$(crudini --get ${SECRETS_FILE} database cluster_name)
    MAXSCALE_USER=$(crudini --get ${SECRETS_FILE} database user)
    MAXSCALE_PASSWORD=$(crudini --get ${SECRETS_FILE} database password)
    DEFAULT_DB_SCHEMA=$(crudini --get ${SECRETS_FILE} database default_schema)
fi

if [ -z "${GALERA_DONER_SERVICE}" ]; then
    error "The galera doner is not set."
    exit 1
fi

info "Try to find a galera doner: ${GALERA_DONER_SERVICE}"

for COUNT in {30..0}; do
    if GALERA_DONER_ADDRESS=$(getent hosts tasks.${GALERA_DONER_SERVICE} | awk '{print $1}' | head -n 1); then
        break;
    fi
    sleep 2
fi

if [ -z "${GALERA_DONER_ADDRESS}"] && [ ${COUNT} -eq 0 ]; then
    error "Failed to find a galera doner. Please check the status of it."
    exit 1
fi

info "Succeed to find a galera doner: ${GALERA_DONER_ADDRESS}"

if [ "${CURRENT_NODE_ADDRESS}" == "${GALERA_DONER_ADDRESS}" ]; then
    info "This node is a galera doner."

    if [ -n "${DEFAULT_DB_SCHEMA}" ]; then
        info "Found default schema..."

cat<< EOF >> /docker-entrypoint-initdb.d/sql-default-schema.sql
CREATE SCHEMA IF NOT EXISTS ${DEFAULT_DB_SCHEMA} CHARACTER SET = UTF8MB4 ;

EOF
    fi
else
    info "This node is one of galera joiners."
    GALERA_CLUSTER_ADDRESS="gcomm://${GALERA_DONER_ADDRESS}?pc.wait_prim=no"
fi


info "Generate Galera Cluster configuration file..."

cat<<EOF >> /etc/mysql/conf.d/galera-cluster.cnf
[mysqld]
# wsrep options
wsrep_cluster_name=${GALERA_CLUSTER_NAME}
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_address=${GALERA_CLUSTER_ADDRESS}
wsrep_node_address=${CURRENT_NODE_ADDRESS}:${GALERA_CLUSTER_PORT}
wsrep_sst_method=rsync
wsrep_provider_options="gcache.size=256M;base_port=${GALERA_CLUSTER_PORT};ist.recv_addr=${CURRENT_NODE_ADDRESS}:${GALERA_IST_PORT}" 
wsrep_sst_receive_address=${CURRENT_NODE_ADDRESS}:${GALERA_SST_PORT}

# general options
binlog_format=ROW
bind-address=0.0.0.0
datadir=/var/lib/mysql
net_read_timeout=600
net_write_timeout=180
wait_timeout=86400
interactive_timeout=86400
max_allowed_packet=16M
connect_timeout=60

# InnoDB options
default_storage_engine=InnoDB
innodb_buffer_pool_size=122M
innodb_autoinc_lock_mode=2
innodb_doublewrite=1
innodb_flush_log_at_trx_commit=0
EOF
 


if [ -z ${MAXSCALE_USER} ] || [ -z ${MAXSCALE_PASSWORD} ]; then
    warning "Maxscale account has non-zero user name and password. Only Galera Cluster is built."
else
cat<< EOF >> /docker-entrypoint-initdb.d/sql-account-maxscale.sql
CREATE USER '${MAXSCALE_USER}'@'%' IDENTIFIED BY '${MAXSCALE_PASSWORD}' ;
GRANT SELECT ON mysql.user TO '${MAXSCALE_USER}'@'%' ;
GRANT SELECT ON mysql.db TO '${MAXSCALE_USER}'@'%' ;
GRANT SELECT ON mysql.tables_priv TO '${MAXSCALE_USER}'@'%' ;
GRANT CREATE ON *.* TO '${MAXSCALE_USER}'@'%' ;
GRANT SHOW DATABASES ON *.* TO '${MAXSCALE_USER}'@'%' ;
GRANT REPLICATION CLIENT ON *.* TO '${MAXSCALE_USER}'@'%' ;
GRANT SELECT, INSERT, UPDATE, DELETE ON *.* TO '${MAXSCALE_USER}'@'%' ;
GRANT DROP ON *.* TO '${MAXSCALE_USER}'@'%' ;
FLUSH PRIVILEGES ;

EOF

fi

