FROM mariadb:latest
LABEL MAINTAINER="Woohyeok Choi <woohyeok.choi@kaist.ac.kr>"

RUN apt-get update \
    && apt-get install -y python python-pip 
    
RUN pip2 install --no-cache-dir crudini

RUN touch /docker-entrypoint-initdb.d/sql-default-schema.sql \ 
            /docker-entrypoint-initdb.d/sql-account-maxscale.sql \ 
            /etc/mysql/conf.d/galera-cluster.cnf \
    && chown mysql:mysql -R /docker-entrypoint-initdb.d \
    && chown mysql:mysql -R /etc/mysql/conf.d/ 

RUN ln -sf /usr/share/zoneinfo/Asia/Seoul /etc/localtime
COPY ./docker-entrypoint.sh /docker-entrypoint-initdb.d/

VOLUME [ "/var/lib/mysql" ]
EXPOSE 3306 4567 4568 4569

CMD ["mysqld"]