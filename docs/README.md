## Supported tags and respective `Dockerfile` links

* [`8.0.15`, `8.0`, `latest`  (8.0/Dockerfile)](https://github.com/thirdgen88/ignition-docker/blob/master/8.0/Dockerfile)
* [`nightly`, `nightly-edge` (8.0/Dockerfile)](https://github.com/thirdgen88/ignition-docker/blob/nightly/8.0/Dockerfile)
* [`7.9.14`, `7.9`, (7.9/Dockerfile)](https://github.com/thirdgen88/ignition-docker/blob/master/7.9/Dockerfile)
* [`7.9.14-edge`, `7.9-edge` (7.9/Dockerfile)](https://github.com/thirdgen88/ignition-docker/blob/master/7.9/Dockerfile)

## Quick Reference

* **Where to file issues**: https://github.com/thirdgen88/ignition-docker/issues

* **Maintained by**:
Kevin Collins (independent Ignition enthusiast)

* **Supported architectures**:
`amd64`, `armhf` ([More Info](#Multi-Architecture%20Builds))

* **Source of this description:** https://github.com/thirdgen88/ignition-docker/tree/master/docs ([History](https://github.com/thirdgen88/ignition-docker/commits/master/docs))

<!-- markdownlint-disable MD026 -->
## What is Ignition?
<!-- markdownlint-enable MD037 -->

![Ignition Logo](https://inductiveautomation.com/static/images/logo_ignition_lg.png)

Ignition is a SCADA software platform made by [Inductive Automation](http://inductiveautomation.com).  This repository, intended for development use on the Ignition platform, is not sponsored by Inductive Automation, please visit their website for more information.

For more information on Inductive Automation and the Ignition Platform, please visit [www.inductiveautomation.com](https://www.inductiveautomation.com).

## How to use this image

The normal Ignition installation process is extremely quick and painless.  This repository explores how to deploy Ignition under Docker, which aims to really accelerate and expand development efforts.  If you wish to explore other deployment scenarios, take a look at the [ignition-examples](https://github.com/thirdgen88/ignition-examples) repo for multi-container Docker Compose examples.

## Start an `Ignition` gateway instance

You can start an instance of Ignition in its own container as below:

    $ docker run -p 8088:8088 --name my-ignition -e GATEWAY_ADMIN_PASSWORD=password -e IGNITION_EDITION=full -d kcollins/ignition:tag

... where `my-ignition` is the container name you'd like to refer to this instance later with, the publish ports `8088:8088` describes the first port `8088` on the host that will forward to the second port `8088` on the container, and `tag` is the tag specifying the version of Ignition that you'd like to provision.  See the list above for current image tags.  _NOTE: GATEWAY_ADMIN_PASSWORD is a new field for Ignition 8.0 and the gateway commissioning process.  See the table below in container customization for more information_

## Start an `Ignition Edge` gateway instance

_New/Updated with Ignition 8.0.14 as of 2020-06-24_

If you want to run the Ignition Edge variant, simply supply `IGNITION_EDITION=edge` as an environment variable against the same image:

    $ docker run -p 8088:8088 --name my-ignition-edge -e GATEWAY_ADMIN_PASSWORD=password -e IGNITION_EDITION=edge -d kcollins/ignition:8.0.14

For older versions (prior to 8.0.14), you can specify the image format with a `-edge` suffix, e.g. `kcollins/ignition:8.0.13-edge`

## Start an `Ignition Maker Edition` gateway instance

_New with Ignition 8.0.14 as of 2020-06-24_

If you want to run the Ignition Maker Edition variant, supply some additional environment variables with the container launch.  You'll need to acquire a _Maker Edition_ license from Inductive Automation to use this image variant.  More information [here](https://inductiveautomation.com/ignition/maker-edition).

* `IGNITION_EDITION=maker` - Specifies Maker Edition
* `IGNITION_LICENSE_KEY=ABCD_1234` - Supply your license key
* `IGNITION_ACTIVATION_TOKEN=xxxxxxx` - Supply your activation token

Run the container with these extra environment variables:

    $ docker run -p 8088:8088 --name my-ignition-maker -e GATEWAY_ADMIN_PASSWORD=password \
        -e IGNITION_EDITION=maker \ 
        -e IGNITION_LICENSE_KEY=ABCD_1234 \
        -e IGNITION_ACTIVATION_TOKEN=asdfghjkl \
        -d kcollins/ignition:latest

You can also place the activation token and/or license key in a file that is either integrated with Docker Secrets (via Docker Compose or Swarm) or simply bind-mounted into the container.  Appending `_FILE` to the environment variables causes the value to be read in from the declared file location.  If we have a file containing our activation token named `activation-token`, we can run the container like below:

    $ docker run -p 8088:8088 --name my-ignition-maker -e GATEWAY_ADMIN_PASSWORD=password \
        -e IGNITION_EDITION=maker \
        -e IGNITION_LICENSE_KEY=ABCD_1234 \
        -v /path/to/activation-token:/activation-token \
        -e IGNITION_ACTIVATION_TOKEN_FILE=/activation-token \
        -d kcollins/ignition:latest

Keep in mind that you should consider [preserving your gateway data](#How-to-persist-Gateway-data) in a volume as well.  Additionally, all [container customizations](#Container-Customization) are supported in all editions/variants, including Maker Edition.

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

<!-- markdownlint-disable MD036 -->
### _Table 1 - General Configurability_
<!-- markdownlint-enable MD036 -->

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
`GATEWAY_HTTPS_PORT`               | Gateway HTTP Port (defaults to `8043`) _only for > 8.0.0_
`GATEWAY_MODULE_RELINK`            | Set to `true` to allow replacement of built-in modules
`GATEWAY_JDBC_RELINK`              | Set to `true` to allow replacement of built-in JDBC drivers
`GATEWAY_RESTORE_DISABLED`         | Set to `1` to perform gateway restore in disabled mode.
`IGNITION_STARTUP_DELAY`           | Defaults to `60`, increase to allow for more time for initial gateway startup
`IGNITION_COMMISSIONING_DELAY`     | Defaults to `30`, increase to allow for more time for initial commisioning servlet to become available
`IGNITION_EDITION`                 | Defaults to `FULL`, choose `FULL`, `EDGE`, or `MAKER` to set the Ignition Gateway type on initial launch
`IGNITION_ACTIVATION_TOKEN`        | Token for automated gateway licensing/activation. **Required for _Maker_ edition.**
`IGNITION_LICENSE_KEY`             | License Key for automated gateway licensing/activation. **Required for _Maker_ edition.**

In the table below, replace `n` with a numeric index, starting at `0`, for each connection definition.  You can define the `HOST` variable and omit the others to use the defaults.  Defaults listed with _gw_ use the Ignition gateway defaults, others use the defaults customized by the Ignition Docker entrypoint script.

<!-- markdownlint-disable MD036 -->
### _Table 2 - Gateway Network Provisioning_
<!-- markdownlint-enable MD036 -->

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

<!-- markdownlint-disable MD036 -->
### _Table 3 - Logging Configurability_
<!-- markdownlint-enable MD036 -->

The Java Wrapper that Ignition uses has some specific configuration variables for logging that can be useful to adjust.  See the [Logging Configuration Properties](https://wrapper.tanukisoftware.com/doc/english/props-logging.html) documentation for the wrapper for more detailed information on some of these settings.

If you need to ensure that all writes to the console log are available immediately after being produced, you will want to set `WRAPPER_CONSOLE_FLUSH` to `true`.  The default behavior is for the wrapper to utilize a buffered output to stdout/stderr and can result in some minor delays in log output.

Variable                       | Default | Description                                                          |
------------------------------ | ------- | -------------------------------------------------------------------- |
`WRAPPER_CONSOLE_FLUSH`        | _not overridden_  | Set to `true` to flush log buffer after each line. [More Info](https://wrapper.tanukisoftware.com/doc/english/prop-console-flush.html)
`WRAPPER_CONSOLE_LOGLEVEL`     | _not overridden_ | Customize the log level for console output [More Info](https://wrapper.tanukisoftware.com/doc/english/prop-console-loglevel.html)
`WRAPPER_CONSOLE_FORMAT`       | _not overridden_    | Customize the format for console output [More Info](https://wrapper.tanukisoftware.com/doc/english/prop-console-format.html)
`WRAPPER_SYSLOG_LOGLEVEL`      | _not overridden_ | Set the log level for syslog output [More Info](https://wrapper.tanukisoftware.com/doc/english/prop-syslog-loglevel.html)
`WRAPPER_SYSLOG_LOCAL_HOST`    | _not overridden_ | Set the local host name reported in the remote syslog packets [More Info](https://wrapper.tanukisoftware.com/doc/english/prop-syslog-local-host.html)
`WRAPPER_SYSLOG_REMOTE_HOST`   | _not overridden_ | Specify the remote syslog server to send logs to [More Info](https://wrapper.tanukisoftware.com/doc/english/prop-syslog-remote-host.html)
`WRAPPER_SYSLOG_REMOTE_PORT`   | _not overridden_ | Specify the UDP port on which to transmit syslog logs to [More Info](https://wrapper.tanukisoftware.com/doc/english/prop-syslog-remote-port.html)

<!-- markdownlint-disable MD036 -->
### _Table 4 - Module Enable/Disable_
<!-- markdownlint-enable MD036 -->

_Added to the image as of 8.0.13!_

See the section _How to enable/disable default modules_ further on in the documentation for more specifics on this feature.

Variable                       | Default | Description                                                          |
------------------------------ | ------- | -------------------------------------------------------------------- |
`GATEWAY_MODULES_ENABLED` | `all` | Comma-delimited list of modules (if not `all`) that should be enabled on Gateway start |

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

## How to enable/disable default modules

_New with latest 7.9.14 and 8.0.13 images as of 2020-06-12!_

_Table 4_ above mentions the environment variable `GATEWAY_MODULES_ENABLED`, that can be used to specify default Ignition modules that will enabled at Gateway startup.  If you override the default value of `all`, any other modules other than the ones you specify will be moved to a `modules-disabled` folder in the container and ignored on Gateway startup.  See the table below for the correlations between module designations that you can supply and the default module filenames that will be matched (and thusly remain enabled):

Module Definition | Module Filename
----------------- | ------------------------
`alarm-notification` | Alarm Notification-module.modl
`allen-bradley-drivers` | Allen-Bradley Drivers-module.modl
`dnp3-driver` | DNP3-Driver.modl
`enterprise-administration` | Enterprise Administration-module.modl
`logix-driver` | Logix Driver-module.modl
`mobile-module` | Mobile-module.modl
`modbus-driver-v2` | Modbus Driver v2-module.modl
`omron-driver` | Omron-Driver.modl
`opc-ua` | OPC-UA-module.modl
`perspective` | Perspective-module.modl
`reporting` | Reporting-module.modl
`serial-support-client` | Serial Support Client-module.modl
`serial-support-gateway` | Serial Support Gateway-module.modl
`sfc` | SFC-module.modl
`siemens-drivers` | Siemens Drivers-module.modl
`sms-notification` | SMS Notification-module.modl
`sql-bridge` | SQL Bridge-module.modl
`symbol-factory` | Symbol Factory-module.modl
`tag-historian` | Tag Historian-module.modl
`udp-tcp-drivers` | UDP and TCP Drivers-module.modl
`user-manual` | User Manual-module.modl
`vision` | Vision-module.modl
`voice-notification` | Voice Notification-module.modl
`web-browser` | Web Browser Module.modl
`web-developer` | Web Developer Module.modl

You can now specify a default set of enabled modules (all others not specified will be disabled/unavailable) like below, order is not important:

    $ docker run -p 8088:8088 -v my-ignition-data:/var/lib/ignition/data \
        -e GATEWAY_ADMIN_PASSWORD=password \
        -e GATEWAY_MODULES_ENABLED=vision,opc-ua,logix-driver,sql-bridge

Combine this and the guidance below regarding third-party modules to declare a truly custom gateway outlay per your requirements!

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

## How to integrate third party JDBC drivers

_New with latest 7.9.13 and 8.0.7 images as of 2020-01-25!_

To automatically link any associated third-party JDBC driver `*.jar` files, place them in a folder on the Docker host, and bind-mount the folder into `/jdbc` within the container.  The `JDBCDRIVERS` table within the gateway configuration database will be searched for Java Class Names that have a match within one of the available `*.jar` files under `/jdbc`.  When matched, the driver will be linked from there into the active location at `/var/lib/ignition/user-lib/jdbc`.  Finally, the `JDBCDRIVERS` table records will be updated with the name of the associated `.jar` file.

    $ ls /path/to/my/jdbc-drivers

    mysql-connector-java-8.0.19.jar

    $ docker run -p 8088:8088 -v my-ignition-data:/var/lib/ignition/data \
         -v /path/to/my/jdbc-drivers:/jdbc \
         -v /path/to/my/modules:/modules \
         -e GATEWAY_ADMIN_PASSWORD=password \
         -d kcollins/ignition:8.0.7

Note that if you remove the JDBC driver `.jar` file in the future, the `JDBCDRIVERS` database table within your gateway configuration database will likely still have the filename definition there, expecting a file to be available.

If you wish to link in a JDBC driver with the same name as a built-in driver, declare an environment variable `GATEWAY_JDBC_RELINK=true`.  This will cause the built-in JDBC driver to be removed and the new one linked in its place prior to gateway startup.

## Upgrading a volume-persisted Ignition Container

_New with latest 7.9.11 and 8.0.2 images as of 2019-06-28!_

Upgrading Ignition versions is now supported!  If you have your container bound with a named volume to `/var/lib/ignition/data` (as described above), upgrading to a newer container is now just a matter of stopping/removing the existing container, and starting a new container against a newer image.  Just make sure to connect the same volume to the new container and the entrypoint script will handle running the upgrader and conduct any additional provisioning actions automatically.

Note:  If you attempt to start a container bound to a newer-version image, an error will be produced and the container will not start.  Upgrades are supported, and downgrades are disallowed (as expected).

## Multi-Architecture Builds

The 8.0 image now supports both `arm64` and `armhf` architectures.  This means you can now run the Ignition or Ignition Edge containers on your Raspberry Pi (among other ARM-based devices).  They've only been tested on 32-bit builds of Raspberry Pi OS, but should work well on other 32-bit ARM platforms.  Use the same image tags you use normally--it will automatically pull the image appropriate for your architecture from Docker Hub.  

> **NOTE:** Regarding the Ignition 7.9.x branch, there is currently an issue with the AdoptOpenJDK JDK8 build that we're using that leaves the JVM without a JIT compiler and reduces performance significantly when running on aarch32/armhf.  Track that issue [here](https://github.com/AdoptOpenJDK/openjdk-build/issues/1531).  Once it is resolved and performance is normal, I'll enable the `armhf` build for `kcollins/ignition:7.9`.  The 8.0 image uses JDK11 and is unaffected by this particular issue.

## License

For licensing information, consult the following links:

* OpenJDK Licensing (base image for 7.9 and below) - http://openjdk.java.net/legal/gplv2+ce.html
* Ignition License - https://inductiveautomation.com/ignition/license
* Ignition Maker Edition - **free ONLY for personal and non-commercial use**, see license link above

As with all Docker images, these likely also contain other software which may be under other licenses (such as Bash, etc from the base distribution, along with any direct or indirect dependencies of the primary software being contained).  The use of third-party modules requires reviewing the related licensing information, as module EULAs are accepted automatically on the user's behalf.

As for any pre-built image usage, it is the image user's responsibility to ensure that any use of this image complies with any relevant licenses for all software contained within.
