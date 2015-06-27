# Introduction #

> The following options are specified to use RATS (SCA) integration. You may only
> > use these options if you have 'rats' in your $PATH:
> > --sinks-hit TRACEFILE                  Show the number of sinks covered, uncovered, and
> > > uninstrumented (with corresponding percentages) for TRACEFILE.

> > --sink-stats TRACEFILE\_DIR             Calculate average, minimum, and maximum number of sinks
> > > covered for all .info files in TRACEFILE\_DIR.

> > --calc-sink-minset TRACEFILE\_DIR       Calculate the minimum set of tracefiles that covers
> > > a maximum number of sinks (as reported by rats).


> --calc-stmt-minset TRACEFILE\_DIR       Calculate the minimum set of tracefiles that covers
> > a maximum amount of statements.

> --limit-to-file SOURCE\_FILE   	 Used in conjunction with --calc-**-minset to limit the
> > analysis to a single source code file in the tracefiles.

> --compare-total TRACEFILE TRACEFILE    Compare total statement coverage of two info files.
> --compare-src-file SRC\_FILE FILE FILE  Compare coverage of a specified src code file (abs. path)
> > that is present in two tracefiles.

> --compare-func FUNC\_NAME FILE FILE     Compare coverage of a specified function
> > that is present in two tracefiles.**Not implemented.


> The following two options may only be used in conjunction with -o, --output-file:
> the result of the operation on the files will be output to the file specified.
> --add TRACEFILE1 TRACEFILE2            Add the execution counts of TRACEFILE1 and
> > TRACEFILE1, then output result to --output-file.

> --subtract TRACEFILE,BASE\_TRACEFILE    Subtract the execution counts of TRACEFILE
> > from BASE\_TRACEFILE and output to --output-file.



> For example,
> > To add two tracefiles that were generated from identical code bases:
> > lcov --add ./run1.info ./run2.info -o ./sum.info


> To subtract two tracefiles that were generated from identical code bases:
> lcov --subtract ./new.info ./baseline.info -o ./difference.info

> To calculate the minimum test set ("minset") of all .info files in a directory:
> (NOTE: The --limit-to-file part is optional, if not specified, all source code
> files in the tracefiles will be used in the analysis)
> lcov --calc-minset /path/to/tracefiles [--limit-to-file /abs/source/code/path.cpp]

> TODO add more examples



# Details #

Add your content here.  Format your content with:
  * Text in **bold** or _italic_
  * Headings, paragraphs, and lists
  * Automatic links to other wiki pages