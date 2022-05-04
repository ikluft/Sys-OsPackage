# Sys::OsPackage
# ABSTRACT: install OS packages and determine if CPAN modules are packaged for the OS 
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

package Sys::OsPackage;

use Carp qw(carp croak confess);
use Sys::OsRelease;
BEGIN {
    # import methods from Sys::OsRelease to manage singleton instance
    Sys::OsRelease->import_singleton();
}

# system configuration
my %_sysconf = (
    # additional common IDs to provide to Sys::OsRelease to recognize as common platforms in ID_LIKE attributes
    # this adds CentOS to recognized common platforms because we use it to recognize Rocky and Alma as needing EPEL
    common_id => [qw(centos)],

    # command search list & path
    search_cmds => [qw(uname curl tar cpan cpanm rpm yum repoquery dnf apt apk pacman brew zypper)],
    search_path => [qw(/bin /usr/bin /sbin /usr/sbin /opt/bin /usr/local/bin)],
);

# platform/package configuration
# all entries in here have a second-level hash keyed on the platform
# TODO: refactor to delegate this to packaging driver classes
my %_platconf = (
    # platform packaging handler class name
    packager => {
        alpine => "Sys::OsPackage::Driver::Alpine",
        arch => "Sys::OsPackage::Driver::Arch",
        centos => "Sys::OsPackage::Driver::RPM", # CentOS no longer exists; CentOS derivatives supported via ID_LIKE
        debian => "Sys::OsPackage::Driver::Debian",
        fedora => "Sys::OsPackage::Driver::RPM",
        suse => "Sys::OsPackage::Driver::Suse",
        ubuntu => "Sys::OsPackage::Driver::Debian",
    },

    # package name override where computed name is not correct
    override => {
        debian => {
            "libapp-cpanminus-perl" => "cpanminus",
        },
        ubuntu => {
            "libapp-cpanminus-perl" => "cpanminus",
        },
        arch => {
            "perl-app-cpanminus" => "cpanminus",
            "tar" => "core/tar",
            "curl" => "core/curl",
        },
    },

    # prerequisite OS packages for CPAN
    prereq => {
        alpine => [qw(perl-utils)],
        fedora => [qw(perl-CPAN)],
        centos => [qw(epel-release perl-CPAN)], # CentOS no longer exists, still used for CentOS-derived systems
        debian => [qw(perl-modules)],
        ubuntu => [qw(perl-modules)],
    },

    # augment command search path on some systems
    # entries may be scalar or array
    cmd_path => {
        arch => [qw(/usr/bin/core_perl /usr/bin/vendor_perl /usr/bin/site_perl)],
    },
);

# Perl-related configuration (read only)
my %_perlconf = (
    sources => {
        "App::cpanminus" => 'https://cpan.metacpan.org/authors/id/M/MI/MIYAGAWA/App-cpanminus-1.7046.tar.gz',
    },

    # Perl module dependencies
    # Sys::OsPackage doesn't have to declare these as dependencies because it will load them by package or CPAN before use
    # That maintains a light footprint for bootstrapping a container or system.
    module_deps => [qw(Term::ANSIColor Perl::PrereqScanner::NotQuiteLite HTTP::Tiny)],

    # OS package dependencies for CPAN
    cpan_deps => [qw(curl tar make)],

    # built-in modules/pragmas to skip processing as dependencies
    skip => {
        "strict" => 1,
        "warnings" => 1,
        "utf8" => 1,
        "feature" => 1,
        "autodie" => 1,
    },
);

#
# class data access functions
#

# helper function to allow methods to get the instance ref when called via the class name
sub class_or_obj
{
    my $coo = shift;
    return $coo if ref $coo; # return it if it's an object

    # safety net: all-stop if we received an undef
    if (not defined $coo) {
        confess "coo got undef from:".(join "|", caller 1);
    }

    # return the instance
    my $inst_method = $coo->can("instance");
    if (not $inst_method) {
        confess "incompatible class $coo from:".(join "|", caller 1);
    }
    return &$inst_method($coo);
}

# system configuration
sub sysconf
{
    my $key = shift;
    return if not exists $_sysconf{$key};
    return $_sysconf{$key};
}

# Perl configuration
sub perlconf
{
    my $key = shift;
    return if not exists $_perlconf{$key};
    return $_perlconf{$key};
}

# platform configuration
sub _platconf { return \%_platconf; } # for testing
sub platconf
{
    my ($class_or_obj, $key) = @_;
    my $self = class_or_obj($class_or_obj);

    return if not defined $self->platform();
    return if not exists $_platconf{$key}{$self->platform()};
    return $_platconf{$key}{$self->platform()};
}

#
# initialization of the singleton instance
# imported methods from Sys::OsRelease: init new instance defined_instance clear_instance
#

# initialize a new instance
## no critic (Subroutines::ProhibitUnusedPrivateSubroutines) # called by imported instance() - perlcritic can't see it
sub _new_instance
{
    my ($class, @params) = @_;

    # enforce class lineage
    if (not $class->isa(__PACKAGE__)) {
        croak "cannot find instance: ".(ref $class ? ref $class : $class)." is not a ".__PACKAGE__;
    }

    # obtain parameters from array or hashref
    my %obj;
    if (scalar @params > 0) {
        if (ref $params[0] eq 'HASH') {
            $obj{_config} = $params[0];
        } else {
            $obj{_config} = {@params};
        }
    }

    # bless instance
    my $obj_ref = bless \%obj, $class;

    # initialization
    if (exists $obj_ref->{_config}{debug}) {
        $obj_ref->{debug} = $obj_ref->{_config}{debug};
    } elsif (exists $ENV{SYS_OSPACKAGE_DEBUG}) {
        $obj_ref->{debug} = deftrue($ENV{SYS_OSPACKAGE_DEBUG});
    }
    if (deftrue($obj_ref->{debug})) {
        print STDERR "_new_instance($class, ".join(", ", @params).")\n";
    }
    $obj_ref->{sysenv} = {};
    $obj_ref->{module_installed} = {};
    $obj_ref->collect_sysenv();

    # instantiate object
    return $obj_ref;
}
## use critic (Subroutines::ProhibitUnusedPrivateSubroutines)

# utility: test if a value is defined and is true
sub deftrue
{
    my $value = shift;
    return ((defined $value) and $value) ? 1 : 0;
}

#
# functions that query instance data
#

# read/write accessor for debug flag
sub debug
{
    my ($class_or_obj, $value) = @_;
    my $self = class_or_obj($class_or_obj);

    if (defined $value) {
        $self->{debug} = $value;
    }
    return $self->{debug};
}

# read-only accessor for quiet flag
sub quiet
{
    my ($class_or_obj, $value) = @_;
    my $self = class_or_obj($class_or_obj);

    return deftrue($self->{_config}{quiet});
}

# read/write accessor for system environment data
# sysenv is the data collected about the system and commands
sub sysenv
{
    my ($class_or_obj, $key, $value) = @_;
    my $self = class_or_obj($class_or_obj);

    if (defined $value) {
        $self->{sysenv}{$key} = $value;
    }
    return $self->{sysenv}{$key};
}

# return system platform type
sub platform
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    return $self->sysenv("platform");
}

# return system packager type, or undef if not determined
sub packager
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    return $self->sysenv("packager"); # undef intentionally returned if it doesn't exist
}

# find if a platform has specific command search paths needed to run Perl scripts
sub plat_cmd_path
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    my $plat_cmd_path = $self->platconf("cmd_path");
    return () if not defined $plat_cmd_path;
    if (ref $plat_cmd_path eq "ARRAY") {
        return @{$plat_cmd_path};
    }
    return $plat_cmd_path;
}

# look up known exceptions for the platform's package naming pattern
sub pkg_override
{
    my ($class_or_obj, $pkg) = @_;
    my $self = class_or_obj($class_or_obj);

    my $override = $self->platconf("override");
    return if ((not defined $override) or (ref $override ne "HASH"));
    return $override->{$pkg};
}

# check if a package name is actually a pragma and may as well be skipped because it's built in to Perl
sub pkg_skip
{
    my ($class_or_obj, $module) = @_;
    my $self = class_or_obj($class_or_obj);

    my $perl_skip = perlconf("skip");
    return if ((not defined $perl_skip) or (ref $perl_skip ne "HASH"));
    return (deftrue($perl_skip->{$module}) ? 1 : 0);
}

# find platform-specific prerequisite packages for installation of CPAN
sub cpan_prereqs
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    my @prereqs = @{perlconf("cpan_deps")};
    my $plat_prereq = $self->platconf("prereq");
    if ((defined $plat_prereq)
        and (ref $plat_prereq eq "ARRAY"))
    {
        push @prereqs, @{$plat_prereq};
    }
    return @prereqs;
}

# determine if a Perl module is installed, or if a value is provided act as a write accessor for the module's flag
sub module_installed
{
    my ($class_or_obj, $name, $value) = @_;
    my $self = class_or_obj($class_or_obj);

    # if a value is provided then act as a write accessor to the module_installed flag for the module
    if (defined $value) {
        my $flag = $value ? 1 : 0;
        $self->{module_installed}{$name} = $flag;
        return $flag;
    }

    # short-circuit the search if we installed the module or already found it installed
    return 1 if deftrue($self->{module_installed}{$name});

    # check each path element for the module
    my $modfile = join("/", split(/::/x, $name));
    foreach my $element (@INC) {
        my $filepath = "$element/$modfile.pm";
        if (-f $filepath) {
            $self->{module_installed}{$name} = 1;
            return 1;
        }
    }
    return 0;
}

# run an external command and capture its standard output
# optional \%args in first parameter
#   carp_errors - carp full details in case of errors
#   list - return an array of result lines
sub capture_cmd
{
    my ($class_or_obj, @cmd) = @_;
    my $self = class_or_obj($class_or_obj);
    $self->debug() and print STDERR "debug(capture_cmd): ".join(" ", @cmd)."\n";

    # get optional arguments if first element of @cmd is a hashref
    my %args;
    if (ref $cmd[0] eq "HASH") {
        %args = %{shift @cmd};
    }

    # capture output
    my @output;
    my $cmd = join( " ", @cmd);

    # @cmd is concatenated into $cmd - any args which need quotes should have them included
    {
        no autodie;
        open my $fh, "-|", $cmd
            or croak "failed to run pipe command '$cmd': $!";
        while (<$fh>) {
            chomp;
            push @output, $_;
        }
        close $fh
            or carp "failed to close pipe for command '$cmd': $!";;
    }

    # detect and handle errors
    if ($? != 0) {
        # for some commands displaying errors are unnecessary - carp errors if requested
        if (deftrue($args{carp_errors})) {
            carp "exit status $? from command '$cmd'";
        }
        return;
    }

    # return results
    if (deftrue($args{list})) {
        # return an array if list option set
        return @output;
    }
    return wantarray ? @output : join("\n", @output);
}

# get working directory (with minimal library prerequisites)
sub pwd
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    my $pwd = $self->capture_cmd('pwd');
    $self->debug() and print STDERR "debug: pwd = $pwd\n";
    return $pwd;
}

# find executable files in the $PATH and standard places
sub cmd_path
{
    my ($class_or_obj, $name) = @_;
    my $self = class_or_obj($class_or_obj);

    # collect and cache path info
    if (not defined $self->sysenv("path_list") or not defined $self->sysenv("path_flag")) {
        $self->sysenv("path_list", [split /:/x, $ENV{PATH}]);
        $self->sysenv("path_flag", {map { ($_ => 1) } @{$self->sysenv("path_list")}});
        my $path_flag = $self->sysenv("path_flag");
        foreach my $dir (@{sysconf("search_path")}, $self->plat_cmd_path()) {
            -d $dir or next;
            if (not exists $path_flag->{$dir}) {
                push @{$self->sysenv("path_list")}, $dir;
                $path_flag->{$dir} = 1;
            }
        }
    }

    # check each path element for the file
    foreach my $element (@{$self->sysenv("path_list")}) {
        my $filepath = "$element/$name";
        if (-x $filepath) {
            return $filepath;
        }
    }
    return;
}

# de-duplicate a colon-delimited path
# utility function
sub _dedup_path
{
    my ($class_or_obj, @in_paths) = @_;
    my $self = class_or_obj($class_or_obj);

    # construct path lists and deduplicate
    my @out_path;
    my %path_seen;
    foreach my $dir (map {split /:/x, $_} @in_paths) {
        $self->debug() and print STDERR "debug: found $dir\n";
        if ($dir eq "." ) {
            # omit "." for good security practice
            next;
        }
        # add the path if it hasn't already been seen, and it exists
        if (not exists $path_seen{$dir} and -d $dir) {
            push @out_path, $dir;
            $self->debug() and print STDERR "debug: pushed $dir\n";
        }
        $path_seen{$dir} = 1;
    }
    return join ":", @out_path;
}

# save library hints where user's local Perl modules go, observed in search/cleanup of paths
sub _save_hint
{
    my ($item, $lib_hints_ref, $hints_seen_ref) = @_;
    if (not exists $hints_seen_ref->{$item}) {
        push @{$lib_hints_ref}, $item;
        $hints_seen_ref->{$item} = 1;
    }
    return;
}

# more exhaustive search for user's local perl library directory
sub user_perldir_search_loop
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    if (not defined $self->sysenv("perlbase")) {
        DIRLOOP: foreach my $dirpath ($self->sysenv("home"), $self->sysenv("home")."/lib",
            $self->sysenv("home")."/.local")
        {
            foreach my $perlname (qw(perl perl5)) {
                if (-d "$dirpath/$perlname" and -w "$dirpath/$perlname") {
                    $self->sysenv("perlbase", $dirpath."/".$perlname);
                    last DIRLOOP;
                }
            }
        }
    }
    return;
}

# if the user's local perl library doesn't exist, create it
sub user_perldir_create
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    if (not defined $self->sysenv("perlbase")) {
        # use a default that complies with XDG directory structure
        my $need_path;
        foreach my $need_dir ($self->sysenv("home"), ".local", "perl", "lib", "perl5") {
            $need_path = (defined $need_path) ? "$need_path/$need_dir" : $need_dir;
            if (not -d $need_path) {
                mkdir $need_path, 755
                    or croak "failed to create $need_path: $!";
            }
        }
        $self->sysenv("perlbase", $self->sysenv("home")."/.local/perl");
        symlink $self->sysenv("home")."/.local/perl", $self->sysenv("perlbase")
            or croak "failed to symlink ".$self->sysenv("home")."/.local/perl to ".$self->sysenv("perlbase").": $!";
    }
    return;
}

# find or create user's local Perl directory
sub user_perldir_search
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    # use environment variables to look for user's Perl library
    my @lib_hints;
    my %hints_seen;
    my $home = $self->sysenv("home");
    if (exists $ENV{PERL_LOCAL_LIB_ROOT}) {
        foreach my $item (split /:/x, $ENV{PERL_LOCAL_LIB_ROOT}) {
            if ($item =~ qr(^$home/)x) {
                $item =~ s=/$==x; # remove trailing slash if present
                _save_hint($item, \@lib_hints, \%hints_seen);
            }
        }
    }
    if (exists $ENV{PERL5LIB}) {
        foreach my $item (split /:/x, $ENV{PERL5LIB}) {
            if ($item =~ qr(^$home/)x) {
                $item =~ s=/$==x; # remove trailing slash if present
                $item =~ s=/[^/]+$==x; # remove last directory from path
                _save_hint($item, \@lib_hints, \%hints_seen);
            }
        }
    }
    if (exists $ENV{PATH}) {
        foreach my $item (split /:/x, $ENV{PATH}) {
            if ($item =~ qr(^$home/)x and $item =~ qr(/perl[5]?/)x) {
                $item =~ s=/$==x; # remove trailing slash if present
                $item =~ s=/[^/]+$==x; # remove last directory from path
                _save_hint($item, \@lib_hints, \%hints_seen);
            }
        }
    }
    foreach my $dirpath (@lib_hints) {
        if (-d $dirpath and -w $dirpath) {
            $self->sysenv("perlbase", $dirpath);
            last;
        }
    }
    
    # more exhaustive search for user's local perl library directory
    $self->user_perldir_search_loop();

    # if the user's local perl library doesn't exist, create it
    $self->user_perldir_create();
    return;
}

# set up user library and environment variables
# this is called for non-root users
sub set_user_env
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    # find or create library under home directory
    if (exists $ENV{HOME}) {
        $self->sysenv("home", $ENV{HOME});
    }
    $self->user_perldir_search();

    #
    # set user environment variables similar to local::lib
    #
    {
        # allow environment variables to be set without "local" in this block - this updates them for child processes
        ## no critic (Variables::RequireLocalizedPunctuationVars)

        # update PATH
        if (exists $ENV{PATH}) {
            $ENV{PATH} = $self->_dedup_path($ENV{PATH}, $self->sysenv("perlbase")."/bin");
        } else {
            $ENV{PATH} = $self->_dedup_path("/usr/bin:/bin", $self->sysenv("perlbase")."/bin", "/usr/local/bin");
        }

        # because we modified PATH: remove path cache/flags and force them to be regenerated
        delete $self->{sysenv}{path_list};
        delete $self->{sysenv}{path_flag};

        # update PERL5LIB
        if (exists $ENV{PERL5LIB}) {
            $ENV{PERL5LIB} = $self->_dedup_path($ENV{PERL5LIB}, $self->sysenv("perlbase")."/lib/perl5");
        } else {
            $ENV{PERL5LIB} = $self->_dedup_path(@INC, $self->sysenv("perlbase")."/lib/perl5");
        }

        # update PERL_LOCAL_LIB_ROOT/PERL_MB_OPT/PERL_MM_OPT for local::lib
        if (exists $ENV{PERL_LOCAL_LIB_ROOT}) {
            $ENV{PERL_LOCAL_LIB_ROOT} = $self->_dedup_path($ENV{PERL_LOCAL_LIB_ROOT}, $self->sysenv("perlbase"));
        } else {
            $ENV{PERL_LOCAL_LIB_ROOT} = $self->sysenv("perlbase");
        }
        {
            ## no critic (Variables::RequireLocalizedPunctuationVars)
            $ENV{PERL_MB_OPT} = '--install_base "'.$self->sysenv("perlbase").'"';
            $ENV{PERL_MM_OPT} = 'INSTALL_BASE='.$self->sysenv("perlbase");
        }

        # update MANPATH
        if (exists $ENV{MANPATH}) {
            $ENV{MANPATH} = $self->_dedup_path($ENV{MANPATH}, $self->sysenv("perlbase")."/man");
        } else {
            $ENV{MANPATH} = $self->_dedup_path("usr/share/man", $self->sysenv("perlbase")."/man", "/usr/local/share/man");
        }
    }

    # display updated environment variables
    if (not $self->quiet()) {
        print "using environment settings: (add these to login shell rc script if needed)\n";
        print "".('-' x 75)."\n";
        foreach my $varname (qw(PATH PERL5LIB PERL_LOCAL_LIB_ROOT PERL_MB_OPT PERL_MM_OPT MANPATH)) {
            print "export $varname=$ENV{$varname}\n";
        }
        print "".('-' x 75)."\n";
        print "\n";
    }
    return;
}

# collect info and deduce platform type
sub resolve_platform
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    # collect uname info
    my $uname = $self->sysenv("uname");
    if (not defined $uname) {
        croak "error: can't find uname command to collect system information";
    }
    $self->sysenv("os", $self->capture_cmd($uname, "-s"));
    $self->sysenv("kernel", $self->capture_cmd($uname, "-r"));
    $self->sysenv("machine", $self->capture_cmd($uname, "-m"));

    # initialize Sys::OsRelease and set platform type
    my $osrelease = Sys::OsRelease->instance(common_id => sysconf("common_id"));
    $self->sysenv("platform", $osrelease->platform());

    # determine system's packager if possible
    my $plat_packager = $self->platconf("packager");
    if (defined $plat_packager) {
        $self->sysenv("packager", $plat_packager);
    }

    # display system info
    my $detected;
    if (defined $osrelease->osrelease_path()) {
        if ($self->platform() eq $osrelease->id()) {
            $detected = $self->platform();
        } else {
            $detected = $osrelease->id()." -> ".$self->platform();
        }
        if (defined $self->sysenv("packager")) {
            $detected .= " handled by ".$self->sysenv("packager");
        }

    } else {
        $detected = $self->platform()." (no os-release data)";
    }
    if (not $self->quiet()) {
        print $self->text_green()."system detected: $detected".$self->text_color_reset()."\n";
    }
    return;
}

# collect system environment info
sub collect_sysenv
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);
    my $sysenv = $self->{sysenv};

    # find command locations
    foreach my $cmd (@{sysconf("search_cmds")}) {
        if (my $filepath = $self->cmd_path($cmd)) {
            $sysenv->{$cmd} = $filepath;
        }
    }

    # collect info and deduce platform type
    $self->resolve_platform();

    # check if user is root
    if ($> == 0) {
        # set the flag to indicate they are root
        $sysenv->{root} = 1;

        # on Alpine, refresh the package data
        if (exists $sysenv->{apk}) {
            $self->run_cmd($sysenv->{apk}, "update");
        }
    } else {
        # set user environment variables as necessary (similar to local::lib but without that as a dependency)
        $self->set_user_env();
    }

    # debug dump
    if ($self->debug()) {
        print STDERR "debug: sysenv:\n";
        foreach my $key (sort keys %$sysenv) {
            if (ref $sysenv->{$key} eq "ARRAY") {
                print STDERR "   $key => [".join(" ", @{$sysenv->{$key}})."]\n";
            } else {
                print STDERR "   $key => ".(exists $sysenv->{$key} ? $sysenv->{$key} : "(undef)")."\n";
            }
        }
    }
    return;
}

# run an external command
sub run_cmd
{
    my ($class_or_obj, @cmd) = @_;
    my $self = class_or_obj($class_or_obj);

    $self->debug() and print STDERR "debug(run_cmd): ".join(" ", @cmd)."\n";
    {
        no autodie;
        system @cmd;
    }
    if ($? == -1) {
        print STDERR "failed to execute '".(join " ", @cmd)."': $!\n";
        exit 1;
    } elsif ($? & 127) {
        printf STDERR "child '".(join " ", @cmd)."' died with signal %d, %s coredump\n",
            ($? & 127),  ($? & 128) ? 'with' : 'without';
        exit 1;
    } else {
        my $retval = $? >> 8;
        if ($retval != 0) {
            printf STDERR "child '".(join " ", @cmd)."' exited with value %d\n", $? >> 8;
            return 0;
        }
    }

    # it gets here if it succeeded
    return 1;
}

# check if the user is root - if so, return true
sub is_root
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    return ($self->sysenv("root") != 0);
}

# handle various systems' packagers
# op parameter is a string:
#   implemented: 1 if packager implemented for this system, otherwise undef
#   pkgcmd: 1 if packager command found, 0 if not found
#   modpkg(module): find name of package for Perl module
#   find(pkg): 1 if named package exists, 0 if not
#   install(pkg): 0 = failure, 1 = success
# returns undef if not implemented
#   for ops which return a numeric status: 0 = failure, 1 = success
#   some ops return a value such as query results
sub manage_pkg
{
    my ($class_or_obj, %args) = @_;
    my $self = class_or_obj($class_or_obj);

    if (not exists $args{op}) {
        croak "manage_pkg() requires op parameter";
    }

    # check if packager is implemented for currently-running system
    if ($args{op} eq "implemented") {
        if ($self->sysenv("os") eq "Linux") {
            if (not defined $self->platform()) {
                # for Linux packagers, we need ID to tell distros apart - all modern distros should provide one
                return;
            }
            if (not defined $self->packager()) {
                # it gets here on Linux distros which we don't have a packager implementation
                return;
            }
        } else {
            # add handlers for more packagers as they are implemented
            return;
        }
        return 1;
    }

    # if a pkg parameter is present, apply package name override if one is configured
    if (exists $args{pkg} and $self->pkg_override($args{pkg})) {
        $args{pkg} = $self->pkg_override($args{pkg});
    }

    # if a module parameter is present, add mod_parts parameter
    if (exists $args{module}) {
        $args{mod_parts} = [split /::/x, $args{module}];
    }

    # look up function which implements op for package type
    ## no critic (BuiltinFunctions::ProhibitStringyEval) # need stringy eval to load a class from a string
    eval "require ".$self->packager()
        or croak "failed to load driver class ".$self->packager();
    ## use critic (BuiltinFunctions::ProhibitStringyEval)
    my $funcname = $self->packager()."::".$args{op};
    $self->debug() and print STDERR "debug: $funcname(".join(" ", map {$_."=".$args{$_}} sort keys %args).")\n";
    my $funcref = $self->packager()->can($args{op});
    if (not defined $funcref) {
        # not implemented - subroutine name not found in driver class
        $self->debug() and print STDERR "debug: $funcname not implemented\n";
        return;
    }

    # call the function with parameters: driver class (class method call), Sys::OsPackage instance, arguments
    return $funcref->($self->packager(), $self, \%args);
}

# return string to turn text green
sub text_green
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    $self->module_installed('Term::ANSIColor') or return "";
    require Term::ANSIColor;
    return Term::ANSIColor::color('green');
}

# return string to turn text back to normal
sub text_color_reset
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    $self->module_installed('Term::ANSIColor') or return "";
    require Term::ANSIColor;
    return Term::ANSIColor::color('reset');
}

# install a Perl module as an OS package
sub module_package
{
    my ($class_or_obj, $module) = @_;
    my $self = class_or_obj($class_or_obj);

    # check if we can install a package
    if (not $self->is_root()) {
        # must be root to install an OS package
        return 0;
    }
    if (not $self->manage_pkg(op => "implemented")) {
        return 0;
    }

    # handle various package managers
    my $pkgname = $self->manage_pkg(op => "modpkg", module => $module);
    return 0 if (not defined $pkgname) or length($pkgname) == 0;
    if (not $self->quiet()) {
        print "\n";
        print $self->text_green()."install $pkgname for $module using ".$self->sysenv("packager")
            .$self->text_color_reset()."\n";
    }

    return $self->manage_pkg(op => "install", pkg => $pkgname);
}

# check if module is installed, and install it if not present
sub check_module
{
    my ($class_or_obj, $name) = @_;
    my $self = class_or_obj($class_or_obj);

    # check if module is installed
    if (not $self->module_installed($name)) {
        # print header for module installation
        if (not $self->quiet()) {
            print  $self->text_green().('-' x 75)."\n";
            print "install $name".$self->text_color_reset()."\n";
        }

        # try first to install it with an OS package (root required)
        my $done=0;
        if ($self->is_root()) {
            if ($self->module_package($name)) {
                $self->module_installed($name, 1);
                $done=1;
            }
        }

        # try again with CPAN or CPANMinus if it wasn't installed by a package
        if (not $done) {
            my $cmd = (defined $self->sysenv("cpan") ? $self->sysenv("cpan") : $self->sysenv("cpanm"));
            $self->run_cmd($cmd, $name)
                or croak "failed to install $name module";
            $self->module_installed($name, 1);
        }
    }
    return;
}

# bootstrap CPAN-Minus in a subdirectory of the current directory
sub bootstrap_cpanm
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    # save current directory
    my $old_pwd = $self->pwd();

    # make build directory and change into it
    if (not -d "build") {
        mkdir "build"
            or croak "can't make build directory in current directory: $!";
    }
    chdir "build";

    # verify required commands are present
    my @missing;
    foreach my $cmd (@{perlconf("cpan_deps")}) {
        if (not defined $self->sysenv("$cmd")) {
            push @missing, $cmd;
        }
    }
    if (scalar @missing > 0) {
        croak "missing ".(join ", ", @missing)." command - can't bootstrap cpanm";
    }

    # download cpanm
    my $perl_sources = perlconf("sources");
    $self->run_cmd($self->sysenv("curl"), "-L", "--output", "app-cpanminus.tar.gz",
        $perl_sources->{"App::cpanminus"}
    )
        or croak "download failed for App::cpanminus";
    my $cpanm_path = (grep {qr(/bin/cpanm$)x} ($self->capture_cmd({list=>1}, $self->sysenv("tar"),
        qw(-tf app-cpanminus.tar.gz))));
    run_cmd($self->sysenv("tar"), "-xf", "app-cpanminus.tar.gz", $cpanm_path);
    $self->sysenv("cpanm", $self->pwd()."/".$cpanm_path);

    # change back up to previous directory
    chdir $old_pwd;
    return;
}

# establish CPAN if not already present
sub establish_cpan
{
    my ($class_or_obj) = @_;
    my $self = class_or_obj($class_or_obj);

    # first get package dependencies for CPAN (and CPAN too if available via OS package)
    if ($self->is_root()) {
        # package dependencies for CPAN (i.e. make, or oddly-named OS package that contains CPAN)
        my @deps = $self->cpan_prereqs();
        $self->manage_pkg(op => "install", pkg => \@deps);

        # check for commands which were installed by their package name, and specifically look for cpan by any package
        foreach my $dep (@deps, "cpan") {
            if (my $filepath = $self->cmd_path($dep)) {
                $self->sysenv($dep, $filepath);
            }
        }
    }

    # install CPAN-Minus if neither CPAN nor CPAN-Minus exist
    if (not defined $self->sysenv("cpan") and not defined $self->sysenv("cpanm")) {
        # try to install CPAN-Minus as an OS package
        if ($self->is_root()) {
            if ($self->module_package("App::cpanminus")) {
                $self->sysenv("cpanm", $self->cmd_path("cpanm"));
            }
        }

        # try again if it wasn't installed by a package
        if (not defined $self->sysenv("cpanm")) {
            $self->bootstrap_cpanm();
        }
    }

    # install CPAN if it doesn't exist
    if (not defined $self->sysenv("cpan")) {
        # try to install CPAN as an OS package
        if ($self->is_root()) {
            if ($self->module_package("CPAN")) {
                $self->sysenv("cpan", $self->cmd_path("cpan"));
            }
        }

        # try again with cpanminus if it wasn't installed by a package
        if (not defined $self->sysenv("cpan")) {
            if ($self->run_cmd($self->sysenv("cpanm"), "CPAN")) {
                $self->sysenv("cpan", $self->cmd_path("cpan"));
            }
        }
    }

    # install dependencies for this tool
    foreach my $dep (@{perlconf("module_deps")}) {
        $self->check_module($dep);
    }
    return;
}

1;

__END__

# POD documentation
=encoding utf8

=head1 NAME

Sys::OsPackage - install OS packages and determine if CPAN modules are packaged for the OS

=head1 SYNOPSIS


=head1 DESCRIPTION


=head1 SEE ALSO

GitHub repository for Sys::OsPackage: L<https://github.com/ikluft/Sys-OsPackage>

=head1 BUGS AND LIMITATIONS

Please report bugs via GitHub at L<https://github.com/ikluft/Sys-OsPackage/issues>

Patches and enhancements may be submitted via a pull request at L<https://github.com/ikluft/Sys-OsPackage/pulls>

=head1 LICENSE INFORMATION

Copyright (c) 2022 by Ian Kluft

This module is distributed in the hope that it will be useful, but it is provided “as is” and without any express or implied warranties. For details, see the full text of the license in the file LICENSE or at L<https://www.perlfoundation.org/artistic-license-20.html>.
