# Full featured SSH Installer Plugin for Jenkins

This plugin is written in ruby and is a rewrite of a plugin written in Java (@Yale) that no longer
is maintained.  The idea is to provide a builder plugin with the following attributes:

* Allow external ssh key management (ie. ability to specify a key path and a passphrase 
  instead of managing them through the Jenkins UI).
* Allow for Pre- and Post- Install SSH commands, or the ability to run an arbitrary set of commands
* Run the build step an arbitrary number of times for an arbitrary set of "nodes" on the destination
* Create a staging directory that "node" specific
* Write out the build parameters as install.properties to a staging dir over SSH
* Substitute the "node" name into the install.properties when it's written
* Checkout an "installer" or other arbitrary data from version control and SCP the contents 
  of the workspace to the destination machine in the staging directory

*This plugin is still in the early stages and doesn't meet all of these goals yet.*