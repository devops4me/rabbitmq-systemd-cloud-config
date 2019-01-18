
#### The igintion json content coming out of here goes into the *user data* of either an [ec2 instance](https://github.com/devops4me/terraform-aws-ec2-instance-cluster/blob/master/ec2.instances-main.tf) or a launch configuration.

---

# RabbitMQ 3.7 Cluster Ignition | etcd v3 peer discovery

Deploying an **N node RabbitMQ 3.7 cluster** is extremely simple when you combine a modular Terraform design, an **etcd peer discovery backend** and two **systemd unit files** that are converted to Ignition json.

You can also **swap out a fixed size ec2 instance cluster** and replace it with one that **auto-scales**.

### RabbitMQ SystemD Unit Configuration

```ini
[Unit]
Description=RabbitMQ Node with ETCD Peer Discovery
After=docker.socket etcd-member.service
Requires=docker.socket etcd-member.service

[Service]
ExecStart=/usr/bin/docker run \
    --detach        \
    --name rabbitmq \
    --network host  \
    --env RABBITMQ_ERLANG_COOKIE="${ erlang_cookie }" \
    --env RABBITMQ_DEFAULT_USER="${ rbmq_username }"  \
    --env RABBITMQ_DEFAULT_PASS="${ rbmq_password }"  \
    devops4me/rabbitmq-3.7

[Install]
WantedBy=multi-user.target
```

Each node will be bootstrapped using **Ignition** to run the **[RabbitMQ 3.7 docker container](https://github.com/devops4me/rabbitmq-3.7/blob/master/Dockerfile)** after CoreOS ETCD 3 has been installed.

The module swallows a username and **spits out an alphanumeric password**. The combination can be used to log into any node in the cluster or via the load balancer.

---

### Etcd SystemD Unit Configuration


```ini
[Unit]
Description=Sets up the inbuilt CoreOS etcd 3 key value store
Requires=coreos-metadata.service
After=coreos-metadata.service

[Service]
EnvironmentFile=/run/metadata/coreos
ExecStart=/usr/lib/coreos/etcd-wrapper $ETCD_OPTS \
  --listen-peer-urls="http://$${COREOS_EC2_IPV4_LOCAL}:2380" \
  --listen-client-urls="http://0.0.0.0:2379" \
  --initial-advertise-peer-urls="http://$${COREOS_EC2_IPV4_LOCAL}:2380" \
  --advertise-client-urls="http://$${COREOS_EC2_IPV4_LOCAL}:2379" \
  --discovery="${file_discovery_url}"
```

When each cluster node wakes up, the above ETCD configuration sets up the key-value store and contacts peers. After that RabbitMQ is started and it uses its local etcd for peer discovery.

---


## Usage

Copy this into a file and then run **`terraform init`** and **`terraform apply -auto-approve`** and out comes the ignition config.

```hcl
module rabbitmq-ignition-config
{
    source        = "github.com/devops4me/terraform-ignition-rabbitmq-config"
    in_node_count = 6
}

output rabbitmq_ignition_config
{
    value = "${ module.rabbitmq-ignition-config.out_ignition_config }"
}
```

Your node is configured when you feed the output into the user data field of either an EC2 instance (**[fixed size cluster](https://github.com/devops4me/terraform-aws-ec2-instance-cluster)**) or a launch configuration (**[auto-scaling cluster](https://github.com/devops4me/terraform-aws-ec2-cluster-auto-scale)**).


---


## How does RabbitMQ find etcd?

It is not immediately obvious how RabbitMQ is given its etcd's host url. The answer lies in

1. the **[rabbitmq.conf file](https://github.com/devops4me/rabbitmq-3.7/blob/master/rabbitmq.conf)** and
1. the **`--network host`** switch in docker run


### the [rabbitmq.conf](https://github.com/devops4me/rabbitmq-3.7/blob/master/rabbitmq.conf) file

```ini
cluster_formation.peer_discovery_backend = rabbit_peer_discovery_etcd
cluster_formation.etcd.host = localhost
```

Rabbit is told that the etcd host url is **`localhost`** (using default port 2379). The docker command started up RabbitMQ using the host's network which is how localhost is the correct place.

Piggy backing off the host's network is why we did not need to publish RabbitMQ ports like **`15672`**.


---


## RabbitMQ User through Docker


Using a **`systemd unit file`** like the one below adds RabbitMQ users through the **`docker exec`** command. The **`apollo`** username and **`p455w0rd`** password can be replaced with placeholders for dynamic configuration.


```ini
[Unit]
Description=Create first Apollo RabbitMQ administrative user
After=docker.socket etcd-member.service rabbitmq.service
Requires=docker.socket etcd-member.service rabbitmq.service

[Service]
ExecStartPre=/usr/bin/docker exec \
    --interactive \
    --tty         \
    rabbitmq      \
    rabbitmqctl add_user apollo p455w0rd

ExecStartPre=/usr/bin/docker exec \
    --interactive \
    --tty         \
    rabbitmq      \
    rabbitmqctl set_user_tags apollo administrator

ExecStart=/usr/bin/docker exec \
    --interactive \
    --tty         \
    rabbitmq      \
    rabbitmqctl set_permissions -p / apollo ".*" ".*" ".*"

[Install]
WantedBy=multi-user.target
```


---


Restart=always
RestartSec=10s
Type=notify
NotifyAccess=all


---


## The [Timer] Section

Timer units are used to schedule tasks to operate at a specific time or after a certain delay. This unit type replaces or supplements some of the functionality of the cron and at daemons. An associated unit must be provided which will be activated when the timer is reached.

The [Timer] section of a unit file can contain some of the following directives:

OnActiveSec=: This directive allows the associated unit to be activated relative to the .timer unit's activation.
OnBootSec=: This directive is used to specify the amount of time after the system is booted when the associated unit should be activated.
OnStartupSec=: This directive is similar to the above timer, but in relation to when the systemd process itself was started.
OnUnitActiveSec=: This sets a timer according to when the associated unit was last activated.
OnUnitInactiveSec=: This sets the timer in relation to when the associated unit was last marked as inactive.


---


## Troubleshoot | Information Gathering

Replace the string **`rabbitmq`** with the name of your service in these systemd information gathering commands.

```bash
docker ps -a                              # Is our container running?
docker logs rabbitmq                      # Tell me the docker viewpoint?
etcdctl cluster-health                 # Health of etcd cluster nodes?
journalctl --unit rabbitmq.service        # Examine (say) rabbitmq.service
journalctl --identifier=ignition --all    # look at the ignition logs
systemctl list-unit-files                 # Is your service in this list?
journalctl --unit coreos-metadata.service # Examine the fetched metadata
journalctl --unit docker.socket           # Did docker start okay?
journalctl --unit network-online.target   # Did the network come onlie?
cat /etc/systemd/system/rabbitmq.service  # Print the systemd unit file
sudo systemctl start rabbitmq         # Will service startup fine?
systemctl status rabbitmq                 # Is service enabled or what?
systemctl cat rabbitmq                    # Print the systemd unit file
journalctl --unit etcd-member.service     # Examine the ETCD 3 service
etcdctl ls / --recursive                  # list the keys that etcd has
```

## Troubleshoot | systemd dependency failure

If these systemd logs **`Dependency failed for`** and **`Job rabbitmq.service/start failed with result 'dependency'`** appear after the command **`journalctl --unit rabbitmq.service`** (whatever your service is), you have a systemd dependency failure.

```
-- Logs begin at Thu 2018-12-13 15:13:29 UTC, end at Thu 2018-12-13 15:32:11 UTC. --
Dec 13 15:14:51 ip-10-66-8-108 systemd[1]: Dependency failed for RabbitMQ Node with ETCD Peer Discovery.
Dec 13 15:14:51 ip-10-66-8-108 systemd[1]: rabbitmq.service: Job rabbitmq.service/start failed with result 'dependency'.
```

To fix this issue you should ensure that

- every systemd unit file ends with **`WantedBy=multi-user.target`** under **`[Install]`**
- **`Restart=always`** and **`RestartSec=10`** is placed under the **`[Service]`** section


[Install]
WantedBy=multi-user.target

Restart=always
RestartSec=3


---



## Troubleshoot | Validate your service unit file

If things aren't going as planned one troubleshooting tactic is to **validate your systemd service unit file** using **`systemctl`** and **`journalctl`**.

If the service file is not already on CoreOS machine you SSH in and use wget to download (say from Github) like this.

```bash
DOWNLOAD_URL=https://raw.githubusercontent.com/devops4me/terraform-ignition-rabbitmq-config/master/systemd-rabbitmq.service
wget $DOWNLOAD_URL
sudo cp systemd-rabbitmq.service /etc/systemd/system/rabbitmq.manual.service
sudo systemctl start rabbitmq.manual
journalctl --unit rabbitmq.manual
docker ps -a
```

Tryout this example which **kicks off RabbitMQ using Docker** and **`docker ps -a`** demonstrates the container in action. Also **`http://<<hosh>>:15672/#/`** should bring up the RabbitMQ welcome page (assuming port 15672 is allowed by the relevant local (or AWS cloud) security group.

Any errors with your service file should show up or if all good you'll get logs like these topp'd and tailed ones.

```
-- Logs begin at Tue 2018-12-04 17:39:35 UTC, end at Tue 2018-12-04 18:17:12 UTC. --
Dec 04 18:17:07 ip-10-66-28-127 systemd[1]: Starting RabbitMQ Node with ETCD Peer Discovery...
Dec 04 18:17:07 ip-10-66-28-127 docker[1956]: Using default tag: latest
Dec 04 18:17:08 ip-10-66-28-127 docker[1956]: latest: Pulling from devops4me/rabbitmq-3.7
Dec 04 18:17:08 ip-10-66-28-127 docker[1956]: 4fe2ade4980c: Pulling fs layer
Dec 04 18:17:12 ip-10-66-28-127 systemd[1]: Started RabbitMQ Node with ETCD Peer Discovery.
Dec 04 18:17:12 ip-10-66-28-127 docker[2074]: b2095a365cbf1f6c9290596e2158b758bc174d1056c16a7b0f8cb62fc177032f
```


---


## Troubleshoot | docker.socket rather than docker.service

When you list units in the latest CoreOS build you'll find that **docker.service is disabled**. It has been pushed aside to make way for **docker.socket**.

So if your service executes a **`docker run`** you should use docker.socket in the **`Requires`** and **`After`** fields.

**You risk starting your services in the wrong order.**

This leads us nicely onto the next troubleshooting tip.


---


## Troubleshoot | Wrong Service Start Order

Examine the time the rabbitmq service started with logs **`journalctl --identifier=ignition --all`** and look at the logs like **`[started]  enabling unit "rabbitmq.service"`**.

Now find out when docker.service was enabled with the command **`journalctl -u docker.service`** and look for the log **`Started Docker Application Container Engine.`**

    Dec 04 15:13:01 localhost ignition[486]: files: op(8): [started]  enabling unit "rabbitmq.service"
    Dec 04 15:18:53 ip-10-66-8-115 systemd[1]: Started Docker Application Container Engine.


#### Docker Started First!

Our docker dependent service started at *15:13* whilst RabbitMQ which depends on docker **started after it at 15:18**.

Look below at the logs with more context around the above two lines.

### Context Log | journalctl --identifier=ignition --all

```
Dec 04 15:13:01 localhost ignition[486]: files: op(3): [started]  processing unit "etcd-member.service"
Dec 04 15:13:01 localhost ignition[486]: files: op(3): op(4): [started]  writing systemd drop-in "20-clct-etcd-member.conf" at "etc/systemd/system/etcd-member.service.d/20-clct-etcd-member.conf"
Dec 04 15:13:01 localhost ignition[486]: files: op(3): op(4): [finished] writing systemd drop-in "20-clct-etcd-member.conf" at "etc/systemd/system/etcd-member.service.d/20-clct-etcd-member.conf"
Dec 04 15:13:01 localhost ignition[486]: files: op(3): [finished] processing unit "etcd-member.service"
Dec 04 15:13:01 localhost ignition[486]: files: op(5): [started]  enabling unit "etcd-member.service"
Dec 04 15:13:01 localhost ignition[486]: files: op(5): [finished] enabling unit "etcd-member.service"
Dec 04 15:13:01 localhost ignition[486]: files: op(6): [started]  processing unit "rabbitmq.service"
Dec 04 15:13:01 localhost ignition[486]: files: op(6): op(7): [started]  writing systemd drop-in "20-clct-rabbitmq-member.conf" at "etc/systemd/system/rabbitmq.service.d/20-clct-rabbitmq-member.conf"
Dec 04 15:13:01 localhost ignition[486]: files: op(6): op(7): [finished] writing systemd drop-in "20-clct-rabbitmq-member.conf" at "etc/systemd/system/rabbitmq.service.d/20-clct-rabbitmq-member.conf"
Dec 04 15:13:01 localhost ignition[486]: files: op(6): [finished] processing unit "rabbitmq.service"
Dec 04 15:13:01 localhost ignition[486]: files: op(8): [started]  enabling unit "rabbitmq.service"
Dec 04 15:13:01 localhost ignition[486]: files: op(8): [finished] enabling unit "rabbitmq.service"
Dec 04 15:13:01 localhost ignition[486]: files: files passed
Dec 04 15:13:01 localhost ignition[486]: Ignition finished successfully
```


### Context Log | journalctl -u docker.service

```
Dec 04 15:18:53 ip-10-66-8-115 env[959]: time="2018-12-04T15:18:53.389072412Z" level=info msg="pickfirstBalancer: HandleSubConnStateChange: 0xc420596fe0, CONNECTING" module=grpc
Dec 04 15:18:53 ip-10-66-8-115 env[959]: time="2018-12-04T15:18:53.389400734Z" level=info msg="pickfirstBalancer: HandleSubConnStateChange: 0xc420596fe0, READY" module=grpc
Dec 04 15:18:53 ip-10-66-8-115 env[959]: time="2018-12-04T15:18:53.389471868Z" level=info msg="Loading containers: start."
Dec 04 15:18:53 ip-10-66-8-115 env[959]: time="2018-12-04T15:18:53.582655184Z" level=info msg="Default bridge (docker0) is assigned with an IP address 172.17.0.0/16. Daemon option --bip can be used to set a preferred IP address"
Dec 04 15:18:53 ip-10-66-8-115 env[959]: time="2018-12-04T15:18:53.867088336Z" level=info msg="Loading containers: done."
Dec 04 15:18:53 ip-10-66-8-115 env[959]: time="2018-12-04T15:18:53.897412579Z" level=info msg="Docker daemon" commit=e68fc7a graphdriver(s)=overlay2 version=18.06.1-ce
Dec 04 15:18:53 ip-10-66-8-115 env[959]: time="2018-12-04T15:18:53.897564205Z" level=info msg="Daemon has completed initialization"
Dec 04 15:18:53 ip-10-66-8-115 systemd[1]: Started Docker Application Container Engine.
Dec 04 15:18:53 ip-10-66-8-115 env[959]: time="2018-12-04T15:18:53.937982101Z" level=info msg="API listen on /var/run/docker.sock"
```


---

## Troubleshoot | What is RabbitMQ listening to (and from where)?

rabbitmqctl uses Erlang Distributed Protocol (EDP) to communicate with RabbitMQ. Port 5672 provides AMQP protocol. You can investigate EDP port that your RabbitMQ instance uses:


    $ netstat -uptan | grep beam


### netstat command result

    tcp        0      0 0.0.0.0:55950           0.0.0.0:*               LISTEN      31446/beam.smp  
    tcp        0      0 0.0.0.0:15672           0.0.0.0:*               LISTEN      31446/beam.smp  
    tcp        0      0 0.0.0.0:55672           0.0.0.0:*               LISTEN      31446/beam.smp  
    tcp        0      0 127.0.0.1:55096         127.0.0.1:4369          ESTABLISHED 31446/beam.smp  
    tcp6       0      0 :::5672                 :::*                    LISTEN      31446/beam.smp  



### This means that RabbitMQ:

- is connected to EPMD (Erlang Port Mapper Daemon) on 127.0.0.1:4369 to make nodes able to see each other
- waits for incoming EDP connection on port 55950
- waits for AMQP connection on port 5672 and 55672
- waits for incoming HTTP management connection on port 15672

To make rabbitmqctl able to connect to RabbitMQ you also have to forward port 55950 and allow RabbitMQ instance connect to 127.0.0.1:4369. It is possible that RabbitMQ EDP port is dinamic, so to make it static you can try to use ERL_EPMD_PORT variable of Erlang environment variables or use inet_dist_listen_min and inet_dist_listen_max of Erlang Kernel configuration options and apply it with RabbitMQ environment variable - export RABBITMQ_CONFIG_FILE="/path/to/my_rabbitmq.conf


---


## Troubleshoot | Wrong Service Name

**`journalctl --unit blahblahblah.service`**

If you look at blahblahblah.service with **`journalctl --unit blahblahblah.service`** you get a lovely little top and tail printout that feels like nothing happened.


    -- Logs begin at Tue 2018-12-04 15:12:58 UTC, end at Tue 2018-12-04 16:13:06 UTC. --
    -- No entries --

**Actually it means the service did not exist or was not found!**



## Troubleshoot | Failed Units Banner

CoreOS and most Linux distros publish a banner if and when service failed to instantiate. When you SSH in you are greeted like this.

```
Failed Units: 1
  rabbitmq.service
```

A quick glance names the services that have let you down.

---


## Troubleshoot | Cleaning up failed nodes

**Consider node removal and setting HA Policies to mirror both data and queues.**

AUTOCLUSTER_CLEANUP to true removes the node automatically, if AUTOCLUSTER_CLEANUP is false you need to remove the node manually.

Scaling down and AUTOCLUSTER_CLEANUP can be very dangerous, if there are not HA policies all the queues and messages stored to the node will be lost. To enable HA policy you can use the command line or the HTTP API, in this case the easier way is the HTTP API, as:

```bash
curl -u guest:guest  -H "Content-Type: application/json" -X PUT \
    -d '{"pattern":"","definition":{"ha-mode":"exactly","ha-params":3,"ha-sync-mode":"automatic"}}' \
    http://172.17.8.101:15672/api/policies/%2f/ha-3-nodes
```

Note: Enabling the mirror queues across all the nodes could impact the performance, especially when the number of the nodes is undefined. Using "ha-mode":"exactly","ha-params":3 we enable the mirror only for 3 nodes. So scaling down should be done for one node at time, in this way RabbitMQ can move the mirroring to other nodes.
