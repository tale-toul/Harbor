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

### SSH connection to the registry host

The registry host is placed in a private subnet not directly accesible from the Internet
since it doesn't have a public name or IP address, only other hosts in the same VPC can
access it, given the security groups and NACLs rules.

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
        ProxyCommand ssh centos@registry.taletoul.com -W %h:%p 

Host registry.taletoul.com
        IdentityFile /home/tale/Descargas/tale_toul-keypair-ireland.pem
```

The first part applies to any host accessed with an IP in the 172.20.0.0/16 network.  The
next line specifies the private key used to authenticate with the hosts in the network:

`IdentityFile /home/tale/Descargas/tale_toul-keypair-ireland.pem`

The next line states that to connect to the hosts in the 172.20.0.0/16 network a proxy
connection has to be opened through the host **centos@registry.taletoul.com** with the
user **centos**:

  `ProxyCommand ssh centos@registry.taletoul.com -W %h:%p`

We also have to add a config block for the bastion host:

```
Host registry.taletoul.com
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
ansible_ssh_common_args='-o ProxyCommand="ssh -W %h:%p -q centos@registry.taletoul.com"'
ansible_user=centos
```

We still need the to start ssh-agent and add the key as above.

There is one last thing to take care of before running ansible against the registry
server.  When we launch a playbook for the first time after the hosts have been probably
recentry created and we have never stablish an ssh connections with them, we therefore
have to accept the ssh key of the remote server.  

We have configure ansible with the option **host_key_checking=False** not to be bothered
with that key validation, but when we make an indirect connection to the registry host we are
asked to accept the key two times, one for the bastion host and another for the registry,
but ansible doesn't seem to be prepared for two question and the play hangs on the second
question until a connection timeout is reached.  

To avoid this problem we have to make sure a connection to the bastion host is stablished
before going to the registry host, for that reason we have to make sure that we run a
play against the bastion host before running another against the registry.

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

### Updating variables with terraform data

The hosts used in this project are created in AWS using terraform code, but since we are
using a DNS name to access the reverse proxy virtual host we don't really need to update
the inventory every time new servers are created.  We still use a template for the
inventory but we could do without it since the only variable that is replaces is the
registry IP, but this is always the same internal private IP.

This play will run against the localhost, so a new group is created in the inventory
called _local_ containing localhost as the only member, and the play will run agains this
group.:

```
[local]
localhost   ansible_connection=local
```

The first task saves the terraform output variables from terraform/EC2 into the file
terraform_outputs.var

```
- name: Create variables file from terraform output EC2 outputs
  shell: terraform output |tr '=' ':' > ../../ansible/terraform_outputs.var
  args:
    chdir: ../terraform/EC2/
```

We need to update the variables related to the S3 bucket that is created using terraform,
so the firts task saves the output variables from terraform/S3 into the file
terraform_outputs.var.  This data is used by the Set up harbor play later.

The use of the **tr** command is needed to convert equal signs into coloms to create a
valid dictionary file understood by ansible.

```
- name: Add variables from terraform S3 outputs
  shell: terraform output |tr '=' ':' > ../../ansible/terraform_outputs.var
  args:
    chdir: ../terraform/S3/
```

This task is always run, creating a _changed_ state for the task, nothing bad comes out of
repeating it though.

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
registry.taletoul.com

[bastion:vars]
ansible_user= centos

[registry]
{{ registry_IP }}

[registry:vars]
ansible_ssh_common_args='-o ProxyCommand="ssh -W %h:%p -q centos@{{ groups['bastion'][0] }}"'
ansible_user= centos
harbor_path = /opt/harbor
installer_package = harbor-offline-installer-v1.6.1.tgz

[local]
localhost   ansible_connection=local
```

The next task is something like a bonus task, it creates the ssh.cfg file from a template.
This file can be used with ssh to connect to the registry host with a command like:

`ssh -F ssh.cfg centos@172.20.2.105`

The last task of the play reloads the newly created inventory file into ansible.  For some
reason the messages next to the _name_ option of this task doesn't show up during play
execution, but the new invetory is actually loaded into ansible.

### Setup the bastion host

This play is used to configure the bastion host as a reverse proxy so the registry host
can be reached from the outside world through the bastion host.

The first task installs the apache web server group.

Then the template defining the virtual host for the registry is applied. This template
uses the variable registry_IP defined in the terraform_outputs.var file so we load this
file at the beginning of the play.

```
vars_files:
  - terraform_outputs.var
```

The next tasks create the directories to store the public and private parts of the x509
certificate used by the virtual host.  The private directory is assigned restrictive
permissions so its contents cannot be seen by a normal user.

The next tasks copy the public and private parts of the certificate to the previously
created directories.  The private part of the certificate is assigned restrictive
permissions so a normal user cannot access it.

The next task enables and starts the apache web server.

The bastion host does not include the docker client so we cannot use the registry directly
from it for security reasons.

### Set up the registry host

The last play of the playbook contains the tasks used to install harbor in the registry
server, they are only run aginst the registry server.

All tasks have to be run as root (become=true).

The first few tasks are used to install docker and docker compose, then enable the docker
service, this is a requirement to later install harbor:

```
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
```

The next task checks whether the harbor installer package already exists in the regitry
server, that is it has been previouly downloaded.  The **installer_package** variable is
defined in the inventory file in the **registry:vars** section.

```
- name: Stat local installer package
  stat:
    path: /tmp/{{ installer_package }}
  register: installer
```

The next task downloads the tar file containing the harbor installer package, but only if
it doesn't already exist.  The installer package is quite big so it is a waste of time and
bandwith downloading it, if it's already there.  The specific file to be downloaded is
defined in the variable **installer_package** defined in the inventory file, so we can
change the version we install easily.

```
- name: Download harbor installer package
  get_url:
    url: https://storage.googleapis.com/harbor-releases/{{ installer_package }}
    dest: /tmp/
  when: not installer.stat.exists
```

The next task extracts the contents of the installer in /opt/harbor.

```
- name: Unpack harbor installer
  unarchive:
    src: /tmp/{{ installer_package }}
    dest: /opt
    remote_src: True
```

The next task creates a directory to hold the certificates that will be used to secure the
web ui and the registry server, the permissions assigned are very tight.

```
- name: Make directory to hold certificates
  file:
    path: /registry_certs
    state: directory
    mode: 0400
```

The next two tasks copy the public and private parts of the certificate to the directory
created before.

```
- name: Copy certificate file
  copy:
    src: files/registry.crt
    dest: /registry_certs
- name: Copy key file
  copy:
    src: files/registry.key
    dest: /registry_certs
    mode: 0600
```

The next task copies the main configuration file from a template. Among other things the
template updates:

* The name of the host.
* The communications protocol to be used. 
* The password for the database root user. and the path to the certificate to secure the
* The password for the web UI admin user.
* Disables user self registration.
* Disables user project creation.

This configuration file contains sensitive information so the access premissions are
restricted to 0600

```
- name: Add harbor config file from template
  template:
    src: templates/harbor.j2
    dest: "{{ harbor_path }}/harbor.cfg"
    mode: 0600
```

The next task copies the storage configuration file from a template.  This configuration
file contains sensitive information so the access premissions are restricted to 0600.  The
variables used in this template were populated in the first play (Update local inventory
file) and are imported into this play by the following directive at the beginning of the
play.  The variables used are: iam_user_access_key; iam_user_secret_key; bucket_region;
bucket_name.

```
vars_files:
  - terraform_outputs.var
```
```
- name: Apply Storage backend template
  template:
   src: templates/config.j2
   dest: "{{ harbor_path }}/common/templates/registry/config.yml"
   mode: 0600
```

The last task runs the installer, but only when the file
**/data/database/postmaster.pid** doesn't exist.

```
- name: Run installation script
  command: ./install.sh
  args:
    chdir: "{{ harbor_path }}"
    creates: /data/database/postmaster.pid
```

After the successful complation of this play, the inventory is up and running, ready to
accept requests.

## Vault use

The **certificates** used to secure the registry's communications are kept in the files/
directory of the ansible project and are included in the git project.

The files include the keys for the registry: registry.key and CA-key.pem.
Should not be shared openly, so we are going to use ansible vault to encrypt them:

```shell
# ansible-vault encrypt registry.key 
 New Vault password: 
 Confirm New Vault password: 
 Encryption successful
```

Same for the file CA-key.pem.  For both files it't easiest to use the same password for
the encryption.

The **db_password** and **harbor_admin_password** configuration variables in the harbor.j2
template are also protected with vault, these variables contain the root password of the
postgresql database and the harbor web ui admin's password.

The password is protected with vault with a command like:

```
# ansible-vault encrypt_string --name 'db_password' 'adlj3alvj'
New Vault password: 
Confirm New Vault password: 
db_password: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          33623235623862613531653033326465396636393633646638326466643639306334616161613665
          3439633861363537386332323865373761363937643837630a633163356163336634613765326238
          63643233383736383266613066636262656430383061366563383763656365336438623438633536
          6235316462383439390a356662396663366235353564653462383130376632613132363961643236
          6162
Encryption successful
```
The vault password used to encrypt the variable's contents is the same we used before for
the certificates.

The resulting ouput is copied in the file **group_vars/registry** since the inventory file
does not support the use of vault encrypted variables, then the db_password variable can
be referenced anywhere in the playbook.

Now when we run ansible we have to use the option --ask-vault-pass or the config option
"ask-vault-pass = True" to get asked for the vault password.


## Running the playbook

To run the playbook use the following command, and have the vault password ready:

    `# ansible-playbook --ask-vault-pass harbor.yml`
