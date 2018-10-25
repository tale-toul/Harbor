provider "aws" {
    region = "eu-west-1"
    version = "~> 1.40"
}

data "terraform_remote_state" "vpc" {
    backend = "local"

    config {
        path = "../VPC/terraform.tfstate"
    }
}

#EC2 instances
resource "aws_instance" "bastion" {
  #Centos 7.5
  ami = "ami-3548444c"
  instance_type = "t2.micro"
  subnet_id = "${data.terraform_remote_state.vpc.subnet1_id}"
  vpc_security_group_ids = ["${data.terraform_remote_state.vpc.sg-ssh-in_id}",
                            "${data.terraform_remote_state.vpc.sg-web-out_id}",
                            "${data.terraform_remote_state.vpc.sg-ssh-out_id}"]
  key_name= "tale_toul-keypair-ireland"
  root_block_device {
    volume_size = 8
    delete_on_termination = true
  }

    tags {
        Name = "bastion"
        Project = "harbor"
    }
}

resource "aws_instance" "registry" {
  #Centos 7.5
  ami = "ami-3548444c"
  instance_type = "t2.micro"
  subnet_id = "${data.terraform_remote_state.vpc.subnet2_id}"
  vpc_security_group_ids = ["${data.terraform_remote_state.vpc.sg-ssh-in-local_id}",
                            "${data.terraform_remote_state.vpc.sg-web-out_id}",
                            "${data.terraform_remote_state.vpc.sg-web-in-local_id}"]
  key_name= "tale_toul-keypair-ireland"
  root_block_device {
    volume_size = 8
    delete_on_termination = true
  }
  private_ip = "172.20.2.20"

    tags {
        Name = "registry"
        Project = "harbor"
    }
}
