#!/bin/sh
# build a container to test Sys::OsPackage on various OS environments
# for sniffing out OS configurations that break when reported by CPAN Testers

# display errors
die() {
    echo "error: $*" >&2
    exit 1
}

# build container
build() {
    # check if OS name has a Containerfile (Podman's equivalent of a Dockerfile) in this directory
    containerfile="$osname.containerfile"
    if [ ! -f "$containerfile" ]
    then
        die "OS name $osname does not have a Containerfile"
    fi

    podman build --file "$containerfile" --tag "$imagename:$timestamp" \
        && podman tag "$imagename:$timestamp" "$imagename:latest"
}

# run container
run() {
    # check if OS name has an image built. If not, build it.
    if ! podman image exists "$imagename:latest"
    then
        build_container || die "build_container failed on $osname"
    fi

    # run container
    mkdir --parents "logs/$timestamp"
    chmod ugo=rwx,ug-s logs "logs/$timestamp"
    podman run -it --label="sys-ospkg-test=1" --env="SYS_OSPKG_TIMESTAMP=$timestamp" \
        --mount "type=bind,src=logs,dst=/opt/container/logs,ro=false" \
        "$imagename:latest"
}

# clean up environment
clean() {
    # clear out logs
    echo clean logs...
    rm -rf logs/2[0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9]

    # clean out containers and images
    echo clean containers...
    # shellcheck disable=SC2046
    containers="$(podman container ls --all --quiet --filter="label=sys-ospkg-test")"
    if [ -n "$containers" ]
    then
        # shellcheck disable=SC2086
        podman container rm $containers
    fi
    echo clean images...
    # shellcheck disable=SC2046
    images="$(podman image ls --quiet \*-sys-ospkg-test)"
    if [ -n "$images" ]
    then
        # shellcheck disable=SC2086
        podman image untag $images
        # shellcheck disable=SC2086
        podman image rm $images
    fi
    
}

# use command name to decide on build or run
cmd="$1"
osname="$2"
timestamp=$(date '+%Y-%m-%d-%H-%M-%S')
imagename="$osname-sys-ospkg-test"
case "$cmd" in
    build) build;;
    run) run;;
    clean) clean;;
    *) die "unrecognized command name $0";;
esac

