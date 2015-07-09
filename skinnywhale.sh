#!/bin/bash
# Isolate the given top-level docker container

AUFS='/var/lib/docker/aufs/diff'

function usage {
#print usage and exit
        echo "usage: skinnywhale.sh <container ID>"
	exit 42
}

function error {
#print an error and exit
        echo "ERROR: ${@}" 1>&2
	exit 42
}

function debug {
	[ "${DEBUG}" ] && echo "DEBUG:: ${@}" 1>&2
}

function getFullHash {
#return the full hash for a given container ID
	basename $(find ${AUFS} -maxdepth 1 -name ${1}* | grep -v 'init')
}

function mountDiff {
# Copy the diff filesystem to our tmp
	mkdir -p ${FS_DIFF}
	cp -a ${1}/* ${FS_DIFF}
	cd ${FS_DIFF}
	rm -Rf var/cache
}

function mountFull {
# Copy the full filesystem to our tmp
	mkdir -p ${FS_FULL}
	cd ${FS_FULL}
	docker export ${1} | tar -x
}

function findDep {
#Find $1 in the full filesystem
	if [ -f "${FS_FULL}/${1}" ]
	then
		echo "${FS_FULL}/${1}"
	fi
}

#lets kick this pig
debug "sanity checking"
[ "${1}" ] || usage 

SD=$(docker info | grep Storage)
if ! echo ${SD} | grep -q aufs
then
	echo "Sorry, docker needs to be running with aufs support"
	exit 42
fi

OURTEMP="/tmp/skinnyRun${RANDOM}"
mkdir -p ${OURTEMP}
debug "rundir is ${OURTEMP}"
FS_DIFF=${OURTEMP}/DIFF
FS_FULL=${OURTEMP}/FULL
LAYER=$(getFullHash ${1})
debug "layer is ${LAYER}"
LPATH="${AUFS}/${LAYER}"
debug "LPATH is ${LPATH}"
DEPS=''

#synch our temp dir
mountDiff ${LPATH}
mountFull ${1}

#copy over the linker
LINKER=$(findDep /usr/bin/ldd)
debug "cp -nv ${LINKER} ${FS_DIFF}/usr/bin"
cp -nv ${LINKER} ${FS_DIFF}/usr/bin

#recursively grab the library dependencies for every binary
for FILE in `find ${FS_DIFF} -type f`
do
	if file ${FILE} | grep -q 'dynamically linked'
	then
		debug "processing deps for ${FILE}"
		D=$(ldd ${FILE} | sed -e 's/\(^[^/]\+\)\([^ ]\+\).*/\2/' | grep '/')
		DEPS=$(printf "%s\n%s" "${DEPS}" "${D}" | sort | uniq)
	fi
done

#copy in the library dependencies
debug "DEPENDENCIES is ${DEPS}"
for DEP in ${DEPS}
do
	mkdir -p ${FS_DIFF}/$(dirname ${DEP})
	SOURCE=$(findDep ${DEP})
	if [ -z "${SOURCE}" ]
	then
		echo "ERROR!!!, can't find ${DEP} in the parent images"
		#need an option to panic and die here
	else
		cp -nv ${SOURCE} ${FS_DIFF}/${DEP}
	fi
done

#Copy in the lib dir if BRUTELIB is set
debug "BRUTELIB enabled! Copying over ${FS_FULL}/lib"
if [ "${BRUTELIB}" ]
then 
	cp -a ${FS_FULL}/lib ${FS_DIFF}
fi

#tar it all up and re-dockerize it
cd ${FS_DIFF}
debug "tar -cv . | docker import - skinny_${1}"
tar -c . --exclude=/var/cache | docker import - skinny_${1}
if [ $? -eq 0 ]
then
	echo "--- Skinnywhale says: skinny_${1} is positively starving ---"
	echo '
                    ##        .            
              ## ## ##       ==            
           ## ## ## ##      ===            
       /""""""""""""""""\___/ ===        
      /	rX
  ~~~{ /\ ~ ~~~ ~~~~ ~~ ~ /  ===- ~~~   
       \______////////////__/            
'
else
	echo 'OH NOES CRITICAL ERROR. I couldnt write your image sorry'
fi

if [ "${NOCLEANUP}" ]
then
	echo "not cleaning up my tempdir because NOCLEANUP is set (${OURTEMP}"
else
	rm -Rf ${OURTEMP}
fi
