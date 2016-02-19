# NCSU/TRLN Blacklight Test

This repository contains a Rails application based on Blacklight 6, along with
tools to populate a sample index.  This is pre-alpha software!

## Provisioning

This test was originally developed using [Vagrant](https://www.vagrantup.com/)
and [Puppet](https://puppetlabs.com/).  The goal was to allow quickly spinning
up an instance of Blacklight for testing, with an eye to automating the
deployment of a potential Blacklight-fronted shared Solr index for TRLN.  Most of what comes below assumes a Red Hat Enterprise Linux (RHEL) style environment, e.g. RHEL 6 or 7, or Centos 6/7.  Vagrant box used was `puppetlabs/centos-7.0.64-puppet`, for reference.

### Limitations

This is currently an all-in-one quickstart, and doesn't cleanly separate out
all of the components that would be involved in a production-ready deployment.

In particular, it leans on the `chruby` and `ruby-install` utilities to manage
ruby versions.  We are investigating both JRuby and "standard" Ruby (aka MRI).
Currently, using MRI is recommended.  We would like to explore JRuby as it
offers deployment and performance benefits (if it works).

## Dependencies  (\* = managed by Puppet, if you use it)

* Ruby version - originally generated in a chruby environment with ruby 2.3.0
* [chruby](https://github.com/postmodern/chruby)
* [ruby-install](https://github.com/postmodern/ruby-install)

Follow the instructions for installation for both projects, then run 

```
$ ruby-install jruby
$ ruby-install ruby
```

will download and install the latest JRuby and MRI versions.  Select an implementation with `chruby [j]ruby` (note you need to start a new shell session to pick up the tools.

System ruby *may* work, but has not been tested. 

* Java 8+
  - puppet installs openjdk 8, Oracle JDK will also work

* Various RPMS
 - git 
 - gcc
 - gcc-c++
 - libxml2, libxml2-devel
 - sqlite, sqlite-devel

* Setup

This is a Rails application, so probably you should read up on that.

The `init.sh` (Bash) script will attempt to do as much of the initial setup as
it can, calling `bundle install` and performing some other tasks such as
creating the data directory for the default Solr core, downloading a suitable
version of Solr (into `$(pwd)/solr-install/solr-$SOLR_VERSION). 

The script will also attempt to create the initial database. (`bundle rake
db:migrate`)

If any of this fails, well, it's early days yet.  The script should tell most
of the tale of what it's trying to do.

# Database 

Blacklight uses a database to store search history and bookmarks for users.  In
this environment, we just have it use sqlite (a file-based database).  This
will probably buckle under any serious load testing =)

* Services (job queues, cache servers, etc.)

None yet.

* Indexing some sample data

We have had some success using [traject](https://github.com/traject/traject) to
do some very simple indexing of NCSU's MARC records.  You will find a sample
traject configuration file in the `config/traject` subdirectory, which you can
copy and customize to your needs.  Follow the comments in that file to create a copy of the traject configuration; I recommend keeping it in the same directory.

Next, edit `config/trln.yml` and make sure that `development => traject =>
config_files` has the right value, paying attention to the comments in that
file.  

Next, find a middlin'-sized file full of MARC records (say, 100 or so) from
your institution (traject will autodetect format and encoding), and execute our
custom rake task:

```bundle exec rake trln:solr:index [ list of marc files ]```

This will execute traject with your configuration file and attempt to insert the contents into the solr index.  Traject's output will go to the console.

Per its authors, traject scales much better if you use JRuby to run it (`chruby
jruby`), but this probably won't matter for small datasets.

*  Running

Assuming you have all the above set up correctly, and have put the right
version of ruby into your environment, start solr using either the solr_wrapper
gem `bundle exec solr_wrapper -c blacklight-core -d ./solr/conf`) or manually
execute `bundle rails server` (or `bundle rails s`) to start rails listening on
port 3000 (the Vagrantfile forwards this to 8088 on the host machine).

## But Why Not Use `solr_wrapper` intead of all this weird stuff in `lib/tasks/trln.rake` ?

Blacklight tries to use `solr_wrapper`, a gem developed by experienced Blacklight / Ruby / Solr folks.  But it turned out to be hard for me to figure out what it was doing and how it worked, so I decided to replicate a lot of what it does (no doubt, poorly) as part of an exercise in figuring out some of the Rails ecosystem.
