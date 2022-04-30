# Sys::OsPackage::Driver::Alpine
# ABSTRACT: Alpine APK packaging handler for Sys::OsPackage
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

package Sys::OsPackage::Driver::Alpine;

use base "Sys::OsPackage::Driver";

# check if packager command found (alpine)
sub pkgcmd
{
    my ($class, $ospkg) = @_;

    return (defined $ospkg->sysenv("apk") ? 1 : 0);
}

# find name of package for Perl module (alpine)
sub modpkg
{
    my ($class, $ospkg, $args_ref) = @_;
    return if not $class->pkgcmd($ospkg);

    # search by alpine format for Perl module packages
    my $pkgname = join("-", "perl", map {lc $_} @{$args_ref->{mod_parts}});
    $args_ref->{pkg} = $pkgname;
    if (not $class->find($args_ref)) {
        return;
    }
    $ospkg->debug() and print STDERR "debug(".__PACKAGE__."->modpkg): $pkgname\n";

    # package was found - return the simpler name since pkg add won't take this full string
    return $pkgname;
}

# find named package in repository (alpine)
sub find
{
    my ($class, $ospkg, $args_ref) = @_;
    return if not $class->pkgcmd($ospkg);

    my $querycmd = $ospkg->sysenv("apk");
    my @pkglist = sort map {substr($_,0,index($_," "))}
        ($ospkg->capture_cmd({list=>1}, $querycmd, qw(list --available --quiet), $args_ref->{pkg}));
    return if not scalar @pkglist; # empty list means nothing found
    return $pkglist[-1]; # last of sorted list should be most recent version
}

# install package (alpine)
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
    my $pkgcmd = $ospkg->sysenv("apk");
    return $ospkg->run_cmd($pkgcmd, "add", @packages);
}

1;
