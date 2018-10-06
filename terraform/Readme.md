## AWS based Infrastructure with terraform

https://www.terraform.io

### Terraform installation

The installation of terraform is as simple as downloading a zip compiled binary
package for your operating system and architecture from:

`https://www.terraform.io/downloads.html`

Then unzip the file:

```shell
 # unzip terraform_0.11.8_linux_amd64.zip 
Archive:  terraform_0.11.8_linux_amd64.zip
  inflating: terraform
```

Place the binary somewhere in your path:

`# cp terraform /usr/local/bin`

Check that it is working:

`# terraform --version`
