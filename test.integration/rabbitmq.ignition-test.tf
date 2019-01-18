
module rabbitmq-ignition-config-1
{
    source         = ".."
}

module rabbitmq-ignition-config-2
{
    source        = ".."
    in_node_count = 6
}

output rabbitmq_ignition_config_1
{
    value = "${ module.rabbitmq-ignition-config-1.out_ignition_config }"
}

output rabbitmq_ignition_config_2
{
    value = "${ module.rabbitmq-ignition-config-2.out_ignition_config }"
}
