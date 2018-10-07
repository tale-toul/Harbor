## AWS based Infrastructure with terraform

https://www.terraform.io

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

Before first use of the terraform command you have to initialize the plugins in the
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

#### VPC creation

To create the VPC issue the following command:


```shell
 # terraform apply
```

This command will show the plan of changes to apply and ask for confirmation.  Enter
"yes" and the VPC will be created.

#### VPC destruction

When the VPC is no longer needed you can remove it using the command:

```shell
 # terraform destroy
```
