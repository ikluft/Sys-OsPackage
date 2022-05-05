#!/usr/bin/perl
#===============================================================================
#         FILE: 101_alpine.t
#  DESCRIPTION: container test with Alpine
#       AUTHOR: Ian Kluft (IKLUFT), 
#      CREATED: 05/03/2022 08:15:00 PM
#===============================================================================

# container tests are expensive and only for author tests, or for advanced users who want to run them
BEGIN {
  unless ($ENV{AUTHOR_TESTING}) {
    print qq{1..0 # SKIP these tests are for testing by the author\n};
    exit;
  }
}

#print qq{1..0 # SKIP under construction\n};
#exit;

# Test Anything Protocol (TAP) output will come from the container
use strict;
use warnings;
exec "perl", "t/testcon.pl", "--alpine";
