#!/usr/bin/perl -w
#
#   Copyright (c) International Business Machines  Corp., 2002,2007
#
#   This program is free software;  you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or (at
#   your option) any later version.
#
#   This program is distributed in the hope that it will be useful, but
#   WITHOUT ANY WARRANTY;  without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#   General Public License for more details.                 
#
#   You should have received a copy of the GNU General Public License
#   along with this program;  if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
#
#
# lcov
#
#   This is a wrapper script which provides a single interface for accessing
#   LCOV coverage data.
#
#
# History:
#   2002-08-29 created by Peter Oberparleiter <Peter.Oberparleiter@de.ibm.com>
#                         IBM Lab Boeblingen
#   2002-09-05 / Peter Oberparleiter: implemented --kernel-directory +
#                multiple directories
#   2002-10-16 / Peter Oberparleiter: implemented --add-tracefile option
#   2002-10-17 / Peter Oberparleiter: implemented --extract option
#   2002-11-04 / Peter Oberparleiter: implemented --list option
#   2003-03-07 / Paul Larson: Changed to make it work with the latest gcov 
#                kernel patch.  This will break it with older gcov-kernel
#                patches unless you change the value of $gcovmod in this script
#   2003-04-07 / Peter Oberparleiter: fixed bug which resulted in an error
#                when trying to combine .info files containing data without
#                a test name
#   2003-04-10 / Peter Oberparleiter: extended Paul's change so that LCOV
#                works both with the new and the old gcov-kernel patch
#   2003-04-10 / Peter Oberparleiter: added $gcov_dir constant in anticipation
#                of a possible move of the gcov kernel directory to another
#                file system in a future version of the gcov-kernel patch
#   2003-04-15 / Paul Larson: make info write to STDERR, not STDOUT
#   2003-04-15 / Paul Larson: added --remove option
#   2003-04-30 / Peter Oberparleiter: renamed --reset to --zerocounters
#                to remove naming ambiguity with --remove
#   2003-04-30 / Peter Oberparleiter: adjusted help text to include --remove
#   2003-06-27 / Peter Oberparleiter: implemented --diff
#   2003-07-03 / Peter Oberparleiter: added line checksum support, added
#                --no-checksum
#   2003-12-11 / Laurent Deniel: added --follow option
#   2004-03-29 / Peter Oberparleiter: modified --diff option to better cope with
#                ambiguous patch file entries, modified --capture option to use
#                modprobe before insmod (needed for 2.6)
#   2004-03-30 / Peter Oberparleiter: added --path option
#   2004-08-09 / Peter Oberparleiter: added configuration file support
#   2008-08-13 / Peter Oberparleiter: added function coverage support

# NOTE: This version of lcov has been changed to add differential code coverage analysis functions
# Changelog- major changes only.
#   2009-05-22 / DAA: initial creation
#

use strict;
use File::Basename; 
use Getopt::Long;
use Data::Dumper; # can be removed for release

# Global constants
our $lcov_version	= "LCOV version 1.7 w/hacks for differential CCA";
our $lcov_url		= "undefined";
our $tool_name		= basename($0);

# Names of the GCOV kernel module
our @gcovmod = ("gcov-prof", "gcov-proc");

# Directory containing gcov kernel files
our $gcov_dir = "/proc/gcov";

# The location of the insmod tool
our $insmod_tool	= "/sbin/insmod";

# The location of the modprobe tool
our $modprobe_tool	= "/sbin/modprobe";

# The location of the rmmod tool
our $rmmod_tool		= "/sbin/rmmod";

# Where to create temporary directories
our $tmp_dir		= "/tmp";

# How to prefix a temporary directory name
our $tmp_prefix		= "tmpdir";


# Prototypes
sub print_usage(*);
sub check_options();
sub userspace_reset();
sub userspace_capture();
sub kernel_reset();
sub kernel_capture();
sub add_traces();
sub read_info_file($);
sub get_info_entry($);
sub set_info_entry($$$$$$$;$$$$);
sub add_counts($$);
sub merge_checksums($$$);
sub combine_info_entries($$$);
sub combine_info_files($$);
sub write_info_file(*$);
sub extract();
sub remove();
sub list();
sub get_common_filename($$);
sub read_diff($);
sub diff();
sub system_no_output($@);
sub read_config($);
sub apply_config($);
sub info(@);
sub unload_module($);
sub check_and_load_kernel_module();
sub create_temp_dir();
sub transform_pattern($);
sub warn_handler($);
sub die_handler($);

# Functions added for differential CCA
sub add_info($$); # adds two .info file execution counts
sub add_counts_mod($$); # adds two %sumcount hashes
sub subtract_counts_mod($$); # subtracts two %sumcount hashes

# walk_tracefile() is an incomplete function that is intended to allow
# easy access to the the contents of a tracefile via callbacks. Not functional.
sub walk_tracefile($);
# fetches and parses the rats report by executing rats via system().
sub get_rat_report($); 

# tracefile_adds_sinks(total_tracefile_path, new_tracefile_path[, limit_to_src_file])
# does new_tracefile_path add sinks to total_tracefile_path?
# total_tracefile_path is the location of a .info file with the running total for the minset.
# new_tracefile_path is the location of a .info file that will be compared to the total to determine
#                    if the new_tracefile_path should be added to our current minset list.
# limit_to_src_file is the path of the src code file to limit the analysis to
sub tracefile_adds_sinks($$;$);

# tracefile_adds_stmt(total_tracefile_path, new_tracefile_path[, limit_to_src_file])
# does new_tracefile_path add statement coverage to total_tracefile_path?
# total_tracefile_path is the location of a .info file with the running total for the minset.
# new_tracefile_path is the location of a .info file that will be compared to the total to determine
#                    if the new_tracefile_path should be added to our current minset list.
# limit_to_src_file is the path of the src code file to limit the analysis to
sub tracefile_adds_stmt($$;$);


# calc_minset()
sub calc_minset ($$);

# calls get_rat_report to get a rat report for each src file in the tracefile specified (the argument).
sub sinks_hit($); 
sub print_debug($); # print out debug information if debug mode is enabled

# returns 0 if the two info files are the same, -1 if the first is greater than the second,
# and 1 and the second is greater than the first (see constants below)
sub compare_info($$);
# constants returned/used by compare_info
use constant GREATER_THAN => 1;
use constant EQUAL => 0;
use constant LESS_THAN => -1;

# Global variables & initialization
our @directory;		# Specifies where to get coverage data from
our @kernel_directory;	# If set, captures only from specified kernel subdirs
our @add_tracefile;	# If set, reads in and combines all files in list
our $list;		# If set, list contents of tracefile
our $extract;		# If set, extracts parts of tracefile
our $remove;		# If set, removes parts of tracefile
our $diff;		# If set, modifies tracefile according to diff
our $reset;		# If set, reset all coverage data to zero
our $capture;		# If set, capture data
our $output_filename;	# Name for file to write coverage data to
our $test_name = "";	# Test case name
our $quiet = "";	# If set, suppress information messages
our $help;		# Help option flag
our $version;		# Version option flag
our $convert_filenames;	# If set, convert filenames when applying diff
our $strip;		# If set, strip leading directories when applying diff
our $need_unload;	# If set, unload gcov kernel module
our $temp_dir_name;	# Name of temporary directory
our $cwd = `pwd`;	# Current working directory
our $to_file;		# If set, indicates that output is written to a file
our $follow;		# If set, indicates that find shall follow links
our $diff_path = "";	# Path removed from tracefile when applying diff
our $base_directory;	# Base directory (cwd of gcc during compilation)
our $checksum;		# If set, calculate a checksum for each line
our $no_checksum;	# If set, don't calculate a checksum for each line
our $compat_libtool;	# If set, indicates that libtool mode is to be enabled
our $no_compat_libtool;	# If set, indicates that libtool mode is to be disabled
our $gcov_tool;
our $ignore_errors;
our $initial;
our $no_recursion = 0;
our $maxdepth;
our $config;		# Configuration file contents
chomp($cwd);
our $tool_dir = dirname($0);	# Directory where genhtml tool is installed

# add_count_files and sub_count_files are globals filled by GetOptions():
our @add_option; #  corresponds to --add arguments
our @subtract_option;  # corresponds to --subtract arguments
our @compare_total;   # corresponds to --compare-total arguments
our @compare_src_file; # corresponds to --compare-src-file
our @compare_func;    # corresponds to --compare-func arguments
our $view; # corresponds to --view argument
our $sinks_hit_option; # corresponds to --sinks-hit argument ()
our $calc_sink_minset_option; # corresponds to --calc-sink-minset argument (directory)
our $calc_stmt_minset_option; # corresponds to --calc-stmt-minset argument (directory)
our $sink_stats_option; # corresponds to --sink-stats argument (tracefile path)
our $limit_to_file_option; # corresponds to --limit-to-file argument (source code file)


#
# Code entry point
#

$SIG{__WARN__} = \&warn_handler;
$SIG{__DIE__} = \&die_handler;

# Add current working directory if $tool_dir is not already an absolute path
if (! ($tool_dir =~ /^\/(.*)$/))
{
	$tool_dir = "$cwd/$tool_dir";
}

# Read configuration file if available
if (-r $ENV{"HOME"}."/.lcovrc")
{
	$config = read_config($ENV{"HOME"}."/.lcovrc");
}
elsif (-r "/etc/lcovrc")
{
	$config = read_config("/etc/lcovrc");
}

if ($config)
{
	# Copy configuration file values to variables
	apply_config({
		"lcov_gcov_dir"		=> \$gcov_dir,
		"lcov_insmod_tool"	=> \$insmod_tool,
		"lcov_modprobe_tool"	=> \$modprobe_tool,
		"lcov_rmmod_tool"	=> \$rmmod_tool,
		"lcov_tmp_dir"		=> \$tmp_dir});
}

# Parse command line options
if (!GetOptions("directory|d|di=s" => \@directory,
		"add-tracefile=s" => \@add_tracefile,
		"list=s" => \$list,
		"kernel-directory=s" => \@kernel_directory,
		"extract=s" => \$extract,

		"remove=s" => \$remove,
		"diff=s" => \$diff,
		"convert-filenames" => \$convert_filenames,
		"strip=i" => \$strip,
		"capture|c" => \$capture,
		"output-file=s" => \$output_filename,
		"test-name=s" => \$test_name,
		"zerocounters" => \$reset,
		"quiet" => \$quiet,
		"help|?" => \$help,
		"version" => \$version,
		"follow" => \$follow,
		"path=s" => \$diff_path,
		"base-directory=s" => \$base_directory,
		"checksum" => \$checksum,
		"no-checksum" => \$no_checksum,
		"compat-libtool" => \$compat_libtool,
		"no-compat-libtool" => \$no_compat_libtool,
		"gcov-tool=s" => \$gcov_tool,
		"ignore-errors=s" => \$ignore_errors,
		"initial|i" => \$initial,
		"no-recursion" => \$no_recursion,
		# start differential mods
		"view=s" => \$view,
		"add=s{2}" => \@add_option,
		"subtract=s{2}" => \@subtract_option,
		"sinks-hit=s" => \$sinks_hit_option,
		"sink-stats=s" => \$sink_stats_option,
		"calc-sink-minset=s" => \$calc_sink_minset_option,
		"calc-stmt-minset=s" => \$calc_stmt_minset_option,
		"limit-to-file=s" => \$limit_to_file_option,
		"compare-total=s{2}" => \@compare_total,
		"compare-src-file=s{3}" => \@compare_src_file,
		"compare-func=s{3}" => \@compare_func
		))
{
	print(STDERR "Use $tool_name --help to get usage information\n");
	exit(1);
}
else
{
	# Merge options
	if (defined($no_checksum))
	{
		$checksum = ($no_checksum ? 0 : 1);
		$no_checksum = undef;
	}

	if (defined($no_compat_libtool))
	{
		$compat_libtool = ($no_compat_libtool ? 0 : 1);
		$no_compat_libtool = undef;
	}
}

# Check for help option
if ($help)
{
	print_usage(*STDOUT);
	exit(0);
}

# Check for version option
if ($version)
{
	print("$tool_name: $lcov_version\n");
	exit(0);
}

# Normalize --path text
$diff_path =~ s/\/$//;

if ($follow)
{
	$follow = "-follow";
}
else
{
	$follow = "";
}

if ($no_recursion)
{
	$maxdepth = "-maxdepth 1";
}
else
{
	$maxdepth = "";
}

# Check for valid options
check_options();

# Only --add, --subtract, --extract, --remove and --diff allow unnamed parameters
# TODO: was this modification correct?
if (@ARGV && !($extract || $remove || $diff || @add_option || @subtract_option))
{
	die("Extra parameter found\n".
	    "Use $tool_name --help to get usage information\n");
}

# Check for output filename
$to_file = ($output_filename && ($output_filename ne "-"));

if ($capture)
{
	if (!$to_file)
	{
		# Option that tells geninfo to write to stdout
		$output_filename = "-";
	}
}
else
{
	if ($initial)
	{
		die("Option --initial is only valid when capturing data (-c)\n".
		    "Use $tool_name --help to get usage information\n");
	}
}

# Check for requested functionality
if ($reset)
{
	# Differentiate between user space and kernel reset
	if (@directory)
	{
		userspace_reset();
	}
	else
	{
		kernel_reset();
	}
}
elsif ($capture)
{
	# Differentiate between user space and kernel 
	if (@directory)
	{
		userspace_capture();
	}
	else
	{
		kernel_capture();
	}
}

# different types of operations the user can request (add-tracefile, extract, remove, list, diff, add, subtract):
#
elsif (defined($view))
{
	my $total = read_info_file("new.info");
	my $new = read_info_file("new2.info");
	#TODO check return value
	print "Result: ".tracefile_adds_sinks($total, $new);
}


elsif (defined($sinks_hit_option))
{
	my $result = sinks_hit($sinks_hit_option);
	
	# number of sinks hit >0 times as reported by sinks_hit()
	my $covered_sinks = 0;
	
	# number of sinks that sinks_hit() returned undef for, ie, not instrumented - no coverage data
	my $uninstr_sinks = 0;
	
	# sinks with zero hits
	my $uncovered_sinks = 0;
	
	# total number of sinks
	my $total_sinks = 0;
	foreach my $file (keys(%{$result}))
	{
		print_debug("Src file: '$file'\n");
		foreach my $line_num (keys( %{ $result->{$file} }) )
		{
			#print "\t$file [$line_num]: ";
			#print $result->{$file}{$line_num}." hits\n" if defined($result->{$file}{$line_num});

			if ( defined($result->{$file}{$line_num}) && ($result->{$file}{$line_num} > 0) )
			{
				$covered_sinks++;
			} elsif( !defined($result->{$file}{$line_num}) )
			{
				$uninstr_sinks++;
			} elsif($result->{$file}{$line_num} == 0)
			{
				$uncovered_sinks++;
			}
			$total_sinks++;
			
		}
	}
	print "================================================================\n";
	printf("Sinks hit >0 times: %d - %.2f%%\n", $covered_sinks, (($covered_sinks/$total_sinks)*100));
	printf("Sinks hit 0 times: %d - %.2f%%\n", $uncovered_sinks, (($uncovered_sinks/$total_sinks)*100));
	printf("Sinks not instrumented: %d - %.2f%%\n", $uninstr_sinks, (($uninstr_sinks/$total_sinks)*100));
	print "==============TOTAL: $total_sinks sinks processed.==============\n\n";
	exit(0);
}

elsif (defined($calc_sink_minset_option)) # directory that contains
{
	my @tracefiles;
	my $minset_tracefiles; #reference to array of abs. paths to the tracefiles that the $sumtotal_tracefile contains
	my $sumtotal_tracefile; #path to the tracefile that is going to be the running total of all of the minset tracefiles
	
	($minset_tracefiles, $sumtotal_tracefile) = calc_minset($calc_sink_minset_option, \&tracefile_adds_sinks);
	
	print "Number of info files in minset: ".scalar(@$minset_tracefiles)."\n";
	
	exit(0);
}

elsif (defined($calc_stmt_minset_option)) # directory that contains
{
	my @tracefiles;
	my $minset_tracefiles; #reference to array of abs. paths to the tracefiles that the $sumtotal_tracefile contains
	my $sumtotal_tracefile; #path to the tracefile that is going to be the running total of all of the minset tracefiles
	
	($minset_tracefiles, $sumtotal_tracefile) = calc_minset($calc_stmt_minset_option, \&tracefile_adds_stmt);
	
	print "Number of info files in minset: ".scalar(@$minset_tracefiles)."\n";
	
	exit(0);
}

elsif (defined($sink_stats_option))
{
	my @tracefiles;
	my @minset_tracefiles; #array of abs. paths to the tracefiles that the $sumtotal_tracefile contains
	my $sumtotal_tracefile; #path to the tracefile that is going to be the running total of all of the minset tracefiles
	
	my %num_sinks; # tracefile => num_sinks_for_tracefile
	# find all the .info files in $calc_minset_option
	opendir DIR,$calc_sink_minset_option or die "open directory '$calc_sink_minset_option' failed : $!\n";
	for(readdir DIR) { push(@tracefiles, $_) if /^\d{1,3}\.info$/; }
	closedir DIR or die "close directory failed : $!\n";

	# get the number of sinks for each tracefile
	my ($min, $min_tracefile, $max_tracefile, $max, $total, $num_processed) = (undef, undef, undef, undef, 0, 0);	

	foreach my $path (@tracefiles) 
	{
		last if $num_processed == 500;
		
		# get the sinks for $path (next tracefile path)
		my $sinks = sinks_hit($calc_sink_minset_option."/".$path);
		next if(!defined($sinks)); # tracefile couldnt be read, user already notified, TODO better error handling
		
		# counters for different categories of sinks, for the entire tracefile
		# number of sinks hit >0 times as reported by sinks_hit()
		my $covered_sinks = 0;
		# number of sinks that sinks_hit() returned undef for, ie, not instrumented - no coverage data
		my $uninstr_sinks = 0;
		# sinks with zero hits
		my $uncovered_sinks = 0;
		# total number of sinks in all categories above
		my $total_sinks = 0;
		
	        foreach my $file (keys(%{$sinks}))
	        {
	                print_debug("Src file: '$file'\n");
	                foreach my $line_num (keys( %{ $sinks->{$file} }) )
	                {
	                        #print "\t$file [$line_num]: ";
	                        #print $sinks->{$file}{$line_num}." hits\n" if defined($sinks->{$file}{$line_num});

	                        if ( defined($sinks->{$file}{$line_num}))
				{
					if ($sinks->{$file}{$line_num} > 0)
					{
						$covered_sinks++;
					} else
					{
						$uncovered_sinks++;
					}
				} else {
					$uninstr_sinks++;
				}
				$total_sinks++;
	                }
	        }
		$num_sinks{$path} = $covered_sinks;
		if(!defined($min) || ($covered_sinks < $min) )
		{
			$min = $covered_sinks;
			$min_tracefile = $path;
		}

		if(!defined($max) || ($covered_sinks > $max) )
		{
			$max = $covered_sinks;
			$max_tracefile = $path;
		}

		$total += $covered_sinks;
		$num_processed++;
	        print "$path: $covered_sinks\n";
	}

	print "-----------------------\n";
	print "Average: ".($total/$num_processed)."\n";
	print "Max: $max - $max_tracefile\nMin: $min - $min_tracefile\nNum processed: $num_processed\n-----------------------------\n\n";

	exit(0);
}


elsif (@compare_total or @compare_src_file or @compare_func)
{
	info("Comparing info files...\n"); 
	my $total_result;
	my @func_result;
	
	#print "Result of comparison: ${total_result}\n";
	#print Dumper(@func_result);
	
	# what mode of operation has the user requested?
	#TODO: this is the wrong option to use for this functionality.. change
	if (@compare_total) # compare the total coverage of two .info files
	{	#FIXME: change this so it keeps track of which .info files comprise the total_tracefile
		my ($info1, $info2) = @compare_total;
		#($total_result, @func_result) = compare_info($info1, $info2);
		print "Comparison of stmt cov in .info files specified:\n";
		print "Total tracefile: $info1\nNew tracefile: $info2\n\n";
		
		print "Result of tracefile_adds_stmt(): ";
		print tracefile_adds_stmt($info1, $info2);
		
	} elsif (@compare_src_file) { # compare the total coverage of two src code files
		my ($src_file, $info1, $info2) = @compare_src_file;
		($total_result, @func_result) = compare_info($info1, $info2);
		print "Comparison of total statement coverage in src file '$src_file' common to .info files specified:\n";

		#if ( defined($func_result{$src_file}
	} elsif (@compare_func) {
			my ($func_name, $info1, $info2) = @compare_func;	
			print "Comparison of total statement coverage in function '$func_name' common to .info files specified:\n";
	}
	exit(0);
}
# user selected --add INFOFILE1 INFOFILE2
#FIXME this is only slightly different than the --add-tracefile option,
#      differentiate the two or remove one
elsif (@add_option)
{
	print "Adding tracefiles...\n";
	
	# $infofile_exhX is the %data hash returned from read_info_file
	my $infofile1 = read_info_file($add_option[0]);
	my $infofile2 = read_info_file($add_option[1]);
	
	# $result_exh is the result of the --add operation (execution counts are added)
	my $result;

	#print "INFOFILE1:\n";
	#print Dumper($infofile1);
	#print "INFOFILE2:\n";
	#print Dumper($infofile2);
	
	$result = add_info($infofile1, $infofile2);
	
	#print "RESULT:\n";
	#print Dumper($result);
	
	# now $result contains the result of the --add operation, write $shell_data
	info("Writing resulting data to $output_filename\n");
	open(INFO_HANDLE, ">$output_filename") or die("ERROR: cannot write to $output_filename!\n");
	write_info_file(*INFO_HANDLE, $result);
	close(*INFO_HANDLE);

	# do not support chaining --add with other lcov functionality
	print "Success!\n";
	exit(0);
}
# user selected --subtract INFOFILE1 INFOFILE2
elsif (@subtract_option)
{
	die("--subtract is currently not implemented, sorry!\n");
}
elsif (@add_tracefile)
{
	add_traces();
}
elsif ($remove)
{
	remove();
}
elsif ($extract)
{
	extract();
}
elsif ($list)
{
	list();
}
elsif ($diff)
{
	if (scalar(@ARGV) != 1)
	{
		die("ERROR: option --diff requires one additional argument!\n".
		    "Use $tool_name --help to get usage information\n");
	}
	diff();
}

info("Done.\n");
exit(0);

#
# print_usage(handle)
#
# Print usage information.
#

sub print_usage(*)
{
	local *HANDLE = $_[0];

	print(HANDLE <<END_OF_USAGE);
Usage: $tool_name [OPTIONS]

Use lcov to collect coverage data from either the currently running Linux
kernel or from a user space application. Specify the --directory option to
get coverage data for a user space program.

Misc:
  -h, --help                      Print this help, then exit
  -v, --version                   Print version number, then exit
  -q, --quiet                     Do not print progress messages

Operation:
  -z, --zerocounters              Reset all execution counts to zero
  -c, --capture                   Capture coverage data
  -a, --add-tracefile FILE        Add contents of tracefiles
  -e, --extract FILE PATTERN      Extract files matching PATTERN from FILE
  -r, --remove FILE PATTERN       Remove files matching PATTERN from FILE
  -l, --list FILE                 List contents of tracefile FILE
      --diff FILE DIFF            Transform tracefile FILE according to DIFF
      
   The following two options may only be used in conjunction with -o, --output-file:
   the result of the operation on the files will be output to the file specified.
  --view TRACEFILE                       Test test.
  --add TRACEFILE TRACEFILE              Add two tracefiles.
  --subtract TRACEFILE,BASE_TRACEFILE    Subtract FILE from BASE (where base is the baseline).
  --sinks-hit TRACEFILE                  
  --sink-stats TRACEFILE                 
  --calc-sink-minset TRACEFILE_DIR       Calculate the minimum set of tracefiles that covers
                                         a maximum number of sinks (you must have rats in your \$PATH).
  --calc-stmt-minset TRACEFILE_DIR       Calculate the minimum set of tracefiles that covers
                                         a maximum amount of statements.
  --limit-to-file SOURCE_CODE_FILE       Used in conjunction with --calc-*-minset to limit the
                                         analysis to a single source code file in the tracefiles.
  --compare-total TRACEFILE TRACEFILE    Compare total statement coverage of two info files.
  --compare-src-file SRC_CODE FILE FILE  Compare coverage of a specified src code
                                         file that is present in two .info files.
  --compare-func FUNC_NAME FILE FILE     Compare coverage of a specified function
                                         that is present in two .info files.

   For example,
       To add two tracefiles that were generated from identical code bases:
       lcov --add ./run1.info ./run2.info -o ./result.info
       
       To calculate the minimum test set ("minset") of all .info files in a directory:
       (NOTE: The --limit-to-file part is optional, if not specified, all source code
       files in the tracefiles will be used in the analysis)
       lcov --calc-minset /path/to/tracefiles [--limit-to-file /abs/source/code/path.cpp]
       
       TODO add more examples

Options:
  -i, --initial                   Capture initial zero coverage data
  -t, --test-name NAME            Specify test name to be stored with data
  -o, --output-file FILENAME      Write data to FILENAME instead of stdout
  -d, --directory DIR             Use .da files in DIR instead of kernel
  -f, --follow                    Follow links when searching .da files
  -k, --kernel-directory KDIR     Capture kernel coverage data only from KDIR
  -b, --base-directory DIR        Use DIR as base directory for relative paths
      --convert-filenames         Convert filenames when applying diff
      --strip DEPTH               Strip initial DEPTH directory levels in diff
      --path PATH                 Strip PATH from tracefile when applying diff
      --(no-)checksum             Enable (disable) line checksumming
      --(no-)compat-libtool       Enable (disable) libtool compatibility mode
      --gcov-tool TOOL            Specify gcov tool location
      --ignore-errors ERRORS      Continue after ERRORS (gcov, source)
      --no-recursion              Exlude subdirectories from processing

For more information see: $lcov_url
END_OF_USAGE
	;
}


#
# check_options()
#
# Check for valid combination of command line options. Die on error.
#

sub check_options()
{
	my $i = 0;
	#DAA TODO, validate --add and --subtract here

	# Count occurrence of mutually exclusive options
	$reset && $i++;
	$capture && $i++;
	@add_tracefile && $i++;
	$extract && $i++;
	$remove && $i++;
	$list && $i++;
	$diff && $i++;
	@add_option && $i++;
	@subtract_option && $i++;
	@compare_total && $i++;
	@compare_src_file && $i++;
	@compare_func && $i++;
	$view && $i++;
	$sinks_hit_option && $i++;
	$calc_sink_minset_option && $i++;
	$calc_stmt_minset_option && $i++;
	
	if ($i == 0)
	{
		die("Need one of the options --add, --subtract, --compare-total, --compare-func, -z, -c, -a, -e, -r, -l or ".
		    "--diff\n".
		    "Use $tool_name --help to get usage information\n");
	}
	elsif ($i > 1)
	{
		die("ERROR: only one of --add, --subtract, -z, -c, -a, -e, -r, -l or ".
		    "--diff allowed!\n".
		    "Use $tool_name --help to get usage information\n");
	}
	
	# make sure $output_filename is supplied for either -add or --subtract operations
	if( (!$output_filename) && (@subtract_option || @add_option) )
	{
		die("ERROR: --output-filename must be specified if you choose to --add or --subtract .info files.\n");
	}
}


#
# userspace_reset()
#
# Reset coverage data found in DIRECTORY by deleting all contained .da files.
#
# Die on error.
#

sub userspace_reset()
{
	my $current_dir;
	my @file_list;

	foreach $current_dir (@directory)
	{
		info("Deleting all .da files in $current_dir".
		     ($no_recursion?"\n":" and subdirectories\n"));
		@file_list = `find "$current_dir" $maxdepth $follow -name \\*\\.da -o -name \\*\\.gcda -type f 2>/dev/null`;
		chomp(@file_list);
		foreach (@file_list)
		{
			unlink($_) or die("ERROR: cannot remove file $_!\n");
		}
	}
}


#
# userspace_capture()
#
# Capture coverage data found in DIRECTORY and write it to OUTPUT_FILENAME
# if specified, otherwise to STDOUT.
#
# Die on error.
#

sub userspace_capture()
{
	my @param;
	my $file_list = join(" ", @directory);

	info("Capturing coverage data from $file_list\n");
	@param = ("$tool_dir/geninfo", @directory);
	if ($output_filename)
	{
		@param = (@param, "--output-filename", $output_filename);
	}
	if ($test_name)
	{
		@param = (@param, "--test-name", $test_name);
	}
	if ($follow)
	{
		@param = (@param, "--follow");
	}
	if ($quiet)
	{
		@param = (@param, "--quiet");
	}
	if (defined($checksum))
	{
		if ($checksum)
		{
			@param = (@param, "--checksum");
		}
		else
		{
			@param = (@param, "--no-checksum");
		}
	}
	if ($base_directory)
	{
		@param = (@param, "--base-directory", $base_directory);
	}
	if ($no_compat_libtool)
	{
		@param = (@param, "--no-compat-libtool");
	}
	elsif ($compat_libtool)
	{
		@param = (@param, "--compat-libtool");
	}
	if ($gcov_tool)
	{
		@param = (@param, "--gcov-tool", $gcov_tool);
	}
	if ($ignore_errors)
	{
		@param = (@param, "--ignore-errors", $ignore_errors);
	}
	if ($initial)
	{
		@param = (@param, "--initial");
	}
	if ($no_recursion)
	{
		@param = (@param, "--no-recursion");
	}

	system(@param);
	exit($? >> 8);
}


#
# kernel_reset()
#
# Reset kernel coverage.
#
# Die on error.
#

sub kernel_reset()
{
	local *HANDLE;
	check_and_load_kernel_module();

	info("Resetting kernel execution counters\n");
	open(HANDLE, ">$gcov_dir/vmlinux") or
		die("ERROR: cannot write to $gcov_dir/vmlinux!\n");
	print(HANDLE "0");
	close(HANDLE);

	# Unload module if we loaded it in the first place
	if ($need_unload)
	{
		unload_module($need_unload);
	}
}


#
# kernel_capture()
#
# Capture kernel coverage data and write it to OUTPUT_FILENAME if specified,
# otherwise stdout.
#

sub kernel_capture()
{
	my @param;

	check_and_load_kernel_module();

	# Make sure the temporary directory is removed upon script termination
	END
	{
		if ($temp_dir_name)
		{
			stat($temp_dir_name);
			if (-r _)
			{
				info("Removing temporary directory ".
				     "$temp_dir_name\n");

				# Remove temporary directory
				system("rm", "-rf", $temp_dir_name)
					and warn("WARNING: cannot remove ".
						 "temporary directory ".
						 "$temp_dir_name!\n");
			}
		}
	}

	# Get temporary directory
	$temp_dir_name = create_temp_dir();

	info("Copying kernel data to temporary directory $temp_dir_name\n");

	if (!@kernel_directory)
	{
		# Copy files from gcov kernel directory
		system("cp", "-dr", $gcov_dir, $temp_dir_name)
			and die("ERROR: cannot copy files from $gcov_dir!\n");
	}
	else
	{
		# Prefix list of kernel sub-directories with the gcov kernel
		# directory
		@kernel_directory = map("$gcov_dir/$_", @kernel_directory);

		# Copy files from gcov kernel directory
		system("cp", "-dr", @kernel_directory, $temp_dir_name)
			and die("ERROR: cannot copy files from ".
				join(" ", @kernel_directory)."!\n");
	}

	# Make directories writable
	system("find", $temp_dir_name, "-type", "d", "-exec", "chmod", "u+w",
	       "{}", ";")
		and die("ERROR: cannot modify access rights for ".
			"$temp_dir_name!\n");

	# Make files writable
	system("find", $temp_dir_name, "-type", "f", "-exec", "chmod", "u+w",
	       "{}", ";")
		and die("ERROR: cannot modify access rights for ".
			"$temp_dir_name!\n");

	# Capture data
	info("Capturing coverage data from $temp_dir_name\n");
	@param = ("$tool_dir/geninfo", $temp_dir_name);
	if ($output_filename)
	{
		@param = (@param, "--output-filename", $output_filename);
	}
	if ($test_name)
	{
		@param = (@param, "--test-name", $test_name);
	}
	if ($follow)
	{
		@param = (@param, "--follow");
	}
	if ($quiet)
	{
		@param = (@param, "--quiet");
	}
	if (defined($checksum))
	{
		if ($checksum)
		{
			@param = (@param, "--checksum");
		}
		else
		{
			@param = (@param, "--no-checksum");
		}
	}
	if ($base_directory)
	{
		@param = (@param, "--base-directory", $base_directory);
	}
	if ($no_compat_libtool)
	{
		@param = (@param, "--no-compat-libtool");
	}
	elsif ($compat_libtool)
	{
		@param = (@param, "--compat-libtool");
	}
	if ($gcov_tool)
	{
		@param = (@param, "--gcov-tool", $gcov_tool);
	}
	if ($ignore_errors)
	{
		@param = (@param, "--ignore-errors", $ignore_errors);
	}
	if ($initial)
	{
		@param = (@param, "--initial");
	}
	system(@param) and exit($? >> 8);


	# Unload module if we loaded it in the first place
	if ($need_unload)
	{
		unload_module($need_unload);
	}
}


#
# info(printf_parameter)
#
# Use printf to write PRINTF_PARAMETER to stdout only when the $quiet flag
# is not set.
#

sub info(@)
{
	if (!$quiet)
	{
		# Print info string
		if ($to_file)
		{
			print(@_)
		}
		else
		{
			# Don't interfer with the .info output to STDOUT
			printf(STDERR @_);
		}
	}
}


#
# Check if the gcov kernel module is loaded. If it is, exit, if not, try
# to load it.
#
# Die on error.
#

sub check_and_load_kernel_module()
{
	my $module_name;

	# Is it loaded already?
	stat("$gcov_dir");
	if (-r _) { return(); }

	info("Loading required gcov kernel module.\n");

	# Do we have access to the insmod tool?
	stat($insmod_tool);
	if (!-x _)
	{
		die("ERROR: need insmod tool ($insmod_tool) to access kernel ".
		    "coverage data!\n");
	}
	# Do we have access to the modprobe tool?
	stat($modprobe_tool);
	if (!-x _)
	{
		die("ERROR: need modprobe tool ($modprobe_tool) to access ".
		    "kernel coverage data!\n");
	}

	# Try some possibilities of where the gcov kernel module may be found
	foreach $module_name (@gcovmod)
	{
		# Try to load module from system wide module directory
		# /lib/modules
		if (system_no_output(3, $modprobe_tool, $module_name) == 0)
		{
			# Succeeded
			$need_unload = $module_name;
			return();
		}

		# Try to load linux 2.5/2.6 module from tool directory
		if (system_no_output(3, $insmod_tool,
				      "$tool_dir/$module_name.ko") == 0)
		{
			# Succeeded
			$need_unload = $module_name;
			return();
		}

		# Try to load linux 2.4 module from tool directory
		if (system_no_output(3, $insmod_tool,
				     "$tool_dir/$module_name.o") == 0)
		{
			# Succeeded
			$need_unload = $module_name;
			return();
		}
	}

	# Hm, loading failed - maybe we aren't root?
	if ($> != 0)
	{
		die("ERROR: need root access to load kernel module!\n");
	}

	die("ERROR: cannot load required gcov kernel module!\n");
}


#
# unload_module()
#
# Unload the gcov kernel module.
#

sub unload_module($)
{
	my $module = $_[0];

	info("Unloading kernel module $module\n");

	# Do we have access to the rmmod tool?
	stat($rmmod_tool);
	if (!-x _)
	{
		warn("WARNING: cannot execute rmmod tool at $rmmod_tool - ".
		     "gcov module still loaded!\n");
	}

	# Unload gcov kernel module
	system_no_output(1, $rmmod_tool, $module)
		and warn("WARNING: cannot unload gcov kernel module ".
		         "$module!\n");
}


#
# create_temp_dir()
#
# Create a temporary directory and return its path.
#
# Die on error.
#

sub create_temp_dir()
{
	my $dirname;
	my $number = sprintf("%d", rand(1000));

	# Endless loops are evil
	while ($number++ < 1000)
	{
		$dirname = "$tmp_dir/$tmp_prefix$number";
		stat($dirname);
		if (-e _) { next; }

		mkdir($dirname)
			or die("ERROR: cannot create temporary directory ".
			       "$dirname!\n");

		return($dirname);
	}

	die("ERROR: cannot create temporary directory in $tmp_dir!\n");
}


#
# read_info_file(info_filename)
#
# Read in the contents of the .info file specified by INFO_FILENAME. Data will
# be returned as a reference to a hash containing the following mappings:
#
# %result: for each filename found in file -> \%data
#
# %data: "test"  -> \%testdata
#        "sum"   -> \%sumcount
#        "func"  -> \%funcdata
#        "found" -> $lines_found (number of instrumented lines found in file)
#	 "hit"   -> $lines_hit (number of executed lines in file)
#        "check" -> \%checkdata
#        "testfnc" -> \%testfncdata
#        "sumfnc"  -> \%sumfnccount
#
# %testdata   : name of test affecting this file -> \%testcount
# %testfncdata: name of test affecting this file -> \%testfnccount
#
# %testcount   : line number   -> execution count for a single test
# %testfnccount: function name -> execution count for a single test
# %sumcount    : line number   -> execution count for all tests
# %sumfnccount : function name -> execution count for all tests
# %funcdata    : function name -> line number
# %checkdata   : line number   -> checksum of source code line
# 
# Note that .info file sections referring to the same file and test name
# will automatically be combined by adding all execution counts.
#
# Note that if INFO_FILENAME ends with ".gz", it is assumed that the file
# is compressed using GZIP. If available, GUNZIP will be used to decompress
# this file.
#
# Die on error.
#

sub read_info_file($)
{
	my $tracefile = $_[0];		# Name of tracefile
	my %result;			# Resulting hash: file -> data
	my $data;			# Data handle for current entry
	my $testdata;			#       "             "
	my $testcount;			#       "             "
	my $sumcount;			#       "             "
	my $funcdata;			#       "             "
	my $checkdata;			#       "             "
	my $testfncdata;
	my $testfnccount;
	my $sumfnccount;
	my $line;			# Current line read from .info file
	my $testname;			# Current test name
	my $filename;			# Current filename
	my $hitcount;			# Count for lines hit
	my $count;			# Execution count of current line
	my $negative;			# If set, warn about negative counts
	my $changed_testname;		# If set, warn about changed testname
	my $line_checksum;		# Checksum of current line
	local *INFO_HANDLE;		# Filehandle for .info file

	info("Reading tracefile $tracefile\n");

	# Check if file exists and is readable
	stat($_[0]);
	if (!(-r _))
	{
		die("ERROR: cannot read file $_[0]!\n");
	}

	# Check if this is really a plain file
	if (!(-f _))
	{
		die("ERROR: not a plain file: $_[0]!\n");
	}

	# Check for .gz extension
	if ($_[0] =~ /\.gz$/)
	{
		# Check for availability of GZIP tool
		system_no_output(1, "gunzip" ,"-h")
			and die("ERROR: gunzip command not available!\n");

		# Check integrity of compressed file
		system_no_output(1, "gunzip", "-t", $_[0])
			and die("ERROR: integrity check failed for ".
				"compressed file $_[0]!\n");

		# Open compressed file
		open(INFO_HANDLE, "gunzip -c $_[0]|")
			or die("ERROR: cannot start gunzip to decompress ".
			       "file $_[0]!\n");
	}
	else
	{
		# Open decompressed file
		open(INFO_HANDLE, $_[0])
			or die("ERROR: cannot read file $_[0]!\n");
	}

	$testname = "";
	while (<INFO_HANDLE>)
	{
		chomp($_);
		$line = $_;

		# Switch statement
		foreach ($line)
		{
			/^TN:([^,]*)/ && do
			{
				# Test name information found
				$testname = defined($1) ? $1 : "";
				if ($testname =~ s/\W/_/g)
				{
					$changed_testname = 1;
				}
				last;
			};

			/^[SK]F:(.*)/ && do
			{
				# Filename information found
				# Retrieve data for new entry
				$filename = $1;

				$data = $result{$filename};
				($testdata, $sumcount, $funcdata, $checkdata,
				 $testfncdata, $sumfnccount) =
					get_info_entry($data);

				if (defined($testname))
				{
					$testcount = $testdata->{$testname};
					$testfnccount = $testfncdata->{$testname};
				}
				else
				{
					$testcount = {};
					$testfnccount = {};
				}
				last;
			};

			/^DA:(\d+),(-?\d+)(,[^,\s]+)?/ && do
			{
				# Fix negative counts
				$count = $2 < 0 ? 0 : $2;
				if ($2 < 0)
				{
					$negative = 1;
				}
				# Execution count found, add to structure
				# Add summary counts
				$sumcount->{$1} += $count;

				# Add test-specific counts
				if (defined($testname))
				{
					$testcount->{$1} += $count;
				}

				# Store line checksum if available
				if (defined($3))
				{
					$line_checksum = substr($3, 1);

					# Does it match a previous definition
					if (defined($checkdata->{$1}) &&
					    ($checkdata->{$1} ne
					     $line_checksum))
					{
						die("ERROR: checksum mismatch ".
						    "at $filename:$1\n");
					}

					$checkdata->{$1} = $line_checksum;
				}
				last;
			};

			/^FN:(\d+),([^,]+)/ && do
			{
				# Function data found, add to structure
				$funcdata->{$2} = $1;

				# Also initialize function call data
				if (!defined($sumfnccount->{$2})) {
					$sumfnccount->{$2} = 0;
				}
				if (defined($testname))
				{
					if (!defined($testfnccount->{$2})) {
						$testfnccount->{$2} = 0;
					}
				}
				last;
			};

			/^FNDA:(\d+),([^,]+)/ && do
			{
				# Function call count found, add to structure
				# Add summary counts
				$sumfnccount->{$2} += $1;

				# Add test-specific counts
				if (defined($testname))
				{
					$testfnccount->{$2} += $1;
				}
				last;
			};
			/^end_of_record/ && do
			{
				# Found end of section marker
				if ($filename)
				{
					# Store current section data
					if (defined($testname))
					{
						$testdata->{$testname} =
							$testcount;
						$testfncdata->{$testname} =
							$testfnccount;
					}	

					set_info_entry($data, $testdata,
						       $sumcount, $funcdata,
						       $checkdata, $testfncdata,
						       $sumfnccount);
					$result{$filename} = $data;
					last;
				}
			};

			# default
			last;
		}
	}
	close(INFO_HANDLE);

	# Calculate hit and found values for lines and functions of each file
	foreach $filename (keys(%result))
	{
		$data = $result{$filename};

		($testdata, $sumcount, undef, undef, $testfncdata,
		 $sumfnccount) = get_info_entry($data);

		# Filter out empty files
		if (scalar(keys(%{$sumcount})) == 0)
		{
			delete($result{$filename});
			next;
		}
		# Filter out empty test cases
		foreach $testname (keys(%{$testdata}))
		{
			if (!defined($testdata->{$testname}) ||
			    scalar(keys(%{$testdata->{$testname}})) == 0)
			{
				delete($testdata->{$testname});
				delete($testfncdata->{$testname});
			}
		}

		$data->{"found"} = scalar(keys(%{$sumcount}));
		$hitcount = 0;

		foreach (keys(%{$sumcount}))
		{
			if ($sumcount->{$_} > 0) { $hitcount++; }
		}

		$data->{"hit"} = $hitcount;

		# Get found/hit values for function call data
		$data->{"f_found"} = scalar(keys(%{$sumfnccount}));
		$hitcount = 0;

		foreach (keys(%{$sumfnccount})) {
			if ($sumfnccount->{$_} > 0) {
				$hitcount++;
			}
		}
		$data->{"f_hit"} = $hitcount;
	}

	if (scalar(keys(%result)) == 0)
	{
		print("ERROR: no valid records found in tracefile $tracefile\n");
		return undef;
	}
	if ($negative)
	{
		warn("WARNING: negative counts found in tracefile ".
		     "$tracefile\n");
	}
	if ($changed_testname)
	{
		warn("WARNING: invalid characters removed from testname in ".
		     "tracefile $tracefile\n");
	}

	return(\%result);
}


#
# get_info_entry(hash_ref)
#
# Retrieve data from an entry of the structure generated by read_info_file().
# Return a list of references to hashes:
# (test data hash ref, sum count hash ref, funcdata hash ref, checkdata hash
#  ref, testfncdata hash ref, sumfnccount hash ref, lines found, lines hit,
#  functions found, functions hit)
#

sub get_info_entry($)
{
	my $testdata_ref = $_[0]->{"test"};
	my $sumcount_ref = $_[0]->{"sum"};
	my $funcdata_ref = $_[0]->{"func"};
	my $checkdata_ref = $_[0]->{"check"};
	my $testfncdata = $_[0]->{"testfnc"};
	my $sumfnccount = $_[0]->{"sumfnc"};
	my $lines_found = $_[0]->{"found"};
	my $lines_hit = $_[0]->{"hit"};
	my $f_found = $_[0]->{"f_found"};
	my $f_hit = $_[0]->{"f_hit"};

	return ($testdata_ref, $sumcount_ref, $funcdata_ref, $checkdata_ref,
		$testfncdata, $sumfnccount, $lines_found, $lines_hit,
		$f_found, $f_hit);
}


#
# set_info_entry(hash_ref, testdata_ref, sumcount_ref, funcdata_ref,
#                checkdata_ref, testfncdata_ref, sumfcncount_ref[,lines_found,
#                lines_hit, f_found, f_hit])
#
# Update the hash referenced by HASH_REF with the provided data references.
#

sub set_info_entry($$$$$$$;$$$$)
{
	my $data_ref = $_[0];

	$data_ref->{"test"} = $_[1];
	$data_ref->{"sum"} = $_[2];
	$data_ref->{"func"} = $_[3];
	$data_ref->{"check"} = $_[4];
	$data_ref->{"testfnc"} = $_[5];
	$data_ref->{"sumfnc"} = $_[6];

	if (defined($_[7])) { $data_ref->{"found"} = $_[7]; }
	if (defined($_[8])) { $data_ref->{"hit"} = $_[8]; }
	if (defined($_[9])) { $data_ref->{"f_found"} = $_[9]; }
	if (defined($_[10])) { $data_ref->{"f_hit"} = $_[10]; }
}


sub trim($)
{
	my $string = shift;
	$string =~ s/^\s+//;
	$string =~ s/\s+$//;
	return $string;
}


###### Start of differential modifications (add, subtract, compare, and sinks-related functionality)


sub print_debug($)
{
	my $msg = shift;
	print "[DEBUG] $msg" if(0);
}


sub calc_minset ($$)
{
	my $tracefile_dir = shift or die("Incorrect arguments to calc_minset()\n");
	my $analysis_callback = shift or die("Incorrect arguments to calc_minset()\n");
	my @tracefiles;
	
	my @minset_tracefiles; #array of abs. paths to the tracefiles that the $sumtotal_tracefile contains
	my $sumtotal_tracefile; #path to the tracefile that is going to be the running total of all of the minset tracefiles
	my $sumtotal_tracefile_data; # reference to the hash returned by read_info_file() for the $sumtotal_tracefile
	
	# find all the .info files in $tracefile_dir
	# TODO dont read into an array - too much memory use
	opendir DIR,$tracefile_dir or die "open directory '$tracefile_dir' failed : $!\n";
	for(readdir DIR) { push(@tracefiles, $tracefile_dir."/".$_) if /^\d{1,3}\.info$/; }
	closedir DIR or die "close directory failed : $!\n";

	# get the number of sinks for each tracefile
	my ($min, $min_tracefile, $max_tracefile, $max, $total, $num_processed) = (undef, undef, undef, undef, 0, 0);	

	foreach my $this_tracefile_path (@tracefiles) 
	{
		last if $num_processed >= 100;
		if($num_processed == 0) # first iteration
		{
			# create $sumtotal_tracefile (path) and $sumtotal_tracefile_data (tracefile data)
			# using the first tracefile in the set as a template
			$sumtotal_tracefile = "./minset_sumtotal.info"; #FIXME let the user choose this
			$sumtotal_tracefile_data = read_info_file($this_tracefile_path);
			
			# write the new $sumtotal_tracefile_data to the path $sumtotal_tracefile
			info("Writing total execution counts for entire minset to $sumtotal_tracefile\n");
			open(INFO_HANDLE, ">$sumtotal_tracefile") or die("ERROR: cannot write to $sumtotal_tracefile!\n");
			write_info_file(*INFO_HANDLE, $sumtotal_tracefile_data);
			close(*INFO_HANDLE);
			
		}
		
		# did the user want to limit the minset analysis to one source file?
		my $num_added = &$analysis_callback($sumtotal_tracefile, $this_tracefile_path, $limit_to_file_option);
		
		# does this iteration's tracefile add sinks/stmt coverage
		# (depending on $analysis_callback) to the minset?
		# the first tracefile is the template for the $sumtotal_tracefile, so it is part of the minset too
		if( ($num_added > 0) || ($num_processed == 0) )
		{
			# the tracefile $path adds sinks to the minset thus far,
			# add it to the minset ($sumtotal_tracefile and @minset_tracefiles)
			push(@minset_tracefiles, $this_tracefile_path);
			print "Adding $this_tracefile_path to minset.\n";
			
			# read the contents of this iteration's tracefile in order to add it to the sumtotal
			my $this_tracefile_data = read_info_file($this_tracefile_path);
			
			# $result is the result of the --add operation (execution counts are added)
			$sumtotal_tracefile_data = add_info($sumtotal_tracefile_data, $this_tracefile_data);
		}
		print "tracefile $this_tracefile_path: adds $num_added.\n";
		
		$num_processed++;
		
		# write the new $sumtotal_tracefile_data to the path $sumtotal_tracefile
		info("Writing total execution counts for entire minset to $sumtotal_tracefile\n");
		open(INFO_HANDLE, ">$sumtotal_tracefile") or die("ERROR: cannot write to $sumtotal_tracefile!\n");
		write_info_file(*INFO_HANDLE, $sumtotal_tracefile_data);
		close(*INFO_HANDLE);
	}
	
	# write a list of all of the tracefiles in the minset to a text file for reference
	open(MINSET_LIST, ">./minset.list.txt") or die("Cant write to ./minset.list.txt: $!");
	foreach $_ (@minset_tracefiles)
	{
		print MINSET_LIST $_."\n";
	}
	close(MINSET_LIST);
	
	return (\@minset_tracefiles, $sumtotal_tracefile);
}

# tracefile_adds_sinks(total_tracefile (path to .info), new_tracefile (path to .info)
#	* returns the number of sinks that new_tracefile adds to total_tracefile
sub tracefile_adds_sinks($$;$)
{
	my $total_tracefile = shift or die("tracefile_adds_sinks: specify two arguments");
	my $new_tracefile = shift or die("tracefile_adds_sinks: specify two arguments");
	my $limit_to_src_file = shift or undef;

	my $num_sinks_added=0; # return value: number of sinks that new_tracefile would add to the total_tracefile
	my $total_sinks_hit = sinks_hit($total_tracefile);
	my $new_sinks_hit = sinks_hit($new_tracefile);

	foreach my $file (keys(%{$total_sinks_hit}))
	{
		# did the user choose to limit the analysis to a single source code file?
		# if so, check to see if this is the source file they wanted-
		my $proceed = 0;
		if( defined($limit_to_src_file) && ($file eq $limit_to_src_file) )
		{
			$proceed = 1;
			
		} #otherwise, if they didn't specify a source file, proceed
		elsif(!defined($limit_to_src_file))
		{
			$proceed = 1;
		}
		
		if($proceed == 0)
		{
			next;
		}
		
		print_debug("Src file: '$file'\n");
		#TODO: add exists() checks in case we're comparing sinks_hit() for two different tracefiles
		foreach my $line_num (keys( %{ $total_sinks_hit->{$file} }) )
		{
			# for each ($line_num => $times_hit) in this src $file in the sinks_hit(total_tracefile)
			
			# undef means that the sink did not have coverage info.
			# for the purposes of this function, consider this equivalent to 0 hits.
			$total_sinks_hit->{$file}{$line_num} = 0 if( !defined($total_sinks_hit->{$file}{$line_num}) );
			$new_sinks_hit->{$file}{$line_num} = 0 if( !defined($new_sinks_hit->{$file}{$line_num}) );
			
			#print "\t[$line_num]: TOTAL TRACE: ".$total_sinks_hit->{$file}{$line_num}." hits\n";
			#print "\t[$line_num]: NEW TRACE  : ".$new_sinks_hit->{$file}{$line_num}." hits\n\n";
			
			# if the sink_line_num was hit zero times in the total_tracefile
			# and more than zero times in the new tracefile
			if( ($total_sinks_hit->{$file}{$line_num} <= 0) && ($new_sinks_hit->{$file}{$line_num} > 0) )
			{
				print "tracefile_adds_sinks(): new tracefile adds sinks to the total!\nfile ${file} [${line_num}]: ".$new_sinks_hit->{$file}{$line_num}."hits.\n\n";
				$num_sinks_added++;
			}
			else
			{
				#print "tracefile_adds_sinks(): this line does NOT add sinks to the total.\n"
			}
			
		}

	} # foreach my $file in the total_sinks_hit

	# how many sinks does the $new_tracefile add to the $total_tracefile?
	return $num_sinks_added;
}


# tracefile_adds_stmt(total_tracefile (path to .info), new_tracefile (path to .info)
#	* returns the number of lines covered that new_tracefile adds to total_tracefile
sub tracefile_adds_stmt($$;$)
{
	my $total_tracefile = shift or die("tracefile_adds_stmt: specify two arguments");
	my $new_tracefile = shift or die("tracefile_adds_stmt: specify two arguments");
	my $limit_to_src_file = shift or undef;

	my $num_lines_added=0; # return value: number of lines covered that new_tracefile would add to the total_tracefile
	# get statement coverage for both tracefiles
	my $total_data = read_info_file($total_tracefile); 
	my $new_data = read_info_file($new_tracefile);
	
	# check if read_info_file() returned undef (indicates TODO)
	my $filename;
	foreach $filename (keys(%{$total_data})) # for each file listed in the total .info file.
	{
		# ensure this $filename exists in $new_data too
		die "Comparing statement coverage of two different tracefiles! Must be from same codebase.\n" if(!exists($new_data->{$filename}));

		# did the user choose to limit the analysis to a single source code file?
		# if so, check to see if this is the source file they wanted-
		my $proceed = 0;
		if( defined($limit_to_src_file) && ($filename eq $limit_to_src_file) )
		{
			$proceed = 1;
			
		} #otherwise, if they didn't specify a source file, proceed
		elsif(!defined($limit_to_src_file))
		{
			$proceed = 1;
		}
		
		next if($proceed == 0);
		
		# see read_info_file() for documentation on the structure of $data
		
		my($total_lines_hit, $total_lines, $new_lines_hit, $new_lines) = (0, 0, 0, 0);
		
		# fill %result with the execution count totals for each line number (as key)
		foreach my $line (keys(%{$total_data->{$filename}{"sum"}}))
		{
			# ensure the line we're looking at exists in the new tracefile too
			die "Comparing statement coverage of two different tracefiles! Must be from same codebase.\n" if(!exists($new_data->{$filename}{"sum"}{$line}));
			
			# $total_count is the execution count for this $line of this $filename
			my $total_count = $total_data->{$filename}{"sum"}{$line};
			# $new_count is the execution count for this $line of this $filename
			my $new_count = $total_data->{$filename}{"sum"}{$line};
			
			if( ($total_count == 0) && ($new_count > 0) )
			{
				$num_lines_added++;
				print "New tracefile adds $filename [$line]: $new_count hits\n";
			}
			
			$total_lines_hit++ if($total_count > 0);
			$total_lines++;
			$new_lines_hit++ if($new_count > 0);
			$new_lines++;
		}
		
		#printf("$filename: total:%.2f-%%total %.2f-%%new\n", ($total_lines_hit/$total_lines)*100, ($new_lines_hit/$new_lines)*100);
	} # foreach filename in the total tracefile

	# how many sinks does the $new_tracefile add to the $total_tracefile?
	return $num_lines_added;
}

# function not currently functional..
# do not remove yet..
sub walk_tracefile($)
{
	# reference to.. TODO
	my $tracefile_path = shift;
	my $data = read_info_file($tracefile_path);
	
	# default to first .info file
	#my $result;
	#%{$result} = %{$data}; # %data, to return
	
	# get_info_entry return values
	my $found;
	my $hit;

	# contains line number -> execution count while we're iterating through each filename in this .info file 
	my $this_sumcount;
		
	# for each source code file in the tracefile (.info file)
	my $filename;
	foreach $filename (keys(%{$data})) # for each file listed in that .info file.
	{
		# see read_info_file() for documentation on the structure of $data
		# TODO: remove unused variables?
		# TODO: update function execution counts along with per-line counts
		my $testdata;
		my $sumcount;
		my $funcdata;
		my $checkdata;
		my $testfncdata;
		my $sumfnccount;
	
		# Retrieve data
		($testdata, $sumcount, $funcdata, $checkdata, $testfncdata,
		 $sumfnccount) = get_info_entry($data->{$filename});
		
		#print("test data for $filename:");
		#print Dumper($funcdata);
		#print("sum coubnt:");
		#print Dumper($sumcount);
		
		# use add_counts_mod to add the per line exec. hist. contained in $sumcount
		#TODO
		#$result->{$filename}->{"sum"} = add_counts_mod($this_test->{$filename}->{"sum"}, $last_test->{$filename}->{"sum"});
		
		# update $result->{$filename}->{"test"} to contain the correct values
#		my $test;
#		foreach $test (keys( %{$data->{$filename}->{"test"}} ))
#		{
#			# ensure the test we're looking at exists in the previous test
#			unless(defined($data->{$filename}->{"test"}->{$test}))
#			{
#				die("ERROR: test: when doing an --add, all .info files must come from the same source code!")
#			}
#			
#			my $line_num;
#			foreach $line_num (keys(%{ $data->{$filename}->{"test"}->{$test} }))
#			{
#				## FIXME
#				callback(\$data, \$filename, \$test, \$line_num);
#
#				$data->{$filename}->{"test"}->{$test}->{$line_num} = 1;#$new_exec_count;
#			}
#		}
	} # foreach $filename
	#return $result;
}


# may be used in the future in conjunction with walk_tracefile() above,
# this will probably get deleted sometime soon. Keep for now. Not functional either.
sub callback_add($$$$)
{
#	my $new_exec_count; # total execution count for both this and previous .info files
#
#	# ensure the line number we're looking at exists in the previous test
#	unless(defined($last_test->{$filename}->{"test"}->{$test}->{$line_num}))
#	{
#		die("ERROR: line_num: when doing an --add, all .info files must come from the same source code!")
#	}
#						
#	# compute the new total execution count and update our return hash
#	$new_exec_count = $last_test->{$filename}->{"test"}->{$test}->{$line_num} + $this_test->{$filename}->{"test"}->{$test}->{$line_num};
#	$result->{$filename}->{"test"}->{$test}->{$line_num} = $new_exec_count;
}



# rats must be in your path.
# Argument is a path to a source file that rats will generate a report for.
# returns: %ret_hash = {filename => (sink_line_num1, sink_line_num2, ..), ... }
sub get_rat_report($)
{
	my $count=0;
	my %ret_hash = (); # filename => (array of lines numbers with sinks), .. 
	my $source_path=shift;
	$source_path =~ s/ /\\ /g;
	my $execute="rats ".$source_path;
	my $rats_output=`$execute`;
	my @rat_data=split("\n",$rats_output);
	
	my $rat_line;
	foreach $rat_line (@rat_data)
	{
		my $filename;
		my $line_number;
		my $severity;
		my $vuln;
		
		#match any lines like :12:, no matter how large or small the number is.
		if ($rat_line =~ m|(.*):(\d+):\s*(\w+):\s*(.*)| )
		{
			($filename,$line_number,$severity,$vuln)=($1,$2,$3,$4); #TODO is $4 right?
			print_debug("$filename:$line_number - $severity: '$vuln'.\n");
			# store per-line sinks for each src file in the tracefile
			$ret_hash{$filename}[$count++] = $line_number;
			#{"fileName"=>$filename,"lineNumber"=>$lineNumber,"severity"=>$severity,"function"=>$function}
		}
	}
	print_debug("get_rat_report: Ret hash: \n");
	print_debug(Dumper(%ret_hash));
	print_debug("--------------------end ret hash-----------------------\n");
	return %ret_hash; # this is an array of values that correspond to line numbers with sinks
}


# sinks_hit(tracefile_path (path to .info))
# uses get_rat_report() to determine which sinks where hit for every src file in the tracefile specified,
# and then determines how many times each sink was hit. If no coverage data exists for a given sink, `undef`
# will be used as the number of times the sink was hit.
## returns: \%sinks_hit = {filename => {sink_line_num => num_times_hit, ...}, ...}
sub sinks_hit($)
{
	my $data= read_info_file($_[0]);
	my %sinks_per_file;
	my %sinks_hit = (); # {filename => {sink_line_num => num_times_hit, ...}, ... }
	my $total_hits=0;
	
	# List all files within this info file
	my $filename;
	foreach $filename (keys(%{$data}))
	{
		#if($filename ne "/home/grey/workspace/libtorrent-rasterbar-0.14.2/examples/client_test.cpp") {
		#	next;
		#}
		
		my $sumcount;
		my $found;
		my $hit = 0; # number of sinks covered
		# Retrieve data
		(undef, $sumcount, undef, undef, undef, undef,$found, $hit) = get_info_entry($data->{$filename});
		print_debug("sumcount for $filename:\n");
		foreach my $line_num (sort {$a <=> $b} keys(%$sumcount) )
		{
			print_debug("SUMCOUNT [$line_num] ".$sumcount->{$line_num}."\n");
		}
		
		%sinks_per_file=get_rat_report($filename);
		
		if (!exists($sinks_per_file{$filename}))
		{
			# no sinks were found for $filename.
			# indicate by setting to undef and skip the rest of this iteration
			$sinks_hit{$filename} = undef;
			next; # next $filenam
		}

		#print "sinks_per_file { $filename } exists - sinks hit:\n";
		my $i = 0;
		
		while ( defined($sinks_per_file{$filename}[$i]) )
		{
			my $sink_line_num = $sinks_per_file{$filename}[$i];
			#print_debug( Dumper($sink_line_num)."\n" );
			my $num_times_hit = $sumcount->{ ${sinks_per_file{$filename}[$i]} };
			
			#TODO: this search is inefficient, but I couldnt get the more sane way (that does 
			#            not involve a search) to work... damn you perl ...
			my $sink_times_hit = undef;
			while( my ($line_num, $times_hit) = each %$sumcount )
			{
				if($line_num eq $sink_line_num)
				{
					$sink_times_hit = $times_hit;
					print_debug("\nSink times hit: $line_num: hit $sink_times_hit times.\n");
					
					# was this sink hit more than once?
					if ($sink_times_hit > 0)
					{
						$total_hits++; # increase ret value: total number of sinks hit
					}
				}
			}
			
			$sinks_hit{$filename}{$sink_line_num} = $sink_times_hit; # even if its undef (line not instrumented)
			
			$i++;
		}
	} # foreach $filename
	print_debug( "sinks_hit(): sinks_hit = ".Dumper(%sinks_hit)."------------------\n");
	return \%sinks_hit;
}

# add_info(\%dataref1, |%dataref2)
#	* use read_info_file to get %dataref1 and %dataref2
#	* returns \%result, which contains the total execution history counts for both info files specified
#         (eg, %dataref1 + %dataref2 = %result (return value))
sub add_info($$)
{
	my @datarefs; # array of \%data references, one for each .info file to process
	# NOTE: this is an array so that we can easily expand this to support addition of multiple .info files
	$datarefs[0] = $_[0];
	$datarefs[1] = $_[1];
	
	# default to first .info file
	my $result;
	%{$result} = %{$datarefs[0]}; # %data, to return
		
	# get_info_entry return values
	my $found;
	my $hit;

	# contains line number -> execution count while we're iterating through each filename in this .info file 
	my $this_sumcount ; 
		
	# for each .info file to add execution counts for
	my $data;
	my $i = 0; # index to @datarefs
	foreach $data (@datarefs) # for each .info file. (should only be two for now)
	{
		my $filename;
		foreach $filename (keys(%{$data})) # for each file listed in that .info file.
		{
			# see read_info_file() for documentation on the structure of $data
			# TODO: remove unused variables?
			# TODO: update function execution counts along with per-line counts
			my $testdata;
			my $sumcount;
			my $funcdata;
			my $checkdata;
			my $testfncdata;
			my $sumfnccount;
		
			# Retrieve data
			($testdata, $sumcount, $funcdata, $checkdata, $testfncdata,
			 $sumfnccount) = get_info_entry($data->{$filename});
			
			if($i >= 1) # if we are not processing the first .info file:
			{
				my $this_test = $datarefs[$i];
				my $last_test = $datarefs[$i-1];
				
				# use add_counts_mod to add the per line exec. hist. contained in $sumcount
				$result->{$filename}->{"sum"} = add_counts_mod($this_test->{$filename}->{"sum"}, $last_test->{$filename}->{"sum"});
				
				# update $result->{$filename}->{"test"} to contain the correct values
				my $test;
				foreach $test (keys( %{$this_test->{$filename}->{"test"}} ))
				{
					# ensure the test we're looking at exists in the previous test
					unless(defined($last_test->{$filename}->{"test"}->{$test}))
					{
						die("ERROR: test: when doing an --add, all .info files must come from the same source code!")
					}
					
					my $line_num;
					foreach $line_num (keys(%{ $this_test->{$filename}->{"test"}->{$test} }))
					{
						my $new_exec_count; # total execution count for both this and previous .info files

						# ensure the line number we're looking at exists in the previous test
						unless(defined($last_test->{$filename}->{"test"}->{$test}->{$line_num}))
						{
							die("ERROR: line_num: when doing an --add, all .info files must come from the same source code!")
						}
						
						# compute the new total execution count and update our return hash
						$new_exec_count = $last_test->{$filename}->{"test"}->{$test}->{$line_num} + $this_test->{$filename}->{"test"}->{$test}->{$line_num};
						$result->{$filename}->{"test"}->{$test}->{$line_num} = $new_exec_count;
					}
				}
			}
			
		}
		$i++;
	}
	return $result;
}


# add_counts_mod(data1_ref, data2_ref):
# 	* data1_ref and data2_ref are references to the %sumcount portion of the
# 	  data structure returned by read_info_file().
#       * Returns a reference to a %sumcount hash containing the same data structure 
#         as the args, but with the execution counts modified to be the total of data1_ref and data2_ref counts.
#
# NOTE: this function is very similar to add_counts(), but this function is used
#       to add two tracefiles that are generated from the same code base. Alternatively,
#       add_counts() can be used if you want to add tracefiles that may contain differing
#       coverage data (lines that are unique to one tracefile will be included in the result)
sub add_counts_mod($$)
{
	my %data1 = %{$_[0]};	# Hash 1
	my %data2 = %{$_[1]};	# Hash 2
	my %result;		# Resulting hash - contains line number -> total_execution_count
	my $line;		        # Current line iteration scalar
	my $data1_count;	# Execution count of line in hash1
	my $data2_count;	# Execution count of line in hash2
	my $data_total;       # = $data1_count+$data2_count
	my $found = 0;	# Total number of lines found - CURRENTLY UNUSED
	my $hit = 0;		# Number of lines with a count > 0 - CURRENTLY UNUSED
	
	# fill %result with the execution count totals for each line number (as key)
	foreach $line (keys(%data1))
	{
		# $data1_count is the execution count of this $line in this the $data1 hash/file
		$data1_count = $data1{$line};
		# $data2_count is the execution count of this $line in the $data2 hash/file
		$data2_count = $data2{$line};

		# Add counts if present in both hashes
		if (defined($data2_count))
		{ 
			$data_total = $data1_count + $data2_count;
		} else 
		{
			# TODO: this condition should not happen, we should be working with identical code, error condition?
			die("Warning: only use add_counts_mod() with %data1 and %data2 having identical line numbers (same code)\n");
		}
			
		# Store sum in %result
		$result{$line} = $data_total;

		$found++;
		if ($data1_count > 0) { $hit++; }
	}

	# Note: we do not add lines that are unique to either dataset, like the original did in certain conditions

	return \%result;
}


# subtract_counts_mod(\%data_ref, \%base_ref):
# 	* %data_ref and %base_ref are references to the %sumcount portion of the
# 	  data structure returned by read_info_file().
#       * Returns a reference to a %sumcount hash containing the same data structure 
#         as the args, but with the execution counts modified to be $data_ref - %base_ref.
sub subtract_counts_mod($$)
{
	my %data = %{$_[0]}; # dataset with more coverage
	my %base = %{$_[1]}; # 'baseline' dataset
	my $line;  		      # Current line iteration scalar
	my $data_count;           # Execution count of line in data
	my $base_count;           # Execution count of line in base
	my $hit = 0;                   # Total number of lines found - CURRENTLY UNUSED
	my $found = 0;              # Number of lines with a count > 0 - CURRENTLY UNUSED

	foreach $line (keys(%data))
	{
		$found++;
		$data_count = $data{$line};
		$base_count = $base{$line};

		if (defined($base_count))
		{
			$data_count -= $base_count;

			# Make sure we don't get negative numbers
			if ($data_count<0) { $data_count = 0; }
		} else
		{
			# TODO: this condition should not happen, we should be working with identical code, error condition?
			die("Warning: only use subtract_counts_mod() with %data and %base having identical line numbers (same code)\n");
		}

		$data{$line} = $data_count;
		if ($data_count > 0) { $hit++; }
	}

	return \%data;
}


# compare_info(dataref1, dataref2)
# Both args are references to %data, the hash returned by read_info_file.
# This function is comparing the statement coverage of dataref1 and dataref2:
# GREATER_THAN, LESS_THAN, or EQUAL are constants used to denote the result of this comparison.
# Because each .info file contains data for several files, we break down the comparison
# in terms of the *total* coverage of dataref1 vs dataref2 AND in terms of per-function coverage.
# returns ($total_coverage, %per_func_coverage)
# where $total_coverage is GREATER_THAN, LESS_THAN, or EQUAL
# where %per_func_coverage is  {$filename1 => GREATER_THAN, $filename2 => EQUAL, ...etc}
sub compare_info($$)
{
	my $data1 = read_info_file($_[0]);
	my $data2 = read_info_file($_[1]);
	my $found;
	my $hit;
	
	# @total_hits is the total found and hit for $data1 and $data[2]
	# @total_hits = ({"found" => $found, "hit" => $hit}, {"found" => $found,  "hit" => $hit}})
	my @total_hits;
	my $filename;
	
	my $total_comparison; # either GREATER_THAN, LESS_THAN, or EQUAL - the results of comparing the two .info files

	# this is the results of the comparison of the coverage of $data1 and $data2
	# $func_cov_comparison{$filename} = GREATHER_THAN, LESS_THAN, or EQUAL
	my %func_cov_comparison;

	# @coverage contains coverage results for $data1 & $data2 (our two .info files to cmp.)
	# $coverage[0] = {$filename => {"found" => $found, "hit" => $hit}}}
	my @coverage;    
	$coverage[0] = $coverage[1] = undef;

	info("Comparing trace (.info) files...\n");

	# For both of the info files we're comparing
	my $data;
	my $data_i;
	$data_i = 0;
	foreach $data ($data1, $data2)
	{
		# List all files within this info file
		foreach $filename (keys(%{$data}))
		{
			my $entry = $data->{$filename};
			(undef, undef, undef, undef, undef, undef, $found, $hit) = get_info_entry($entry);
			printf("$filename: $hit of $found lines hit\n");

			# set the found/hit hash for each filename in each .info file
			$coverage[$data_i]{$filename} = {"found" => $found, "hit" => $hit, "percentage" => $hit/$found }; 

			# if this is the 2nd info file, $data2
			if($data_i == 1)
			{
				# compare the coverage for each $filename in each .info file
				if($coverage[0]{$filename}{"percentage"} > $coverage[1]{$filename}{"percentage"})
				{
					$func_cov_comparison{$filename} = GREATER_THAN;
				} elsif($coverage[0]{$filename}{"percentage"} < $coverage[1]{$filename}{"percentage"}) 
				{
					$func_cov_comparison{$filename} = LESS_THAN;
				} else
				{
					$func_cov_comparison{$filename} = EQUAL;
				}
			}
			
			$total_hits[$data_i]{"hit"} += $hit;
			$total_hits[$data_i]{"found"} += $found;
		}
		$data_i += 1;
	}

	if($total_hits[0]{"hit"} > $total_hits[1]{"hit"})
	{
		$total_comparison = GREATER_THAN;

	} elsif($total_hits[0]{"hit"} < $total_hits[1]{"hit"})
	{
		$total_comparison = LESS_THAN;
	} else 
	{
		$total_comparison =  EQUAL;
	}

	return ($total_comparison, %func_cov_comparison)
}


########################################################################
### End differential mods..
########################################################################


#
# add_counts(data1_ref, data2_ref)
#
# DATA1_REF and DATA2_REF are references to hashes containing a mapping
#
#   line number -> execution count
#
# Return a list (RESULT_REF, LINES_FOUND, LINES_HIT) where RESULT_REF
# is a reference to a hash containing the combined mapping in which
# execution counts are added.
#

sub add_counts($$)
{
	my %data1 = %{$_[0]};	# Hash 1
	my %data2 = %{$_[1]};	# Hash 2
	my %result;		# Resulting hash
	my $line;		# Current line iteration scalar
	my $data1_count;	# Count of line in hash1
	my $data2_count;	# Count of line in hash2
	my $found = 0;		# Total number of lines found
	my $hit = 0;		# Number of lines with a count > 0

	foreach $line (keys(%data1))
	{
		$data1_count = $data1{$line};
		$data2_count = $data2{$line};

		# Add counts if present in both hashes
		if (defined($data2_count)) { $data1_count += $data2_count; }

		# Store sum in %result
		$result{$line} = $data1_count;

		$found++;
		if ($data1_count > 0) { $hit++; }
	}

	# Add lines unique to data2
	foreach $line (keys(%data2))
	{
		# Skip lines already in data1
		if (defined($data1{$line})) { next; }

		# Copy count from data2
		$result{$line} = $data2{$line};

		$found++;
		if ($result{$line} > 0) { $hit++; }
	}

	return (\%result, $found, $hit);
}



#
# merge_checksums(ref1, ref2, filename)
#
# REF1 and REF2 are references to hashes containing a mapping
#
#   line number -> checksum
#
# Merge checksum lists defined in REF1 and REF2 and return reference to
# resulting hash. Die if a checksum for a line is defined in both hashes
# but does not match.
#

sub merge_checksums($$$)
{
	my $ref1 = $_[0];
	my $ref2 = $_[1];
	my $filename = $_[2];
	my %result;
	my $line;

	foreach $line (keys(%{$ref1}))
	{
		if (defined($ref2->{$line}) &&
		    ($ref1->{$line} ne $ref2->{$line}))
		{
			die("ERROR: checksum mismatch at $filename:$line\n");
		}
		$result{$line} = $ref1->{$line};
	}

	foreach $line (keys(%{$ref2}))
	{
		$result{$line} = $ref2->{$line};
	}

	return \%result;
}


#
# merge_func_data(funcdata1, funcdata2, filename)
#

sub merge_func_data($$$)
{
	my ($funcdata1, $funcdata2, $filename) = @_;
	my %result;
	my $func;

	%result = %{$funcdata1};

	foreach $func (keys(%{$funcdata2})) {
		my $line1 = $result{$func};
		my $line2 = $funcdata2->{$func};

		if (defined($line1) && ($line1 != $line2)) {
			warn("WARNING: function data mismatch at ".
			     "$filename:$line2\n");
			next;
		}
		$result{$func} = $line2;
	}

	return \%result;
}


#
# add_fnccount(fnccount1, fnccount2)
#
# Add function call count data. Return list (fnccount_added, f_found, f_hit)
#

sub add_fnccount($$)
{
	my ($fnccount1, $fnccount2) = @_;
	my %result;
	my $f_found;
	my $f_hit;
	my $function;

	%result = %{$fnccount1};
	foreach $function (keys(%{$fnccount2})) {
		$result{$function} += $fnccount2->{$function};
	}
	$f_found = scalar(keys(%result));
	$f_hit = 0;
	foreach $function (keys(%result)) {
		if ($result{$function} > 0) {
			$f_hit++;
		}
	}

	return (\%result, $f_found, $f_hit);
}

#
# add_testfncdata(testfncdata1, testfncdata2)
#
# Add function call count data for several tests. Return reference to
# added_testfncdata.
#

sub add_testfncdata($$)
{
	my ($testfncdata1, $testfncdata2) = @_;
	my %result;
	my $testname;

	foreach $testname (keys(%{$testfncdata1})) {
		if (defined($testfncdata2->{$testname})) {
			my $fnccount;

			# Function call count data for this testname exists
			# in both data sets: merge
			($fnccount) = add_fnccount(
				$testfncdata1->{$testname},
				$testfncdata2->{$testname});
			$result{$testname} = $fnccount;
			next;
		}
		# Function call count data for this testname is unique to
		# data set 1: copy
		$result{$testname} = $testfncdata1->{$testname};
	}

	# Add count data for testnames unique to data set 2
	foreach $testname (keys(%{$testfncdata2})) {
		if (!defined($result{$testname})) {
			$result{$testname} = $testfncdata2->{$testname};
		}
	}
	return \%result;
}

#
# combine_info_entries(entry_ref1, entry_ref2, filename)
#
# Combine .info data entry hashes referenced by ENTRY_REF1 and ENTRY_REF2.
# Return reference to resulting hash.
#

sub combine_info_entries($$$)
{
	my $entry1 = $_[0];	# Reference to hash containing first entry
	my $testdata1;
	my $sumcount1;
	my $funcdata1;
	my $checkdata1;
	my $testfncdata1;
	my $sumfnccount1;

	my $entry2 = $_[1];	# Reference to hash containing second entry
	my $testdata2;
	my $sumcount2;
	my $funcdata2;
	my $checkdata2;
	my $testfncdata2;
	my $sumfnccount2;

	my %result;		# Hash containing combined entry
	my %result_testdata;
	my $result_sumcount = {};
	my $result_funcdata;
	my $result_testfncdata;
	my $result_sumfnccount;
	my $lines_found;
	my $lines_hit;
	my $f_found;
	my $f_hit;

	my $testname;
	my $filename = $_[2];

	# Retrieve data
	($testdata1, $sumcount1, $funcdata1, $checkdata1, $testfncdata1,
	 $sumfnccount1) = get_info_entry($entry1);
	($testdata2, $sumcount2, $funcdata2, $checkdata2, $testfncdata2,
	 $sumfnccount2) = get_info_entry($entry2);

	# Merge checksums
	$checkdata1 = merge_checksums($checkdata1, $checkdata2, $filename);

	# Combine funcdata
	$result_funcdata = merge_func_data($funcdata1, $funcdata2, $filename);

	# Combine function call count data
	$result_testfncdata = add_testfncdata($testfncdata1, $testfncdata2);
	($result_sumfnccount, $f_found, $f_hit) =
		add_fnccount($sumfnccount1, $sumfnccount2);
	
	# Combine testdata
	foreach $testname (keys(%{$testdata1}))
	{
		if (defined($testdata2->{$testname}))
		{
			# testname is present in both entries, requires
			# combination
			($result_testdata{$testname}) =
				add_counts($testdata1->{$testname},
					   $testdata2->{$testname});
		}
		else
		{
			# testname only present in entry1, add to result
			$result_testdata{$testname} = $testdata1->{$testname};
		}

		# update sum count hash
		($result_sumcount, $lines_found, $lines_hit) =
			add_counts($result_sumcount,
				   $result_testdata{$testname});
	}

	foreach $testname (keys(%{$testdata2}))
	{
		# Skip testnames already covered by previous iteration
		if (defined($testdata1->{$testname})) { next; }

		# testname only present in entry2, add to result hash
		$result_testdata{$testname} = $testdata2->{$testname};

		# update sum count hash
		($result_sumcount, $lines_found, $lines_hit) =
			add_counts($result_sumcount,
				   $result_testdata{$testname});
	}
	
	# Calculate resulting sumcount

	# Store result
	set_info_entry(\%result, \%result_testdata, $result_sumcount,
		       $result_funcdata, $checkdata1, $result_testfncdata,
		       $result_sumfnccount, $lines_found, $lines_hit,
		       $f_found, $f_hit);

	return(\%result);
}


#
# combine_info_files(info_ref1, info_ref2)
#
# Combine .info data in hashes referenced by INFO_REF1 and INFO_REF2. Return
# reference to resulting hash.
#

sub combine_info_files($$)
{
	my %hash1 = %{$_[0]};
	my %hash2 = %{$_[1]};
	my $filename;

	foreach $filename (keys(%hash2))
	{
		if ($hash1{$filename})
		{
			# Entry already exists in hash1, combine them
			$hash1{$filename} =
				combine_info_entries($hash1{$filename},
						     $hash2{$filename},
						     $filename);
		}
		else
		{
			# Entry is unique in both hashes, simply add to
			# resulting hash
			$hash1{$filename} = $hash2{$filename};
		}
	}

	return(\%hash1);
}


#
# add_traces()
#

sub add_traces()
{
	my $total_trace;
	my $current_trace;
	my $tracefile;
	local *INFO_HANDLE;

	info("Combining tracefiles.\n");

	foreach $tracefile (@add_tracefile)
	{
		$current_trace = read_info_file($tracefile);
		if ($total_trace)
		{
			$total_trace = combine_info_files($total_trace,
							  $current_trace);
		}
		else
		{
			$total_trace = $current_trace;
		}
	}

	# Write combined data
	if ($to_file)
	{
		info("Writing data to $output_filename\n");
		open(INFO_HANDLE, ">$output_filename")
			or die("ERROR: cannot write to $output_filename!\n");
		write_info_file(*INFO_HANDLE, $total_trace);
		close(*INFO_HANDLE);
	}
	else
	{
		write_info_file(*STDOUT, $total_trace);
	}
}


#
# write_info_file(filehandle, data)
#

sub write_info_file(*$)
{
	local *INFO_HANDLE = $_[0];
	my %data = %{$_[1]};
	my $source_file;
	my $entry;
	my $testdata;
	my $sumcount;
	my $funcdata;
	my $checkdata;
	my $testfncdata;
	my $sumfnccount;
	my $testname;
	my $line;
	my $func;
	my $testcount;
	my $testfnccount;
	my $found;
	my $hit;
	my $f_found;
	my $f_hit;

	foreach $source_file (keys(%data))
	{
		$entry = $data{$source_file};
		($testdata, $sumcount, $funcdata, $checkdata, $testfncdata,
		 $sumfnccount) = get_info_entry($entry);
		foreach $testname (keys(%{$testdata}))
		{
			$testcount = $testdata->{$testname};
			$testfnccount = $testfncdata->{$testname};
			$found = 0;
			$hit   = 0;

			print(INFO_HANDLE "TN:$testname\n");
			print(INFO_HANDLE "SF:$source_file\n");

			# Write function related data
			foreach $func (
				sort({$funcdata->{$a} <=> $funcdata->{$b}}
				keys(%{$funcdata})))
			{
				print(INFO_HANDLE "FN:".$funcdata->{$func}.
				      ",$func\n");
			}
			foreach $func (keys(%{$testfnccount})) {
				print(INFO_HANDLE "FNDA:".
				      $testfnccount->{$func}.
				      ",$func\n");
			}
			($f_found, $f_hit) =
				get_func_found_and_hit($testfnccount);
			print(INFO_HANDLE "FNF:$f_found\n");
			print(INFO_HANDLE "FNH:$f_hit\n");

			# Write line related data
			foreach $line (sort({$a <=> $b} keys(%{$testcount})))
			{
				print(INFO_HANDLE "DA:$line,".
				      $testcount->{$line}.
				      (defined($checkdata->{$line}) &&
				       $checksum ?
				       ",".$checkdata->{$line} : "")."\n");
				$found++;
				if ($testcount->{$line} > 0)
				{
					$hit++;
				}

			}
			print(INFO_HANDLE "LF:$found\n");
			print(INFO_HANDLE "LH:$hit\n");
			print(INFO_HANDLE "end_of_record\n");
		}
	}
}


#
# transform_pattern(pattern)
#
# Transform shell wildcard expression to equivalent PERL regular expression.
# Return transformed pattern.
#

sub transform_pattern($)
{
	my $pattern = $_[0];

	# Escape special chars

	$pattern =~ s/\\/\\\\/g;
	$pattern =~ s/\//\\\//g;
	$pattern =~ s/\^/\\\^/g;
	$pattern =~ s/\$/\\\$/g;
	$pattern =~ s/\(/\\\(/g;
	$pattern =~ s/\)/\\\)/g;
	$pattern =~ s/\[/\\\[/g;
	$pattern =~ s/\]/\\\]/g;
	$pattern =~ s/\{/\\\{/g;
	$pattern =~ s/\}/\\\}/g;
	$pattern =~ s/\./\\\./g;
	$pattern =~ s/\,/\\\,/g;
	$pattern =~ s/\|/\\\|/g;
	$pattern =~ s/\+/\\\+/g;
	$pattern =~ s/\!/\\\!/g;

	# Transform ? => (.) and * => (.*)

	$pattern =~ s/\*/\(\.\*\)/g;
	$pattern =~ s/\?/\(\.\)/g;

	return $pattern;
}


#
# extract()
#

sub extract()
{
	my $data = read_info_file($extract);
	my $filename;
	my $keep;
	my $pattern;
	my @pattern_list;
	my $extracted = 0;
	local *INFO_HANDLE;

	# Need perlreg expressions instead of shell pattern
	@pattern_list = map({ transform_pattern($_); } @ARGV);

	# Filter out files which do not match any pattern
	foreach $filename (sort(keys(%{$data})))
	{
		$keep = 0;

		foreach $pattern (@pattern_list)
		{
			$keep ||= ($filename =~ (/^$pattern$/));
		}


		if (!$keep)
		{
			delete($data->{$filename});
		}
		else
		{
			info("Extracting $filename\n"),
			$extracted++;
		}
	}

	# Write extracted data
	if ($to_file)
	{
		info("Extracted $extracted files\n");
		info("Writing data to $output_filename\n");
		open(INFO_HANDLE, ">$output_filename")
			or die("ERROR: cannot write to $output_filename!\n");
		write_info_file(*INFO_HANDLE, $data);
		close(*INFO_HANDLE);
	}
	else
	{
		write_info_file(*STDOUT, $data);
	}
}


#
# remove()
#

sub remove()
{
	my $data = read_info_file($remove);
	my $filename;
	my $match_found;
	my $pattern;
	my @pattern_list;
	my $removed = 0;
	local *INFO_HANDLE;

	# Need perlreg expressions instead of shell pattern
	@pattern_list = map({ transform_pattern($_); } @ARGV);

	# Filter out files that match the pattern
	foreach $filename (sort(keys(%{$data})))
	{
		$match_found = 0;

		foreach $pattern (@pattern_list)
		{
			$match_found ||= ($filename =~ (/$pattern$/));
		}


		if ($match_found)
		{
			delete($data->{$filename});
			info("Removing $filename\n"),
			$removed++;
		}
	}

	# Write data
	if ($to_file)
	{
		info("Deleted $removed files\n");
		info("Writing data to $output_filename\n");
		open(INFO_HANDLE, ">$output_filename")
			or die("ERROR: cannot write to $output_filename!\n");
		write_info_file(*INFO_HANDLE, $data);
		close(*INFO_HANDLE);
	}
	else
	{
		write_info_file(*STDOUT, $data);
	}
}


#
# list()
#

sub list()
{
	my $data = read_info_file($list);
	my $filename;
	my $found;
	my $hit;
	my $entry;

	info("Listing contents of $list:\n");

	# List all files
	foreach $filename (sort(keys(%{$data})))
	{
		$entry = $data->{$filename};
		(undef, undef, undef, undef, undef, undef, $found, $hit) =
			get_info_entry($entry);
		printf("$filename: $hit of $found lines hit\n");
	}
}


#
# get_common_filename(filename1, filename2)
#
# Check for filename components which are common to FILENAME1 and FILENAME2.
# Upon success, return
#
#   (common, path1, path2)
#
#  or 'undef' in case there are no such parts.
#

sub get_common_filename($$)
{
        my @list1 = split("/", $_[0]);
        my @list2 = split("/", $_[1]);
	my @result;

	# Work in reverse order, i.e. beginning with the filename itself
	while (@list1 && @list2 && ($list1[$#list1] eq $list2[$#list2]))
	{
		unshift(@result, pop(@list1));
		pop(@list2);
	}

	# Did we find any similarities?
	if (scalar(@result) > 0)
	{
	        return (join("/", @result), join("/", @list1),
			join("/", @list2));
	}
	else
	{
		return undef;
	}
}


#
# strip_directories($path, $depth)
#
# Remove DEPTH leading directory levels from PATH.
#

sub strip_directories($$)
{
	my $filename = $_[0];
	my $depth = $_[1];
	my $i;

	if (!defined($depth) || ($depth < 1))
	{
		return $filename;
	}
	for ($i = 0; $i < $depth; $i++)
	{
		$filename =~ s/^[^\/]*\/+(.*)$/$1/;
	}
	return $filename;
}


#
# read_diff(filename)
#
# Read diff output from FILENAME to memory. The diff file has to follow the
# format generated by 'diff -u'. Returns a list of hash references:
#
#   (mapping, path mapping)
#
#   mapping:   filename -> reference to line hash
#   line hash: line number in new file -> corresponding line number in old file
#
#   path mapping:  filename -> old filename
#
# Die in case of error.
#

sub read_diff($)
{
	my $diff_file = $_[0];	# Name of diff file
	my %diff;		# Resulting mapping filename -> line hash
	my %paths;		# Resulting mapping old path  -> new path
	my $mapping;		# Reference to current line hash
	my $line;		# Contents of current line
	my $num_old;		# Current line number in old file
	my $num_new;		# Current line number in new file
	my $file_old;		# Name of old file in diff section
	my $file_new;		# Name of new file in diff section
	my $filename;		# Name of common filename of diff section
	my $in_block = 0;	# Non-zero while we are inside a diff block
	local *HANDLE;		# File handle for reading the diff file

	info("Reading diff $diff_file\n");

	# Check if file exists and is readable
	stat($diff_file);
	if (!(-r _))
	{
		die("ERROR: cannot read file $diff_file!\n");
	}

	# Check if this is really a plain file
	if (!(-f _))
	{
		die("ERROR: not a plain file: $diff_file!\n");
	}

	# Check for .gz extension
	if ($diff_file =~ /\.gz$/)
	{
		# Check for availability of GZIP tool
		system_no_output(1, "gunzip", "-h")
			and die("ERROR: gunzip command not available!\n");

		# Check integrity of compressed file
		system_no_output(1, "gunzip", "-t", $diff_file)
			and die("ERROR: integrity check failed for ".
				"compressed file $diff_file!\n");

		# Open compressed file
		open(HANDLE, "gunzip -c $diff_file|")
			or die("ERROR: cannot start gunzip to decompress ".
			       "file $_[0]!\n");
	}
	else
	{
		# Open decompressed file
		open(HANDLE, $diff_file)
			or die("ERROR: cannot read file $_[0]!\n");
	}

	# Parse diff file line by line
	while (<HANDLE>)
	{
		chomp($_);
		$line = $_;

		foreach ($line)
		{
			# Filename of old file:
			# --- <filename> <date>
			/^--- (\S+)/ && do
			{
				$file_old = strip_directories($1, $strip);
				last;
			};
			# Filename of new file:
			# +++ <filename> <date>
			/^\+\+\+ (\S+)/ && do
			{
				# Add last file to resulting hash
				if ($filename)
				{
					my %new_hash;
					$diff{$filename} = $mapping;
					$mapping = \%new_hash;
				}
				$file_new = strip_directories($1, $strip);
				$filename = $file_old;
				$paths{$filename} = $file_new;
				$num_old = 1;
				$num_new = 1;
				last;
			};
			# Start of diff block:
			# @@ -old_start,old_num, +new_start,new_num @@
			/^\@\@\s+-(\d+),(\d+)\s+\+(\d+),(\d+)\s+\@\@$/ && do
			{
			$in_block = 1;
			while ($num_old < $1)
			{
				$mapping->{$num_new} = $num_old;
				$num_old++;
				$num_new++;
			}
			last;
			};
			# Unchanged line
			# <line starts with blank>
			/^ / && do
			{
				if ($in_block == 0)
				{
					last;
				}
				$mapping->{$num_new} = $num_old;
				$num_old++;
				$num_new++;
				last;
			};
			# Line as seen in old file
			# <line starts with '-'>
			/^-/ && do
			{
				if ($in_block == 0)
				{
					last;
				}
				$num_old++;
				last;
			};
			# Line as seen in new file
			# <line starts with '+'>
			/^\+/ && do
			{
				if ($in_block == 0)
				{
					last;
				}
				$num_new++;
				last;
			};
			# Empty line
			/^$/ && do
			{
				if ($in_block == 0)
				{
					last;
				}
				$mapping->{$num_new} = $num_old;
				$num_old++;
				$num_new++;
				last;
			};
		}
	}

	close(HANDLE);

	# Add final diff file section to resulting hash
	if ($filename)
	{
		$diff{$filename} = $mapping;
	}

	if (!%diff)
	{
		die("ERROR: no valid diff data found in $diff_file!\n".
		    "Make sure to use 'diff -u' when generating the diff ".
		    "file.\n");
	}
	return (\%diff, \%paths);
}


#
# apply_diff($count_data, $line_hash)
#
# Transform count data using a mapping of lines:
#
#   $count_data: reference to hash: line number -> data
#   $line_hash:  reference to hash: line number new -> line number old
#
# Return a reference to transformed count data.
#

sub apply_diff($$)
{
	my $count_data = $_[0];	# Reference to data hash: line -> hash
	my $line_hash = $_[1];	# Reference to line hash: new line -> old line
	my %result;		# Resulting hash
	my $last_new = 0;	# Last new line number found in line hash
	my $last_old = 0;	# Last old line number found in line hash

	# Iterate all new line numbers found in the diff
	foreach (sort({$a <=> $b} keys(%{$line_hash})))
	{
		$last_new = $_;
		$last_old = $line_hash->{$last_new};

		# Is there data associated with the corresponding old line?
		if (defined($count_data->{$line_hash->{$_}}))
		{
			# Copy data to new hash with a new line number
			$result{$_} = $count_data->{$line_hash->{$_}};
		}
	}
	# Transform all other lines which come after the last diff entry
	foreach (sort({$a <=> $b} keys(%{$count_data})))
	{
		if ($_ <= $last_old)
		{
			# Skip lines which were covered by line hash
			next;
		}
		# Copy data to new hash with an offset
		$result{$_ + ($last_new - $last_old)} = $count_data->{$_};
	}

	return \%result;
}


#
# get_hash_max(hash_ref)
#
# Return the highest integer key from hash.
#

sub get_hash_max($)
{
	my ($hash) = @_;
	my $max;

	foreach (keys(%{$hash})) {
		if (!defined($max)) {
			$max = $_;
		} elsif ($hash->{$_} > $max) {
			$max = $_;
		}
	}
	return $max;
}

sub get_hash_reverse($)
{
	my ($hash) = @_;
	my %result;

	foreach (keys(%{$hash})) {
		$result{$hash->{$_}} = $_;
	}

	return \%result;
}

#
# apply_diff_to_funcdata(funcdata, line_hash)
#

sub apply_diff_to_funcdata($$)
{
	my ($funcdata, $linedata) = @_;
	my $last_new = get_hash_max($linedata);
	my $last_old = $linedata->{$last_new};
	my $func;
	my %result;
	my $line_diff = get_hash_reverse($linedata);

	foreach $func (keys(%{$funcdata})) {
		my $line = $funcdata->{$func};

		if (defined($line_diff->{$line})) {
			$result{$func} = $line_diff->{$line};
		} elsif ($line > $last_old) {
			$result{$func} = $line + $last_new - $last_old;
		}
	}

	return \%result;
}


#
# get_line_hash($filename, $diff_data, $path_data)
#
# Find line hash in DIFF_DATA which matches FILENAME. On success, return list
# line hash. or undef in case of no match. Die if more than one line hashes in
# DIFF_DATA match.
#

sub get_line_hash($$$)
{
	my $filename = $_[0];
	my $diff_data = $_[1];
	my $path_data = $_[2];
	my $conversion;
	my $old_path;
	my $new_path;
	my $diff_name;
	my $common;
	my $old_depth;
	my $new_depth;

	foreach (keys(%{$diff_data}))
	{
		# Try to match diff filename with filename
		if ($filename =~ /^\Q$diff_path\E\/$_$/)
		{
			if ($diff_name)
			{
				# Two files match, choose the more specific one
				# (the one with more path components)
				$old_depth = ($diff_name =~ tr/\///);
				$new_depth = (tr/\///);
				if ($old_depth == $new_depth)
				{
					die("ERROR: diff file contains ".
					    "ambiguous entries for ".
					    "$filename\n");
				}
				elsif ($new_depth > $old_depth)
				{
					$diff_name = $_;
				}
			}
			else
			{
				$diff_name = $_;
			}
		};
	}
	if ($diff_name)
	{
		# Get converted path
		if ($filename =~ /^(.*)$diff_name$/)
		{
			($common, $old_path, $new_path) =
				get_common_filename($filename,
					$1.$path_data->{$diff_name});
		}
		return ($diff_data->{$diff_name}, $old_path, $new_path);
	}
	else
	{
		return undef;
	}
}


#
# convert_paths(trace_data, path_conversion_data)
#
# Rename all paths in TRACE_DATA which show up in PATH_CONVERSION_DATA.
#

sub convert_paths($$)
{
	my $trace_data = $_[0];
	my $path_conversion_data = $_[1];
	my $filename;
	my $new_path;

	if (scalar(keys(%{$path_conversion_data})) == 0)
	{
		info("No path conversion data available.\n");
		return;
	}

	# Expand path conversion list
	foreach $filename (keys(%{$path_conversion_data}))
	{
		$new_path = $path_conversion_data->{$filename};
		while (($filename =~ s/^(.*)\/[^\/]+$/$1/) &&
		       ($new_path =~ s/^(.*)\/[^\/]+$/$1/) &&
		       ($filename ne $new_path))
		{
			$path_conversion_data->{$filename} = $new_path;
		}
	}

	# Adjust paths
	FILENAME: foreach $filename (keys(%{$trace_data}))
	{
		# Find a path in our conversion table that matches, starting
		# with the longest path
		foreach (sort({length($b) <=> length($a)}
			      keys(%{$path_conversion_data})))
		{
			# Is this path a prefix of our filename?
			if (!($filename =~ /^$_(.*)$/))
			{
				next;
			}
			$new_path = $path_conversion_data->{$_}.$1;

			# Make sure not to overwrite an existing entry under
			# that path name
			if ($trace_data->{$new_path})
			{
				# Need to combine entries
				$trace_data->{$new_path} =
					combine_info_entries(
						$trace_data->{$filename},
						$trace_data->{$new_path},
						$filename);
			}
			else
			{
				# Simply rename entry
				$trace_data->{$new_path} =
					$trace_data->{$filename};
			}
			delete($trace_data->{$filename});
			next FILENAME;
		}
		info("No conversion available for filename $filename\n");
	}
}

#
# sub adjust_fncdata(funcdata, testfncdata, sumfnccount)
#
# Remove function call count data from testfncdata and sumfnccount which
# is no longer present in funcdata.
#

sub adjust_fncdata($$$)
{
	my ($funcdata, $testfncdata, $sumfnccount) = @_;
	my $testname;
	my $func;
	my $f_found;
	my $f_hit;

	# Remove count data in testfncdata for functions which are no longer
	# in funcdata
	foreach $testname (%{$testfncdata}) {
		my $fnccount = $testfncdata->{$testname};

		foreach $func (%{$fnccount}) {
			if (!defined($funcdata->{$func})) {
				delete($fnccount->{$func});
			}
		}
	}
	# Remove count data in sumfnccount for functions which are no longer
	# in funcdata
	foreach $func (%{$sumfnccount}) {
		if (!defined($funcdata->{$func})) {
			delete($sumfnccount->{$func});
		}
	}
}

#
# get_func_found_and_hit(sumfnccount)
#
# Return (f_found, f_hit) for sumfnccount
#

sub get_func_found_and_hit($)
{
	my ($sumfnccount) = @_;
	my $function;
	my $f_found;
	my $f_hit;

	$f_found = scalar(keys(%{$sumfnccount}));
	$f_hit = 0;
	foreach $function (keys(%{$sumfnccount})) {
		if ($sumfnccount->{$function} > 0) {
			$f_hit++;
		}
	}
	return ($f_found, $f_hit);
}

#
# diff()
#

sub diff()
{
	my $trace_data = read_info_file($diff);
	my $diff_data;
	my $path_data;
	my $old_path;
	my $new_path;
	my %path_conversion_data;
	my $filename;
	my $line_hash;
	my $new_name;
	my $entry;
	my $testdata;
	my $testname;
	my $sumcount;
	my $funcdata;
	my $checkdata;
	my $testfncdata;
	my $sumfnccount;
	my $found;
	my $hit;
	my $f_found;
	my $f_hit;
	my $converted = 0;
	my $unchanged = 0;
	local *INFO_HANDLE;

	($diff_data, $path_data) = read_diff($ARGV[0]);

        foreach $filename (sort(keys(%{$trace_data})))
        {
		# Find a diff section corresponding to this file
		($line_hash, $old_path, $new_path) =
			get_line_hash($filename, $diff_data, $path_data);
		if (!$line_hash)
		{
			# There's no diff section for this file
			$unchanged++;
			next;
		}
		$converted++;
		if ($old_path && $new_path && ($old_path ne $new_path))
		{
			$path_conversion_data{$old_path} = $new_path;
		}
		# Check for deleted files
		if (scalar(keys(%{$line_hash})) == 0)
		{
			info("Removing $filename\n");
			delete($trace_data->{$filename});
			next;
		}
		info("Converting $filename\n");
		$entry = $trace_data->{$filename};
		($testdata, $sumcount, $funcdata, $checkdata, $testfncdata,
		 $sumfnccount) = get_info_entry($entry);
		# Convert test data
		foreach $testname (keys(%{$testdata}))
		{
			$testdata->{$testname} =
				apply_diff($testdata->{$testname}, $line_hash);
			# Remove empty sets of test data
			if (scalar(keys(%{$testdata->{$testname}})) == 0)
			{
				delete($testdata->{$testname});
				delete($testfncdata->{$testname});
			}
		}
		# Rename test data to indicate conversion
		foreach $testname (keys(%{$testdata}))
		{
			# Skip testnames which already contain an extension
			if ($testname =~ /,[^,]+$/)
			{
				next;
			}
			# Check for name conflict
			if (defined($testdata->{$testname.",diff"}))
			{
				# Add counts
				($testdata->{$testname}) = add_counts(
					$testdata->{$testname},
					$testdata->{$testname.",diff"});
				delete($testdata->{$testname.",diff"});
				# Add function call counts
				($testfncdata->{$testname}) = add_fnccount(
					$testfncdata->{$testname},
					$testfncdata->{$testname.",diff"});
				delete($testfncdata->{$testname.",diff"});
			}
			# Move test data to new testname
			$testdata->{$testname.",diff"} = $testdata->{$testname};
			delete($testdata->{$testname});
			# Move function call count data to new testname
			$testfncdata->{$testname.",diff"} =
				$testfncdata->{$testname};
			delete($testfncdata->{$testname});
		}
		# Convert summary of test data
		$sumcount = apply_diff($sumcount, $line_hash);
		# Convert function data
		$funcdata = apply_diff_to_funcdata($funcdata, $line_hash);
		# Convert checksum data
		$checkdata = apply_diff($checkdata, $line_hash);
		# Convert function call count data
		adjust_fncdata($funcdata, $testfncdata, $sumfnccount);
		($f_found, $f_hit) = get_func_found_and_hit($sumfnccount);
		# Update found/hit numbers
		$found = 0;
		$hit = 0;
		foreach (keys(%{$sumcount}))
		{
			$found++;
			if ($sumcount->{$_} > 0)
			{
				$hit++;
			}
		}
		if ($found > 0)
		{
			# Store converted entry
			set_info_entry($entry, $testdata, $sumcount, $funcdata,
				       $checkdata, $testfncdata, $sumfnccount,
				       $found, $hit, $f_found, $f_hit);
		}
		else
		{
			# Remove empty data set
			delete($trace_data->{$filename});
		}
        }

	# Convert filenames as well if requested
	if ($convert_filenames)
	{
		convert_paths($trace_data, \%path_conversion_data);
	}

	info("$converted entr".($converted != 1 ? "ies" : "y")." converted, ".
	     "$unchanged entr".($unchanged != 1 ? "ies" : "y")." left ".
	     "unchanged.\n");

	# Write data
	if ($to_file)
	{
		info("Writing data to $output_filename\n");
		open(INFO_HANDLE, ">$output_filename")
			or die("ERROR: cannot write to $output_filename!\n");
		write_info_file(*INFO_HANDLE, $trace_data);
		close(*INFO_HANDLE);
	}
	else
	{
		write_info_file(*STDOUT, $trace_data);
	}
}


#
# system_no_output(mode, parameters)
#
# Call an external program using PARAMETERS while suppressing depending on
# the value of MODE:
#
#   MODE & 1: suppress STDOUT
#   MODE & 2: suppress STDERR
#
# Return 0 on success, non-zero otherwise.
#

sub system_no_output($@)
{
	my $mode = shift;
	my $result;
	local *OLD_STDERR;
	local *OLD_STDOUT;

	# Save old stdout and stderr handles
	($mode & 1) && open(OLD_STDOUT, ">>&STDOUT");
	($mode & 2) && open(OLD_STDERR, ">>&STDERR");

	# Redirect to /dev/null
	($mode & 1) && open(STDOUT, ">/dev/null");
	($mode & 2) && open(STDERR, ">/dev/null");
 
	system(@_);
	$result = $?;

	# Close redirected handles
	($mode & 1) && close(STDOUT);
	($mode & 2) && close(STDERR);

	# Restore old handles
	($mode & 1) && open(STDOUT, ">>&OLD_STDOUT");
	($mode & 2) && open(STDERR, ">>&OLD_STDERR");
 
	return $result;
}


#
# read_config(filename)
#
# Read configuration file FILENAME and return a reference to a hash containing
# all valid key=value pairs found.
#

sub read_config($)
{
	my $filename = $_[0];
	my %result;
	my $key;
	my $value;
	local *HANDLE;

	if (!open(HANDLE, "<$filename"))
	{
		warn("WARNING: cannot read configuration file $filename\n");
		return undef;
	}
	while (<HANDLE>)
	{
		chomp;
		# Skip comments
		s/#.*//;
		# Remove leading blanks
		s/^\s+//;
		# Remove trailing blanks
		s/\s+$//;
		next unless length;
		($key, $value) = split(/\s*=\s*/, $_, 2);
		if (defined($key) && defined($value))
		{
			$result{$key} = $value;
		}
		else
		{
			warn("WARNING: malformed statement in line $. ".
			     "of configuration file $filename\n");
		}
	}
	close(HANDLE);
	return \%result;
}


#
# apply_config(REF)
#
# REF is a reference to a hash containing the following mapping:
#
#   key_string => var_ref
#
# where KEY_STRING is a keyword and VAR_REF is a reference to an associated
# variable. If the global configuration hash CONFIG contains a value for
# keyword KEY_STRING, VAR_REF will be assigned the value for that keyword. 
#

sub apply_config($)
{
	my $ref = $_[0];

	foreach (keys(%{$ref}))
	{
		if (defined($config->{$_}))
		{
			${$ref->{$_}} = $config->{$_};
		}
	}
}

sub warn_handler($)
{
	my ($msg) = @_;

	warn("$tool_name: $msg");
}

sub die_handler($)
{
	my ($msg) = @_;

	die("$tool_name: $msg");
}
