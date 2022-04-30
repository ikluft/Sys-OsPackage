# Sys::OsPackage::Driver::RPM
# ABSTRACT: RedHat/Fedora RPM packaging handler for Sys::OsPackage
# Copyright (c) 2022 by Ian Kluft
# Open Source license Perl's Artistic License 2.0: <http://www.perlfoundation.org/artistic_license_2_0>
# SPDX-License-Identifier: Artistic-2.0

# This module is maintained for minimal dependencies so it can build systems/containers from scratch.

## no critic (Modules::RequireExplicitPackage)
# This resolves conflicting Perl::Critic rules which want package and strictures each before the other
use strict;
use warnings;
use utf8;
## use critic (Modules::RequireExplicitPackage)

package Sys::OsPackage::Driver::RPM;

use base "Sys::OsPackage::Driver";

# check if packager command found (rpm)
sub pkgcmd
{
    my ($class, $ospkg) = @_;

    return ((defined $ospkg->sysenv("dnf") or (defined $ospkg->sysenv("yum") and defined $ospkg->sysenv("repoquery"))) ? 1 : 0);
}

# find name of package for Perl module (rpm)
sub modpkg
{
    my ($class, $ospkg, $args_ref) = @_;
    return if not $class->pkgcmd($ospkg);

    #return join("-", "perl", @{$args_ref->{mod_parts}}); # rpm format for Perl module packages
    my @querycmd = ((defined $ospkg->sysenv("dnf"))
        ? ($ospkg->sysenv("dnf"), "repoquery")
        : $ospkg->sysenv("repoquery"));
    my @pkglist = sort $ospkg->capture_cmd({list=>1}, @querycmd, qw(--available --whatprovides),
        "'perl(".$args_ref->{module}.")'");
    $ospkg->debug()
        and print STDERR "debug(".__PACKAGE__."->modpkg): ".$args_ref->{module}." -> ".join(" ", @pkglist)."\n";
    return if not scalar @pkglist; # empty list means nothing found
    return $pkglist[-1]; # last of sorted list should be most recent version
}

# find named package in repository (rpm)
sub find
{
    my ($class, $ospkg, $args_ref) = @_;
    return if not $class->pkgcmd($ospkg);

    my @querycmd = ((defined $ospkg->sysenv("dnf"))
        ? ($ospkg->sysenv("dnf"), "repoquery")
        : $ospkg->sysenv("repoquery"));
    my @pkglist = sort $ospkg->capture_cmd({list=>1}, @querycmd, qw(--available), $args_ref->{pkg});
    return if not scalar @pkglist; # empty list means nothing found
    return $pkglist[-1]; # last of sorted list should be most recent version
}

# install package (rpm)
sub install
{
    my ($class, $ospkg, $args_ref) = @_;
    return if not $class->pkgcmd($ospkg);

    # determine packages to install
    my @packages;
    if (exists $args_ref->{pkg}) {
        if (ref $args_ref->{pkg} eq "ARRAY") {
            push @packages, @{$args_ref->{pkg}};
        } else {
            push @packages, $args_ref->{pkg};
        }
    }

    # install the packages
    my $pkgcmd = $ospkg->sysenv("dnf") // $ospkg->sysenv("yum");
    return $ospkg->run_cmd($pkgcmd, "install", "--assumeyes", "--setopt=install_weak_deps=false", @packages);
}

1;
