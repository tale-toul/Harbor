## Harbor: docker image registry

https://goharbor.io/
https://github.com/goharbor/harbor/blob/master/README.md

### Installation

This instructions are for installing the 1.6.0 version of harbor.

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

    `$ sudo ./install.sh`

### Building and starting harbor with terraform and ansible

To build the harbor project from scratch do the following:

* Export the the variables **AWS_ACCESS_KEY_ID** and **AWS_SECRET_ACCESS_KEY** with the
  values of an AWS user with proper permissions

* Go to **terraform/VPC** and run the following command to create the VPC where harbor
  will be installed:

        `# terraform apply`

* Go to **terraform/NAT_gateway** and run the following command to create the NAT gateway for
  harbor's private subnet:

        `# terraform apply`

* Go to **terraform/EC2** and run:

        `# terraform apply`

* Go to **terraform/S3** and run:

        `# terraform apply`

* Add the ssh key with permission to connect to the EC2 instances to the ssh agent:

        `# ssh-add Descargas/tale_toul-keypair-ireland.pem`
 
  Check it with:

        `# ssh-add -L`

* Go to ansible and run the playbook to setup the bastion and registry hots, and to
  install harbor in the registry host.

        `# ansible-playbook harbor.yml`

* If you don't need the NAT_gateway anymore you can delete it and bring it back up when
  needed again.

        `# cd terraform/NAT_gateway && terraform destroy`


### Connecting to the registry

* From the bastion host.
    * Access the website.- To access the harbor website from the local workstation we will
      create a ssh tunnel, this is needed because the registry server is not directly
      accesible since it is housed in a private subnet.  The command to create the ssh
      tunnel is like:

    ```
    # ssh -i ~/Descargas/tale_toul-keypair-ireland.pem -fN -L 8080:172.20.2.180:80 \
        centos@ec2-34-244-134-185.eu-west-1.compute.amazonaws.com
    ```

      Now we can connect to the web interface with the URL http://localhost:8080

    * In the harbor web site:

        * Create a user: Administration -> Users -> + NEW USER

        * Create a proyect: Projects -> + NEW PROJECT 

        * Add the user created before to the project: Projects -> <project name> ->
          Members -> + USER

    * Add the registry as insecure registry.- Edit the file **/etc/sysconfig/docker** and
      add to the OPTIONS variable a section like the following, then restart the docker
      service:

        `--insecure-registry 172.20.2.180`

        `$ sudo systemctl restart docker`

    * Log in to the registry.- The registry server listens of port 80, at least initially,
      so the command to log in is:

        `sudo docker login http://172.20.2.180`

#### Testing the registry

To test that the registry is working properly we will upload an image:

* Pull an image from the bastion host:

    `$ sudo docker pull centos`

* Tag the image to point to the harbor registry:

    `$ sudo docker tag docker.io/centos 172.20.2.112/pro1/centos

* Push the image to the harbor registry:

    `$ sudo docker push 172.20.2.112/pro1/centos`

### S3 storage backend

By default harbor stores images on the local filesystem, while this is good for testing it
might not be the best option for a productio system.  In this section we will see how to
configure an AWS S3 bucket as the storage backend for harbor. 

The storage configuration is defined in the section **storage** of the file
**common/templates/registry/config.yml**.

The configuration for an S3 storage backend is:

```yaml
storage:
  s3:
    accesskey: al3a0ckAKIAJDRL3CX
    secretkey: k3alc3lLlla3adlalrj3dcadyxl
    region: eu-west-1
    bucket: tanami-s3-test
    secure: true
    chunksize: 6291456
    multipartcopychunksize: 8388608
    multipartcopymaxconcurrency: 100
    multipartcopythresholdsize: 33554432
```
The documentation for this configuration options can be found at [docker registry
storage](https://docs.docker.com/registry/configuration/#storage) 

This configuration changes must be made before the **install.sh** script is run, otherwise
the configuration that will be used is the one using the local filesystem as storage
backend.

The access and secret keys should belong to an AWS user (lenan) with just enough
priviledges to operate the S3 bucket.  In this example the user in question doesn't have
any policies assigned so it doesn't have permission to do any operation against any AWS
resources.  On the S3 side a bucket policy has been defined in the tanami-s3-test bucket
that will be used as storage backend for harbor:

```json
{
    "Version": "2012-10-17",
    "Id": "Policy1540060404336",
    "Statement": [
        {
            "Sid": "Stmt1540060363946",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::768219552881:user/lenan"
            },
            "Action": [
                "s3:ListBucket",
                "s3:GetBucketLocation",
                "s3:ListBucketMultipartUploads"
            ],
            "Resource": "arn:aws:s3:::tanami-s3-test"
        },
        {
            "Sid": "Stmt1540060363947",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::768219552881:user/lenan"
            },
            "Action": [
                "s3:AbortMultipartUpload",
                "s3:DeleteObject",
                "s3:GetObject",
                "s3:ListMultipartUploadParts",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::tanami-s3-test/*"
        }
    ]
}
```

This policy is defined to allow the actions recomended by the doker registry [documentation](https://github.com/docker/docker.github.io/blob/master/registry/storage-drivers/s3.md#s3-permission-scopes)

This configuration is enough to use the S3 bucket as backend storage for harbor, however
this configuration is static and any changes in the bucket or the user will requiere a
manual reconfiguration the config.yml and the policy files.  In the next section we will
see how to automate the creation of the user, bucket and bucket policy using terraform,
and apply the configuration with ansible.

#### S3 bucket automation

Following the concept of Inmutable infrastructure that has been a core concept in this
project, we are going to setup terraform and ansible to automatically create a bucket; an
AWS user to manage the bucket; a bucket policy to staple together the bucket and user with
just the minimum permissions requiere by harbor; and the configuration files needed by
harbor to use the bucket as a storage backend.

For the details on the creation of the resources with terraform see the section **S3
storage** in the terraform/Readme.md file.

For the details on the creation of the configuration file for harbor by ansible see the
section **Set up the registry host** in the ansible/Readme.md file.

### Setting up TLS

[Configuring harbor with HTTPS](https://github.com/goharbor/harbor/blob/master/docs/configure_https.md#configuring-harbor-with-https-access)

You should never access the registry through an insecure connection over HTTP.  By default
harbor installation does not configure a secure connection, so we will show here how to do
it propely.

#### Certificate creation

We will create an x509 certificate using openssl.  This certificate created here is used
both for accessing the web interface and for securing the registry communications.

You can perform the following steps from any computer with the openssl command.  The
official documentation includes instructions on how to do it:

* Create a selfsigned CA certificate:

    `# openssl req -x509 -newkey rsa:4096 -keyout CA-key.pem -out CA.pem -days 365 -nodes`

  The resultin certificate is valid for 1 year.  To see its contents use the command:

    `# openssl x509 -in CA.pem -text -noout`

* Create a certificate signing request:

    `# openssl req -newkey rsa:4096 -nodes -sha256 -keyout registry.tanami.xyz.key -out registry.tanami.xyz.csr`

* If you need to access the registry with more than one name or IP create a file with the
  variable subjectAltName. IPs are prefixed with **IP:** DNS names are prefixed with
  **DNS:**.  The elements in the list are comma separated:

    `subjectAltName = IP:172.20.2.20, DNS:registry.tanami.es`

* Generate the certificate:

    `# openssl x509 -req -days 365 -in registry.tanami.xyz.csr -CA CA.pem -CAkey CA-key.pem -CAcreateserial -extfile extfile.cnf -out registry.tanami.xyz.crt`
  
  *extfile.cnf* is the file with the subjectAltName variable defined.

This certificate is valid for the IP 172.20.2.20 so the registry server should always have
that address; a static private IP is assigned to the registry from the terraform file.

#### Harbor configuration

* A directory is created in the registry to hold the certificate, both its public and
  private parts:

    `# mkdir /registry_certs`

  This directory is created outside the harbor path so that a new versión of harbor
  doesn't overwrite it.

* The permission are restricted to avoid unaothorized access

    `# chmod 0400 /registry_certs`

* The certificates are copied to the registry server into the newly created directory:

    `# scp registry.tanami.xyz.crt registry.tanami.xyz.key centos@172.20.2.20:/registry_certs`

* Harbor's configuration file is modified to enable the HTTPS connections, the affected
  arguments are:

    ```
    hostname = 172.20.2.20
    ui_url_protocol = https
    ssl_cert = /opt/harbor/certs/registry.tanami.xyz.crt
    ssl_cert_key = /opt/harbor/certs/registry.tanami.xyz.key
    ```
    
  **hostname** must contain the name or IP that we will use to access the registry
  with the docker client.  

  **ui_url_protocol** must be set to https for obvious reasons

  **ssl_cert** and **ss_cert_key** contain the paths to the public and private parts of
  the certificate.

* If this is the first setup of harbor we can just run the install.sh script.  If harbor
  was already running, we must run the prepare script and restart harbor:

    ```shell
    # ./prepare
    # docker-compose down
    # docker-compose up -d
    ```     

#### Docker client configuration

To enable the docker client to access the registry we must create a directory in
**/etc/docker/certs.d/** with the same name as the hostname we are going to use to connect
to the registry:

    `# mkdir /etc/docker/certs.d/172.20.2.20`

Then copy the public part of the CA certificate that signed the registry certificate, the
file must have the name **ca.crt**:

    `# scp CA.pem centos@ec2-18-203-65-237.eu-west-1.compute.amazonaws.com:/etc/docker/certs.d/172.20.2.20/ca.crt`

Now we can login to the registry and use it:

    `# docker login 172.20.2.20`
