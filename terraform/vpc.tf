provider "aws" {
    region = "eu-west-1"
    version = "~> 1.39"
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
