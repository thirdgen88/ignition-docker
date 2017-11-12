# Supported tags and respective `Dockerfile` links

* [`7.9.4`, `7.9` (7.9/Dockerfile)]()

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

![Ignition Logo Dark](https://inductiveautomation.com/static/images/logo_ignition_lg.png)

The normal Ignition installation process is extremely quick and painless.  This repository explores how to deploy Ignition under Docker, which aims to really accelerate and expand development efforts.  Over time, additional deployment scenarios (with database linkages and multi-gateway environments) will be detailed here, so stay tuned.

# How to use this image

## Start an `ignition` gateway instance
You can start an instance of Ignition in its own container as below:

    $ docker run -p 8088:8088 --name my-ignition -d kcollins/ignition:tag

... where `my-ignition` is the container name you'd like to refer to this instance later with, the publish ports `8088:8088` describes the first port `8088` on the host that will forward to the second port `8088` on the container, and `tag` is the tag specifying the version of Ignition that you'd like to provision.  See the list above for available tags.

## Connect to your Ignition instance
This image exposes the standard gateway ports (`8088`, `8043`), so if you utilize the `run` sequence above, you'll be able to connect to your instance against your host computer's port `8088`.  If you wish to utilize the SSL connection, simply publish `8043` as well.
