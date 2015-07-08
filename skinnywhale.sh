#!/bin/bash
# Isolate the given top-level docker container

AUFS='/var/lib/docker/aufs/diff'

function usage {
#print usage and exit
        echo "usage: whalestarve <container ID>"
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

function findDep {
#walk the images starting at $1 looking for $2
	if [ -f "${AUFS}/${1}/${2}" ]
	then
		echo "${AUFS}/${1}/${2}"
	else
		fdPARENT=$(docker inspect ${1} | egrep 'Parent":' | sort | uniq | cut -d':' -f2 | tr -d '", ')
		for P in $(docker history ${fdPARENT} | sed -ne '2,$p' | sed -e 's/ .*//')
		do
			IMAGE=$(getFullHash ${P})
			debug "checking for ${AUFS}/${IMAGE}/${2}"
			if [ -f "${AUFS}/${IMAGE}/${2}" ]
			then
				debug "Found $2 at ${AUFS}/${IMAGE}/${2}"
				echo "${AUFS}/${IMAGE}/${2}"
				break
			fi	
		done
	fi
}

function panicAndFindDep {
#be stupid and just find the dang thing
	DEP=$(basename ${1})
	find ${AUFS} -name ${DEP} | head -n1
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

LAYER=$(getFullHash ${1})
debug "layer is ${LAYER}"
LPATH="${AUFS}/${LAYER}"
debug "LPATH is ${LPATH}"
PARENT_NAME=$(docker ps -a | grep ${1}| sed -e 's/ \+/ /g' | cut -d\  -f2)
PARENT=$(docker images | grep "^${PARENT_NAME}" | sed -e 's/ \+/ /g' | cut -d\  -f3)
debug "PARENT is ${PARENT}"
DEPS=''

#copy over the linker
LINKER=$(findDep $(getFullHash ${PARENT}) /usr/bin/ldd)
debug "cp -nv ${LINKER} ${LPATH}/usr/bin"
cp -nv ${LINKER} ${LPATH}/usr/bin

#recursively grab the library dependencies for every binary
for FILE in `find ${LPATH} -type f`
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
	mkdir -p ${LPATH}/$(dirname ${DEP})
	SOURCE=$(findDep ${PARENT} ${DEP})
	if [ -z "${SOURCE}" ]
	then
		SOURCE=$(panicAndFindDep ${DEP})
	fi
	if [ -z "${SOURCE}" ]
	then
		echo "ERROR!!!, can't find ${DEP} in the parent images"
		#exit 42
	else
		cp -nv ${SOURCE} ${LPATH}/${DEP}
	fi
done

#tar it all up and re-dockerize it
cd ${LPATH}
tar -c . --exclude=/var/cache | docker import - skinny_${1}
debug "tar -cv . | docker import - skinny_${1}"
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
