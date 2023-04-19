#!/bin/bash

docker-compose -f ./docker-compose.yml up -d

echo "Waiting for Kafka Connect to start"
while [[ "$(curl -s -o /dev/null -w ''%{http_code}'' http://localhost:8083)" != "200" ]]; do sleep 5; done

echo "Creating topic test-topic1 in source legacy cluster"
docker exec -i broker1_legacy kafka-topics.sh --create --topic test-topic1 --partitions 1 --replication-factor 1 --if-not-exists --zookeeper zookeeper1_legacy:2181

echo "Sending messages to topic test-topic1 in source legacy cluster"
seq 10 | docker exec -i broker1_legacy kafka-console-producer.sh --broker-list broker1_legacy:9092 --topic test-topic1

echo ""
echo "Creating Replicator connector"
docker exec -it connect curl -X PUT \
    -H "Content-Type: application/json" \
    --data '{
        "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
        "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
        "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
        "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
        "src.consumer.group.id": "replicator-legacy-to-cp",
        "confluent.topic.replication.factor": 1,
        "topic.whitelist": "test-topic1",
        "dest.kafka.bootstrap.servers": "broker1:9092",
        "src.kafka.bootstrap.servers": "broker1_legacy:9092",
        "offset.translator.tasks.max": 0,
        "offset.timestamps.commit": false
        }' \
    http://connect:8083/connectors/replicator-legacy-to-cp/config

sleep 10

echo ""
echo "Verify we have received the data in test-topic1 in the target cluster"
docker exec broker1 kafka-console-consumer --bootstrap-server broker1:9092 --topic test-topic1 --from-beginning --max-messages 10


echo "Creating topic test-topic2 in source legacy cluster"
docker exec -i broker1 kafka-topics --create --topic test-topic2 --partitions 1 --replication-factor 1 --if-not-exists --bootstrap-server broker1:9092
echo "Sending messages to topic test-topic2 in source legacy cluster"
seq 10 | docker exec -i broker1 kafka-console-producer --bootstrap-server broker1:9092 --topic test-topic2


docker exec -it connect curl -X PUT \
    -H "Content-Type: application/json" \
    --data '{
        "connector.class":"io.confluent.connect.replicator.ReplicatorSourceConnector",
        "key.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
        "value.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
        "header.converter": "io.confluent.connect.replicator.util.ByteArrayConverter",
        "src.consumer.group.id": "replicator-cp-to-legacy",
        "confluent.topic.replication.factor": 1,
        "topic.whitelist": "test-topic2",
        "dest.kafka.bootstrap.servers": "broker1_legacy:9092",
        "src.kafka.bootstrap.servers": "broker1:9092",
        "offset.translator.tasks.max": 0,
        "offset.timestamps.commit": false,
        "producer.override.bootstrap.servers": "broker1_legacy:9092"
        }' \
    http://connect:8083/connectors/replicator-cp-to-legacy/config

sleep 10

echo ""
echo "Verify we have received the data in test-topic1 in the target cluster"
docker exec broker1_legacy kafka-console-consumer.sh --bootstrap-server broker1_legacy:9092 --topic test-topic2 --from-beginning --max-messages 10
