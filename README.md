# skinnywhale
Skinnywhale helps you make smaller (as in megabytes) Docker containers

It's a shell script that you can use to isolate the runtime environment you
need to execute something like a python/ruby/java program in a container. The
images you make with Skinnywhale are normally hundreds of megs smaller than
their bloated counterparts.  Here's how you use it:

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

## How does this work?
Skinnywhale is pretty simple, it finds the aufs path for the container ID you
give it, and walks through it looking for binary files that are dynamically
linked. Skinnywhale resolves each of these dependencies by copying the linked
library files in from the parent image's aufs directory. It then tars up the
resulting filesystem and *docker import*s it. 

There are two caveats to this process. First, some runtime environments (like
the oracle JDK), contain files that link to libs that may not be installed on
the client (if, for example you're using a base-image that doesn't have Xorg
installed, the JDK will have binary files that are linked to X11 libs that
don't exist on the base image). This is not usually a problem; as long as your
app actually works with the base image you're trying to use, it should work
post-skinnywhale. 

Second, Skinnywhale can't detect if your runtime uses dlOpen(). You're on
you're on there I'm afraid. I've been using skinnywhale for python and java
stuff at work, and in practice I've found this not to be an issue.  If it
becomes an issue I might think about adding options to just wholesale copy
across the parent /lib /usr/lib et al..
