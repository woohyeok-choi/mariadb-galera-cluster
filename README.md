# woohyeokchoi/mariadb-galera-cluster

This image automatically setup [MariaDB's Galera Cluster](https://mariadb.com/kb/en/library/galera-cluster/).

It can be used with the [Maxscale image](https://github.com/woohyeok-choi/mariadb-maxscale).

I strongly recommend to use this image in a Docker compose, not a single container.

## How to use

```bash
docker stack deploy --compose-file your-compose-file-here your-docker-stack-name
```

A compose file is like below:

```yaml
version: '3.5'
services:
  cluster-doner:
    image: woohyeokchoi/mariadb-galera-cluster
    command: ["mysqld", "--wsrep-new-cluster"]
    environment:
      GALERA_CLUSTER_NAME: galera_cluster
      DEFAULT_DB_SCHEMA: db_schema
    secrets:
      - settings
    deploy:
      replicas: 1
      restart_policy:
        delay: 5s
        max_attempts: 5
      placement:
        constraints:
          - node.role == manager
    networks:
      - db-network

  cluster-joiners:
    image: woohyeok.choi/mariadb-galera-cluster
    environment:
      GALERA_DONER_SERVICE: cluster-doner
      GALERA_CLUSTER_NAME: galera_cluster
    command: ["mysqld"]
    secrets:
      - settings
    deploy:
      replicas: 2
      restart_policy:
        delay: 5s
        max_attempts: 10
    networks:
      - db-network
networks:
  db-network:
    driver: overlay
    attachable: true
```

The Docker compose above has two different services (but same image), cluster-doner and cluster-joiners. The doner is responsible for initial setup for Galera clusters. So, you should set its replica to **only one**. The joiners are joined to a cluster after the doner competes initial setup. The number of its replicas should be equal to or greater than 2 (meaning that the number of nodes in your cluster should equal to or greater than 3).

## Environment variables

* (require) **GALERA_CLUSTER_NAME**: the name of your galera cluster
* (require) **GALERA_DONER_SERVICE**: the service name of the doner of Galera Cluster.
* MYSQL_USER, MYSQL_PASSWORD: same as MariaDB's [Docker image](https://hub.docker.com/_/mariadb/)
* **MAXSCALE_USER**, **MAXSCALE_PASSWORD**: Maxscale account when you want to use Maxscale.
  * If you want to Maxscale DB load-balancer with this image, please see my Maxscale Docker [image](https://github.com/woohyeok-choi/mariadb-maxscale)
