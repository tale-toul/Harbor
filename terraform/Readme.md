## AWS based Infrastructure with terraform

https://www.terraform.io

The harbor project will be deployed in its own AWS based infrastructure.

All the resources created for this project that support tags, will have the tag
Project="harbor" to make them easily identifiable.

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

### Authentication with AWS

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

The terraform project will consist of several connected elements, each residing in its own
directory.

With this setup we can start, stop and modify each element without affecting the others.

The directories that will be created are: 

* VPC.- This will hold the code to create the VPC and other network related resources

* NAT_gateway.- This direcotory will hold the NAT gateway.

* EC2.- This will hold the code to create the EC2 instances.

* S3.- Holds the code to create the storage infrastructure, including buckets, users and policies.

#### Remote state and backends

For the different elements to be able to access data from each other in the project, for
example to add the NAT gateway to the subnet defined in the VPC, we have to define a
remote state that will be kept in a backend.

The backend used will be *local* which is just the normal local file
terraform.tfstate but explicitily declared so that later another element can access
it.  

Currently only the VPC creates a remote state that the other elements (NAT_gateway; EC2;
S3) can read from.

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
NAT gateway element. 

The output variables are created in its own file outputs.tf.

```
output "subnet1_id" {
    value = "${aws_subnet.subnet1.id}"
}
```
Variable used from NAT gateway:

```
 subnet_id = "${data.terraform_remote_state.vpc.subnet1_id}"
```

### Terraform initialization

There are several occations when it is necessary to initialize terraform:

* Before first use of the terraform command you have to initialize the plugins 
  by running the _init_ subcommand in the directory where your terraform files will
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

* After defining a template file datasource.

### Resource creation

To create the resources defined in the terraform files issue the following command:

```shell
 # terraform apply
```

This command will show the plan of changes to apply and ask for confirmation.  Enter
"yes" and the VPC will be created.

### Resource destruction

When the resources are no longer needed, you can remove them with the following command:

```shell
 # terraform destroy
```

### Deploy a VPC

To create a VPC the following terraform directives are used:

```terraform
provider "aws" {
    region = "eu-west-1"
    version = "~> 1.39"
}
```

Obviously we use the aws provider, and define the Ireland region as the one to create all
resources.  The version option is suggested by the **terraform init** command as shown in
the next section.

```terraform
terraform {
    backend "local" {
        path = "terraform.tfstate"
    }
}
```
The remote state definition as explained in "Remote state and backend"

```
resource "aws_vpc" "vpc" {
    cidr_block = "172.20.0.0/16"
    enable_dns_hostnames = true

    tags {
        Name = "volatil"
        Project = "harbor"
    }
}
```

The VPC definition uses the IPV4 network range 172.20.0.0/16 and enables the assignment of
dns hostnames to the EC2 instances created inside.  

Then a Name and Project tag is defined.

#### Subnets

The VPC will contain two subnets: one public and one private.

The public subnet will host the EC2 instance used as a bastion hosts; the private subnet
will host the harbor registry server.

To create the subnets a data source is defined to get the names of the availability
zones in the region:

`data "aws_availability_zones" "avb-zones" {}`

Later the names are extracted the following expressions, to get the first and second
availability zones in the region:

```
availability_zone = "${data.aws_availability_zones.avb-zones.names[0]}"`
availability_zone = "${data.aws_availability_zones.avb-zones.names[1]}"
```

The subnets must have different names (subnet1; subnet2); different address blocks
wihin the VPC address space (172.20.1.0/24; 172.20.2.0/24); 

Subnet1 is made a public subnet by assigning public IPs to the EC2 instances launched
inside, and providing a routing table with a "default" entry that connects to
an Internet Gateway, more on this later.

`map_public_ip_on_launch = true`

#### Internet Gateway

For the public subnet1 to communicate with the Internet it needs an Internet Gateway,
which acts as a default route for the instances in the subnet.

The Internet Gateway is created and associated with the VPC not a particular subnet.
Later we will use a route table to allow instances in the public subnet1 to send and
receive network packets to and from the Internet, via the Internet Gateway.

#### Route table and association

To allow the instances in the public subnet1 to communicate with the Internet we need
to associate the route table created above with this subnet.  The route table includes an
entry stating that any traffic not sent to the VPC will be sent to the Internet Gateway.

We create a route table and add the default route entry, then we associate the route table
with the public subnet1, and with no other.  We only need to create the "default" route
entry, the one for the local traffic is created automatically when the route table is
created in the VPC.

#### Security groups

Security groups are like stateful firewall rules, that are attached to EC2 instances to
allow traffic into an out of them.

A few security groups are created:

* sg-ssh-in.- Allows inbound ssh connections from the network 185.192.0.0/10
  which corresponds to the addresss space of MedinaNet.  

* sg-ssh-out.- Allows outgoing ssh connections to any IP within the VPC network
  172.20.0.0/16

* sg-ssh-in-local.- Allows inbound ssh connections from any IP within the VPC network
  172.20.0.0/16

* sg-web-out.- Allows http and https outbound connections from the EC2 instance to any
  IP so they can install and update packages.

* sg-web-in-local.- Allows http and https inbound connections from any IP in the VPC

* st-web-in-medina.- Allows https inbound connections from the MedinaNet network
  (185.192.0.0/10) so that we can connect to the registry's web interface and use the
  docker cliente.

### NAT gateway

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

@#The NAT gateway is also used to access the S3 bucket, but we should probably use an S3
Endpoint instead#@

### EC2 instances

EC2 instances are defined in its own independent directory and file **EC2/ec2.tf** so we
can start and stop them indepently from the rest of the project.

Part of the information needed to define the instances, like subnet and security groups
ids are obtained from the VPC datasource, that is declared at the begining of the file:

```
data "terraform_remote_state" "vpc" {
    backend = "local"

    config {
        path = "../VPC/terraform.tfstate"
    }
}
```

Another datasource is declared to be able to get information from the DNS zone
_taletoul.com_.  This is required so that we can add records to the zone as we will see
later. 

This datasource is created using the name of the preexisting zone (taletoul.com.);
terraform will look for a zone for that DNS suffix and populate the state file with its
information.

```
data "aws_route53_zone" "taletoul" {
    name = "taletoul.com."
}
```

When defining the instances it is important to consider the lifecycle of the disks
attached to the them, by default each instance will get an 8GB root device that **will NOT
be deleted** when the instance is terminated.  This means that if we apply and destroy
the terraform plan several times we will end up with as many ebs disks in our aws account,
that will increase the bill at the end of the month.  To avoid this problem I will
specifically define the option for the root device **delete_on_termination**, this will
have the effect of eliminating the ebs disk when the EC2 instance is terminanted:

```
  root_block_device {
    volume_size = 8
    delete_on_termination = true
  }
```

We add the bastion host to the public subnet, this will use a Redhat 7.5 image installed
on a t2.micro instance; the host is placed in the public subnet and applied the security
groups sg-ssh-in; sg-ssh-out and sg-web-out and web-in-medina; these allow ssh connections
from the Medinanet network, connect via ssh to other instances in the VPC, connect to any
web server via http or https and receive https connections from the MedinaNet network;
finally we assign an ssh key to authenticate with, and a pair of tags.

The registry server is created in the private subnet2, it uses the same type of instance
as the bastión host, at least for the moment, later it will have to be a more powerfull
machine.  The security group for ssh connections (sg-ssh-in-local) only allows connections
from other instances in the VPC network 172.20.0.0/16, the security group for the outgoing
web connections is the same that the bastion server uses (sg-web-out), the security group
for inbound web connections (sg-web-in-local) allows connections to ports 80 and 443 only
if they come from other hosts in the same VPC; we assign an ssh key to authenticate with.
A static private IP has been assigned to the server so that we don't have to change the
address defined in the x509 certificate used to connect via HTTPS.

An elastic IP is created and assigned to the bastion host, then an A record is added
to the taletoul.com DNS zone linking the elastic IP and the name "registry", this way we
can use the name **registry.taletoul.com** in the rest of the project and from the web
browser and docker client to access the registry host.  To create the DNS record we have
to use the zone id, we get it from the datasource that was defined at the beginning of the
file.

As with the other components we have to initialize terraform in this directory:

`# terraform init`

Then we can start the instances:

`# terraform apply`

#### Connecting to the instances

After deploying all the infrastructure defined so far we can connect to the instances usin
ssh.  

To connect to the bastion host we use a command like:

```shell
# ssh -i ~/Descargas/tale_toul-keypair-ireland.pem centos@registry.taletoul.com
```

This command uses the ssh private certificate assigned to the instance during creation.
The user connecting is predefined by AWS to be **centos** (ec2-user in the case of other
amis).  

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

`ec2-user@ip-172-20-1-33 ~]$ ssh ec2-user@172.20.2.142`

We can create a more advance configuration to connect directly to the registry host
without the need to explicitly connect to the bastion host, the details can be found in
the *ansible/Readme.md* file, section **SSH connection to the registry host**

### S3 storage

The terraform code to manage the S3 storage is found in the directory **terraform/S3**.

The code creates:

* An IAM user who will be used by harbor to access the bucket where the images will be
  stored, this user will have just the minimum permissions requiere by harbor as stated in
  the
[documentation](https://github.com/docker/docker.github.io/blob/master/registry/storage-drivers/s3.md#s3-permission-scopes)

* An access key for the IAM user, this key is **not encrypted** so it will be found in
  clear text in the state file of terraform.  In a future version the key may be
  encrypted.

* A bucket policy from a template, the template requieres two variables ${user} which
  contains the name of the user that will access the bucket; and ${name} which the
  globally unique name of the bucket.  The ${user} is taken from the user resource
  previously created in the same file.  The ${name} is defined as a variable at the
  begining of the file.

* A bucket to store the images managed by the registry, the name of the bucket is defined
  in the variable *bucket_name* which must be unique across all AWS.  The bucket receives
  the policy created previously from the template.  One argument to highlight is
  **force_destroy=true**, this causes the bucket and its contents to be deleted upon
  execution of the **terraform destroy** command, if we don't explicitly define this
  argument it default to false, and the bucket is not deleted if it has any objects
  inside.

A file with output definitions is also created in this directory to export the information
needed by ansible to create the storage configuration for harbor.  The variables exported
are: iam_user_access_key; iam_user_secret_key; bucket_region and bucket_name.

