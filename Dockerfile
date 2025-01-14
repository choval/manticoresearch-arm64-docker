FROM ubuntu:focal

RUN groupadd -r manticore && useradd -r -g manticore manticore

ENV GOSU_VERSION 1.11
ENV MANTICORE_VERSION 3.6.0

RUN set -x \
    && apt-get update && apt-get install -y --no-install-recommends ca-certificates wget gnupg dirmngr && rm -rf /var/lib/apt/lists/* \
    && wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture)" \
    && wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$(dpkg --print-architecture).asc" \
    && export GNUPGHOME="$(mktemp -d)" \
    && gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
    && gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu \
    && { command -v gpgconf > /dev/null && gpgconf --kill all || :; } \
    && rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc \
    && chmod +x /usr/local/bin/gosu \
    && gosu nobody true \
    && wget https://repo.manticoresearch.com/manticore-repo.noarch.deb \
    && dpkg -i manticore-repo.noarch.deb
RUN export VERSION=`wget -q -O- https://repo.manticoresearch.com/service/rest/repository/browse/manticoresearch_focal_dev/packages/m/manticore/|grep href|tail -n1|sed -e 's/<[^>]*>//g'|sed -e 's/ *//g'` \
    && export DEB_URI=https://repo.manticoresearch.com/repository/manticoresearch_focal_dev/pool/m/manticore/manticore_${VERSION}_arm64.deb \
    && wget -q $DEB_URI \
    && dpkg -i `basename $DEB_URI` \
    && rm `basename $DEB_URI` \
    && rm manticore-repo.noarch.deb
RUN mkdir -p /var/run/manticore && mkdir -p /var/lib/manticore/replication \
    && apt-get update && apt install -y  libexpat1 libodbc1 libpq5 openssl libcrypto++6 mysql-client \
    && apt-get purge -y --auto-remove ca-certificates wget \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /usr/bin/mariabackup /usr/bin/mysqldump /usr/bin/mysqlslap /usr/bin/mysqladmin /usr/bin/mysqlimport /usr/bin/mysqlshow /usr/bin/mbstream /usr/bin/mysql_waitpid /usr/bin/innotop /usr/bin/mysqlaccess /usr/bin/mytop /usr/bin/mysqlreport /usr/bin/mysqldumpslow /usr/bin/mysql_find_rows /usr/bin/mysql_fix_extensions /usr/bin/mysql_embedded /usr/bin/mysqlcheck \
    && rm -f /usr/bin/spelldump /usr/bin/wordbreaker \
    && mkdir -p /var/run/mysqld/ && chown manticore:manticore /var/run/mysqld/ \
    && echo "\n[mysql]\nsilent\nwait\ntable\n" >> /etc/mysql/my.cnf

COPY manticore.conf /etc/manticoresearch/
COPY sandbox.sql /sandbox.sql
COPY .mysql_history /root/.mysql_history

COPY docker-entrypoint.sh /usr/local/bin/
RUN ln -s usr/local/bin/docker-entrypoint.sh /entrypoint.sh
WORKDIR /var/lib/manticore
ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 9306
EXPOSE 9308
EXPOSE 9312
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8
CMD ["searchd", "--nodetach"]
