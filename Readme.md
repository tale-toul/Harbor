## Harbor: docker image registry

https://goharbor.io/
https://github.com/goharbor/harbor/blob/master/README.md

### Installation

I will be installing the 1.6.0 version.

https://github.com/goharbor/harbor/blob/release-1.6.0/docs/installation_guide.md

#### Requirements

The installation will be performed on AWS machines.

The minimum requirements are:

* Hardware
  * 2 CPUS
  * 4GB RAM
  * 40GB DISK space
* Software
  * Python 2.7
  * Docker 1.10
  * Docker composer 1.6
  * Openssl  

The network ports used are:

* 443  Harbor UI and API will accept requests on this port for https protocol
* 4443  Connections to the Docker Content Trust service for Harbor, only needed when
  Notary is enabled
* 80  Harbor UI and API will accept requests on this port for http protocol

#### Installation steps

* Download the installer, in this case I will be using the online installer from version
  1.6.0:
```
$ curl -o harbor1.6.0-online.tgz https://storage.googleapis.com/harbor-releases/release-1.6.0/harbor-online-installer-v1.6.0.tgz
```

* Extract the tar file:
```
$ tar xvf harbor1.6.0-online.tgz
```

* Edit the harbor.cfg file according to the installation instructions

* Run the installer:

    `#./install.sh`

### Building and starting harbor with terraform and ansible

To build the harbor project from scratch do the following:

* Export the the variables AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY with the values of
  an AWS user with proper permissions

* Go to terraform/VPC and run the following command to create the VPC where harbor will be
  installed:

`# terraform apply`

* Go to terraform/NAT_gateway and run the following command to create the NAT gateway for
  harbor's private subnet:

`# terraform apply`

* Add the ssh key with permission to connect to the EC2 instances to the ssh agent:

`# ssh-add Descargas/tale_toul-keypair-ireland.pem`
 
  Check it with:

`# ssh-add -L`

* Go to ansible and run the playbook to setup the bastion and registry hots, and to
  install harbor in the registry host.

`# ansible-playbook harbor.yml`


### Connecting to the registry

* From the bastion host.

    * Add the registry as insecure registry.- Edit the file **/etc/sysconfig/docker** and
      add to the OPTIONS variable a section like the following, then restart the docker
      service:

        `--insecure-registry 172.20.2.180:80`

    * Log in to the registry.- The registry server listens of port 80, at least initially,
      so the command to log in is:

        `sudo docker login http://172.20.2.180:80`

    * Access the website.- To access the harbor website from the local workstation we will
      create a ssh tunnel, this is needed because the registry server is not directly
      accesible since it is housed in a private subnet.  The command to create the ssh
      tunnel is like:

`# ssh -i ~/Descargas/tale_toul-keypair-ireland.pem -fN -L 8080:172.20.2.180:80 centos@ec2-34-244-134-185.eu-west-1.compute.amazonaws.com`

      Now we can connect to the web interface with the URL http://localhost:8080
