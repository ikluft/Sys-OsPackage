FROM ubuntu:20.04
WORKDIR /opt/container
COPY container-startup.sh Sys-OsPackage-*.tar.gz .
RUN apt update && apt install -y tar tree perl perl-modules-5.30 cpanminus libdist-zilla-perl \
    libdist-zilla-plugin-installguide-perl libdist-zilla-plugin-podweaver-perl
CMD /usr/bin/perl /opt/container/container-startup.sh
