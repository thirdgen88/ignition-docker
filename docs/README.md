# Supported tags and respective `Dockerfile` links

* [`8.0.2`, `8.0`, `latest`  (8.0/Dockerfile)](https://github.com/thirdgen88/ignition-docker/blob/master/8.0/Dockerfile)
* [`8.0.2-edge`, `8.0-edge`, `latest-edge`  (8.0/Dockerfile)](https://github.com/thirdgen88/ignition-docker/blob/master/8.0/Dockerfile)
* [`7.9.12`, `7.9`, (7.9/Dockerfile)](https://github.com/thirdgen88/ignition-docker/blob/master/7.9/Dockerfile)
* [`7.9.12-edge`, `7.9-edge`, `latest-edge` (7.9/Dockerfile)](https://github.com/thirdgen88/ignition-docker/blob/master/7.9/Dockerfile)
* [`7.8.5`, `7.8` (7.8/Dockerfile)](https://github.com/thirdgen88/ignition-docker/blob/master/7.8/Dockerfile)
* [`7.7.10`, `7.7` (7.7/Dockerfile)](https://github.com/thirdgen88/ignition-docker/blob/master/7.7/Dockerfile)

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
The normal Ignition installation process is extremely quick and painless.  This repository explores how to deploy Ignition under Docker, which aims to really accelerate and expand development efforts.  If you wish to explore other deployment scenarios, take a look at the [ignition-examples](https://github.com/thirdgen88/ignition-examples) repo for multi-container Docker Compose examples.

## Start an `ignition` gateway instance
You can start an instance of Ignition in its own container as below:

    $ docker run -p 8088:8088 --name my-ignition -e GATEWAY_ADMIN_PASSWORD=password -d kcollins/ignition:tag

... where `my-ignition` is the container name you'd like to refer to this instance later with, the publish ports `8088:8088` describes the first port `8088` on the host that will forward to the second port `8088` on the container, and `tag` is the tag specifying the version of Ignition that you'd like to provision.  See the list above for available tags.  _NOTE: GATEWAY_ADMIN_PASSWORD is a new field for Ignition 8.0 and the gateway commissioning process.  See the table below in container customization for more information_

## Start an `ignition-edge` gateway instance
If you want to run the Ignition Edge variant, simply use the `-edge` suffix on the desired tag:

    $ docker run -p 8088:8088 --name my-ignition-edge -e GATEWAY_ADMIN_PASSWORD=password -d kcollins/ignition:tag-edge

The `tag` would be replaced with the version, so your resultant image name might be something like `kcollins/ignition:7.9.7-edge`.

## Restore an existing gateway backup on container startup
You can now use this image to restore a gateway backup on first-start of the container.  Bind-mount the gateway backup to `/restore.gwbk` and the image will take care of the rest:

    $ docker run -p 8088:8088 --name my-ignition -v /path/to/gateway.gwbk:/restore.gwbk -d kcollins/ignition:tag

Specify the full path to your gateway backup file in the `-v` bind-mount argument.  The container will start up, restore the backup, and then restart.

## Using `docker-compose`

For examples and guidance on using the Ignition Docker Image alongside other services with Docker Compose, take a look at the [ignition-examples](https://github.com/thirdgen88/ignition-examples) repo on GitHub.

## Container Customization

_New with 7.9.10 Docker image as of 2018-12-29!_
_New 8.0.x options added on 2019-04-27!_

There are additional ways to customize the configuration of the Ignition container via environment variables.  

_Table 1 - General Configurability_

For Ignition 8.x, you _must_ specify either `GATEWAY_ADMIN_PASSWORD` or `GATEWAY_RANDOM_ADMIN_PASSWORD` on container launch.  This will only affect the initial credentials for the gateway.  When restoring from a backup, the admin credentials specified through these environment variables will be set on initial restore, overriding the existing credentials from the gateway backup file.

Variable                           | Description                                                            |
---------------------------------- | ---------------------------------------------------------------------- |
`GATEWAY_SYSTEM_NAME`              | Set this to a string to drive the Ignition Gateway Name.
`GATEWAY_USESSL`                   | Set to `true` to enforce connections to the gateway use SSL on port `8043`.
`GATEWAY_NETWORK_AUTOACCEPT_DELAY` | Number of _seconds_ to auto accept new certificates for incoming gateway network connections.
`GATEWAY_INIT_MEMORY`              | Initial Java Heap Size
`GATEWAY_MAX_MEMORY`               | Maximum Java Heap Size
`GATEWAY_ADMIN_USERNAME`           | Gateway Admin Username (defaults to `admin`) _only for > 8.0.0_
`GATEWAY_ADMIN_PASSWORD`           | Gateway Admin Password _only for > 8.0.0_
`GATEWAY_RANDOM_ADMIN_PASSWORD`    | Set to `1` to generate random Gateway Admin Password _only for > 8.0.0_
`GATEWAY_HTTP_PORT`                | Gateway HTTP Port (defaults to `8088`) _only for > 8.0.0_
`GATEWAY_HTTPS_PORT`                | Gateway HTTP Port (defaults to `8043`) _only for > 8.0.0_
`GATEWAY_MODULE_RELINK`            | Set to `true` to allow replacement of built-in modules

In the table below, replace `n` with a numeric index, starting at `0`, for each connection definition.  You can define the `HOST` variable and omit the others to use the defaults.  Defaults listed with _gw_ use the Ignition gateway defaults, others use the defaults customized by the Ignition Docker entrypoint script.

_Table 2 - Gateway Network Provisioning_

Variable                       | Default | Description                                                          |
------------------------------ | ------- | -------------------------------------------------------------------- |
`GATEWAY_NETWORK_n_HOST`       |         | Define host or IP to initiate outbound gateway network connection.
`GATEWAY_NETWORK_n_PORT`       | `8060`  | Define port for connection (`8060` is default for SSL, `8088` for non-SSL)
`GATEWAY_NETWORK_n_PINGRATE`   | _gw_    | Frequency in _milliseconds_ for remote machine pings
`GATEWAY_NETWORK_n_ENABLED`    | _gw_    | Set to `false` to disable connection after creation
`GATEWAY_NETWORK_n_ENABLESSL`  | `true`  | Set to `false` to use unencrypted connection.

Declaring automatically provisioned gateway network connections will require approval in the remote gateway configuration, unless it is being started at the same time with a nominal `GATEWAY_NETWORK_AUTOACCEPT_DELAY` setting.  

Creating an Ignition Gateway with the gateway name `spoke1` and a single outbound gateway connection to `10.11.12.13` can be done as per the example below:

    $ docker run -p 8088:8088 --name my-ignition -e GATEWAY_SYSTEM_NAME=spoke1 -e GATEWAY_NETWORK_0_HOST=10.11.12.13 -d kcollins/ignition:7.9.10

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
        -e GATEWAY_ADMIN_PASSWORD=password \
        -d kcollins/ignition:tag

This will start a new container named `my-ignition` that utilizes the `ignition.conf` file located at `/path/to/custom/ignition.conf` on the host computer.  Note that linking the file into the container in this way (versus mounting a containing folder) may cause unexpected behavior in editing this file on the host with the container running.  Since this file is only read on startup of the container, there shouldn't be any real issues with this methodology (since an edit to this file will necessitate restarting the container). 

# Features

## How to persist Gateway data

With no additional options for volume management specified to the container, all of the information related to the Gateway state is contained wholly inside the storage layers of the container itself.  If you need to change the container configuration in some way (requiring a new container, for example), this puts your data in a precarious position.  While this may be acceptable for short-term dev scenarios, longer term solutions are better solved by utilizing a data volume to house state-data of the container.  See the Docker Reference about how to [use Volumes](https://docs.docker.com/engine/admin/volumes/volumes/) for more information.

Getting a volume created is as simple as using a `-v` flag when starting your container:

    $ docker run -p 8088:8088 -v my-ignition-data:/var/lib/ignition/data \
        -e GATEWAY_ADMIN_PASSWORD=password \
        -d kcollins/ignition:tag

This will start a new container and create (or attach, if it already exists) a data volume called `my-ignition-data` against `/var/lib/ignition/data` within the container, which is where Ignition stores all of the runtime data for the Gateway.  Removing the container now doesn't affect the persisted Gateway data and allows you to create and start another container (perhaps in a stack with other components like a database) and pick up where you left off.

_NOTE_: If you need to integrate third-party modules, see below.  If you need to integrate custom python files directly into `/var/lib/ignition/user-lib/pylib`, you can bind-mount a directory under there.  

## How to integrate third party modules

_New with latest 7.9.11 and 8.0.2 images as of 2019-06-15!_

To add external or third-party modules to your gateway, place your modules in a folder on the Docker host, and bind-mount the folder into `/modules` within the container.  Modules will be linked from here into the active location at `/var/lib/ignition/user-lib/modules`.  Additionally, module certificates and licenses will be automatically accepted within the Gateway so that they start up automatically with no additional user intervention required.

    $ ls /path/to/my/modules
    
    MQTT-Transmission-signed.modl
    
    $ docker run -p 8088:8088 -v my-ignition-data:/var/lib/ignition/data \
        -v /path/to/my/modules:/modules \
        -e GATEWAY_ADMIN_PASSWORD=password \
        -d kcollins/ignition:8.0.2

Note that if you wish to remove a third-party module from your gateway, you will need to remove it from `/path/to/my/modules` after removing it through the Gateway Webpage.  If you do not remove the module from the bind-mount path, it will be relinked the next time the gateway restarts.

If you wish to overwrite a built-in module with one from the bind-mount path, declare an environment variable `GATEWAY_MODULE_RELINK=true`.  This will cause the built-in module to be removed and the new one linked in its place prior to gateway startup.

## Upgrading a volume-persisted Ignition Container

_New with latest 7.9.11 and 8.0.2 images as of 2019-06-28!_

Upgrading Ignition versions is now supported!  If you have your container bound with a named volume to `/var/lib/ignition/data` (as described above), upgrading to a newer container is now just a matter of stopping/removing the existing container, and starting a new container against a newer image.  Just make sure to connect the same volume to the new container and the entrypoint script will handle running the upgrader and conduct any additional provisioning actions automatically.

Note:  If you attempt to start a container bound to a newer-version image, an error will be produced and the container will not start.  Upgrades are supported, and downgrades are disallowed (as expected).

## How to set Gateway Timezone

To set the gateway timezone, simply add a `TZ` environment variable to the container:

    $ docker run -p 8088:8088 -v my-ignition-data:/var/lib/ignition/data \
        -e GATEWAY_ADMIN_PASSWORD=password \
        -e TZ="America/Chicago"
        -d kcollins/ignition:latest

Once the gateway starts, you should be able to see the designated local time in the _Environment_ section of the Gateway Status Overview Webpage.

# License

For licensing information, consult the following links:

* OpenJDK Licensing (base image for 7.9 and below) - http://openjdk.java.net/legal/gplv2+ce.html
* Ignition License - https://inductiveautomation.com/ignition/license

As with all Docker images, these likely also contain other software which may be under other licenses (such as Bash, etc from the base distribution, along with any direct or indirect dependencies of the primary software being contained).  The use of third-party modules requires reviewing the related licensing information, as module EULAs are accepted automatically on the user's behalf.

As for any pre-built image usage, it is the image user's responsibility to ensure that any use of this image complies with any relevant licenses for all software contained within.