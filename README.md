# Manticore Search Docker image

This is the git repo of official [Docker image](https://hub.docker.com/r/manticoresearch/manticore/) for [Manticore Search](https://manticoresearch.com/).

Manticore Search is a powerful free open source search engine with a focus on low latency and high throughput full-text search and high volume stream filtering. It helps thousands of companies from small to large, such as Craigslist, to search and filter petabytes of text data on a single or hundreds of nodes, do stream full-text filtering, add auto-complete, spell correction, more-like-this, faceting and other search-related technologies to their sites.

The default configuration includes a sample Real-Time index and listens on the default ports:
  * `9306` for connections from a MySQL client
  * `9308` for connections via HTTP
  * `9312` for connections via a binary protocol (e.g. in case you run a cluster)

The image comes with libraries for easy indexing data from MySQL, PostgreSQL XML and CSV files.

# How to run this image

## Quick usage

The below is the simplest way to start Manticore in a container and log in to it via mysql client:
  
```
docker run --name manticore --rm -d manticoresearch/manticore && docker exec -it manticore mysql -w && docker stop manticore
```

When you exit from the mysql client it stops and removes the container, so use it only for testing / sandboxing purposes. See below how to use it in production.

The image comes with a sample index which can be loaded like this:

```
mysql> source /sandbox.sql
```

Also the mysql client has in history several sample queries that you can run on the above index, just use Up/Down arrows in the client to see and run them.

## Production use 


### Ports and mounting points

For data persistence the  folder `/var/lib/manticore/` should be mounted to local storage or other desired storage engine. 

Configuration file inside the instance is located at  `/etc/manticoresearch/manticore.conf`. For custom settings, this file should be mounted to own configuration file.

The ports are 9306/9308/9312 for SQL/HTTP/Binary, expose them depending on how you are going to use Manticore. For example:

```
docker run --name manticore -v $(pwd)/data:/var/lib/manticore -p 127.0.0.1:9306:9306 -p 127.0.0.1:9308:9308 -d manticoresearch/manticore
```

```
docker run --name manticore -v $(pwd)/manticore.conf:/etc/manticoresearch/manticore.conf -v $(pwd)/data:/var/lib/manticore/data/ -p 127.0.0.1:9306:9306 -p 127.0.0.1:9308:9308 -d manticoresearch/manticore
```

Make sure to remove `127.0.0.1:` if you want the ports to be available for external hosts.

### Docker-compose

In many cases you might want to use Manticore together with other images specified in a docker-compose YAML file. Here is the minimal recommended specification for Manticore Search in docker-compose.yml:

```
version: '2.2'

services:
  manticore:
    container_name: manticore
    image: manticoresearch/manticore
    restart: always
    ports:
      - 127.0.0.1:9306:9306
      - 127.0.0.1:9308:9308
    ulimits:
      nproc: 65535
      nofile:
         soft: 65535
         hard: 65535
      memlock:
        soft: -1
        hard: -1
    volumes:
      - ./data:/var/lib/manticore
#      - ./manticore.conf:/etc/manticoresearch/manticore.conf # uncommment if you use a custom config
```

Besides using the exposed ports 9306 and 9308 you can log into the instance by running `docker-compose exec manticore mysql`.

### HTTP protocol

HTTP protocol is exposed on port 9308. You can map the port locally and connect with curl:

```
docker run --name manticore -p 9308:9308 -d manticoresearch/manticore
```

Create a table:
```
curl -X POST 'http://127.0.0.1:9308/sql' -d 'mode=raw&query=CREATE TABLE testrt ( title text, content text, gid integer)'
```
Insert a document:

```
curl -X POST 'http://127.0.0.1:9308/json/insert' -d'{"index":"testrt","id":1,"doc":{"title":"Hello","content":"world","gid":1}}'
```

Perform a simple search:

```
curl -X POST 'http://127.0.0.1:9308/json/search' -d '{"index":"testrt","query":{"match":{"*":"hello world"}}}'
```

### Logging

By default, the daemon is set to send it's logging to `/dev/stdout`, which can be viewed from the host with:


```
docker logs manticore
```

The query log can be diverted to Docker log by passing variable `QUERY_LOG_TO_STDOUT=true`.


### Multi-node cluster with replication

Here is a simple `docker-compose.yml` for defining a two node cluster:

```
version: '2.2'

services:

  manticore-1:
    image: manticoresearch/manticore
    restart: always
    ulimits:
      nproc: 65535
      nofile:
         soft: 65535
         hard: 65535
      memlock:
        soft: -1
        hard: -1
    networks:
      - manticore
  manticore-2:
    image: manticoresearch/manticore
    restart: always
    ulimits:
      nproc: 65535
      nofile:
        soft: 65535
        hard: 65535
      memlock:
        soft: -1
        hard: -1
    networks:
      - manticore
networks:
  manticore:
    driver: bridge
```
* Start it: `docker-compose up`
* Create a cluster: 
  ```
  $ docker-compose exec manticore-1 mysql

  mysql> CREATE TABLE testrt ( title text, content text, gid integer);

  mysql> CREATE CLUSTER posts;
  Query OK, 0 rows affected (0.24 sec)

  mysql> ALTER CLUSTER posts ADD testrt;
  Query OK, 0 rows affected (0.07 sec)
  
  MySQL [(none)]> exit
  Bye
  ```
* Join to the the cluster on the 2nd instance
  ```
  $ docker-compose exec manticore-2 mysql

  mysql> JOIN CLUSTER posts AT 'manticore-1:9312';
  mysql> INSERT INTO posts:testrt(title,content,gid)  VALUES('hello','world',1);
  Query OK, 1 row affected (0.00 sec)
  
  MySQL [(none)]> exit
  Bye
  ```
  
* If you now go back to the first instance you'll see the new record:
  ```
  $ docker-compose exec manticore-1 mysql

  MySQL [(none)]> select * from testrt;
  +---------------------+------+-------+---------+
  | id                  | gid  | title | content |
  +---------------------+------+-------+---------+
  | 3891565839006040065 |    1 | hello | world   |
  +---------------------+------+-------+---------+
  1 row in set (0.00 sec)
  
  MySQL [(none)]> exit
  Bye
  ```

## Memory locking and limits

It's recommended to overwrite the default ulimits of docker for the Manticore instance:

```
 --ulimit nofile=65536:65536
```

For best performance, index components can be mlocked into memory. When Manticore is run under Docker, the instance requires additional privileges to allow memory locking. The following options must be added when running the instance:

```
  --cap-add=IPC_LOCK --ulimit memlock=-1:-1 
```

## Custom config

If you want to run Manticore with your custom config containing indexes definition you will need to mount the configuration to the instance:

```
docker run --name manticore -v $(pwd)/manticore.conf:/etc/manticoresearch/manticore.conf -v $(pwd)/data/:/var/lib/manticore -p 127.0.0.1:9306:9306 -d manticoresearch/manticore
```

Take into account that Manticore search inside the container is run under user `manticore`. Performing operations with index files (like creating or rotating plain indexes) should be also done under `manticore`. Ootherwise the files will be created under `root` and the search daemon won't have rights to open them. For example here is how you can rotate all indexes:

```
docker exec -it manticore gosu manticore indexer --all --rotate
```
 
# Issues

For reporting issues, please use the [issue tracker](https://github.com/manticoresoftware/docker/issues).
