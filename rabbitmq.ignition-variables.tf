
################ ############################################################## ########
################ Module [[[etcd ignition configuration]]] Input Variables List. ########
################ ############################################################## ########


### ########################## ###
### [[variable]] in_node_count ###
### ########################## ###

variable in_node_count
{
    description = "The instance (node) count for the initial cluster which defaults to four (4)."
    default     = "4"
}


### ############################ ###
### [[variable]] in_rmq_username ###
### ############################ ###

variable in_rmq_username
{
    description = "Username of the first provisioned RabbitMQ user which defaults to apollo."
    default     = "devops4me"
}
