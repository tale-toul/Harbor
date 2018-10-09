provider "aws" {
    region = "eu-west-1"
    version = "~> 1.39"
}

data "terraform_remote_state" "vpc" {
    backend = "local"

    config {
        path = "../VPC/terraform.tfstate"
    }
}

#EIP
resource "aws_eip" "nateip" { 

    tags {
        Name = "nateip"
        Project = "harbor"
    }

}

#NAT GATEWAY
resource "aws_nat_gateway" "natgw" {
    allocation_id = "${aws_eip.nateip.id}"
    subnet_id = "${data.terraform_remote_state.vpc.subnet1_id}"

    tags {
        Name = "natgw"
        Project = "harbor"
    }
}

#ROUTE TABLE
resource "aws_route_table" "rtable2" {
    vpc_id = "${data.terraform_remote_state.vpc.vpc_id}"

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = "${aws_nat_gateway.natgw.id}"
    }
    tags {
        Name = "rtable2"
        Project = "harbor"
    }
}

#ROUTE TABLE ASSOCIATION
resource "aws_route_table_association" "rtabasso_nat" {
    subnet_id = "${data.terraform_remote_state.vpc.subnet2_id}"
    route_table_id = "${aws_route_table.rtable2.id}"
}
