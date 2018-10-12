## Ansible playbooks to setup harbor

### Set up the bastion host

We are going to use the bastion host created in the public subnet as the ansible
controller, so the first order of business is setting up this host as such controller,
which basically consists on installing ansible, this we will do from the rpm packages.

We use ansible from a local machine to setup ansible in the bastion host.

The inventory file will contain a group of one host called _bastion_ with the DNS name of
the bastion host and the remote user to connect via ssh.  This name will change on every
execution of terraform so a dynamic inventory could be a good idea here.  The
*ansible_user* must match the default user of the ami, in RedHat it is __ec2-user__, in
CentOS it is __centos__

```
[bastion]
ec2-52-211-33-67.eu-west-1.compute.amazonaws.com ansible_user=centos
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
  become: True

  tasks:
    - name: Install EPEL repository on RedHat
      yum:
        name: https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
        state: present
      when: ansible_distribution == 'RedHat'
    - name: Install EPEL repository on CentOS
      yum:
        name: epel-release
        state: present
      remote_user: centos
      when: ansible_distribution == 'CentOS'
    - name: Install ansible and docker
      yum:
        name: ansible, docker
        state: present
    - name: Enable and start docker service
      service:
        name: docker
        state: started
        enabled: True
...

```

The tasks have to be run as root (become=true).

The first task installs the rpm package that enables the EPEL repository, this task is
different between RedHat and CentOS hosts

The second task installs ansible and docker.

Then the docker service is started and enabled.

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
