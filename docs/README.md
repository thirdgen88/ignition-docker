# Supported tags and respective `Dockerfile` links

* [`7.9.4`, `7.9`, `latest` (7.9/Dockerfile)](https://github.com/thirdgen88/ignition-docker/blob/master/7.9/Dockerfile)

# Quick Reference

* **Where to file issues**:
https://github.com/thirdgen88/ignition-docker/issues

* **Maintained by**:
Kevin Collins (independent Ignition enthusiast)

* **Supported architectures**:
`amd64`

* **Source of this description:**
https://github.com/thirdgen88/ignition-docker/tree/master/docs ([History](https://github.com/thirdgen88/ignition-docker/commits/master/docs))

# What is Ignition?

Ignition is a SCADA software platform made by [Inductive Automation](http://inductiveautomation.com).  This repository, intended for development use on the Ignition platform, is not sponsored by Inductive Automation, please visit their website for more information.

For more information on Inductive Automation and the Ignition Platform, please visit [www.inductiveautomation.com](https://www.inductiveautomation.com).

![Ignition Logo Dark](https://inductiveautomation.com/static/images/logo_ignition_lg.png)

# How to use this image
The normal Ignition installation process is extremely quick and painless.  This repository explores how to deploy Ignition under Docker, which aims to really accelerate and expand development efforts.  Over time, additional deployment scenarios (with database linkages and multi-gateway environments) will be detailed here, so stay tuned.

## Start an `ignition` gateway instance
You can start an instance of Ignition in its own container as below:

    $ docker run -p 8088:8088 --name my-ignition -d kcollins/ignition:tag

... where `my-ignition` is the container name you'd like to refer to this instance later with, the publish ports `8088:8088` describes the first port `8088` on the host that will forward to the second port `8088` on the container, and `tag` is the tag specifying the version of Ignition that you'd like to provision.  See the list above for available tags.

## Connect to your Ignition instance
This image exposes the standard gateway ports (`8088`, `8043`), so if you utilize the `run` sequence above, you'll be able to connect to your instance against your host computer's port `8088`.  If you wish to utilize the SSL connection, simply publish `8043` as well.

## Container shell access and viewing Ignition Gateway logs

The `docker exec` command allows you to run commands inside of a Docker container.  The following command will launch a _bash_ shell inside your `ignition` container:

    $ docker exec -it my-ignition bash
    
The Ignition Gateway Wrapper log is available through the Docker container's log:

    $ docker logs my-ignition

## Using a custom gateway configuration file

The `ignition.conf` file can be used to customize the gateway launch parameters and other aspects of its configuration (such as Java heap memory allocation, garbage collector configuration, and developer mode settings).  If you wish to utilize a custom `ignition.conf` file, you can create a copy of that file in a directory on your host computer and then mount that file as `/var/lib/ignition/data/ignition.conf` inside the `ignition` container.

If `/path/to/custom/ignition.conf` is the path and filename of your custom Ignition gateway configuration file, you can start the `ignition` container with the following command:

    $ docker run --name my-ignition \
        -v /path/to/custom/ignition.conf:/var/lib/ignition/data/ignition.conf \
        -d kcollins/ignition:tag

This will start a new container named `my-ignition` that utilizes the `ignition.conf` file located at `/path/to/custom/ignition.conf` on the host computer.  Note that linking the file into the container in this way (versus mounting a containing folder) may cause unexpected behavior in editing this file on the host with the container running.  Since this file is only read on startup of the container, there shouldn't be any real issues with this methodology (since an edit to this file will necessitate restarting the container). 

# Caveats

## How to persist Gateway data

With no additional options for volume management specified to the container, all of the information related to the Gateway state is contained wholly inside the storage layers of the container itself.  If you need to change the container configuration in some way (requiring a new container, for example), this puts your data in a precarious position.  While this may be acceptable for short-term dev scenarios, longer term solutions are better solved by utilizing a data volume to house state-data of the container.  See the Docker Reference about how to [use Volumes](https://docs.docker.com/engine/admin/volumes/volumes/) for more information.

Getting a volume created is as simple as using a `-v` flag when starting your container:

    $ docker run -p 8088:8088 -v my-ignition-data:/var/lib/ignition \
        -d kcollins/ignition:tag

This will start a new container and create (or attach, if it already exists) a data volume called `my-ignition-data` against `/var/lib/ignition` within the container, which is where Ignition stores all of the runtime data for the Gateway.  Removing the container now doesn't affect the persisted Gateway data and allows you to create and start another container (perhaps in a stack with other components like a database) and pick up where you left off.

# License

For licensing information, consult the following links:

* OpenJDK Licensing (base image) - http://openjdk.java.net/legal/gplv2+ce.html
* Ignition License - https://inductiveautomation.com/ignition/license

As with all Docker images, these likely also contain other software which may be under other licenses (such as Bash, etc from the base distribution, along with any direct or indirect dependencies of the primary software being contained).

As for any pre-built image usage, it is the image user's responsibility to ensure that any use of this image complies with any relevant licenses for all software contained within.