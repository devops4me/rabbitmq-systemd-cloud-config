
FROM rabbitmq:3.7.8-management-alpine

# -- Enable the auto cluster functionality that as of RabbitMQ 3.7 has
# -- now been included in the core codebase. We are staking our claim to
# -- cluster using the etcd key-value store.

RUN rabbitmq-plugins --offline enable rabbitmq_peer_discovery_etcd


# -- Copy the new style configuration into /etc/rabbitmq/rabbitmq.conf

COPY rabbitmq.conf /etc/rabbitmq/rabbitmq.conf
