provider "aws" {
    region = "eu-west-1"
    version = "~> 1.39"
}

terraform {
    backend "local" {
        path = "terraform.tfstate"
    }
}

#VPC
resource "aws_vpc" "vpc" {
    cidr_block = "172.20.0.0/16"
    enable_dns_hostnames = true

    tags {
        Name = "volatil"
        Project = "harbor"
    }
}

#SUBNETS
data "aws_availability_zones" "avb-zones" {}

resource "aws_subnet" "subnet1" {
    vpc_id = "${aws_vpc.vpc.id}"
    availability_zone = "${data.aws_availability_zones.avb-zones.names[0]}"
    cidr_block = "172.20.1.0/24"
    map_public_ip_on_launch = true

    tags {
        Name = "subnet1"
        Project = "harbor"
    }
}

resource "aws_subnet" "subnet2" {
    vpc_id = "${aws_vpc.vpc.id}"
    availability_zone = "${data.aws_availability_zones.avb-zones.names[1]}"
    cidr_block = "172.20.2.0/24"
    map_public_ip_on_launch = false

    tags {
        Name = "subnet2"
        Project = "harbor"
    }
}

#INTERNET GATEWAY
resource "aws_internet_gateway" "intergw" {
    vpc_id = "${aws_vpc.vpc.id}"

    tags {
        Name = "intergw"
        Project = "harbor"
    }
}

#ROUTE TABLE
resource "aws_route_table" "rtable" {
    vpc_id = "${aws_vpc.vpc.id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_internet_gateway.intergw.id}"
    }
    tags {
        Name = "rtable"
        Project = "harbor"
    }
}

#ROUTE TABLE ASSOCIATION
resource "aws_route_table_association" "rtabasso" {
    subnet_id = "${aws_subnet.subnet1.id}"
    route_table_id = "${aws_route_table.rtable.id}"
}

#SECURITY GROUPS
resource "aws_security_group" "sg-ssh-in" {
    name = "ssh-in"
    description = "Allow ssh connections from MedinaNet"
    vpc_id = "${aws_vpc.vpc.id}"

	ingress {
		from_port = 22
		to_port = 22
		protocol = "tcp"
		cidr_blocks = ["185.192.0.0/10"]
    }

    tags {
        Name = "sg-ssh"
        Project = "harbor"
    }
}

resource "aws_security_group" "sg-ssh-out" {
    name = "ssh-out"
    description = "Allow outgoing ssh connections to the VPC network"
    vpc_id = "${aws_vpc.vpc.id}"

	egress {
		from_port = 22
		to_port = 22
		protocol = "tcp"
		cidr_blocks = ["172.20.0.0/16"]
    }

    tags {
        Name = "sg-ssh-out"
        Project = "harbor"
    }
}

resource "aws_security_group" "sg-ssh-in-local" {
    name = "ssh-in-local"
    description = "Allow ssh connections from same VPC"
    vpc_id = "${aws_vpc.vpc.id}"

	ingress {
		from_port = 22
		to_port = 22
		protocol = "tcp"
		cidr_blocks = ["172.20.0.0/16"]
    }

    tags {
        Name = "sg-ssh-local"
        Project = "harbor"
    }
}

resource "aws_security_group" "sg-web-out" {
    name = "web-out"
    description = "Allow http and https outgoing connections"
    vpc_id = "${aws_vpc.vpc.id}"

	egress {
		from_port = 80
		to_port = 80
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	egress {
		from_port = 443
		to_port = 443
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

    tags {
        Name = "sg-web-out"
        Project = "harbor"
    }
}

resource "aws_security_group" "sg-web-in-local" {
    name = "web-in"
    description = "Allow http and https inbound connections from same VPC"
    vpc_id = "${aws_vpc.vpc.id}"

    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
		cidr_blocks = ["172.20.0.0/16"]
    }

    ingress {
        from_port = 443
        to_port = 443
        protocol = "tcp"
		cidr_blocks = ["172.20.0.0/16"]
    }

    tags {
        Name = "sg-web-in-local"
        Project = "harbor"
    }
}

#EC2 instances
resource "aws_instance" "bastion" {
  #Centos 7.5
  ami = "ami-3548444c"
  instance_type = "t2.micro"
  subnet_id = "${aws_subnet.subnet1.id}"
  vpc_security_group_ids = ["${aws_security_group.sg-ssh-in.id}",
                            "${aws_security_group.sg-web-out.id}",
                            "${aws_security_group.sg-ssh-out.id}"]
  key_name= "tale_toul-keypair-ireland"

    tags {
        Name = "bastion"
        Project = "harbor"
    }
}

resource "aws_instance" "registry" {
  #Centos 7.5
  ami = "ami-3548444c"
  instance_type = "t2.micro"
  subnet_id = "${aws_subnet.subnet2.id}"
  vpc_security_group_ids = ["${aws_security_group.sg-ssh-in-local.id}",
                            "${aws_security_group.sg-web-out.id}",
                            "${aws_security_group.sg-web-in-local.id}"]
  key_name= "tale_toul-keypair-ireland"

    tags {
        Name = "registry"
        Project = "harbor"
    }
}
