#!/usr/bin/perl -w

use strict;
use Cwd;
use Data::Dumper;
use File::Basename;
use Getopt::Long;


# CLI-configured variables - default values
our $VERBOSE = undef;
# our list of input files, in this case, .torrent files to generate .info files for
our $TEST_DIR = undef;
our $TEST_START = undef; # tests (input .torrent files) start at ${TEST_START}.torrent,
our $TEST_END = undef; # with sequential values going up to ${TEST_END}.torrent
our $TEST_EXT = ".torrent";
# output directory where a .info file is generated for each test file in $TEST_DIR
our $INFO_DIR = undef;
# directory where partial downloads go. If none is specified with --tmp-dir,
#  a directory under /tmp will be created (and subsequently used)
our $TMP_DIR = undef;
# how many seconds to wait before killing each child process
our $WAIT_SEC = 2;
our $DEBUG = 0;
our $HELP = 0;
our $CMD = undef;

$SIG{TERM} = 'IGNORE';

sub log_to_file($$)
{
	my $str = shift;
	my $file = shift;
	open(FH, ">>$file") or die("Cant open file: $!\n");
	print FH $str;
	close(FH);
}

sub usage
{
	my $msg = shift or undef;
	print $msg if defined($msg);
	#TODO the formatting is fucked up here
	print << "END";
Usage: generate_coverage_results.pl --input-dir="/path/to/tests" --output-dir="/info_file_output_dir"
								    --test-start=0  --test-end=100
								    --cmd="/path/to/instrumented/executable"
        -i, --input-dir=TEST_DIR        Specify list of input files / tests, to be used as arguments to --cmd.
        -o, --info-dir=INFO_DIR    Specify directory to output .info files that lcov generates.
        -s, --test-start=START          Specify an integer to specify which test number to start out (tests
                                                        are named sequentially from START.EXT to END.EXT, see --test-end and
                                                        --test-ext below).
        -e, --test-end=END
        -x, --test-ext=TEST_EXT        Specify the extension to use for the input tests found in TEST_DIR. Default: .torrent.
        -c, --cmd=CMD_PATH             Specify the path of the command that lcov will execute. Must be instrumented with gcov!
	-w, --wait=WAIT_SEC            Specify the number of seconds to let each --cmd run before killing it.
        -h, --help                                Display this help message.
        -v, --verbose                          Display verbose messages.
        -d, --debug                            Display debug messages.
END
	exit(1);
}

my $result = GetOptions ("verbose"  => \$VERBOSE,
					"input-dir=s" => \$TEST_DIR,
					"tmp-dir=s" => \$TMP_DIR, # for storing partial download files
					"info-dir=s" => \$INFO_DIR,
					"test-start=i" => \$TEST_START,
					"test-end=i" => \$TEST_END,
					"test-ext=s" => \$TEST_EXT,
					"cmd=s" => \$CMD,
					"wait=i" => \$WAIT_SEC,
					"help" => \$HELP,
					"debug" => \$DEBUG); 

usage("Failed: couldnt parse arguments\n")  if(!$result);
usage() if ($HELP);

# check for required arguments:
my $i = 0;
defined($TEST_DIR) or usage("Failed: specify a input dir. with --input-dir.\n");
defined($INFO_DIR)  or usage("Failed: specify a output dir. (for lcov's .info files) with --info-dir.\n");
defined($TEST_START)  or usage("Failed: specify the first test (first input file) in the set with --test-start.\n");
defined($TEST_END) or usage("Failed: specify the last test (last input file) in the set with --test-end.\n");
defined($CMD) or usage("Failed: specify the path of the instrumented executable to run with --cmd.\n");
unless(defined($TMP_DIR))
{
	$TMP_DIR = "/tmp/$$/".int(rand(100));
	mkdir($TMP_DIR); # set default tmp dir if not spec'd
	print "No temp (partial downloads) directory specified: using '$TMP_DIR'.\n";
}

# check that the input and output directories exist

# the directory to cwd to before we execute $CMD with the next input file
#TODO: allow command to have arguments for user customization
die("--cmd: file '$CMD' does not exist. Check the path and try again.\n") if (! -e $CMD);
our $CMD_DIR = dirname($CMD);
our $CMD_BASENAME = basename($CMD); # relative to $CMD_DIR

# check the input and output directories
die("--input-dir: directory '$TEST_DIR' does not exist. Check the path and try again.\n") if (! -e $TEST_DIR);
die("--output-dir: directory '$INFO_DIR' does not exist. Check the path and try again.\n") if (! -e $INFO_DIR);


# cwd into the directory so that .gcda files will be generated in the right place
cwd($CMD_DIR);

# run_cmd($exec, $wait_sec): returns void
#  run $exec, wait $sec_before_kill, then kill $exec
sub run_cmd($$)
{
	# command to execute
	my $exec = shift;
	# how many seconds to wait before we kill our child
	my $sleep_sec = shift;

	print "Spawning child process..\n";
	my $pid = fork();
	if (not defined $pid) {
		warn "resources not avilable.\n";
		exit(1);
	} elsif ($pid == 0) {
		print "I'M THE CHILD, PID=$$\n";
		print "Executing $exec\n";
		log_to_file("$$\n", "singlechild_alive");
		exec("exec ".$exec); #exec never returns unless it fails
		die("Exec '$exec' failed: $!")
	} else {
		print "Parent: Child PID=$pid. Waiting for child to exit.\n";
		# wait silently until it's time..
		sleep($sleep_sec);
		# .. to murder the child
		print "Killing -".getpgrp($pid).".. (SIGINT)\n";
		log_to_file("-".getpgrp($pid)."\n", "singlechild_dead");
		
		# negative indicates a process group - because sh is spawning the --cmd, 2 processes total!
		kill(15, "-".getpgrp($pid)); 
		#system("killall -2 ctorrent")
		# wait for the child to finish
		#waitpid($pid,0);
	}
}

for (my $test_i = $TEST_START; $test_i<=$TEST_END; $test_i++)
{
	print "Generating info file for $TEST_DIR/${test_i}${TEST_EXT}..\n";
	my $output;

	print "Zeroing lcov counters (in .gcda files..)\n";
	$output = `lcov --zerocounters --directory "$CMD_DIR"`;

	#TODO fix the output file (-s ) hack below
	my $run = "\"$CMD_DIR/$CMD_BASENAME\" -s \"./out/output_for_$test_i\" \"$TEST_DIR/${test_i}${TEST_EXT}\"";
	#my $run = "sleep 300";
	run_cmd($run, $WAIT_SEC);
	print "LCOV OUTPUT: $output\n";
	print "Executing lcov --directory \"$CMD_DIR\" --capture --output-file \"$INFO_DIR/$test_i.info\"";	
	$output = `lcov --directory "$CMD_DIR" --capture --output-file "$INFO_DIR/$test_i.info"`;
	print "LCOV OUTPUT: $output\n";
}

print "Done generating .info files.\n";

print "Adding test results for total coverage...\n";

print "Done.\n";
