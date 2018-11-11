## Harbor: docker image registry

https://goharbor.io/
https://github.com/goharbor/harbor/blob/master/README.md

### Installation

https://github.com/goharbor/harbor/blob/release-1.6.0/docs/installation_guide.md

This instructions are intended for the installing the 1.6.x version of harbor.


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

* Download the installer, in this case I will be using the offline installer from version
  1.6.0, this package includes all the neccesary components to have the registry up and
  running:
```
$ curl -o harbor-offline-installer-v1.6.0.tgz https://storage.googleapis.com/harbor-releases/release-1.6.0/harbor-offline-installer-v1.6.0.tgz  
```

* Extract the tar file:
```
$ tar xvf harbor-offline-installer-v1.6.0.tg
```

* Edit the harbor.cfg file according to the installation instructions

* Run the installer:

    `$ sudo ./install.sh`

### Building and starting harbor with terraform and ansible

To build the harbor project from scratch do the following:

1. Export the the variables **AWS_ACCESS_KEY_ID** and **AWS_SECRET_ACCESS_KEY** with the
  values of an AWS user with proper permissions

1. Go to **terraform/VPC** and run the following command to create the VPC where harbor
  will be installed:

        `# terraform apply`

1. Go to **terraform/NAT_gateway** and run the following command to create the NAT gateway for
  harbor's private subnet:

        `# terraform apply`

1. Go to **terraform/EC2** and run:

        `# terraform apply`

1. Go to **terraform/S3** and run:

        `# terraform apply`

1. Add the ssh key with permission to connect to the EC2 instances to the ssh agent:

        `# ssh-add Descargas/tale_toul-keypair-ireland.pem`
 
  Check it with:

        `# ssh-add -L`

1. Delete the entries for the hosts: _registry.taletoul.com_ and _172.20.2.20_ from the
   file **~/.ssh/known_hosts**.

1. Go to ansible and run the playbook to setup the bastion and registry hots, and to
  install harbor in the registry host.

        `# ansible-playbook --ask-vault-pass harbor.yml`


### Connecting to the registry

* From the bastion host.
    * Access the website.- To access the harbor website from the local workstation we will
      create a ssh tunnel, this is needed because the registry server is not directly
      accesible since it is housed in a private subnet.  The command to create the ssh
      tunnel is like:

    ```
    # ssh -i ~/Descargas/tale_toul-keypair-ireland.pem -fN -L 8080:172.20.2.20:80 \
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

* Via the reverse proxy.
    * To access the website just enter the URL
      [https://registry.taletoul.com](https://registry.taletoul.com) in the browser.

    * To connect with the docker client, create the directory
      /etc/docker/certs.d/registry.taletoul.com/ and copy the public part of the CA certificate that signed the registry certificate, the
      file must have the name **ca.crt**:

    ```shell
    # mkdir /etc/docker/certs.d/registry.taletoul.com/ 
    # cp ca.crt /etc/docker/certs.d/registry.taletoul.com/ 
    ```
    * Now we can login to the registry and use it:

    ```shell
    # docker login registry.taletoul.com
    ```


#### Testing the registry

To test that the registry is working properly we will upload an image:

* Pull an image from the bastion host:

    `$ sudo docker pull centos`

* Tag the image to point to the harbor registry:

    `$ sudo docker tag docker.io/centos 172.20.2.112/pro1/centos

* Push the image to the harbor registry:

    `$ sudo docker push 172.20.2.112/pro1/centos`

### Harbor's lifecycle

* To stop Harbor use the command:

`$ sudo docker-compose stop`

* To start Harbor use the command:

`$ sudo docker-compose start`

* To update Harbor's configuration, first stop Harbor; then update harbor.cfg; then run
  the *prepare* script to populate the configuration. Finally start Harbor: 

```shell
$ sudo docker-compose down -v
$ vim harbor.cfg
$ sudo ./prepare
$ sudo docker-compose up -d
```

* To remove Harbor's containers while keeping the image data and Harbor's database files on
  the file system:

`$ sudo docker-compose down -v`

* To remove Harbor's database and image data for a clean re-installation:

  Stop docker as explained before.

  * When using the filesystem storage backend:

    ```shell
    $ sudo rm -r /data/database
    $ sudo rm -r /data/registry
    ```

  * When using the s3 storage backend:

    Delete the contents of the S3 bucket, then the contents of the database:

    ```shell
    $ sudo rm -r /data/database
    ```

### S3 storage backend

By default harbor stores images on the local filesystem, while this is good for testing it
might not be the best option for a production system.  In this section we will see how to
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
the configuration that will be used is the one for the local filesystem as storage
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
manual reconfiguration of the config.yml and policy files.  In the next section we will
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

### Setting up a Reverse Proxy

[Official docker documentation](https://docs.docker.com/registry/recipes/apache/)

In this section we will setup a reverse proxy in the bastion host so that we can access
the registry from hosts that don't have direct access to the registry server.  In this
configuration we don't limit what hosts can access the registry in the reverse proxy.

The reverse proxy only allows HTTPS connections, between client and proxy and between
proxy and registry, in both connections the same server certificate is used.

We will use apache for the reverse proxy.

We need to create an x509 certificate, it will be valid for the name **registry.taletoul.com**
and for the IP **172.20.2.20**, which are the DNS of the registry service 
and the static private IP for the registry server.  During infrastructure
creation time an elastic IP will be assigned to the bastion host and a DNS record wil be
created linking that IP with the DNS name.

We create a virtual host for the registry which will respond to requests for the name
registry.taletoul.com, and the port 443; it will use the x509 certificates we created
before so it must use the same name we used in that certificate, and will have the SSL
reverse proxy option enabled (SSLProxyEngine on) so it can connect to a backend server
using a secure connection, the docker registry documentation states that the following
headers must be setup:

```
Header always set "Docker-Distribution-Api-Version" "registry/2.0"
Header onsuccess set "Docker-Distribution-Api-Version" "registry/2.0"
RequestHeader set X-Forwarded-Proto "https"
```

The requests proxied from the bastion to the registry host will keep the original
Host header, not a new one with the name of the backend server (ProxyPreserveHost on) and
the reverse proxy will not enforce that the name of the backend server matches that of the
certificate it uses for the connection.

```
SSLProxyCheckPeerCN off
SSLProxyCheckPeerName off
```

All requests received by this virtual host are sent over to the backend:

```
ProxyPass        / https://{{ registry_IP }}/
ProxyPassReverse / https://{{ registry_IP }}/
```

### Harbor CLI

https://github.com/int32bit/python-harborclient

This is a command line tool that allows us interact with the registry without the need to
connect to the web ui.


#### Installation

The recommended installation method consists of creating a docker image from the sources.

Start by cloning the github repository:

```shell
# git clone https://github.com/int32bit/python-harborclient.git
```

Then run the build process:


```shell
# cd python-harborclient
# sudo docket build -t registry.taletoul.com/harborclient .
```

To check that the cli works properly use the command:

```shell
# docker run -ti registry.taletoul.com/harborclient harbor help
```

If the previous command was successful we can go ahead and contact the registry server,
the following command is quite long but later we will see how to make it shorter.


```shell
# docker run --rm -ti -e HARBOR_USERNAME="admin" -e HARBOR_PASSWORD="XXX" \
  -e HARBOR_URL="https://registry.taletoul.com" -e HARBOR_PROJECT=1 \
  -v /etc/docker/certs.d/registry.taletoul.com/ca.crt:/ca.crt:Z \
  registry.taletoul.com/harborclient harbor --os-cacert /ca.crt info
+--------------------------------+-----------------------+
| Property                       | Value                 |
+--------------------------------+-----------------------+
| admiral_endpoint               | NA                    |
| auth_mode                      | db_auth               |
| disk_free                      | 3897479168            |
| disk_total                     | 8578400256            |
| harbor_version                 | v1.6.1-98bcac6c       |
| has_ca_root                    | False                 |
| next_scan_all                  | 0                     |
| project_creation_restriction   | adminonly             |
| read_only                      | False                 |
| registry_storage_provider_name | filesystem            |
| registry_url                   | registry.taletoul.com |
| self_registration              | False                 |
| with_admiral                   | False                 |
| with_chartmuseum               | False                 |
| with_clair                     | False                 |
| with_notary                    | False                 |
+--------------------------------+-----------------------+
```

In the previous command we define the user and password to connect to the registry:

`-e HARBOR_USERNAME="admin" -e HARBOR_PASSWORD="XXX"`

Then the registry URL:

`-e HARBOR_URL="https://registry.taletoul.com"`

Then the project, this is mandatory although we are running a command unrelated to any
project, project 1 doesn't even exist in the registry:

`-e HARBOR_PROJECT=1`

Then we add the certificate to verify the registry certificate, otherwise we get a message
saying that the registry certificate could not be verified.  Instead of this we can use
the option --insecure to avoid the certificate verification. The **Z** at the end is
needed to avoid problems with SELinux:

`-v /etc/docker/certs.d/registry.taletoul.com/ca.crt:/ca.crt:Z`

Finally we specify the image to use, and the CLI command:

`registry.taletoul.com/harborclient harbor --os-cacert /ca.crt info`

This command uses the option **--os-cacert /ca.crt** to specify the CA certificate to
validate the registry's certificate, and runs the command **info** to get information
about the remote registry.

To reduce the typing we can create an alias with the commong arguments:

```shell
# alias harbor='sudo docker run --rm -ti -e HARBOR_USERNAME="admin" -e
HARBOR_PASSWORD="NaHCO3" -e HARBOR_URL="https://registry.taletoul.com" \
-e HARBOR_PROJECT=1 -v /etc/docker/certs.d/registry.taletoul.com/ca.crt:/ca.crt:Z \
registry.taletoul.com/harborclient harbor --os-cacert /ca.crt'
```

And then use a simpler command like:

`# harbor info`

#### Limitations

The harbor cli cannot do all of the operations that the admin can do through the web ui,
for example it cannot add members to a project.

### Role Based Access Control

[Documentation Reference](https://github.com/goharbor/harbor/blob/master/docs/user_guide.md#role-based-access-controlrbac)
