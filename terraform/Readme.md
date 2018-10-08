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

The terraform project will consist of several connected elements, each one of the
will reside in its own separate directory, with this we can start, stop and modify
each element without affecting the others.

The directories that will be created initially are: 

* VPC.- This will hold the code to create the VPC and other network related resources

* NAT_gateway.- This direcotory will hold the NAT gateway.

#### Remote state and backends

For the different elements to be able to access data from other elements, necessary
for example to add the NAT gateway to the subnet defined in the VPC, we have to
define a remote state that will be kept in a backend.

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

The path is relative to where the vpc.tf file is found.

The remote state data source is defined in the code of the element that wants to
access the data, for example from the NAT gateway's nat.tf file we add the following
definition:

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

Output variable found in VPC:

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

Obiously we use the aws provider, and define the Ireland region as the one to create
all resources.  The version option is suggested by the **terraform init** command as
shown in the next section.

The VPC definition uses the IPV4 network range 172.20.0.0/16 and enables the
assignment of dns hostnames to the EC2 instances created inside.  

Then a Name and Project tag is defined.

#### Terraform initialization

There are several ocations when it is necessary to initialize terraform:

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

Two security groups are created one to allow inbound ssh connections from the network
185.229.0.0/16 corresponding with the addresss space of MedinaNet.  The other to
allow http and https outbound connections from the EC2 instances so they can install
and update packages.

#### NAT gateway

For the servers in the private subnet2 to access outside services like installing or
updating packages, we need a NAT gateway.

The NAT gateway must be connected to the public subnet, and it also needs an elastic
IP address (IPv4 only) attached to the NAT gateway.

First we create the elastic IP, then the NAT gateway.

The NAT gateway and elastic IP are defined in its own directory so we can create
and destroy them easily when necessary, since you get charged for them even if you
don't use them.

We create the new directory and the nat.tf file to describe the element:

```shell
# mkdir NAT_gateway
# vim nat.tf
```

The nat.tf file contains a datasource definition for the remote state of the VPC
element, then the definitions for the elastic IP and the NAT gateway itself.

### EC2 instances

Once we have the networking part of the configuration all sorted out, we can start
deploying the servers.

First we add the bastion host to the public subnet, this will use a Redhat 7.5 image
installed on a t2.micro instance; the host is placed in the public subnet and applyed
the security groups that allow ssh connections to the machine and outgoing web
connectios; finally we assign an ssh key to connect with and a pair of tags.

After deploying all the infrastructure defined so far we can connect to the bastion
host with a command like:

```shell
# ssh -i ~/Descargas/tale_toul-keypair-ireland.pem ec2-user@ec2-52-49-13-213.eu-west-1.compute.amazonaws.com
```
