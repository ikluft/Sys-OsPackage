#!/usr/bin/env perl 
# PODNAME: fetch-reqs.pl
#        USAGE: ./fetch-reqs.pl  
#  DESCRIPTION: install prerequisite modules for a Perl script with minimal prerequisites for this tool
#       AUTHOR: Ian Kluft (IKLUFT), 
#      CREATED: 04/14/2022 05:45:29 PM
# As part of Sys::OsPackage, this must be maintained for minimal dependencies to build systems and containers.

use strict;
use warnings;
use utf8;
use autodie;
use feature qw(say);
use Carp qw(carp croak);
use Data::Dumper;
use Sys::OsPackage;

sub process
{
    my $filename = shift;
    my $ospackage = Sys::OsPackage->instance();

    my $basename;
    if (index($filename, '/') == -1) {
        # no directory provided so use pwd
        $basename = $filename;
        $filename = $ospackage->pwd()."/".$filename;
    } else {
        # $filename is a path so keep it that way, and extract basename
        $basename = substr($filename, rindex($filename, '/')+1);
    }
    $ospackage->debug() and say STDERR "debug(process): filename=$filename basename=$basename";

    # scan for dependencies
    require Perl::PrereqScanner::NotQuiteLite;
    my $scanner = Perl::PrereqScanner::NotQuiteLite->new();
    my $deps_ref = $scanner->scan_file($filename);
    $ospackage->debug() and say STDERR "debug: deps_ref = ".Dumper($deps_ref);

    # load Perl modules for dependencies
    my $deps = $deps_ref->requires();
    $ospackage->debug() and say STDERR "deps = ".Dumper($deps);
    foreach my $module (sort keys %{$deps->{requirements}}) {
        next if $ospackage->pkg_skip($module);
        $ospackage->debug() and say STDERR "check_module($module)";
        $ospackage->check_module($module);
    }
    return;
}

#
# mainline
#

# set up
Sys::OsPackage->init();
Sys::OsPackage->establish_cpan(); # make sure CPAN is available

# process command line
foreach my $arg (@ARGV) {
    process($arg);
}
