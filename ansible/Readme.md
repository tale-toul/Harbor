## Ansible playbooks to setup harbor

### Set up the bastion host

We are going to use the bastion host created in the public subnet as the ansible
controller, so the first order of business is setting up this host as such controller,
which basically consists on installing ansible, this we will do from the rpm packages.

We use ansible from a local machine to setup ansible in the bastion host.

The inventory file will contain a group of one host called bastion with the DNS name of
the bastion host, this name will change on every running of the terraform files so a
dinamy inventory could be a good idea here.

```
[bastion]
ec2-34-245-72-227.eu-west-1.compute.amazonaws.com
```

The ansible.cfg file will contain the following options:

```
[defaults]
inventory=inventario
host_key_checking=False
private_key_file=/home/tale/Descargas/tale_toul-keypair-ireland.pem
```

The meaning of this options is:

* inventory=inventario.- the name of the inventory file
* host_key_checking=False.- The ssh key signature of the files not in known_hosts will be
  included without prompting the user
* private_key_file=/home/tale/Descargas/tale_toul-keypair-ireland.pem.- This is the
  private key used to connect to the managed hosts.

The playbook to install ansible is:

```
---
- name: Set up the bastion host as an ansible controller host
  hosts: bastion
  remote_user: ec2-user
  become: True

  tasks:
    - name: Install EPEL repository
      yum:
        name: https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
        state: present
    - name: Update packages
      yum: 
        name: '*'
        state: latest
    - name: Install ansible
      yum:
        name: ansible
        state: present
...
```

We use the remote user *ec2-user* which is the available user in most of the aws AMIs,
then run the tasks as root (become=true).

The first task installs the rpm package that enables the EPEL repository.

The second task updates the already installed packages

The third task install ansible proper.

To run the playbook use the following command:

`$ ansible-playbook bastion.yml'

### Testing the connection 

To test that the local hosts can connect to the soon-to-be managed hosts we can use a
simple ad-hoc command like:

```shell
$ ansible all -m ping -u ec2-user
ec2-34-245-72-227.eu-west-1.compute.amazonaws.com | SUCCESS => {
    "changed": false, 
    "ping": "pong"
}
```

If the result is success the connection is good.

### Set up the registry host

* Install docker
