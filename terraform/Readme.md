## AWS based Infrastructure with terraform

https://www.terraform.io

All the resources created for this project will have the tag Project="harbor" to make
them easily identifiable 

### Terraform installation

The installation of terraform is as simple as downloading a zip compiled binary
package for your operating system and architecture from:

`https://www.terraform.io/downloads.html`

Then unzip the file:

```shell
 # unzip terraform_0.11.8_linux_amd64.zip 
Archive:  terraform_0.11.8_linux_amd64.zip
  inflating: terraform
```

Place the binary somewhere in your path:

```shell
# cp terraform /usr/local/bin
```

Check that it is working:

```shell
# terraform --version
```

#### Authentication with AWS

In order for terraform to manage your AWS resources it needs the credentials of an
IAM user with the proper privileges, one way to do this is by defining the
environment variables: **AWS_ACCESS_KEY_ID** and **AWS_SECRET_ACCESS_KEY** with the
corresponding values for the IAM user found in IAM -> Users -> Select the user ->
Security Credentials

```shell
 # export AWS_ACCESS_KEY_ID="adljALSDJ"
 # export AWS_SECRET_ACCESS_KEY="asdlqqljdDFDUOJxxx"
```

This variables are only defined for the current shell.

### Project structure

The terraform project will consist of several connected elements, each one of them
residing in its own separate directory.  With this setup we can start, stop and modify
each element without affecting the others.

The directories that will be created are: 

* VPC.- This will hold the code to create the VPC and other network related resources

* NAT_gateway.- This direcotory will hold the NAT gateway.

* EC2.- This will hold the code to create the EC2 instances.

#### Remote state and backends

For the different componentes to have the ability to access data from other components in
the project, for example, to add the NAT gateway to the subnet defined in the VPC, we have
to define a remote state that will be kept in a backend.

The backend used will be *local* which is just the normal local file
terraform.tfstate but explicitily declared so that later another element can access
it.  

To define the local backend for the VPC code we add the following code to the vpc.tf
file:

```
terraform {
    backend "local" {
        path = "terraform.tfstate"
    }
}

```

The path is relative to the directory where the vpc.tf file is found.

The remote state data source is defined in the code of the element that wants to
access the data, we use the same declaration from both the NAT gateway's nat.tf file and
the EC2's ec2.tf file:

```
data "terraform_remote_state" "vpc" {
    backend = "local"

    config {
        path = "../terraform.tfstate"
    }
}

```

With this we declare the vpc data source to access the remote state found in a local
backend at the relative path ../terraform.tfstate.

From now on we can export output variables from the VPC element and use them in the
NAT gateway element. For example:

```
output "subnet1_id" {
    value = "${aws_subnet.subnet1.id}"
}
```
Variable used from NAT gateway:

```
 subnet_id = "${data.terraform_remote_state.vpc.subnet1_id}"
```

### Deploy a VPC

The harbor project will be deployed in its own infrastructure, starting with a VPC,
to create a VPC the following terraform file is used:

```terraform
provider "aws" {
    region = "eu-west-1"
    version = "~> 1.39"
}

resource "aws_vpc" "vpc" {
    cidr_block = "172.20.0.0/16"
    enable_dns_hostnames = true

    tags {
        Name = "volatil"
        Project = "harbor"
    }
}
```

Obviously we use the aws provider, and define the Ireland region as the one to create all
resources.  The version option is suggested by the **terraform init** command as shown in
the next section.

The VPC definition uses the IPV4 network range 172.20.0.0/16 and enables the assignment of
dns hostnames to the EC2 instances created inside.  

Then a Name and Project tag is defined.

#### Terraform initialization

There are several occations when it is necessary to initialize terraform:

* Before first use of the terraform command you have to initialize the plugins in the
  by running the _init_ subcommand in the directory where you terraform files will
  reside:

```shell
 # terraform init
Initializing provider plugins...
- Checking for available provider plugins on https://releases.hashicorp.com...
- Downloading plugin for provider "aws" (1.39.0)...

The following providers do not have any version constraints in configuration,
so the latest version was installed.

To prevent automatic upgrades to new major versions that may contain breaking
changes, it is recommended to add version = "..." constraints to the
corresponding provider blocks in configuration, with the constraint strings
suggested below.

* provider.aws: version = "~> 1.39"

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.

If you ever set or change modules or backend configuration for Terraform,
rerun this command to reinitialize your working directory. If you forget, other
commands will detect it and remind you to do so if necessary.
```

* After making a new subdirectory to keep the terraform files for an element in the
  project 

* After defining a backend to be used to keep the state information of terraform in
  any subdirectory

#### Resource creation

To create the VPC issue the following command:


```shell
 # terraform apply
```

This command will show the plan of changes to apply and ask for confirmation.  Enter
"yes" and the VPC will be created.

#### Resource destruction

When the VPC is no longer needed you can remove it using the command:

```shell
 # terraform destroy
```

#### Subnets

The VPC will contain two subnets: one public and one private.

The public subnet will host the EC2 used as bastion hosts; the private subnet will
host the harbor server.

To create the subnets a data source is defined to get the names of the availability
zones in the region:

`data "aws_availability_zones" "avb-zones" {}`

Later the names are extracted with:

`availability_zone = "${data.aws_availability_zones.avb-zones.names[0]}"`

The subnets must have different names (subnet1; subnet2); different address blocks
wihin the VPC address space (172.20.1.0/24; 172.20.2.0/24); 

Subnet1 is made a public subnet by assigning public IPs to the EC2 instances launched
inside of it, and providing a routing table with a "default" entry that connects to
an Internet Gateway, more on this later.

`map_public_ip_on_launch = true`

#### Internet Gateway

For the public subnet1 to communicate with the Internet it needs an Internet Gateway.

The Internet Gateway is created and associated with the VPC not a particular subnet.
Later we will use a route table to allow instances in the public subnet1 to send and
receive network packets to and from the Internet.

#### Route table and association

To allow the instances in the public subnet1 to communicate with the Internet we need
to associate a route table only with this subnet that includes an entry saying that
any traffic not sent to the VPC will be sent to the Internet Gateway.

We create a route table and add the aforementioned entry, then next we associate the
route table with the public subnet1, and with no other.  We only need to create the
"default" route entry, the one for the local traffic is created automatically when
the route table is created in the VPC.

#### Security groups

A few security groups are created:

* sg-ssh-in.- Allows inbound ssh connections from the network 185.192.0.0/10
  corresponding with the addresss space of MedinaNet.  

* sg-ssh-out.- To allow outgoing ssh connections to any IP within the VPC network
  172.20.0.0/16

* sg-ssh-in-local.- To allow inbound ssh connections from any IP within the VPC network
  172.20.0.0/16

* sg-web-out.- To allow http and https outbound connections from the EC2 instances to any
  IP so they can install and update packages.

* sg-web-in-local.- Allows http and https inbound connections from any IP in the VPC

#### NAT gateway

[AWS documentation](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)

For the servers in the private subnet2 to be able to access outside services like
installing or updating packages, we need a NAT gateway.

The NAT gateway must be connected to the public subnet, and needs an elastic IP address
(IPv4 only) attached to it.

A route table must be created and assigned to the private subnet, with a default route to
the NAT gateway.

First we create the elastic IP, then the NAT gateway and finally the route table.

The NAT gateway, elastic IP and route table are all defined in its own directory so we can
create and destroy them easily when necessary, since you get charged for them even if you
don't use them.

We create the new directory and the nat.tf file to describe the element:

```shell
# mkdir NAT_gateway
# vim nat.tf
```

The nat.tf file contains a datasource definition for the remote state of the VPC
element so the subnet and vpc ids are available from here, then the definitions for the
elastic IP and the NAT gateway itself.

### EC2 instances

These are defined in its own directory EC2/ec2.tf so we can start and stop them indepently
from the network part of the project.

Part of the information needed to define the instances, like subnet and security groups
ids are obtained from the VPC datasource.

First we add the bastion host to the public subnet, this will use a Redhat 7.5 image
installed on a t2.micro instance; the host is placed in the public subnet and applied
the security groups sg-ssh-in; sg-ssh-out and sg-web-out that allow ssh connections from
the Medinanet network, connect via ssh to other instances in the VPC and connect to any
web server via http or https; finally we assign an ssh key to connect with and a pair of
tags.

The the registry server that will contain harbor is created in the private subnet2, is
similar to the bastión host, at least for the moment, later it will have to be a more
powerfull machine.  The security group for ssh connections (sg-ssh-in-local) only allows
connections from other instances in the VPC network 172.20.0.0/16, the security group for
the outgoing connections is the same that the bastion server uses, but it could be tigthen
more because the registry will only be able to connect to IPs in the VPC, the security
group for inbound web connections (sg-web-in-local) allows connections to ports 80 and 443
only if they come from other hosts in the same VPC.

As with the other components we have to initialize terraform in this directory:

`# terraform init`

Then we can start the instances:

`# terraform apply`

### How to connect to the instances

After deploying all the infrastructure defined so far we can connect to the instances usin
ssh.  

To connect to the bastion host we use a command like:

```shell
# ssh -i ~/Descargas/tale_toul-keypair-ireland.pem ec2-user@ec2-52-49-13-213.eu-west-1.compute.amazonaws.com
```

This command uses the ssh private certificate assigned to the instance during creation.
The user connecting is predefined by AWS to be **ec2-user**.  The public DNS name is
obtained from the output variable bastion_name.

Connecting to the registry host is a bit more complicated since this server is in a
private network and doesn't have a public IP or name.  We have to connect to the bastion
host and the connect to the registry host.  For this double jump to work we have configure
SSH agent forwarding, we do this in two steps:

* First we have to add in our local host the configuration option **ForwardAgent yes** 
  in the file ~/.ssh/config:

```
Host *
	ForwardAgent yes
```

* Then we have to add the ssh key to the SSH agent with the command:

`$ ssh-add ~/Descargas/tale_toul-keypair-ireland.pem`

To check that the key has been added use the command:

`$ ssh-add -L`

Now we can connect to the bastion host as before and then to the registry host using its
private IP or name:

`[ec2-user@ip-172-20-1-33 ~]$ ssh ec2-user@172.20.2.142`
