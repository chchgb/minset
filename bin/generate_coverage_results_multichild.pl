#!/usr/bin/perl -w

use strict;
use Cwd;
use Data::Dumper;

######## CONFIGURATION ###############################
# our list of input files, in this case, .torrent files to generate .info files for
our $TEST_DIR = "/home/grey/workspace/bt/src/out";
#TODO use GetOptions() for these values
our $TEST_START = 0; # tests (input .torrent files) start at ${TEST_START}.torrent,
our $TEST_END = 20; # with sequential values going up to ${TEST_END}.torrent
# output directory where a .info file is generated for each test file in $TEST_DIR
our $INFO_DIR = "info";
# the directory to cwd to before we execute $CMD with the next input file
our $CMD_DIR = "/home/grey/workspace/bt/ctorrent-dnh3.3.2";
our $CMD = "ctorrent"; # relative to $CMD_DIR
##################################################

# cwd into the directory so that .gcda files will be generated in the right place
cwd($CMD_DIR);


sub log_to_file($$)
{
	my $str = shift;
	my $file = shift;
	open(FH, ">>$file") or die("Cant open file: $!\n");
	print FH $str;
	close(FH);
}

##########################
# CONFIGURE
my $child_lifetime = 2; #how long do we wait before we kill each child?
my $max_children = 5;
##########################
my %children; # {$pid => time() of birth, .. }

for(my $test_i=0; $test_i<$TEST_END; $test_i++) {
	# for each test:

	# Did we just spawn a child that brought us to the max limit?
	# After the loop is done, we should have <$max_children children, because
	# we going to be spawning one below. Iterate until we can continue
	# spawning children..
	my $j = 0; # how many times we've been in the while() below
	while(keys %children >= $max_children) # keys %children is the number of children keys
	{
		# If we check all of our children once and there's none 
		# to kill, we want to wait before trying again..
		sleep($child_lifetime/2) if($j > 0);
		child_reaper(\%children);
		$j++;
	}

	# Once we get to this point, we will have <$max_children children.
	# We have a test to run, so spawn a child and execute the test.
	my $pid = fork();
	if(!defined $pid) # then the fork() failed
	{
		die "fork failed: $!";
	}
	elsif ($pid == 0) # then this is the child (child pid $pid)
	{
		my $exec = "\"$CMD_DIR/$CMD\" \"$TEST_DIR/$test_i.torrent\"";
		#my $exec = "sleep 250"; # useful for debugging
		print "PID $pid Executing $exec\n";
		system($exec);
		# Ends the child process when exec() returns (when the
		# parent kills us). Last task as a child is to execute lcov.
#		generate_info_file($CMD_DIR, $INFO_DIR);
		exit(0);
	} 
	else # then this is the parent (child pid $pid)
	{
	    	# record existence of this child
		log_to_file("$pid\n", "./children");
		print "Recording existence of child $pid-\n";
    		$children{$pid} = time();
		# continue on to next iteration,
		# killing children that are done and spawning if necessary
	}
}


# make sure no zombie children exist
print "Waiting for last children..\n";
while(keys %children > 0)
{
	print "Killing last children in $child_lifetime sec.\n";
	sleep($child_lifetime);
	child_reaper(\%children);
}

# The following waits until all child processes have
# finished, before allowing the parent to die.
1 while (wait() != -1);

print "Checking for zombie children.\n";
foreach my $child (%children)
{
	print "Internal error- ZOMBIE PROCESS: ".$children{$child}."\n";
	print "Killing....\n";
	kill 9, $child;
}

print "Complete!\n";


# child_reaper(%children) 
#TODO: we're not killing the process that's being exec()'d
# use the following:
#my $handle = IO::Handle->new;
#my $pid = open($handle, 'command & |') or die $!;
# the child will need to catch kill signals and kill the process it launched when the signal occurs.
###############33

# ctorrent ends up zombified
sub child_reaper()
{
	# children must a reference to a hash
	my $children = shift;
	
	# Check each child, and if it's expired as per $child_lifetime,
	# kill it.
	foreach my $child (keys(%$children))
	{
		print "Checking child $child..\n";
		# if it's this child's time to die
		print "time: ".time()." kill time:".($$children{$child}+$child_lifetime)."\n";
		if(time() >= ($$children{$child}+$child_lifetime))
		{
			print "   $child: time to die\n";
			kill 9, $child;
			log_to_file("$child\n", "./dead_children");
			delete $$children{$child};
			waitpid($child,0); #TODO useful in this context?
		}
    	}
}


########################################
# Info file generation- make this a function common to the single and multi child versions.
sub generate_info_file($$)
{
	my $dir = shift;
	my $out_file = shift;

	print "Generating info file $out_file..\n";
	my $lcov_output;

	print "Executing lcov --directory \"$dir\" --capture --output-file \"$out_file\"\n";
	$lcov_output = `lcov --directory "$dir" --capture --output-file "$out_file"`;
	print "LCOV OUTPUT: $lcov_output\n";
	# TODO check $lcov_output for indication of failure
	
	print "Executing lcov --zerocounters\n";
	$lcov_output = `lcov --zerocounters`;
	print "LCOV OUTPUT: $lcov_output\n";
}
