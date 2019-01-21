#!/usr/bin/env perl

### This script is intended to produce data for use in troubleshooting
### ebuilds on funtoo, and should be triggered using the 
### post_src_prepare hook in /etc/portage/bashrc

use strict;
use warnings;


my $modified_ebuild = replace_ebuild_vars( get_ebuild() );
my $build_dir       = $ENV{"PORTAGE_BUILDDIR"};
my @file_list       = `find "$build_dir/files/" -type f`;

print @{ get_patch_files( $modified_ebuild, \@file_list ) };


## get_ebuild function accepts a path to an ebuild file and
## returns it's contents as a string
sub get_ebuild{
	open (my $fh, '<', $ENV{EBUILD}) or die "could not open ebuild file";
	my @ebuild_lines = <$fh>;
	close $fh;
	return join '',@ebuild_lines;
}

## replace_ebuild_vars function accepts a string that is the contents
## of an ebuild and returns a string that has all the associated
## keys from the env replaced with their values in the same string
sub replace_ebuild_vars {
	my $string = shift;
	
	foreach my $key (keys %ENV){
		# print "$key = $ENV{$key}\n";
		$string =~ s/\$\{\Q$key\E\}/$ENV{$key}/;
		$string =~ s/[\"\']//;
	}
	
	return $string;
}

## This function accepts a string that is a modified ebuild
## and a reference to an array of files 
## and returns a list of patch files found in it
sub get_patch_files{
	my $ebuild = shift;
	my $file_list_ref = shift;
	my @found_files;
	
	foreach my $filename (@{$file_list_ref}) {
		chomp $filename;
		
		if (index($ebuild,$filename)) {
			my $path_end = substr $filename, length($build_dir) + 1;
			$filename = "$ENV{CATEGORY}/$ENV{PN}/$path_end";
			push (@found_files, "$filename\n");
		}
	}
	return \@found_files;	
}