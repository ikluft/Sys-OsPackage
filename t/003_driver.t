#===============================================================================
#         FILE: 003_driver.t
#  DESCRIPTION: test Sys::OsPackage::Driver and driver subclasses
#       AUTHOR: YOUR NAME (), 
#      CREATED: 04/30/2022 07:47:25 PM
#===============================================================================

use strict;
use warnings;
use Sys::OsPackage;
use Readonly;
use Test::More;

# constants
Readonly::Array my @packagers => qw(Alpine Arch Debian RPM);

plan tests => scalar @packagers;

my $ospkg = Sys::OsPackage->instance(quiet => 1);
foreach my $packager (@packagers) {
    my $driver = "Sys::OsPackage::Driver::$packager";
    $ospkg->sysenv("packager", $driver); # force value of packager to the driver class we want
    my $str = $ospkg->manage_pkg(op => "ping");
    is($str, $driver, "driver $driver responded to ping");
}
