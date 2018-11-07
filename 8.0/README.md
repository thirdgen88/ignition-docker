# Ignition 8.0.x Docker Image

**NOTE**: This is currently a NIGHTLY build beta image for Ignition 8.0. 

You can build this image yourself with the following:

    $ docker image build -f Dockerfile -t custom-ignition:tag

... where the `Dockerfile` is in the current directory and `custom-ignition` is the new image name with tag `tag`.

If you've got [Vagrant](https://vagrantup.com) installed, you can leverage the `Vagrantfile` here to automate the building and testing of the image.  Build the image and start the container with the following:

    $ vagrant up --provider docker

The preceding command will cause Vagrant to build the image and launch a container from the resulting image.  If you make changes to the `Dockerfile`, you can quickly rebuild the image (with Vagrant taking care of removing the previous container instance) with:

    $ vagrant reload

To stop the container (preserving it), you can use the `halt` command as follows:

    $ vagrant halt