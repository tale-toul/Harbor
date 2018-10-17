output "bastion_name" {
    value= "${aws_instance.bastion.public_dns}"
}

output "registry_IP" {
    value = "${aws_instance.registry.private_ip}"
}
