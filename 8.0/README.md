# Ignition 8.0.x Docker Image

You can build this image yourself with the following:

    $ docker image build -f Dockerfile -t custom-ignition:tag

... where the `Dockerfile` is in the current directory and `custom-ignition` is the new image name with tag `tag`.

If you've got [Vagrant](https://vagrantup.com) installed, you can leverage the `Vagrantfile` here to automate the building and testing of the image.  The latest Vagrant configuration includes multiple containers configured into a gateway network.  Build the image and start the containers with the following:

    $ vagrant up

The preceding command will cause Vagrant to build the image and launch `hub` and `spoke1` containers.  If you make changes to the `Dockerfile`, you can quickly rebuild the image (with Vagrant taking care of removing the previous container instances) with:

    $ vagrant reload

To stop the containers (preserving them), you can use the `halt` command as follows:

    $ vagrant halt