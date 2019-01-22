#!/usr/bin/env perl

### This script is intended to produce data for use in troubleshooting
### ebuilds on funtoo, and should be triggered using the
### post_src_prepare hook in /etc/portage/bashrc

use strict;
use warnings;

use English qw(-no_match_vars);
use File::Find;

our $VERSION = 0.0.1;

my $modified_ebuild = strip_all_quotes( replace_ebuild_vars( get_ebuild() ) );
my $build_dir       = $ENV{'PORTAGE_BUILDDIR'};
my @file_list;
find(
    sub {
        if (-f) {
            push @file_list, $File::Find::name;
        }
    },
    "$build_dir/files/"
);

## If there's no files, there's nothing to do, so exit
if ( !scalar @file_list ) {
    exit 0;
}

print @{ get_patch_files( $modified_ebuild, \@file_list ) };

## get_ebuild function accepts a path to an ebuild file and
## returns it's contents as a string
sub get_ebuild {
    open my $fh, '<', $ENV{EBUILD}
        or die "Could not open ebuild file $ENV{EBUILD}: $ERRNO\n";
    my @ebuild_lines = <$fh>;
    close $fh or die "Unable to close filehandle: $ERRNO\n";
    return join q(), @ebuild_lines;
}

## replace_ebuild_vars function accepts a string that is the contents
## of an ebuild and returns a string that has all the associated
## keys from the env replaced with their values in the same string
sub replace_ebuild_vars {
    my $string = shift;

    # Substitute variable references for their values
    foreach my $key ( keys %ENV ) {
        $string =~ s/\$[{] \Q$key\E [}]/$ENV{$key}/xmsg;
    }

    return $string;
}

## strip_all_quotes function accepts a string and returns
## a string with all quote characters ["'] stripped.
sub strip_all_quotes {
    my $string = shift;

    $string =~ s/[\"\']//xmsg;

    return $string;
}

## This function accepts a string that is a modified ebuild
## and a reference to an array of files
## and returns a list of patch files found in it
sub get_patch_files {
    my $ebuild        = shift;
    my $file_list_ref = shift;
    my @found_files;

    foreach my $filename ( @{$file_list_ref} ) {
        chomp $filename;

        if ( index( $ebuild, $filename ) != -1 ) {
            my $path_end = substr $filename, length($build_dir) + 1;
            $filename = "$ENV{CATEGORY}/$ENV{PN}/$path_end";
            push @found_files, "$filename\n";
        }
    }
    return \@found_files;
}
