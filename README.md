# Sys::OsPackage
Modules in this distribution:
* [Sys::OsPackage](main)
* [Sys::OsPackage::DepTree](deptree)

As an overview, the manual for the Sys::OsPackage library follows.

# SYNOPSIS

    use Sys::OsPackage;
    my $ospackage = Sys::OsPackage->instance();
    foreach my $module ( qw(module-name ...)) {
      $ospackage->install_module($module);
    }

# DESCRIPTION

_Sys::OsPackage_ is used for installing Perl module dependencies.
It can look up whether a Perl module is available under some operating systems' packages.
If the module is available as an OS package, it installs it via the packaging system of the OS.
Otherwise it runs CPAN to install the module.

The use cases of _Sys::OsPackage_ include setting up systems or containers with Perl modules using OS packages
as often as possible. It can also be used fvor installing dependencies for a Perl script on an existing system.

OS packaging systems currently supported by _Sys::OsPackage_ are the Linux distributions Alpine, Arch, Debian,
Fedora and OpenSuse.
Using [Sys::OsRelease](https://metacpan.org/pod/Sys%3A%3AOsRelease) it's able to detect operating systems derived from a supported platform use the correct driver.

RHEL and CentOS are supported by the Fedora driver.
CentOS-derived systems Rocky and Alma are supported by recognizing them as derivatives.
Ubuntu is supported by the Debian driver.

Other packaging systems for Unix-like operating systems should be feasible to add by writing a driver module.

# SEE ALSO

[fetch-reqs.pl](https://metacpan.org/pod/fetch-reqs.pl) comes with _Sys::OsPackage_ to provide a command-line interface.

[Sys::OsPackage::Driver](https://metacpan.org/pod/Sys%3A%3AOsPackage%3A%3ADriver)

"pacman/Rosetta" at Arch Linux Wiki compares commands of 5 Linux packaging systems [https://wiki.archlinux.org/title/Pacman/Rosetta](https://wiki.archlinux.org/title/Pacman/Rosetta)

GitHub repository for Sys::OsPackage: [https://github.com/ikluft/Sys-OsPackage](https://github.com/ikluft/Sys-OsPackage)

# BUGS AND LIMITATIONS

Please report bugs via GitHub at [https://github.com/ikluft/Sys-OsPackage/issues](https://github.com/ikluft/Sys-OsPackage/issues)

Patches and enhancements may be submitted via a pull request at [https://github.com/ikluft/Sys-OsPackage/pulls](https://github.com/ikluft/Sys-OsPackage/pulls)

# LICENSE INFORMATION

Copyright (c) 2022 by Ian Kluft

This module is distributed in the hope that it will be useful, but it is provided “as is” and without any express or implied warranties. For details, see the full text of the license in the file LICENSE or at [https://www.perlfoundation.org/artistic-license-20.html](https://www.perlfoundation.org/artistic-license-20.html).
