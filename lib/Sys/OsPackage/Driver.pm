# Sys::OsPackage::Driver
# ABSTRACT: parent class for packaging handler drivers for Sys::OsPackage
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

package Sys::OsPackage::Driver;

# all drivers respond to ping for testing: demonstrate module is accessible without launching packaging commands
sub ping
{
    my $class = shift;

    # enforce class lineage
    if (not $class->isa(__PACKAGE__)) {
        return __PACKAGE__;
    }

    return $class;
}

1;
