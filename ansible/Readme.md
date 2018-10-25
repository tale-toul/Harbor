## Ansible playbooks to install and setup harbor

Ansible will be used to automate the installation and configuration of harbor.

The ansible.cfg file will contain the following options:

```
[defaults]
inventory=inventario
host_key_checking=False
private_key_file=/home/tale/Descargas/tale_toul-keypair-ireland.pem
```

The meaning of these options are:

* inventory=inventario.- the name of the inventory file
* host_key_checking=False.- The ssh key signature of the files not in known_hosts will be
  included without prompting the user
* private_key_file=/home/tale/Descargas/tale_toul-keypair-ireland.pem.- This is the
  private key used to connect to the managed hosts.

To run the playbook use the following command:

`$ ansible-playbook harbor.yml'

### SSH connection to the registry host

The registry host is placed in a private subnet not directly accesible from the Internet
since it doesn't have a public name or IP address, only other hosts in the same VPC can
access it, given that the security groups and NACLs allow it.

We are using a bastion host created in the public subnet to indirectly connect to the
registry host both using ssh and ansible.  This way we can run the ansible playbooks from
the local workstation without the need to install ansible in the bastion host.

To connect to the registry host with ssh via the bastion host we have to add some
configuration to the ssh client config file in the local machine.

The registry host is in the network 172.20.2.0/24 and the bastion host has a public IP and
DNS name.  The required configuration is:

```
Host 172.20.*.*
        IdentityFile /home/tale/Descargas/tale_toul-keypair-ireland.pem
        ProxyCommand ssh centos@ec2-34-249-106-182.eu-west-1.compute.amazonaws.com -W %h:%p 

Host ec2-34-249-106-182.eu-west-1.compute.amazonaws.com
        IdentityFile /home/tale/Descargas/tale_toul-keypair-ireland.pem
```

The first part applies to any host accessed with an IP in the 172.20.0.0/16 network.  The
next line specifies the private key used to authenticate with the hosts in the network:

`IdentityFile /home/tale/Descargas/tale_toul-keypair-ireland.pem`

The next line specifies that to connect to the hosts in the 172.20.0.0/16 network a proxy
connection has to be opened through the host
**ec2-34-249-106-182.eu-west-1.compute.amazonaws.com** with the user **centos**:

`ProxyCommand ssh centos@ec2-34-249-106-182.eu-west-1.compute.amazonaws.com -W %h:%p`

We also have to add a config block for the bastion host:

```
Host ec2-34-249-106-182.eu-west-1.compute.amazonaws.com
        IdentityFile /home/tale/Descargas/tale_toul-keypair-ireland.pem
```

This block specifies the ssh key to use when authenticating with the bastion host.

Finally we have to start the ssh-agent (maybe only the first time) and add the key

```
# ssh-agent bash
# ssh-add /home/tale/Descargas/tale_toul-keypair-ireland.pem
```

Now we can connect to the registry host with a simple ssh command like the following, in
this example we have added the configuration to the ssh.cfg file:

`# ssh -F ssh.cfg centos@172.20.2.79`

One important thing to notice is that the 172.20.2.0/24 network is not accesible from the
localhost where the command is issued but still we get an ssh session in that host.

To apply this setup to ansible we define the variable ansible_ssh_common_args for the
group of hosts in the private network, for example in the inventory file:

```
...
[registry]
172.20.2.79 

[registry:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -W %h:%p -q centos@ec2-34-249-106-182.eu-west-1.compute.amazonaws.com"'
ansible_user=centos
```

We still need the to start ssh-agent and add the key as above.

There is one last thing to take care of before running ansible against the registry
server.  When we launch a playbook for the first time after the hosts have been newly
created we have to accept the ssh key of the remote server.  We have configure ansible
with the option **host_key_checking=False** not to be bothered with that question, but
when we make an indirect connection to the registry host we are asked to accept the key
two times, one for the bastion host, another for the registry host, but ansible doesn't
seem prepared for two question and the play hangs on the second question until a
connection timeout is reached.  

To avoid this problem we have to make sure a connection to the bastion host is stablished
before going to the registry host, for that reason the ansile playbook includes a dummy
connection before the play that is run against both the bastion and registry hosts.  This
first connection overcomes the hurdle of that double question.

```
- name: Dummy connection to bastion host
  hosts: bastion

  tasks:
    - name: Just a simple message
      debug:
        msg: Hello from bastion

```

After that we can run ansible commands or playbooks against the hosts in the private
network:

#### Testing the connection 

To test that the local hosts can connect to the soon-to-be managed hosts we can use a
simple ad-hoc command like:

```shell
$ ansible all -m ping -u centos
ec2-34-245-72-227.eu-west-1.compute.amazonaws.com | SUCCESS => {
    "changed": false, 
    "ping": "pong"
}
```

If the result is success the connection is good.

### Updating the inventory file with terraform data

The hosts used in this project are created on demand in AWS using terraform code, so we
need to update the inventory file used by ansible every time new servers replace the old
ones (terraform destroy -> terraform apply).  To simplify this error prone process we
leverage ansible and defining a new play for this.

This play will run against the localhost, that will not change when terraform creates new
EC2 instances, so a new group is created in the inventory called _local_ conatining
localhost as the only member, and the play will run agains this group.:

```
[local]
localhost   ansible_connection=local
```

The play basically creates the inventory file by filling the variables in a template, but
first we have to define these variables, for that we use a task that saves the output
variables from terraform/VPC into a file:

```
- name: Create variables file from terraform output
  shell: terraform output |tr '=' ':' > ../../ansible/terraform_outputs.var
  args:
    chdir: ../terraform/EC2/
```
The use of the **tr** command is needed to convert equal signs into coloms to create a
dictionary file understandable by ansible.

This task is always run, creating a _changed_ state for the task, since nothing bad comes out of
repeating it.

Next task saves the output variables from terraform/S3 into the same file
terraform_outputs.var.  This task doesn't have anything to do with the inventory update,
it is used by the Set up harbor play later.

The next task loads the variables from the file just created into ansible making them
available for the next tasks:
```
- name: Load the terraform out variables
  include_vars:
    file: terraform_outputs.var
```

The next task fills in the template and creates the new inventory file:

```
- name: Apply inventory template
  template:
    src: templates/inventario.j2
    dest: inventario
```

The template file is a simple variable substituion template without any extra logic:

```
[bastion]
{{ bastion_name }}

[bastion:vars]
ansible_user= centos

[registry]
{{ registry_IP }}

[registry:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -W %h:%p -q centos@{{ bastion_name }}"'
ansible_user= centos

[aws:children]
bastion
registry

[local]
localhost   ansible_connection=local
```

The next task is something like a bonus task, it updates the ssh.cfg file from a template.
This file can be used with ssh to connect to the registry host with a command like:

`ssh -F ssh.cfg centos@172.20.2.105`

The last task of the play reloads the newly created inventory file into ansible.  For some
reason the messages next to the _name_ option of this task doesn't show up during play
execution, but the new invetory seems to be loaded into ansible.

### Installing docker and docker compose with ansible 

All servers (bastion and registry) need docker and docker compose installed.  The play
"Setup docker and docker compose" is used to install these packages and enable the docker
service.  In addition the bastion host is setup to accept the registry's certificate for
the secure connections.

The play is executed against the group aws wich is made of the groups bastion and
registry.

The vars of the bastion group consist of the remote user to connect via ssh to this host.
The *ansible_user* must match the default user of the ami, in RedHat it is __ec2-user__,
in CentOS it is __centos__.  

The inventory file also contains the group _registry_ with the private IP of the registry
server, this address is not directly accesible from the outside world, see [SSH connection
to the registry host][### SSH connection to the registry host].  This addess changes on
every execution of the terraform plan.

The vars section of the registry group contains the ssh configuration needed to connect to
the registry host, and the remote user to connect as.  The inventory file is created from
a template on every playbook executions (see Updating the inventory file with terraform
data)

```
[bastion]
ec2-34-245-13-203.eu-west-1.compute.amazonaws.com

[bastion:vars]
ansible_user=centos

[registry]
172.20.2.23

[registry:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -W %h:%p -q centos@ec2-34-245-13-203.eu-west-1.compute.amazonaws.com"'
ansible_user=centos
```

The contents of this play are:

```
- name: Setup docker and docker compose
  hosts: aws
  become: True
  vars_files:
    - terraform_outputs.var

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
    - name: Install docker and docker compose
      yum:
        name: docker, docker-compose
        state: present
    - name: Enable and start docker service
      service:
        name: docker
        state: started
        enabled: True
      block:
          - name: Create directory for registry certs
            file
              path: /etc/docker/certs.d/{{ registry_IP }}
              state: directory
          - name: Copy CA public cert to servers certificates
            copy:
              src: files/CA.pem
              dest: /etc/docker/certs.d/{{ registry_IP }}/ca.crt
      when: inventory_hostname == bastion_name

```

All tasks have to be run as root (become=true).

The first tasks add the EPEL repository, needed to later install docker compose. There is
one task for RedHat servers and another for CentOS servers.

The next task installs docker and docker compose.

The next taks startes and enables the docker service.

Then comes a block that creates the directory to put the registry certificate, and copies
it inside.  The directory must be created in /etc/docker/certs.d/ and the its name must be
the same we use to connect to the server.  This block is only executed on the bastion host
**when: inventory_hostname == bastion_name**

### Set up the registry host

The last play of the playbook contains the tasks used to install harbor in the registry
server, they are only run aginst the registry server:

```
- name: Download harbor online installer
  get_url:
    url: https://storage.googleapis.com/harbor-releases/release-1.6.0/harbor-online-installer-v1.6.0.tgz
    dest: /tmp/
- name: Unpack harbor installer
  unarchive:
    src: /tmp/harbor-online-installer-v1.6.0.tgz
    dest: /opt
    remote_src: True
- name: Make directory to hold certificates
  file:
    path: /registry_certs
    state: directory
    mode: 0400
- name: Copy certificate file
  copy:
    src: files/registry.tanami.xyz.crt
    dest: /registry_certs
- name: Copy key file
  copy:
    src: files/registry.tanami.xyz.key
    dest: /registry_certs
    mode: 0600
- name: Add harbor config file from template
  template:
    src: templates/harbor.j2
    dest:  /opt/harbor/harbor.cfg
- name: Apply Storage backend template
  template: 
   src: templates/config.j2
   dest: /opt/harbor/common/templates/registry/config.yml
- name: Run installation script
  command: ./install.sh
  args:
    chdir: /opt/harbor
        creates: /data/database/postmaster.pid
```

The first task downloads the tar file containing the online installer.

The next task extracts the contents of the installer in /opt/harbor.

The next task creates a directory to hold the certificates that will be used to secure the
web ui and the registry server.

The next two tasks copy the public and private parts of the certificate to the directory
created before.

The next task copies the main configuration file from a template. Among other things the
template updtes the name of the host, the protocol to be used, and the path to the
certificate to secure the registry.

The next task copies the storage configuration file from a template.  The variables used
by this template were populated in the first play (Update local inventory file) and are
imported into this play by the following directive at the begening of the play.  The
variables used are: iam_user_access_key; iam_user_secret_key; bucket_region; bucket_name.

```
  vars_files:
    - terraform_outputs.var
```

The fifth task runs the installer, but only when the file
**/data/database/postmaster.pid** doesn't exist.

After the successful complation of this play, the inventory is up and running, ready to
accept requests.

## Vault use

The certificates used to secure the registry are ketp in the files directory of the
ansible project and in the git project.

The files contain the keys for the registry: registry.tanami.xyz.key and CA-key.pem.
Should not be shared openly, so we are going to use ansible vault to encrypt them:

```shell
# ansible-vault encrypt registry.tanami.xyz.key 
 New Vault password: 
 Confirm New Vault password: 
 Encryption successful
```

Same for the file CA-key.pem.  For both files it't easiest to use the same password for
the encryption.

Now when we run ansible we have to use the option --ask-vault-pass or the config option
"ask-vault-pass = True" to get asked for the vault password.


## Running the playbook

To run the playbook use the following command, and have the vault password ready:

    `# ansible-playbook --ask-vault-pass harbor.yml`
