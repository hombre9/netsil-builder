## Description
The *netsil-builder* has two functions. 

1. Provisions DCOS from a base CoreOS image. 
2. Provisions Netsil AOC on top of the DCOS system provisioned in *1*.

The build process for Netsil AOC takes one external input: an `apps` directory with mustache templates and build-time variables. 
This `apps` directory essentially defines the version of Netsil AOC to be built.

## Usage
### Building the DCOS or Netsil AOC machine image
Use the `bake.sh` script to build the DCOS or Netsil AOC machine image. 
For the Netsil AOC build, set the `APPS_DIR` environment variable as the full path of the `apps` directory on your filesystem.
To specify whether to build DCOS or Netsil AOC, set the `BUILD_OUTPUT` environment variable as `base-dcos` or `netsil-aoc`, respectively.

Examples of both build invocations are given below.

**DCOS**
```
BUILD_TYPE=amazon-ebs BUILD_OUTPUT=base-dcos ./netsil-builder/bake.sh
```

**Netsil AOC**
```
BUILD_TYPE=amazon-ebs BUILD_OUTPUT=netsil-aoc BASE_DCOS_IMAGE=ami-57f25337 APPS_DIR=/home/dev/AOC/apps ./netsil-builder/bake.sh
```
### Secrets
In order to support AWS, googlecompute, and azure-arm builds, you may have to set some secret keys and credentials files. These are detailed below:

**SSH Keys**
* Put a private and public SSH key, named `id_rsa` and `id_rsa.pub` in your secrets directory.

**Docker auth**
* This is only necessary if you're building Netsil AOC from non-production docker images. If so, provide a file named `netsil-dev-docker-auth.json` in your secrets directory that has your docker credentials. This is usually found in `~/.docker/config.json` after logging in with `docker login`

**AWS**
* You will need the `aws-cli` tool installed, as well as AWS credentials configured in the *default* profile from the host where you're running these build scripts.

**Googlecompute**
* Provide an account file named `account.json` in your secrets directory. See the [packer docs](https://www.packer.io/docs/builders/googlecompute.html) for details.

**Azure-arm**
* Provide the password or secret for your "service principal" in a file called `azure-client-secret` in your secrets directory

### Templating
A `template.sh` script is provided if you only wish to template the app definitions. This will mostly be used by Netsil internally.

## Technical Details

The Packer build process utilizes QEMU, Ansible, and Packer within a Docker container. The container runs a script which begins the Packer build. A CoreOS QEMU image is brought online and Packer uses Ansible to provision DCOS, create a new image, and finally converts the image to the various formats. Here are the steps involved.

1. A Docker image is built with QEMU, Ansible, and Packer.
2. A Docker container will prepare the environment and launch the Packer build (`start.sh`).
3. Packer uses the QEMU builder to launch a VM with a generated user_data file containing the SSH public key.
4. Packer then provisions the VM with Python and DCOS using Ansible.
5. The VM image is saved as a qcow2 image file.
6. A Packer post-processor launches an Ansible playbook that converts the qcow2 image to vdi, vhd, and vmdk images.
7. The image output directory is then renamed as date and timestamp.

## Requirements

* Linux host with KVM (Intel or AMD) support and able run QEMU.
* Recent version of Docker installed and running: https://docs.docker.com/engine/installation/
* CoreOS QEMU image: https://stable.release.core-os.net/amd64-usr/current/coreos_production_qemu_image.img.bz2
* Private and public SSH keys.

## Configuration

### SSH Keys

Private and public SSH keys will need to be present in order for Packer to build an image. They are also necessary for accessing the final images.

    ssh-keygen -N "" -f /path/to/secrets/id_rsa

The generated keys should be stored on the host system and mounted within the Docker container for use by Packer.

    docker run -v /path/to/secrets:/opt/secrets ...

The path within the container can be adjusted by changing the corresonding environment variables.

### CoreOS QEMU Image

The CoreOS QEMU image must be downloaded, decompressed, and placed into the images directory. This image will be read by Packer and used for storing the new images.

    cd /path/to/images
    curl -OL https://stable.release.core-os.net/amd64-usr/current/coreos_production_qemu_image.img.bz2
    bzip2 -d coreos_production_qemu_image.img.bz2

The `/path/to/images` directory will be mounted as a volume inside the container. Packer will read the CoreOS QEMU image from this directory and write new images to a subdirectory within this directory. This prevents large files from being written to the Docker container image itself.

### CoreOS Image Checksum

The Packer `packer-config.json` requires the MD5 checksum of the CoreOS QEMU image. Open the `packer-config.json` file and update the `checksum` value with the proper checksum:

    "checksum": "1a094aa25f912f6cbe5f92f7d1cd381e",

### Packer Build Types

By default, only local images (qcow2, vhd, vmdk, etc.) using QEMU will be built. If the `AWS_ACCESS_KEY` and `AWS_SECRET_KEY` environment variables are included in the Docker `run` command, then an AWS AMI will also be built.

Either QEMU **or** AWS images can be explicitly built.

    docker run -e BUILD_TYPE=qemu ...

To build only an AMI:

    docker run -e AWS_ACCESS_KEY=1234 -e AWS_SECRET_KEY=abcxyz -e BUILD_TYPE=amazon-ebs ...

## Usage

    $ docker build -t netsil-builder .
    $ docker run --privileged -ti \
          -v /path/to/images:/opt/images \
          -v /path/to/secrets:/opt/secrets \
          -e SSH_PUBLIC_KEY=/opt/secrets/id_rsa.pub \
          -e SSH_PRIVATE_KEY=/opt/secrets/id_rsa \
          -e IMAGE_PATH=/opt/images \
          -e IMAGE_NAME=base-dcos \
          -e AWS_ACCESS_KEY="ACCESSKEY" \
          -e AWS_SECRET_KEY="SECRETKEY" \
          netsil-builder

## Project Files

* **ansible/convert-images.yml** - Uses `qemu-img` to convert the created qcow2 image to vdi, vhd, and vmdk images.
* **ansible/dcos-bootstrap.yml** - Bootstraps the CoreOS image with DCOS master and slave roles.
* **ansible/roles** - Various Ansible roles used by the available playbooks.
* **Dockerfile** - Dockerfile necessary to build an Ubuntu image with QEMU, Ansible, and Packer.
* **packer-config.json** - Packer config file that launches the VM, bootstraps the image, and saves the image.
* **start.sh** - The script that launches Packer build process.

## Docker Variables

* **AWS_ACCESS_KEY** - AWS account access key.
* **AWS_SECRET_KEY** - AWS account secret key.
* **AWS_REGION** - AWS region for the build. Default: `us-west-2`
* **BUILD_TYPE** - The Packer build type can be either `amazon-ebs` or `qemu`.
* **IMAGE_NAME** - The name of the images without any extension. Default: `coreso-stable`
* **IMAGE_PATH** - The path inside the container where the images will be saved. This *should* map to a location on the host system. Default: `/opt/images`
* **SSH_PRIVATE_KEY** - The SSH private key used to connect to the CoreOS VM instance by Packer and Ansible. This will be necessary to save as it provides SSH access to the image VM.
* **SSH_PUBLIC_KEY** - The SSH public key that will be injected into the CoreOS image for provisioning and future access to the VM.

## Miscellaneous Notes

A udev rules file is created during the user_data injection that disables predictable network interface naming. This will result in VMs using **eth0** instead of **en0s0** and other name variations across different platforms.
