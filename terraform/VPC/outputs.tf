#Public subnet1 
output "subnet1_id" {
    value = "${aws_subnet.subnet1.id}"
}

output "bastion_name" {
    value= "{aws_instance.bastion.public_dns}"
}
