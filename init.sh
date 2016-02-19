#!/bin/sh

function assert_success() {
	if [ $? -ne 0 ]; then
		die "$1"
	fi
}

die () {
	echo "$@"
	exit 1
}

# make sure we have some kind of ruby executable on path

# first check for system ruby
if [ ! $(type -P ruby ) ]; then
	# OK, let's try to use chruby
	if [ "$(type -t chruby)" != 'function' ]; then
		source /etc/profile.d/chruby.sh
	fi
	chruby ruby
fi

if [ ! $(type -P gem) ]; then 
	echo "The 'gem' binary is not installed.  Cannot continue."
	die "Please execute `chruby ruby` from the command line and re-run  this script"
fi


if [ ! $(type -P bundle) ]; then
	echo "Installing the 'bundle' gem"
	gem install bundle
fi

# add our dependencies

bundle install   

# make sure the solr data directory is there
[[ ! -d solr/data ]] && mkdir -p solr/data

# initialize database

RAILS_ENV=development

if [ ! -e db/"${RAILS_ENV}.db" ]; then 
	echo "Creating initial database for the ${RAILS_ENV} environment"
	bundle exec rake db:migrate

fi

echo "Now installing Solr."

# download Solr and create a new core, if needed 

bundle exec rake trln:solr:install
