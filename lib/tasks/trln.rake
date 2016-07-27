require 'solr'
require 'yaml'
require 'traject/command_line'
require 'cocaine'

# see comments in 'development' section of config/trln.yml for more information

config = YAML.load(
		File.read(
			File.join(Rails.root, "config/trln.yml")
		)
	)[Rails.env].deep_symbolize_keys()


def is_running?(port = 8983)
	line = Cocaine::CommandLine.new(
		"lsof", ":ports", expected_outcodes: [0,1]
	)
  	begin
        	output = line.run(ports: ["-iTCP", "-i:#{port}"])
                if output != ''
			# lsof says something's holding the port open
			return true
		end
		puts "Found output: '#{output}'"
		return false
        rescue Cocaine::ExitStatusError => e
        	puts e
                exit 1
        end
	# looks like we got return code 1 from lsof, meaning port is open
	return false
end

server = SolrServer.new config[:solr] 

desc "Custom tasks for TRLN"
namespace :trln do
	namespace :solr do
		install_dir = ENV['SOLR_INSTALL_DIR'] || File.absolute_path(config[:solr][:install_dir], Rails.root)
		solr_version = config[:solr][:version] || '5.5.2'
		solr_cmd = File.join(install_dir,"solr-#{solr_version}/bin/solr")
		solr_port = config[:solr][:port] || 8983


		desc "Installs solr (if necessary)"
		task :install => :environment do
			# by default, install solr to the "solr_install"
			# directory at the top level of this project
			#
			
			f = Fetcher.new(install_dir)
			f.install
		end

		desc 'Stops solr if is running '
		task :stop => [ :environment, :install ] do
			server.stop if server.is_running?
		end

		desc "Ensures solr is running"
		task :start => [ :environment, :install ] do
			server.start unless server.is_running?
		end

		desc "Creates the basic solr index"
		task :create_core => [ :environment, :start ] do
			if server.core_exists?
				puts "Core already created."
			else 
				server.create_core
				puts "Core created.  You may now add files to the index"
			end
		end

		desc "Unloads (deletes) core (DANGEROUS)"
		task :delete_core => [ :environment, :start ] do
			if server.core_exists?
				server.delete_core
				puts "DELETED!"
			end
		end

		desc 'Indexes supplied files.  See config/index.yml'
		task  :index => [ :environment, :create_core ] do
			# todo : put this into a library
			configfiles = config[:traject][:config_files].collect {
				|f|
				[ '-c', File.absolute_path(f,File.join(Rails.root, 'config/traject')) ]
			}.flatten!
			
			args = config[:traject][:cmdline_base]
			args <<= configfiles
			# now stick on all the files specified after
			# the task name
			args = (args << ARGV[1..-1]).flatten!
			cmdline = Traject::CommandLine.new(args)
			result = cmdline.execute
			if result
				puts "Indexing complete.  Committing"
				server.commit
			else
				exit 1
			end
		end
	end
end
