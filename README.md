# skinnywhale
Skinnywhale helps you make smaller (as in megabytes) Docker containers

If, for example, you want to run a python script in a container, normally you'd
have to download a 600MB image that had the python interpretor along with most
of an OS inside it. Skinnywhale helps you isolate runtime environments like
python, ruby, and java, and throw the rest of the stuff away, so the images you
make with it are normally hundreds of megs smaller than their bloated
counterparts. Starting from a generic Ubuntu Docker image, my Skinnywhale
Python images usually come out to be around 30MB. Here's how you use it:

## step 1. Start with a normal fat image

``` docker run -ti ubuntu ```

## step 2. Make a container that has the runtime you need in it

``` 
apt-get update
apt-get install python3
exit

docker ps -a
<copy the container ID you just created eg.. 8efbc5497abb>
```

## step 3. isolate the runtime layer you just added

```
skinnywhale 8efbc5497abb
```

Skinnywhale requires that you're using an *aufs-backed* docker that is version
1.6 or later (there are bugs earlier than that which cause "file not found"
errors on images imported from tarballs)

You can see what kind of back-end you have with:

```
#  docker info
Containers: 2
Images: 7
Storage Driver: aufs
 Root Dir: /var/lib/docker/aufs
 Backing Filesystem: extfs
 Dirs: 11
 Dirperm1 Supported: false
```

If you're on ubuntu and your docker is not using aufs, it's probably because
you're missing the linux-image-extra package. Try running: 

```
apt-get -y install linux-image-extra-$(uname -r)
service docker restart
docker info
```

ANYWAY if everything went ok, skinnywhale will write a "skinny" version of the
container you listed as an image. You should see it listed in *docker images*.
You can specify this image in a Dockerfile like so:

```
FROM skinny_8efbc5497abb
ADD  myPythonScript.py /
CMD ["myPythonScript.py"]
```
Now build it: 

```
docker build -t myTeensyAppContainer .
```
...and now you have a dockerized version of your app that contains only your
script and the runtime needed to execute it (and not the entire rest of ubuntu
or whatever). 

## How does this work?
Skinnywhale is pretty simple, it finds the aufs path for the container ID you
give it, and walks through it looking for binary files that are dynamically
linked. Skinnywhale resolves each of these dependencies by copying the linked
library files in from the parent image's aufs directory. It then tars up the
resulting filesystem and *docker import*s it. 

There are two caveats to this process. First, some binary-distributed runtime
environments (like the oracle JDK), contain files that link to libs that may
not be installed on the client (if, for example you're using a base-image that
doesn't have Xorg installed, the JDK WILL have binary files that are linked to
X11 libs that don't exist on your base image). This is not usually a problem;
as long as your app works with the base image you're trying to use, it should
also work post-skinnywhale. 

Second, Skinnywhale can't detect if your runtime uses dlOpen(). You're on
you're on there I'm afraid. FWIW I've been using skinnywhale for python and
java stuff at work, and in practice I've found this not to be an issue.  If it
becomes an issue I might think about adding options to just wholesale copy
across the parent /lib /usr/lib et al.. Chances are though, if someone is using
dlOpen(), those libs are going to be part of the distribution files for the
runtime (ie you aren't going to assume a lib file is lying around somewhere
unless *you* put it there, (unless you're silly or mean)), and since
skinnywhale grabs the entire runtime, it *ought* to be pretty safe with respect
to dlOpen'd stuff. YMMV.  Caveat emptor. etc...

## No I mean *HOW* does this work?
Oh. Pretty well I guess? Java images are still stupid big, because java is
stupid big. Skinnywhale is irrelevent for Go because static binaries. It gets a
python runtime down to about 33MB, but yeah, the jvm environments are still
like 370MB (it is what it is.  Still beats the gigabyte-sized java images
floating around in the public registries).

Since skinnywhale is really just using the diff functionality built-in to aufs,
it's completely agnostic to factors like the OS of your base-image. So if you
start with a busy-box image, and use skinnywhale to isolate the java-runtime
from that, you may end up with something smaller. The relevant factor is how
much crap the package-manager in your base-image vomits into the file system
when you use it to install something like Java. Good luck!
