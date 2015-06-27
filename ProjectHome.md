Base lcov functionality was left unchanged, with major additions to the `lcov` and `genhtml` scripts. rats (http://www.fortify.com/security-resources/rats.jsp) is required to be in your $PATH if you want to use rats integration features. You can add, subtract, and compare code coverage reports based on statement coverage or sinks (as reported by rats).

lcov has been modified to do minimum test set analysis ("minset") on a set of .info files, which can be based on either statement coverage or sinks.

TBD Documentation